// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:gcloud/db.dart' as db;
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

part 'models.g.dart';

final _uuid = Uuid();

abstract class HistorySource {
  static const String account = 'account';
  static const String analyzer = 'analyzer';
  static const String dartdoc = 'dartdoc';
}

@db.Kind(name: 'History', idType: db.IdType.String)
class History extends db.ExpandoModel {
  History();

  History._({
    this.packageName,
    this.packageVersion,
    this.timestamp,
    this.source,
    HistoryEvent event,
  }) {
    id = _uuid.v4();
    timestamp ??= DateTime.now().toUtc();
    historyEvent = event;
  }

  factory History.entry(HistoryEvent event) {
    return History._(
      packageName: event.packageName,
      packageVersion: event.packageVersion ?? '*',
      timestamp: event.timestamp,
      source: event.source,
      event: event,
    );
  }

  @db.StringProperty(required: true)
  String packageName;

  @db.StringProperty()
  String packageVersion;

  /// The timestamp of the entry.
  @db.DateTimeProperty()
  DateTime timestamp;

  @db.StringProperty(required: true)
  String source;

  @db.StringProperty(required: true)
  String eventType;

  @db.StringProperty()
  String eventJson;

  Map<String, dynamic> get eventData =>
      json.decode(eventJson) as Map<String, dynamic>;
  set eventData(Map<String, dynamic> value) {
    eventJson = json.encode(value);
  }

  HistoryUnion get historyUnion =>
      HistoryUnion.fromJson({eventType: eventData});

  HistoryEvent get historyEvent => historyUnion.event;
  set historyEvent(HistoryEvent event) {
    final union = HistoryUnion.ofEvent(event);
    final map = union.toJson();
    eventType = map.keys.single;
    eventData = map.values.single as Map<String, dynamic>;
  }

  String formatMarkdown() => historyEvent?.formatMarkdown();
}

abstract class HistoryEvent {
  String get source;
  String get packageName;
  String get packageVersion;
  DateTime get timestamp;
  String formatMarkdown();
  HistoryEvent migrateUser(
      String fromUserId, String fromEmail, String toUserId, String toEmail);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class HistoryUnion {
  final PackageUploaded packageUploaded;
  final UploaderChanged uploaderChanged;
  final UploaderInvited uploaderInvited;
  final AnalysisCompleted analysisCompleted;

  HistoryUnion({
    this.packageUploaded,
    this.uploaderChanged,
    this.uploaderInvited,
    this.analysisCompleted,
  }) {
    assert(_items.where((x) => x != null).length == 1);
  }

  factory HistoryUnion.ofEvent(HistoryEvent event) {
    if (event is PackageUploaded) {
      return HistoryUnion(packageUploaded: event);
    } else if (event is UploaderChanged) {
      return HistoryUnion(uploaderChanged: event);
    } else if (event is UploaderInvited) {
      return HistoryUnion(uploaderInvited: event);
    } else if (event is AnalysisCompleted) {
      return HistoryUnion(analysisCompleted: event);
    } else {
      throw ArgumentError('Unknown type: ${event.runtimeType}');
    }
  }

  factory HistoryUnion.fromJson(Map<String, dynamic> json) =>
      _$HistoryUnionFromJson(json);

  List<HistoryEvent> get _items {
    return <HistoryEvent>[
      packageUploaded,
      uploaderChanged,
      uploaderInvited,
      analysisCompleted,
    ];
  }

  HistoryEvent get event => _items.firstWhere((x) => x != null);

  Map<String, dynamic> toJson() => _$HistoryUnionToJson(this);
}

@JsonSerializable()
class PackageUploaded implements HistoryEvent {
  @override
  final String packageName;
  @override
  final String packageVersion;
  final String uploaderId;
  final String uploaderEmail;
  @override
  final DateTime timestamp;

