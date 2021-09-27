import 'dart:convert';
import 'dart:io' show Platform;
import 'package:test/test.dart';
import 'package:ulid/ulid.dart' show Ulid;
import 'package:appengine/appengine.dart';
import 'package:gcloud/http.dart';
import 'package:googleapis/iamcredentials/v1.dart';

import '../shared/test_services.dart';

final serviceAccount = 'dartlang-pub-dev@appspot.gserviceaccount.com';

void main() {
  test('Simple GlobalLock withClaim', () async {
    await withAppEngineServices(() async {
      final api = IamcredentialsApi(authClientService);
      api.projects.serviceAccounts.signJwt(
          SignJwtRequest()
            ..payload = json.encode({
              'iat': DateTime.now()
                      .subtract(Duration(minutes: 15))
                      .millisecondsSinceEpoch ~/
                  1000,
              'exp': DateTime.now()
                      .add(Duration(hours: 3))
                      .millisecondsSinceEpoch ~/
                  1000,
              'sub': 'worker-234233ulid2323(instance-name)',
              'iss': 'https://pub.dev',
              'aud': 'https://pub.dev',
              'pub.dev#task': {
                'package': 'retry',
                'versions': ['1.0.0', '2.0.0'],
              },
            }),
          serviceAccount);
    });
  },
      skip: Platform.environment['GCLOUD_PROJECT'] != null &&
              // Avoid running against production by accident
              Platform.environment['GCLOUD_PROJECT'] != 'dartlang-pub' &&
              Platform.environment['GCLOUD_KEY'] != null
          ? false
          : 'GlobalLock testing requires GCLOUD_PROJECT and GCLOUD_KEY');
}
