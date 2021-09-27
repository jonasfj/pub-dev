// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';
import 'package:neat_cache/cache_provider.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:pub_worker/pana_report.dart' show PanaReport;
import 'package:pub_worker/blob.dart' show BlobIndex;

import 'package:client_data/package_api.dart' show VersionScore;

import '../account/models.dart' show LikeData, UserSessionData;
import '../dartdoc/models.dart' show DartdocEntry, FileInfo;
import '../package/models.dart' show PackageView;
import '../publisher/models.dart' show PublisherPage;
import '../scorecard/models.dart' show ScoreCardData;
import '../search/search_service.dart' show PackageSearchResult;
import '../service/secret/backend.dart';
import 'convert.dart';
import 'versions.dart';

final Logger _log = Logger('rediscache');
final _random = Random.secure();
final _defaultCacheReadTimeout = Duration(milliseconds: 300);
final _defaultCacheWriteTimeout = Duration(milliseconds: 1000);

class CachePatterns {
  final Cache<List<int>> _cache;
  CachePatterns._(Cache<List<int>> cache)
      : _cache = cache
            .withPrefix('rv-$runtimeVersion')
            .withTTL(Duration(minutes: 10));

  // NOTE: This class should only contain methods that return Entry<T>, as well
  //       configuration options like prefix and TTL.

