// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../package/models.dart' show Package;
import '../shared/datastore.dart';
import '../shared/exceptions.dart';
import '../shared/scheduler_stats.dart';
import '../shared/task_scheduler.dart';
import '../shared/task_sources.dart';

import 'backend.dart';
import 'search_service.dart';

final Logger _logger = Logger('pub.search.updater');

/// Sets the index updater.
void registerIndexUpdater(IndexUpdater updater) =>
    ss.register(#_indexUpdater, updater);

/// The active index updater.
IndexUpdater get indexUpdater => ss.lookup(#_indexUpdater) as IndexUpdater;

class IndexUpdater implements TaskRunner {
  final DatastoreDB _db;
  final PackageIndex _packageIndex;
  Timer? _statsTimer;

  IndexUpdater(this._db, this._packageIndex);

  /// Loads the package index snapshot, or if it fails, creates a minimal
  /// package index with only package names and minimal information.
  Future<void> init() async {
    final isReady = await _initSnapshot();
    if (!isReady) {
      _logger.info('Loading minimum package index...');
      int cnt = 0;
      await for (final pd in searchBackend.loadMinimumPackageIndex()) {
        await _packageIndex.addPackage(pd);
        cnt++;
        if (cnt % 500 == 0) {
          _logger.info('Loaded $cnt minimum package data (${pd.package})');
        }
      }
      await _packageIndex.markReady();
      _logger.info('Minimum package index loaded with $cnt packages.');
    }
    snapshotStorage.startTimer();
  }

  /// Updates all packages in the index.
  /// It is slower than searchBackend.loadMinimum_packageIndex, but provides a
  /// complete document for the index.
  @visibleForTesting
  Future<void> updateAllPackages() async {
    /*await for (final p in _db.query<Package>().run()) {
      try {
        final doc = await searchBackend.loadDocument(p.name!);
        await _packageIndex.addPackage(doc);
      } on RemovedPackageException catch (_) {
        await _packageIndex.removePackage(p.name!);
      }
    }*/
    for (var i = 0; i < 80000; i++) {
      final readmeText = '''
Lorem ipsum $i dolor sit amet, consectetur adipiscing elit. Nullam leo ex, 
fringilla et finibus in, mollis nec urna. Vestibulum sagittis efficitur justo 
sit amet condimentum. Ut porta accumsan est quis pellentesque. Vivamus finibus 
fringilla sem, sit amet tempor tellus cursus at. Vestibulum lacus nunc,
convallis sit amet feugiat in, lobortis vel neque. Curabitur at nulla vehicula,
interdum felis et, cursus ante. In quis vestibulum ligula. Interdum et 
malesuada fames ac ante ipsum primis in faucibus. Duis in luctus nisl. 
Curabitur nisi tortor, vestibulum condimentum hendrerit et, tristique viverra
dui. Vivamus finibus fringilla arcu, vitae auctor metus luctus id. 
Interdum et malesuada fames ac ante ipsum primis in faucibus. Praesent 
vestibulum scelerisque urna, eget viverra arcu. Ut vel vehicula neque. 
Proin vel pulvinar turpis.

Duis quis velit at neque tempor placerat eget sed eros. Ut sagittis ante nisl, 
faucibus maximus diam dignissim eu. Aenean tempor, enim eu facilisis elementum,
nibh nisi sollicitudin risus, vitae aliquam elit massa vitae ex. Sed non justo 
sapien. Curabitur lacinia vulputate pharetra. Quisque sit amet hendrerit sem. 
Maecenas volutpat, enim eu lacinia lacinia, turpis mauris eleifend tortor, eu 
consequat augue metus et nibh. Sed eu dolor dui. Aliquam quam quam, ultrices ut 
mauris vitae, ullamcorper lacinia turpis. Cras dignissim, orci sed scelerisque 
sodales, massa augue volutpat orci, vel semper leo nisi eu erat. Duis tempus
 maximus placerat.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed a convallis dui.
Nam consectetur nulla vulputate augue tincidunt fermentum. In odio tellus, 
hendrerit ac tortor eu, faucibus fermentum erat. Ut pharetra accumsan bibendum. 
Proin mollis orci velit, at facilisis mauris cursus sollicitudin. In viverra 
condimentum vestibulum. Vivamus quis urna at libero tristique dictum sit amet 
sed nibh. Fusce consequat molestie efficitur. Maecenas porttitor quis libero ac 
congue. Quisque consectetur gravida dui, id placerat nulla pellentesque at. 
Nam maximus, ex quis mattis lacinia, est mi eleifend urna, nec varius sem 
est id ex.

Morbi cursus placerat quam. Proin non nunc eu nisl fringilla volutpat eu sit 
amet ipsum. Mauris vel dolor blandit lacus pellentesque faucibus. Phasellus 
sed nisl in ipsum imperdiet tincidunt a vehicula sem. Maecenas quis tellus
vitae purus suscipit scelerisque quis nec felis. Phasellus consequat enim enim, 
a suscipit felis porta et. Vivamus luctus nunc nec ullamcorper varius. Integer 
mattis libero nec elit accumsan, in faucibus lacus imperdiet. Proin bibendum
mi felis, quis laoreet libero malesuada et. Maecenas facilisis dolor nisi, 
a dapibus velit consequat eget. Suspendisse volutpat convallis arcu. Nulla
sodales vel turpis ac sodales. Morbi congue, erat sit amet ultrices
vestibulum, nisi eros dignissim nunc, in pulvinar dui augue tincidunt 
velit. Proin dapibus volutpat enim eu rutrum. Class aptent taciti 
sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos.

Etiam nec tincidunt dui. Nullam placerat, ante eu dignissim mattis, tortor 
massa suscipit nulla, nec tempor purus magna volutpat justo. Curabitur 
vulputate libero nec velit consectetur blandit. Nunc pellentesque dui a ex 
commodo, vitae commodo purus malesuada. Ut risus risus, dictum in ullamcorper 
vel, mattis malesuada libero. Duis nisl eros, vehicula vitae eros ac, 
malesuada rhoncus turpis. Curabitur quis lobortis nunc, sed fringilla risus.
Praesent auctor nisl et turpis laoreet, vel pharetra lacus tincidunt. 
Quisque metus turpis, luctus nec dignissim at, hendrerit non neque.
''';
      final words = readmeText.split(' ')..shuffle(Random(i));
      final readme = words.join(' ');

      await _packageIndex.addPackage(PackageDocument(
        package: 'foo_$i',
        created: DateTime.now().subtract(Duration(seconds: i * 10)),
        description: readme.substring(0, 160),
        readme: readme,
        grantedPoints: 40 + (i % 80),
        maxPoints: 140,
        likeCount: i,
        tags: 'platform:linux platfrom:windows topic:pkg-$i'.split(' '),
        version: '1.0.$i',
        updated: DateTime.now(),
        timestamp: DateTime.now(),
        apiDocPages: [
          ApiDocPage(
              relativePath: 'foo_$i.dart',
              symbols: readme.substring(0, 1024).split(' ')),
        ],
      ));
    }
    print('LOADED DATA');
    await _packageIndex.markReady();
  }

  /// Returns whether the snapshot was initialized and loaded properly.
  Future<bool> _initSnapshot() async {
    try {
      _logger.info('Loading snapshot...');
      await snapshotStorage.fetch();
      final documents = snapshotStorage.documents;
      await _packageIndex.addPackages(documents.values);
      // Arbitrary sanity check that the snapshot is not entirely bogus.
      // Index merge will enable search.
      if (documents.length > 10) {
        _logger.info('Merging index after snapshot.');
        await _packageIndex.markReady();
        _logger.info('Snapshot load completed.');
        return true;
      }
    } catch (e, st) {
      _logger.warning('Error while fetching snapshot.', e, st);
    }
    return false;
  }

  /// Starts the scheduler to update the package index.
  void runScheduler({required Stream<Task> manualTriggerTasks}) {
    final scheduler = TaskScheduler(
      this,
      [
        ManualTriggerTaskSource(manualTriggerTasks),
        DatastoreHeadTaskSource(
          _db,
          TaskSourceModel.package,
          sleep: const Duration(minutes: 10),
        ),
        DatastoreHeadTaskSource(
          _db,
          TaskSourceModel.scorecard,
          sleep: const Duration(minutes: 10),
          skipHistory: true,
        ),
        _PeriodicUpdateTaskSource(),
      ],
    );
    scheduler.run();

    _statsTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      updateLatestStats(scheduler.stats());
    });
  }

  Future<void> close() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    // TODO: close scheduler
  }

  @override
  Future<void> runTask(Task task) async {
    try {
      final sd = snapshotStorage.documents[task.package];

      // Skip tasks that originate before the current document in the snapshot
      // was created (e.g. the index and the snapshot was updated since the task
      // was created).
      // This preempts unnecessary work at startup (scanned Packages are updated
      // only if the index was not updated since the last snapshot), and also
      // deduplicates the periodic-updates which may not complete in 2 hours.
      if (sd != null && sd.timestamp.isAfter(task.updated)) return;

      final doc = await searchBackend.loadDocument(task.package);
      snapshotStorage.add(doc);
      await _packageIndex.addPackage(doc);
    } on RemovedPackageException catch (_) {
      _logger.info('Removing: ${task.package}');
      snapshotStorage.remove(task.package);
      await _packageIndex.removePackage(task.package);
    }
  }
}

/// A task source that generates an update task for stale documents.
///
/// It scans the current search snapshot every two hours, and selects the
/// packages that have not been updated in the last 5 days.
class _PeriodicUpdateTaskSource implements TaskSource {
  @override
  Stream<Task> startStreaming() async* {
    for (;;) {
      await Future.delayed(Duration(hours: 2));
      final now = clock.now();
      final tasks = snapshotStorage.documents.values
          .where((pd) => now.difference(pd.timestamp).inDays >= 5)
          .map((pd) => Task(pd.package, pd.version!, now))
          .toList();
      _logger
          .info('Periodic scheduler found ${tasks.length} packages to update.');
      for (Task task in tasks) {
        yield task;
      }
    }
  }
}
