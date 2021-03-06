// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show json;

import 'package:googleapis/oauth2/v2.dart' as oauth2_v2;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:retry/retry.dart' show retry;

import '../service/secret/backend.dart';
import '../shared/email.dart' show isValidEmail;
import 'auth_provider.dart' show AuthProvider, AuthResult;

final _logger = Logger('pub.account.google_auth2');

/// The token-info end-point.
final _tokenInfoEndPoint = Uri.parse('https://oauth2.googleapis.com/tokeninfo');

/// Provides OAuth2-based authentication through Google accounts.
class GoogleOauth2AuthProvider extends AuthProvider {
  final String _siteAudience;
  final List<String> _trustedAudiences;
  http.Client _httpClient;
  oauth2_v2.Oauth2Api _oauthApi;
  bool _secretLoaded = false;
  String _secret;

  GoogleOauth2AuthProvider(this._siteAudience, this._trustedAudiences) {
    _httpClient = http.Client();
    _oauthApi = oauth2_v2.Oauth2Api(_httpClient);
  }

  @override
  String authorizationUrl(String redirectUrl, String state) {
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'client_id': _siteAudience,
        'redirect_uri': redirectUrl,
        'scope': 'openid profile email',
        'response_type': 'code',
        'access_type': 'online',
        'state': state,
      },
    ).toString();
  }

  @override
  Future<String> authCodeToAccessToken(String redirectUrl, String code) async {
    try {
      await _loadSecret();
      final rs = await _httpClient
          .post('https://www.googleapis.com/oauth2/v4/token', body: {
        'code': code,
        'client_id': _siteAudience,
        'client_secret': _secret,
        'redirect_uri': redirectUrl,
        'grant_type': 'authorization_code',
      });
      if (rs.statusCode >= 400) {
        _logger.info('Bad authorization token: $code for $redirectUrl');
        return null;
      }
      final tokenMap = json.decode(rs.body) as Map<String, dynamic>;
      return tokenMap['access_token'] as String;
    } catch (e) {
      _logger.info('Bad authorization token: $code for $redirectUrl', e);
    }
    return null;
  }

  /// Authenticate [token] as `access_token` or `id_token`.
  @override
  Future<AuthResult> tryAuthenticate(String token) async {
    if (token == null || token.isEmpty) {
      return null;
    }

    AuthResult result;
    // Note: it might be overkill to try both authentication flows. But once
    //       we've migrated the pub client to authenticate using id_tokens
    //       the implications of accidentally breaking access_token
    //       authentication will be much smaller and we can switch to a mode
    //       where we only check if it's an accessToken if it looks like an
    //       accessToken.
    //       But to reduce the risk of an outage we shall attempt both flows
    //       for now. Notice that the cost of the second check is small
    //       assuming we rarely receive invalid access_tokens or id_tokens.
    if (_isLikelyAccessToken(token)) {
      // If this is most likely an access_token, we try access_token first
      result = await _tryAuthenticateAccessToken(token);
      if (result != null) {
        return result;
      }
      // If not a valid access_token we try it as a JWT
      return await _tryAuthenticateJwt(token);
    } else {
      // If this is not likely to be an access_token, we try JWT first
      result = await _tryAuthenticateJwt(token);
      if (result != null) {
        return result;
      }
      // If not valid JWT we try it as access_token
      return await _tryAuthenticateAccessToken(token);
    }
  }

  /// Authenticate with oauth2 [accessToken].
  Future<AuthResult> _tryAuthenticateAccessToken(String accessToken) async {
    oauth2_v2.Tokeninfo info;
    try {
      info = await _oauthApi.tokeninfo(accessToken: accessToken);
      if (info == null) {
        return null;
      }

      if (!_trustedAudiences.contains(info.audience)) {
        _logger.warning('OAuth2 access attempted with invalid audience, '
            'for email: "${info.email}", audience: "${info.audience}"');
        return null;
      }

      if (info.expiresIn == null ||
          info.expiresIn <= 0 ||
          info.userId == null ||
          info.userId.isEmpty ||
          info.verifiedEmail != true ||
          info.email == null ||
          info.email.isEmpty ||
          !isValidEmail(info.email)) {
        _logger.warning('OAuth2 token info invalid: ${info.toJson()}');
        return null;
      }

      return AuthResult(info.userId, info.email.toLowerCase());
    } on oauth2_v2.ApiRequestError catch (e) {
      _logger.info('Access denied for OAuth2 access token.', e);
    } catch (e, st) {
      _logger.warning('OAuth2 access token lookup failed.', e, st);
    }
    return null;
  }

  /// Authenticate with openid-connect `id_token`.
  Future<AuthResult> _tryAuthenticateJwt(String jwt) async {
    // Hit the token-info end-point documented at:
    // https://developers.google.com/identity/sign-in/web/backend-auth
    // Note: ideally, we would verify these JWTs locally, but unfortunately
    //       we don't have a solid RSA implementation available in Dart.
    final u = _tokenInfoEndPoint.replace(queryParameters: {'id_token': jwt});
    final response = await retry(
      () => _httpClient.get(u, headers: {'accept': 'application/json'}),
      maxAttempts: 2, // two attempts is enough, we don't want delays here
    );
    // Expect a 200 response
    if (response.statusCode != 200) {
      return null;
    }
    final r = json.decode(response.body) as Map<String, dynamic>;
    if (r.containsKey('error')) {
      return null; // presumably an invalid token.
    }
    // Sanity check on the algorithm and type.
    if (r['alg'] == 'none' || r['typ'] != 'JWT') {
      return null;
    }
    // Validate the issuer.
    if (r['iss'] != 'https://accounts.google.com') {
      return null;
    }
    // Validate create time
    final fiveMinFromNow = DateTime.now().toUtc().add(Duration(minutes: 5));
    if (r['iat'] == null || _parseTimestamp(r['iat']).isAfter(fiveMinFromNow)) {
      return null; // Token is created more than 5 minutes in the future
    }
    // Validate expiration time
    final fiveMinInPast = DateTime.now().toUtc().subtract(Duration(minutes: 5));
    if (r['exp'] == null || _parseTimestamp(r['exp']).isBefore(fiveMinInPast)) {
      return null; // Token is expired more than 5 minutes in the past
    }
    // Validate audience
    if (r['aud'] is! String) {
      return null; // missing audience
    }
    if (!_trustedAudiences.contains(r['aud'] as String)) {
      return null; // Not trusted audience
    }
    // Validate subject is present
    if (r['sub'] is! String) {
      return null; // missing subject (probably missing 'openid' scope)
    }
    // Validate email is present and verified
    if (r['email_verified'] != true || r['email'] is! String) {
      return null; // Missing the 'email' scope
    }
    return AuthResult(r['sub'] as String, r['email'] as String);
  }

  @override
  Future close() async {
    _httpClient.close();
  }

  Future _loadSecret() async {
    if (_secretLoaded) return;
    _secret =
        await secretBackend.lookup('${SecretKey.oauthPrefix}$_siteAudience');
    _secretLoaded = true;
  }
}

