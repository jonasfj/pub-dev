// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test is fragile because creating instances and waiting for them to start is
// slow, and something that could throw all sorts of exceptions, we don't want
// run this as part of normal testing.
@Tags(['fragile'])

import 'dart:async';
import 'dart:convert' show json;
import 'dart:io' show Platform, File;
import 'package:test/test.dart';
import 'package:appengine/appengine.dart';
import 'package:googleapis/compute/v1.dart' show ComputeApi;
import 'package:pub_dev/task/cloudcompute/cloudcompute.dart';
import 'package:pub_dev/task/cloudcompute/googlecloudcompute.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import '../../shared/test_services.dart';

void main() {
  test('CloudCompute from createGoogleCloudCompute()', () async {
    setupLogging();

    await withAppEngineServices(() async {
      // Hack around the fact that [authClientService] does not get the
      // compute scope.
      final client = await auth.clientViaServiceAccount(
        auth.ServiceAccountCredentials.fromJson(json.decode(
          File(Platform.environment['GCLOUD_KEY']).readAsStringSync(),
        )),
        [ComputeApi.ComputeScope],
      );

      // Create CloudCompute instance
      final gce = await createGoogleCloudCompute(
        client: client,
        project: Platform.environment['GCLOUD_PROJECT'],
        poolLabel: 'manual-testing',
      );

      // Fail if any instances exist
      var instances = await gce.listInstances().toList();
      expect(instances, isEmpty);

      // Create instance that terminates
      scheduleMicrotask(() async {
        print('creating instance');
        final instance = await gce.createInstance(
          zone: gce.zones.first,
          dockerImage: 'busybox:1.31.1',
          arguments: [
            'sh',
            '-c',
            'whoami; date -R; sleep 5s; date -R; uname -a',
          ],
          description: 'test instance that terminates rather quickly',
        );
        print('Created instance: ${instance.name}, $instance');
      });

      // Wait until we have a terminated instance
      print('### Wait for instance to terminate on its own');
      while (!instances.any((i) => i.state == InstanceState.terminated)) {
        instances = await gce.listInstances().toList();
        print('listInstances():');
        for (final inst in instances) {
          print(' - ${inst.name}, state: ${inst.state}');
        }
        await Future.delayed(Duration(seconds: 1));
      }
      // Delete instances
      print('### Delete all instances');
      for (final inst in instances) {
        await gce.delete(inst.zone, inst.name);
      }

      // Wait until instances are deleted from listing
      print('### Wait for instance to disappear from listings');
      while (instances.isNotEmpty) {
        instances = await gce.listInstances().toList();
        print('listInstances():');
        for (final inst in instances) {
          print(' - ${inst.name}, state: ${inst.state}');
        }
        await Future.delayed(Duration(seconds: 1));
      }
    });
  },
      timeout: Timeout.parse('30m'),
      skip: Platform.environment['GCLOUD_PROJECT'] != null &&
              // Avoid running against production by accident
              Platform.environment['GCLOUD_PROJECT'] != 'dartlang-pub' &&
              Platform.environment['GCLOUD_KEY'] != null
          ? false
          : 'createGoogleCloudCompute testing requires GCLOUD_PROJECT and GCLOUD_KEY');
}
