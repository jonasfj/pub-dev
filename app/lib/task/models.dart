// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show json;
import 'package:gcloud/db.dart' as db;
import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

/// Time before an analysis/dartdoc task is retriggered due to age.
///
/// We periodically re-analyze all packages to ensure eventual consistency.
const taskRetriggerInterval = Duration(days: 31);

/// Time before an anlysis/dartdoc task for a given package/version is will
/// piggyback on the sandbox used for analysis of another version of the same
/// package.
const minTaskRetriggerInterval = Duration(days: 24);

/// Minimum time before a dependency change can trigger a new analysis/dartdoc
/// for a given package/version.
///
/// When a dependency of a package is updated, the `lastDependencyChanged` will
/// be updated, and when then analysis of a version is older than
/// [taskDependencyRetriggerCoolOff] the version will be scheduled for analysis.
/// Hence, this limits how frequently we schedule if dependencies are updated
/// frequently.
///
/// Notice, that if we are scheduling a task for analysis for some other reason
/// any package versions not updated before `lastDependencyChanged` will also
/// be scheduled, by piggybacking on the same sandbox / task / instance.
const taskDependencyRetriggerCoolOff = Duration(hours: 24);

/// Maximum number of times an analysis/dartdoc task should be retried for a
/// given version.
const taskRetryLimit = 3;

/// Maximum time a task may be running.
///
/// This is used to determine:
///  * When instances should be killed, and,
///  * If `secretToken` used for authorization has expired.
const maxTaskExecutionTime = Duration(hours: 3);

/// Delay before scheduling a fail analysis/dartdoc task again.
///
/// Failures can happen due to bugs in our code, or pre-emption of GCE VMs.
Duration taskRetryDelay(int attempts) =>
    Duration(hours: 3) * (attempts * attempts);

/// [PackageState] is used for storing the analysis state of a package for a
/// given `runtimeVersion`.
///
///  * `id`, is the `runtimeVersion / packageName`.
///  * `PackageState` entities never has a parent.
@db.Kind(name: 'PackageState', idType: db.IdType.String)
class PackageState extends db.ExpandoModel<String> {
  /// Create a key for [runtimeVersion] and [packageName] in [ddb].
  static db.Key<String> createKey(
    db.DatastoreDB ddb,
    String runtimeVersion,
    String packageName,
  ) =>
      ddb.emptyKey.append<String>(
        PackageState,
        id: '$runtimeVersion/$packageName',
      );

  /// Set the [id] using given [runtimeVersion] and [packageName].
  void setId(String runtimeVersion, String packageName) =>
      id = '$runtimeVersion/$packageName';

  String get package => id.split('/').last;

  /// Runtime version this [PackageState] belongs to.
  ///
  /// This is also encoded in the [id], but duplicated here for stronger query
  /// support.
  @db.StringProperty(required: true)
  String runtimeVersion;

  /// Scheduling state for all versions of this package.
  @PackageVersionStateMapProperty(required: true)
  Map<String, PackageVersionState> versions;

  /// Next [DateTime] at which point some package version becomes pending.
  @db.DateTimeProperty(required: true, indexed: true)
  DateTime pendingAt;

  /// List of all package names depended on by some version of this package.
  ///
  /// This is all dependencies, including transitive dependencies from any
  /// version of this package. This property is used to scan for dependent
  /// packages when a new version of a package is published.
  @db.StringListProperty(indexed: true)
  List<String> dependencies;

  /// Last [DateTime] a dependency was updated.
  @db.DateTimeProperty(required: true)
  DateTime lastDependencyChanged;

  /// Derive [pendingAt] using [versions] and [lastDependencyChanged].
  ///
  /// When updating PackageState the pendingAt property is set to the minimum of:
  ///   * `scheduled + 31 days` for any version,
  ///   * `scheduled + 24 hours` for any version where `dependencyChanged > scheduled`
  ///   * `scheduled + 3 hours * attempts^2` for any version where `attempts > 0 && attempts < 3`.
  void derivePendingAt() => pendingAt = [
        // scheduled + 31 days
        ...versions.values.map((v) => v.scheduled.add(taskRetriggerInterval)),
        // scheduled + 24 hours, where scheduled < lastDependencyChanged
        ...versions.values
            .where((v) => v.scheduled.isBefore(lastDependencyChanged))
            .map((v) => v.scheduled.add(taskDependencyRetriggerCoolOff)),
        // scheduled + 3 hours * attempts^2, where attempts > 0 && attempts < 3
        ...versions.values
            .where((v) => v.attempts > 0 && v.attempts < taskRetryLimit)
            .map((v) => v.scheduled.add(taskRetryDelay(v.attempts))),
        // Pick the minimum of the candiates, default scheduling in year 3k
        // if there is no date before that.
      ].fold(DateTime(3000), (a, b) => a.isBefore(b) ? a : b);