/// Pattern for a valid JWT, these must 3 base64 segments separated by dots.
final _jwtPattern = RegExp(
    r'^[a-zA-Z0-9+/=_-]{4,}\.[a-zA-Z0-9+/=_-]{4,}\.[a-zA-Z0-9+/=_-]{4,}$');

/// Return `true` if [token] is an `access_token`, and `false` if [token] is a
/// JWT.
///
/// The format of an oauth2 token does not appear to be limited. Indeed a JWT
/// could be used as an oauth2 `access_token`. Thus, the only correct thing to
/// do is to attempt authentication as both kinds of tokens. However, in
/// practice Google oauth2 `access_token`s starts with `'ya29.'` and do not
/// match the regular expression for JWTs. Thus, we can avoid significant
/// overhead by trying the most likley approach first.
bool _isLikelyAccessToken(String token) {
  // access_tokens starts with 'ya29.'
  if (token.startsWith('ya29.')) {
    return true;
  }
  // If it looks like a JWT, then it's probably not an access_token.
  if (_jwtPattern.hasMatch(token)) {
    return false;
  }
  return true; // anything goes
}

/// Parse a timestamp from JWT as returned by token-info end-point.
///
/// Note. the token-info end-point returns strings, though the JWT specification
/// says that JWTs must be integers. We shall support both here for robustness.
/// Presumably the API will not break regardless.
DateTime _parseTimestamp(dynamic timestamp) {
  ArgumentError.checkNotNull(timestamp, 'timestamp');
  if (timestamp is String) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp) * 1000);
  }
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  }
  throw ArgumentError.value(timestamp, 'timestamp', 'must be int or string');
}