  PackageUploaded({
    @required this.packageName,
    @required this.packageVersion,
    @required this.uploaderId,
    @required this.uploaderEmail,
    DateTime timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().toUtc();

  factory PackageUploaded.fromJson(Map<String, dynamic> json) =>
      _$PackageUploadedFromJson(json);

  @override
  String get source => HistorySource.account;

  @override
  String formatMarkdown() {
    return 'Version $packageVersion was uploaded by `$uploaderEmail`.';
  }

  Map<String, dynamic> toJson() => _$PackageUploadedToJson(this);

  @override
  HistoryEvent migrateUser(
      String fromUserId, String fromEmail, String toUserId, String toEmail) {
    return PackageUploaded(
      packageName: packageName,
      packageVersion: packageVersion,
      uploaderId: _changeValue(uploaderId, fromUserId, toUserId),
      uploaderEmail: _changeValue(uploaderEmail, fromEmail, toEmail),
      timestamp: timestamp,
    );
  }
}

@JsonSerializable(includeIfNull: false)
class UploaderChanged implements HistoryEvent {
  @override
  final String packageName;
  final String currentUserId;
  final String currentUserEmail;
  final List<String> addedUploaderIds;
  final List<String> addedUploaderEmails;
  final List<String> removedUploaderIds;
  final List<String> removedUploaderEmails;
  @override
  final DateTime timestamp;

  UploaderChanged({
    @required this.packageName,
    @required this.currentUserId,
    @required this.currentUserEmail,
    this.addedUploaderIds,
    this.addedUploaderEmails,
    this.removedUploaderIds,
    this.removedUploaderEmails,
    DateTime timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().toUtc();

  @override
  String get packageVersion => null;

  factory UploaderChanged.fromJson(Map<String, dynamic> json) =>
      _$UploaderChangedFromJson(json);

  @override
  String get source => HistorySource.account;

  @override
  String formatMarkdown() {
    final changes = <String>[];
    if (addedUploaderEmails != null && addedUploaderEmails.isNotEmpty) {
      final emails = addedUploaderEmails.map((e) => '`$e`').join(', ');
      changes.add('added $emails');
    }
    if (removedUploaderEmails != null && removedUploaderEmails.isNotEmpty) {
      final emails = removedUploaderEmails.map((e) => '`$e`').join(', ');
      changes.add('removed $emails');
    }
    final actor = (currentUserEmail != null && currentUserEmail.isNotEmpty)
        ? currentUserEmail
        : 'A site administrator';
    return '$actor has changed uploaders: ${changes.join(' and ')}.';
  }

  Map<String, dynamic> toJson() => _$UploaderChangedToJson(this);

  @override
  HistoryEvent migrateUser(
      String fromUserId, String fromEmail, String toUserId, String toEmail) {
    List<String> mapUserIds(List<String> list) =>
        list?.map((s) => _changeValue(s, fromUserId, toUserId))?.toList();
    List<String> mapEmails(List<String> list) =>
        list?.map((s) => _changeValue(s, fromEmail, toEmail))?.toList();
    return UploaderChanged(
      packageName: packageName,
      currentUserId: _changeValue(currentUserId, fromUserId, toUserId),
      currentUserEmail: _changeValue(currentUserEmail, fromEmail, toEmail),
      addedUploaderIds: mapUserIds(addedUploaderIds),
      addedUploaderEmails: mapEmails(addedUploaderEmails),
      removedUploaderIds: mapUserIds(removedUploaderIds),
      removedUploaderEmails: mapEmails(removedUploaderIds),
    );
  }
}

@JsonSerializable(includeIfNull: false)
class UploaderInvited implements HistoryEvent {
  @override
  final String packageName;
  final String currentUserId;
  final String currentUserEmail;
  final String uploaderUserEmail;
  @override
  final DateTime timestamp;

  UploaderInvited({
    @required this.packageName,
    @required this.currentUserId,
    @required this.currentUserEmail,
    @required this.uploaderUserEmail,
    DateTime timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().toUtc();

  factory UploaderInvited.fromJson(Map<String, dynamic> json) =>
      _$UploaderInvitedFromJson(json);

  @override
  String get packageVersion => null;

  @override
  String get source => HistorySource.account;

  @override
  String formatMarkdown() {
    return '`$currentUserEmail` invited `$uploaderUserEmail` to be an uploader.';
  }

  Map<String, dynamic> toJson() => _$UploaderInvitedToJson(this);

  @override
  HistoryEvent migrateUser(
      String fromUserId, String fromEmail, String toUserId, String toEmail) {
    return UploaderInvited(
      packageName: packageName,
      currentUserId: _changeValue(currentUserId, fromUserId, toUserId),
      currentUserEmail: _changeValue(currentUserEmail, fromEmail, toEmail),
      uploaderUserEmail: _changeValue(uploaderUserEmail, fromEmail, toEmail),
      timestamp: timestamp,
    );
  }
}

@JsonSerializable()
class AnalysisCompleted implements HistoryEvent {
  @override
  final String packageName;
  @override
  final String packageVersion;
  final bool hasErrors;
  final bool hasPlatforms;
  @override
  final DateTime timestamp;

  AnalysisCompleted({
    @required this.packageName,
    @required this.packageVersion,
    @required this.hasErrors,
    @required this.hasPlatforms,
    DateTime timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now().toUtc();

  factory AnalysisCompleted.fromJson(Map<String, dynamic> json) =>
      _$AnalysisCompletedFromJson(json);

  @override
  String get source => HistorySource.analyzer;

  @override
  String formatMarkdown() {
    if (hasErrors) {
      return 'Analysis of `package:$packageName` failed.';
    } else if (hasPlatforms) {
      return 'Analysis of `package:$packageName` completed successful.';
    } else {
      return 'Analysis of `package:$packageName` completed, but no platform has been identified.';
    }
  }

  Map<String, dynamic> toJson() => _$AnalysisCompletedToJson(this);

  @override
  HistoryEvent migrateUser(
      String fromUserId, String fromEmail, String toUserId, String toEmail) {
    return this;
  }
}

String _changeValue(String value, String from, String to) {
  return value == from ? to : value;
}
