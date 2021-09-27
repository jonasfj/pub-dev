// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Directory, File, gzip;
import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart';
import 'package:pub_worker/blob.dart' show IndexedBlobBuilder, BlobIndex;
import 'package:path/path.dart' as p;
import 'package:pub_worker/src/utils.dart' show streamToBuffer;

/// Pair containing and in-memory [blob] and matching [index].
@sealed
class BlobIndexPair {
  /// Blob indexed by [index].
  final Uint8List blob;

  /// Index pointing into [blob].
  final BlobIndex index;

  BlobIndexPair._(this.blob, this.index);

  /// Create a blob and [BlobIndex] with [blobId] containing all files and
  /// folders within [folder], encoded with paths relative to [folder].
  static Future<BlobIndexPair> folderToIndexedBlob(
    String blobId,
    String folder,
  ) async {
    final c = StreamController<List<int>>();

    Uint8List blob;
    BlobIndex index;

    await Future.wait([
      (() async => index = await _folderToIndexedBlob(c, blobId, folder))(),
      (() async => blob = await streamToBuffer(c.stream))(),
    ]);

    return BlobIndexPair._(blob, index);
  }
}

Future<BlobIndex> _folderToIndexedBlob(
  StreamSink<List<int>> blob,
  String blobId,
  String sourcePath,
) async {
  final b = IndexedBlobBuilder(blob);

  final files = Directory(sourcePath).list(recursive: true, followLinks: false);
  await for (final f in files) {
    if (f is File) {
      final path = p.relative(f.path, from: sourcePath);
      await b.addFile(path, f.openRead().transform(gzip.encoder));
    }
  }

  return await b.buildIndex(blobId);
}
