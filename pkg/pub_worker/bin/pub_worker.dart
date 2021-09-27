// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show json;
import 'dart:io' show exit;

import 'package:pub_worker/payload.dart';
import 'package:pub_worker/src/analyze.dart' show analyze;

void _printUsage() => print('Usage: pub_worker.dart <JSON_PAYLOAD>');

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    _printUsage();
    exit(1);
  }
  Payload payload;
  try {
    payload = Payload.fromJson(
      json.decode(args.first) as Map<String, Object>,
    );
  } on FormatException {
    _printUsage();
    exit(1);
  }
  await analyze(payload);
}