  /// Cache for [UserSessionData].
  Entry<UserSessionData> userSessionData(String sessionId) => _cache
      .withPrefix('account-usersession')
      .withTTL(Duration(hours: 24))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (UserSessionData data) => data.toJson(),
        decode: (d) => UserSessionData.fromJson(d as Map<String, dynamic>),
      ))[sessionId];

  /// Cache for [DartdocEntry] objects.
  Entry<DartdocEntry> dartdocEntry(String package, String version) => _cache
      .withPrefix('dartdoc-entry')
      .withTTL(Duration(hours: 24))
      .withCodec(wrapAsCodec(
        encode: (DartdocEntry entry) => entry.asBytes(),
        decode: (data) => DartdocEntry.fromBytes(data),
      ))['$package-$version'];

  /// Cache for [FileInfo] objects used by dartdoc.
  Entry<FileInfo> dartdocFileInfo(String objectName) => _cache
      .withPrefix('dartdoc-fileinfo')
      .withTTL(Duration(minutes: 60))
      .withCodec(wrapAsCodec(
        encode: (FileInfo info) => info.asBytes(),
        decode: (data) => FileInfo.fromBytes(data),
      ))[objectName];

  /// Cache for API summaries used by dartdoc.
  Entry<Map<String, dynamic>> dartdocApiSummary(String package) => _cache
      .withPrefix('dartdoc-apisummary')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (map) => map,
        decode: (obj) => obj as Map<String, dynamic>,
      ))[package];

  Entry<String> uiPackagePage(String package, String version) => _cache
      .withPrefix('ui-packagepage')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageChangelog(String package, String version) => _cache
      .withPrefix('ui-package-changelog')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageExample(String package, String version) => _cache
      .withPrefix('ui-package-example')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageInstall(String package, String version) => _cache
      .withPrefix('ui-package-install')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageLicense(String package, String version) => _cache
      .withPrefix('ui-package-license')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackagePubspec(String package, String version) => _cache
      .withPrefix('ui-package-pubspec')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageScore(String package, String version) => _cache
      .withPrefix('ui-package-score')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package-$version'];

  Entry<String> uiPackageVersions(String package) => _cache
      .withPrefix('ui-package-versions')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)['$package'];

  Entry<String> uiIndexPage() => _cache
      .withPrefix('ui-indexpage')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)['/'];

  Entry<String> uiPublisherListPage() => _cache
      .withPrefix('ui-publisherpage')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)['/publishers'];

  /// The first, non-search page for publisher's packages.
  Entry<String> uiPublisherPackagesPage(String publisherId) => _cache
      .withPrefix('ui-publisherpage')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)[publisherId];

  Entry<bool> packageVisible(String package) => _cache
      .withPrefix('package-visible')
      .withTTL(Duration(days: 7))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (bool value) => value,
        decode: (d) => d as bool,
      ))[package];

  Entry<List<int>> packageData(String package) => _cache
      .withPrefix('api-package-data-by-uri')
      .withTTL(Duration(minutes: 10))['$package'];

  Entry<VersionScore> versionScore(String package, String version) => _cache
      .withPrefix('api-version-score')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (d) => d.toJson(),
        decode: (d) => VersionScore.fromJson(d as Map<String, dynamic>),
      ))['$package-$version'];

  Entry<String> packageLatestVersion(String package) => _cache
      .withPrefix('package-latest-version')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)[package];

  Entry<PackageView> packageView(String package) => _cache
      .withPrefix('package-view')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (PackageView pv) => pv.toJson(),
        decode: (d) => PackageView.fromJson(d as Map<String, dynamic>),
      ))[package];

  Entry<Map<String, dynamic>> apiPackagesListPage(int page) => _cache
      .withPrefix('api-packages-list')
      .withTTL(Duration(minutes: 10))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (map) => map,
        decode: (obj) => obj as Map<String, dynamic>,
      ))['$page'];

  Entry<PackageSearchResult> packageSearchResult(String url, {Duration ttl}) {
    ttl ??= const Duration(minutes: 1);
    return _cache
        .withPrefix('search-result')
        .withTTL(ttl)
        .withCodec(utf8)
        .withCodec(json)
        .withCodec(wrapAsCodec(
          encode: (PackageSearchResult r) => r.toJson(),
          decode: (d) =>
              PackageSearchResult.fromJson(d as Map<String, dynamic>),
        ))[url];
  }

  Entry<ScoreCardData> scoreCardData(String package, String version) => _cache
      .withPrefix('scorecarddata')
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (ScoreCardData d) => d.toJson(),
        decode: (d) => ScoreCardData.fromJson(d as Map<String, dynamic>),
      ))['$package-$version'];

  Entry<List<LikeData>> userPackageLikes(String userId) => _cache
      .withPrefix('user-package-likes')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (List<LikeData> l) =>
            l.map((LikeData l) => l.toJson()).toList(),
        decode: (d) => (d as List)
            .map((d) => LikeData.fromJson(d as Map<String, dynamic>))
            .toList(),
      ))[userId];

  Entry<String> secretValue(String secretId) => _cache
      .withPrefix('secret-value')
      .withTTL(Duration(minutes: 60))
      .withCodec(utf8)[secretId];

  Entry<String> sitemap(String requestedUri) => _cache
      .withPrefix('sitemap')
      .withTTL(Duration(hours: 12))
      .withCodec(utf8)[requestedUri];

  Entry<List<int>> packageNameCompletitionDataJsonGz() => _cache
      .withPrefix('api-package-name-completition-data-json-gz')
      .withTTL(Duration(hours: 8))['-'];

  Entry<PublisherPage> allPublishersPage() => publisherPage('-');

  Entry<PublisherPage> publisherPage(String userId) => _cache
      .withPrefix('publisher-page')
      .withTTL(Duration(hours: 4))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (PublisherPage list) => list.toJson(),
        decode: (data) => PublisherPage.fromJson(data as Map<String, dynamic>),
      ))['$userId'];

  Entry<String> atomFeedXml() => _cache
      .withPrefix('atom-feed-xml')
      .withTTL(Duration(minutes: 3))
      .withCodec(utf8)['/'];

  /// Cache for [PanaReport] objects using by TaskBackend.
  Entry<PanaReport> panaReport(String package, String version) => _cache
      .withPrefix('pana-report')
      .withTTL(Duration(hours: 24))
      .withCodec(utf8)
      .withCodec(json)
      .withCodec(wrapAsCodec(
        encode: (PanaReport entry) => entry.toJson(),
        decode: (data) => PanaReport.fromJson(data as Map<String, dynamic>),
      ))['$package-$version'];

  /// Cache for pana-log objects, used by TaskBackend.
  Entry<String> panaLog(String package, String version, String id) => _cache
      .withPrefix('pana-log')
      .withCodec(utf8)
      .withTTL(Duration(hours: 6))['$package-$version/$id'];

  /// Cache for dartdoc-index objects, used by TaskBackend.
  Entry<BlobIndex> dartdocIndex(String package, String version) => _cache
      .withPrefix('dartdoc-index')
      .withTTL(Duration(hours: 24))
      .withCodec(wrapAsCodec(
        encode: (BlobIndex entry) => entry.asBytes(),
        decode: (data) => BlobIndex.fromBytes(data),
      ))['$package-$version'];

  /// Cache for dartdoc-page used by TaskBackend.
  Entry<List<int>> dartdocPage(
    String package,
    String version,
    String blobId,
    String path,
  ) =>
      _cache
          .withPrefix('dartdoc-page')
          .withTTL(Duration(hours: 6))['$package-$version/$blobId/$path'];
}

