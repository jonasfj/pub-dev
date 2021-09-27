import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:pub_dev/shared/configuration.dart';
import 'package:pub_dev/shared/utils.dart';
import 'package:pub_dev/task/cloudcompute/cloudcompute.dart';
import 'package:pub_dev/task/global_lock.dart';
import 'package:pub_dev/shared/versions.dart' show runtimeVersion;
import 'package:logging/logging.dart' show Logger;
import 'package:pub_dev/task/models.dart';
import 'package:gcloud/db.dart' show DatastoreDB;
import 'package:pub_dev/shared/datastore.dart';

final _log = Logger('pub.task.schedule');

/// Maximum number of instances that may be used concurrently.
const _concurrentInstanceLimit = 500;

const _maxInstanceAge = Duration(hours: 2);

const _maxInstancesPerIteration = 50;

Future<void> schedule(
  GlobalLockClaim claim,
  CloudCompute compute,
  DatastoreDB db,
) async {
  // Map from zone to DateTime when zone is allowed again
  final zoneBannedUntil = <String, DateTime>{
    for (final zone in compute.zones) zone: DateTime(0),
  };

  // Set of `CloudInstance.name`s currently being deleted.
  // This to avoid deleting instances where the deletion process is still
  // running.
  final deletionInProgress = <String>{};

  // Create a fast RNG with random seed for picking zones.
  final rng = Random(Random.secure().nextInt(2 << 31));

  // Run scheduling iterations, so long as we have a valid claim
  while (claim.valid) {
    final iterationStart = DateTime.now();

    // Count number of instances, and delete old instances
    var instances = 0;
    await for (final instance in compute.listInstances()) {
      instances += 1; // count the instance

      // If terminated or older than maxInstanceAge, delete the instance...
      if (instance.state == InstanceState.terminated &&
          instance.created.isBefore(DateTime.now().subtract(_maxInstanceAge)) &&
          // Prevent multiple calls to delete the same instance
          deletionInProgress.add(instance.name)) {
        scheduleMicrotask(() async {
          final deletionStart = DateTime.now();
          try {
            await compute.delete(instance.zone, instance.name);
          } catch (e, st) {
            _log.severe('Failed to delete instance "${instance.name}"', e, st);
          } finally {
            // Wait at-least 5 minutes from start of deletion until we remove
            // it from [deletionInProgress] that way we give the API some time
            // reconcile state.
            await _sleep(Duration(minutes: 5), since: deletionStart);
            deletionInProgress.remove(instance.name);
          }
        });
      }
    }

    // If we are not allowed to create new instances within the allowed quota,
    if (_concurrentInstanceLimit >= instances) {
      // Wait 30 seconds then list instances again, so that we can count them
      await _sleep(Duration(seconds: 30), since: iterationStart);
      continue; // skip the rest of the iteration
    }

    // Determine which zones are not banned
    final allowedZones = zoneBannedUntil.entries
        .where((e) => e.value.isBefore(DateTime.now()))
        .map((e) => e.key)
        .toList()
          ..shuffle(rng);
    var nextZoneIndex = 0;
    String pickZone() => allowedZones[nextZoneIndex++ % allowedZones.length];

    // If no zones are available, we sleep and try again later.
    if (allowedZones.isEmpty) {
      await _sleep(Duration(seconds: 30), since: iterationStart);
      continue;
    }

    // Schedule analysis for some packages
    var pendingPackagesReviewed = 0;
    await Future.wait(await (db.query<PackageState>()
          ..filter('runtimeVersion =', runtimeVersion)
          ..filter('pendingAt <=', DateTime.now())
          ..order('pendingAt')
          ..limit(min(
            _maxInstancesPerIteration,
            max(0, _concurrentInstanceLimit - instances),
          )))
        .run()
        .map<Future<void>>((state) async {
      pendingPackagesReviewed += 1;

      String payload;
      String description;
      final instanceName = compute.generateInstanceName();
      final zone = pickZone();

      await withRetryTransaction(db, (tx) async {
        final s = await tx.lookupOrNull<PackageState>(state.key);
        if (s == null) {
          payload = null; // presumably the package was deleted.
          return;
        }

        final now = DateTime.now();
        final pendingVersions = s.pendingVersions(at: now);
        if (pendingVersions.isEmpty) {
          payload = null; // do not schedule anything
          return;
        }

        // Update PackageState
        s.versions.addAll({
          for (final v in pendingVersions)
            v: PackageVersionState(
              scheduled: now,
              attempts: s.versions[v].attempts + 1,
              zone: zone,
              instance: instanceName,
              secretToken: createUuid(),
            ),
        });
        s.derivePendingAt();
        tx.insert(s);

        // Create payload
        payload = json.encode({
          'package': s.package,
          'callback': activeConfiguration.defaultServiceBaseUrl,
          'versions': pendingVersions.map((v) => {
                'version': v,
                'token': s.versions[v].secretToken,
              })
        });

        // Create human readable description for GCP console.
        description =
            'package:${s.package} analysis of ${pendingVersions.length} '
            'versions.';
      });

      if (payload == null) {
        return;
      }

      scheduleMicrotask(() async {
        try {
          _log.info(
            'creating instance $instanceName in $zone for '
            'package:${state.package}',
          );
          await compute.createInstance(
            zone: zone,
            name: instanceName,
            dockerImage: 'gcr.io/${envConfig.gcloudProject}'
                '/pub_worker:${envConfig.gaeVersion}',
            arguments: [payload],
            description: description,
          );
        } on Exception catch (e, st) {
          _log.warning(
            'Failed to create instance $instanceName in $zone',
            e,
            st,
          );
          // Ban usage of zone for 15 minutes
          zoneBannedUntil[zone] = DateTime.now().add(Duration(minutes: 15));

          // Restore the state of the PackageState for versions that were
          // suppose to run on the instance we just failed to create.
          // If this doesn't work, we'll eventually retry. Hence, correctness
          // does not hinge on this transaction being successful.
          await withRetryTransaction(db, (tx) async {
            final s = await tx.lookupOrNull<PackageState>(state.key);
            if (s == null) {
              return; // Presumably, the package was deleted.
            }

            s.versions.addEntries(
              s.versions.entries
                  .where((e) => e.value.instance == instanceName)
                  .map((e) => MapEntry(e.key, state.versions[e.key])),
            );
            s.derivePendingAt();
            tx.insert(s);
          });
        }
      });
    }).toList());

    // If there was no pending packages reviewed, and no instances currently
    // running, then we can easily sleep 1 minute before we poll again.
    if (instances == 0 && pendingPackagesReviewed == 0) {
      await Future.delayed(Duration(minutes: 1));
      continue;
    }

    // If more tasks is available and quota wasn't used up, we only sleep 10s
    await _sleep(Duration(seconds: 10), since: iterationStart);
  }
}

/// Sleep [delay] time [since] timestamp, or now if not given.
Future<void> _sleep(Duration delay, {DateTime since}) async {
  ArgumentError.checkNotNull(delay, 'delay');
  since ??= DateTime.now();

  delay = delay - DateTime.now().difference(since);
  if (delay.isNegative) {
    // Await a micro task to ensure consistent behavior
    await Future.microtask(() {});
  } else {
    await Future.delayed(delay);
  }
}
