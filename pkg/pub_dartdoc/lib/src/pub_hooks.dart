// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
// ignore: implementation_imports
import 'package:analyzer/src/generated/sdk.dart';
// ignore: implementation_imports
import 'package:analyzer/src/generated/source.dart';
import 'package:dartdoc/dartdoc.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_dartdoc_data/blob.dart';
import 'package:watcher/watcher.dart';

const _defaultMaxFileCount = 10 * 1000 * 1000; // 10 million files
const _defaultMaxTotalLengthBytes = 2 * 1024 * 1024 * 1024; // 2 GiB

/// Thrown when current output exceeds limits.
class DocumentationTooBigException implements Exception {
  final String _message;
  DocumentationTooBigException(this._message);

  @override
  String toString() => 'DocumentationTooBigException: $_message';
}

/// Creates an overlay file system with binary file support on top
/// of the input sources.
///
/// TODO: Use a proper overlay in-memory filesystem with binary support,
///       instead of overriding file writes in the output path.
class PubResourceProvider implements ResourceProvider {
  final ResourceProvider _defaultProvider;
  final _memoryResourceProvider = MemoryResourceProvider();
  final int _maxFileCount;
  final int _maxTotalLengthBytes;
  String _outputPath;
  int _fileCount = 0;
  int _totalLengthBytes = 0;
  final _paths = <String>[];

  PubResourceProvider(
    this._defaultProvider, {
    int maxFileCount,
    int maxTotalLengthBytes,
  })  : _maxFileCount = maxFileCount ?? _defaultMaxFileCount,
        _maxTotalLengthBytes =
            maxTotalLengthBytes ?? _defaultMaxTotalLengthBytes;

  /// Writes in-memory files to disk.
  Future<void> writeFilesToDiskSync(String out) async {
    io.Directory(out).createSync(recursive: true);
    final b =
        IndexedBlobBuilder(io.File(p.join(out, 'doc-blob.blob')).openWrite());
    try {
      for (final path in _paths) {
        final r = _memoryResourceProvider.getResource(path);
        final c = r as File;
        final file = io.File(c.path);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(c.readAsBytesSync());

        await b.addFile(
          p.relative(path, from: out),
          Stream.value(io.gzip.encode(c.readAsBytesSync())),
        );
      }
    } finally {
      final index = await b.buildIndex('hello-world');
      io.File(p.join(out, 'doc-index.json')).writeAsBytesSync(index.asBytes());
    }
  }

  /// Checks if we have reached any file write limit before storing the bytes.
  void _aboutToWriteBytes(String path, int length) {
    _paths.add(path);
    _fileCount++;
    _totalLengthBytes += length;
    if (_fileCount > _maxFileCount) {
      throw DocumentationTooBigException(
          'Reached $_maxFileCount files in the output directory.');
    }
    if (_totalLengthBytes > _maxTotalLengthBytes) {
      throw DocumentationTooBigException(
          'Reached $_maxTotalLengthBytes bytes in the output directory.');
    }
  }

  void setConfig({
    @required String output,
  }) {
    _outputPath = output;
  }

  bool _isOutput(String path) {
    return _outputPath != null &&
        (path == _outputPath || p.isWithin(_outputPath, path));
  }

  ResourceProvider _rp(String path) =>
      _isOutput(path) ? _memoryResourceProvider : _defaultProvider;

  @override
  File getFile(String path) => _File(this, _rp(path).getFile(path));

  @override
  Folder getFolder(String path) => _rp(path).getFolder(path);

  @override
  Future<List<int>> getModificationTimes(List<Source> sources) async {
    // ignore: deprecated_member_use
    return _defaultProvider.getModificationTimes(sources);
  }

  @override
  Resource getResource(String path) => _rp(path).getResource(path);

  @override
  Folder getStateLocation(String pluginId) {
    return _defaultProvider.getStateLocation(pluginId);
  }

  @override
  p.Context get pathContext => _defaultProvider.pathContext;
}

class _File implements File {
  final PubResourceProvider _provider;
  final File _delegate;
  _File(this._provider, this._delegate);

  @override
  Stream<WatchEvent> get changes => _delegate.changes;

  @override
  File copyTo(Folder parentFolder) => _delegate.copyTo(parentFolder);

  @override
  Source createSource([Uri uri]) => _delegate.createSource(uri);

  @override
  void delete() => _delegate.delete();

  @override
  bool get exists => _delegate.exists;

  @override
  bool isOrContains(String path) => _delegate.isOrContains(path);

  @override
  int get lengthSync => _delegate.lengthSync;

  @override
  int get modificationStamp => _delegate.modificationStamp;

  @override
  Folder get parent => _delegate.parent2;

  @override
  Folder get parent2 => _delegate.parent2;

  @override
  String get path => _delegate.path;

  @override
  ResourceProvider get provider => _delegate.provider;

  @override
  List<int> readAsBytesSync() => _delegate.readAsBytesSync();

  @override
  String readAsStringSync() => _delegate.readAsStringSync();

  @override
  File renameSync(String newPath) => _delegate.renameSync(newPath);

  @override
  Resource resolveSymbolicLinksSync() => _delegate.resolveSymbolicLinksSync();

  @override
  String get shortName => _delegate.shortName;

  @override
  Uri toUri() => _delegate.toUri();

  @override
  void writeAsBytesSync(List<int> bytes) {
    _provider._aboutToWriteBytes(path, bytes.length);
    _delegate.writeAsBytesSync(bytes);
  }

  @override
  void writeAsStringSync(String content) {
    writeAsBytesSync(utf8.encode(content));
  }
}

/// Allows the override of [resourceProvider].
class PubPackageMetaProvider implements PackageMetaProvider {
  final PackageMetaProvider _delegate;
  final ResourceProvider _resourceProvider;

  PubPackageMetaProvider(this._delegate, this._resourceProvider);

  @override
  DartSdk get defaultSdk => _delegate.defaultSdk;

  @override
  Folder get defaultSdkDir => _delegate.defaultSdkDir;

  @override
  PackageMeta fromDir(Folder dir) => _delegate.fromDir(dir);

  @override
  PackageMeta fromElement(LibraryElement library, String s) =>
      _delegate.fromElement(library, s);

  @override
  PackageMeta fromFilename(String s) => _delegate.fromFilename(s);

  @override
  ResourceProvider get resourceProvider => _resourceProvider;

  @override
  String getMessageForMissingPackageMeta(
          LibraryElement library, DartdocOptionContext optionContext) =>
      _delegate.getMessageForMissingPackageMeta(library, optionContext);
}
