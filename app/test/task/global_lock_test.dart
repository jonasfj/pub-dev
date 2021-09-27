// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;
import 'package:test/test.dart';
import 'package:pub_dev/task/global_lock.dart' show GlobalLock;
import 'package:ulid/ulid.dart' show Ulid;
import 'package:appengine/appengine.dart';

import '../shared/test_services.dart';

void main() {
  testWithServices('Simple GlobalLock use case', () async {
    final lock = GlobalLock.create(
      'simple-test-${Ulid()}',
      expiration: Duration(seconds: 10),
    );

    final claim = await lock.claim();
    expect(claim.valid, isTrue);

    final claim2 = await lock.tryClaim();
    expect(claim2, isNull);

    final refreshed = await claim.refresh();
    expect(refreshed, isTrue);

    await claim.release();
    expect(claim.valid, isFalse);
  });

  test('Simple GlobalLock withClaim', () async {
    await withAppEngineServices(() async {
      final lock = GlobalLock.create(
        'simple-test-${Ulid()}',
        expiration: Duration(seconds: 3),
      );

      var running = 0;
      await Future.wait([
        Future.microtask(() async {
          await lock.withClaim((claim) async {
            running++;
            expect(running, equals(1));
            expect(claim.valid, isTrue);
            expect(claim.expires.isAfter(DateTime.now().toUtc()), isTrue);

            final oldExpires = claim.expires;
            await Future.delayed(Duration(seconds: 3));
            expect(running, equals(1));
            expect(claim.valid, isTrue);
            expect(claim.expires.isAfter(DateTime.now().toUtc()), isTrue);
            expect(claim.expires != oldExpires, isTrue);
            running--;
          });
        }),
        Future.microtask(() async {
          await lock.withClaim((claim) async {
            running++;
            expect(running, equals(1));
            expect(claim.valid, isTrue);
            expect(claim.expires.isAfter(DateTime.now().toUtc()), isTrue);

            final oldExpires = claim.expires;
            await Future.delayed(Duration(seconds: 3));
            expect(running, equals(1));
            expect(claim.valid, isTrue);
            expect(claim.expires.isAfter(DateTime.now().toUtc()), isTrue);
            expect(claim.expires != oldExpires, isTrue);
            running--;
          });
        }),
      ]);
    });
  },
      skip: Platform.environment['GCLOUD_PROJECT'] != null &&
              // Avoid running against production by accident
              Platform.environment['GCLOUD_PROJECT'] != 'dartlang-pub' &&
              Platform.environment['GCLOUD_KEY'] != null
          ? false
          : 'GlobalLock testing requires GCLOUD_PROJECT and GCLOUD_KEY');
}