  /// Return a list of pending versions for this package.
  ///
  /// When scheduling analysis of a package we piggyback along versions that
  /// are going to be pending soon too. Hence, we return a version if:
  ///   * `now - scheduled > 21 days`,
  ///   * `lastDependencyChanged > scheduled`, or,
  ///   * `attempts > 0 && attempts < 3 && now - scheduled > 3 hours * attemps^2`
  List<String> pendingVersions({DateTime at}) {
    at ??= DateTime.now();
    Duration timeSince(DateTime past) => at.difference(past);
    Duration delay(int attempts) => Duration(hours: 3) * (attempts * attempts);

    return versions.entries
        .where(
          // NOTE: Any changes here must be reflected in [derivePendingAt]
          (e) =>
              // If scheduled more than 21 days ago
              timeSince(e.value.scheduled) > minTaskRetriggerInterval ||
              // If a dependency has changed since it was last scheduled
              lastDependencyChanged.isBefore(e.value.scheduled) ||
              // If:
              //  - attempts > 0 (analysis is not done, and has been started)
              //  - no more than 3 attempts have been done,
              //  - now - scheduled > 3 hours * attempts^2
              (0 > e.value.attempts &&
                  e.value.attempts < 3 &&
                  timeSince(e.value.scheduled) > delay(e.value.attempts)),
        )
        .map((e) => e.key)
        .toList();
  }
}

/// State of a given `version` within a [PackageState].
@JsonSerializable()
class PackageVersionState {
  /// [DateTime] this version of the package was last scheduled for analysis.
  ///
  /// This is `DateTime(0)` if never scheduled.
  final DateTime scheduled;

  /// Number of attempts to schedule the package version for analysis.
  ///
  /// This is zero when the analysis is done, or has never been initiated.
  final int attempts;

  /// Name of the zone in which the [instance] analysing this package version is
  /// running.
  ///
  /// This can be used for logging, debugging and terminating instances without
  /// further package versions to process.
  ///
  /// This should be updated to `null` when analysis result have been reported.
  final String zone;

  /// Name of the instance analysing this package version.
  ///
  /// This can be used for logging, debugging and terminating instances without
  /// further package versions to process.
  ///
  /// This should be updated to `null` when analysis result have been reported.
  final String instance;

  /// Secret token (UUIDv4) used for authenticating worker requests.
  ///
  /// The token is expired when `now - scheduled > maxTaskExecutionTime`.
  /// This should be updated to `null` when analysis result have been reported.
  ///
  /// **WARNING**, do not compare `secretToken` without using a fixed-time
  /// comparison. Please use [isAuthorized] for validating a request.
  final String secretToken;

  /// Return true, if [token] matches [secretToken] and it has not expired.
  ///
  /// This does a fixed-time comparison to mitigate timing attacks.
  bool isAuthorized(String token) {
    if (token == null ||
        secretToken == null ||
        instance == null ||
        token.length != secretToken.length) {
      return false;
    }
    var equal = true;
    final N = secretToken.length;
    for (int i = 0; i < N; i++) {
      equal = token[i] == secretToken[i] && equal;
    }
    return DateTime.now().difference(scheduled) < maxTaskExecutionTime && equal;
  }

  PackageVersionState({
    this.scheduled,
    this.attempts,
    this.secretToken,
    this.zone,
    this.instance,
  });
}

/// [GlobalLockState] is used for locking in a distributed system.
///
///  * `id`, is the `lockId`.
///  * `GlobalLockState` entities never has a parent.
@db.Kind(name: 'GlobalLockState', idType: db.IdType.String)
class GlobalLockState extends db.ExpandoModel<String> {
  /// Get the lockId
  String get lockId => id;

  /// Unique ULID identifying the claim currently holding the lock.
  ///
  /// Empty, if not currently locked.
  @db.StringProperty(required: true)
  String claimId;

  /// DateTime at which point the lock becomes free again.
  @db.DateTimeProperty(required: true)
  DateTime lockedUntil;
}

/// A [db.Property] encoding a Map from version to [PackageVersionState] as JSON.
class PackageVersionStateMapProperty extends db.Property {
  const PackageVersionStateMapProperty(
      {String propertyName, bool required = false})
      : super(propertyName: propertyName, required: required, indexed: false);

  @override
  Object encodeValue(
    db.ModelDB mdb,
    Object value, {
    bool forComparison = false,
  }) =>
      json.encode((value as Map<String, PackageVersionState>).map(
        (version, state) => MapEntry(
          version,
          _$PackageVersionStateToJson(state),
        ),
      ));

  @override
  Object decodePrimitiveValue(
    db.ModelDB mdb,
    Object value,
  ) =>
      (json.decode(value as String) as Map<String, dynamic>).map(
        (version, state) => MapEntry(
          version,
          _$PackageVersionStateFromJson(state as Map<String, dynamic>),
        ),
      );

  @override
  bool validate(db.ModelDB mdb, Object value) =>
      super.validate(mdb, value) &&
      (value == null || value is Map<String, PackageVersionState>);
}
