// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'payload.g.dart';

/// JSON payload given as single argument to the `pub_worker.dart` command.
@JsonSerializable()
class Payload {
  /// Package name of the package to be processed.
  final String package;

  /// Base URL for doing callbacks to the default service.
  ///
  /// This property should not end in a slash.
  ///
  /// The [callback] URL should work in the following requests:
  ///  * `POST <callback>/api/tasks/<package>/<version>/upload`
  ///  * `POST <callback>/api/tasks/<package>/<version>/finished`
  ///
  /// These requests must be authenticated with: `authorization: bearer <token>`.
  /// Using the `<token>` matching the `<version>` being reported.
  final String callback;

  /// Lists of (`version`, `token`) for versions to process.
  final List<VersionTokenPair> versions;

  // json_serializable boiler-plate
  Payload({
    @required this.package,
    @required this.callback,
    @required this.versions,
  });
  factory Payload.fromJson(Map<String, dynamic> json) =>
      _$PayloadFromJson(json);
  Map<String, dynamic> toJson() => _$PayloadToJson(this);
}

/// Pair of [version] and [token].
@JsonSerializable()
class VersionTokenPair {
  /// Version of [Payload.package] to be processed.
  final String version;

  /// Secret token for authenticating `/upload` and `/finished` API callbacks
  /// for [version].
  ///
  /// The [token] is attached to requests using:
  /// `authorization: bearer <token>`.
  final String token;

  // json_serializable boiler-plate
  VersionTokenPair({
    @required this.version,
    @required this.token,
  });
  factory VersionTokenPair.fromJson(Map<String, dynamic> json) =>
      _$VersionTokenPairFromJson(json);
  Map<String, dynamic> toJson() => _$VersionTokenPairToJson(this);
}