/// The active cache.
CachePatterns get cache => ss.lookup(#_cache) as CachePatterns;

void _registerCache(CachePatterns cache) => ss.register(#_cache, cache);

final _delayedCachePurgerKey = #_delayedCachePurger;
_DelayedCachePurger get _delayedCachePurger =>
    ss.lookup(_delayedCachePurgerKey) as _DelayedCachePurger;
void _registerDelayedCachePurgerKey(_DelayedCachePurger value) =>
    ss.register(_delayedCachePurgerKey, value);

/// Initializes caches based on the environment.
/// - In AppEngine, it will use redis cache,
/// - otherwise, a local in-memory cache.
Future<void> setupCache() async {
  // Use in-memory cache, if not running on AppEngine
  if (Platform.environment.containsKey('GAE_VERSION')) {
    await _registerRedisCache();
  } else {
    _log.warning('using in-memory cache instead of redis');
    await _registerInmemoryCache();
  }

  final purger = _DelayedCachePurger();
  _registerDelayedCachePurgerKey(purger);
  ss.registerScopeExitCallback(purger._close);
}

/// Read redis connection string from the secret backend and initialize redis
/// cache.
Future _registerRedisCache() async {
  final connectionString =
      await secretBackend.lookup(SecretKey.redisConnectionString);
  // Validate that we got a connection string
  if (connectionString == null || connectionString.isEmpty) {
    throw Exception('Secret ${SecretKey.redisConnectionString} is missing');
  }

  // Create and register a cache
  final cacheProvider = await _ConnectionRefreshingCacheProvider.connect(
      () async => Cache.redisCacheProvider(connectionString));
  _registerCache(CachePatterns._(Cache(cacheProvider)));
  ss.registerScopeExitCallback(() async => cacheProvider.close());
}

Future _registerInmemoryCache() async {
  _registerCache(CachePatterns._(Cache(Cache.inMemoryCacheProvider(4096))));
}

/// Creates a [CacheProvider] when called.
typedef _CacheProviderFn<T> = Future<CacheProvider<T>> Function();

/// The redis client uses a single connection for a long period. To make sure we
/// don't accumulate objects around a single connection accidentally, this cache
/// provider will reconnect to redis ~every hour.
class _ConnectionRefreshingCacheProvider<T> implements CacheProvider<T> {
  final _CacheProviderFn<T> _fn;
  CacheProvider<T> _delegate;
  Timer _timer;
  bool _isClosed = false;

  _ConnectionRefreshingCacheProvider._(this._fn, this._delegate) {
    final duration = Duration(minutes: 55 + _random.nextInt(10));
    _timer = Timer.periodic(duration, (_) async {
      _log.info('Starting to update redis connection...');
      try {
        final newProvider = await _fn();
        // Warm-up redis connection
        await newProvider.get('ping');

        if (_isClosed) {
          // discard if `close` was called during the Timer callback
          await newProvider.close();
        } else {
          // otherwise update provider and close old one
          final d = _delegate;
          _delegate = newProvider;
          await d.close();
        }
      } catch (e, st) {
        _log.shout('Failed to update redis connection.', e, st);
      }
    });
  }

  static Future<_ConnectionRefreshingCacheProvider<T>> connect<T>(
      _CacheProviderFn<T> fn) async {
    return _ConnectionRefreshingCacheProvider._(fn, await fn());
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _timer.cancel();
    await _delegate.close();
  }

  @override
  Future<T> get(String key) => _delegate
      .get(key)
      .timeout(_defaultCacheReadTimeout, onTimeout: () => null);

  @override
  Future<void> purge(String key) => _delegate
      .purge(key)
      .timeout(_defaultCacheWriteTimeout, onTimeout: () => null);

  @override
  Future<void> set(String key, T value, [Duration ttl]) => _delegate
      .set(key, value, ttl)
      .timeout(_defaultCacheWriteTimeout, onTimeout: () => null);
}

extension EntryPurgeExt on Entry {
  /// Datastore.query is only eventually consistent, and when we are changing
  /// entries that are then fetched via query, the cache may store the old values.
  /// Running a repeated purge after a reasonable delay will make sure that the
  /// cache won't store the old values for too long.
  Future purgeAndRepeat({int retries = 0, Duration delay}) async {
    await purge(retries: retries);
    _delayedCachePurger.add(this, delay);
  }
}

class _DelayedCachePurger {
  final _entries = <_DelayedPurge>[];
  Timer _timer;

  void add(Entry cacheEntry, Duration delay) {
    final entry = _DelayedPurge(cacheEntry, delay);
    _entries.add(entry);
    _timer ??= Timer.periodic(Duration(seconds: 20), (timer) {
      _purge();
    });
  }

  Future<void> _purge() async {
    final now = DateTime.now();
    for (final e in _entries.where((e) => !e.time.isAfter(now)).toList()) {
      await e.entry.purge();
      _entries.remove(e);
    }
    if (_entries.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _close() async {
    _timer?.cancel();
    _timer = null;
  }
}

class _DelayedPurge {
  final Entry entry;
  final DateTime time;

  _DelayedPurge(this.entry, Duration delay)
      : time = DateTime.now().add(delay ?? Duration(seconds: 30));
}
