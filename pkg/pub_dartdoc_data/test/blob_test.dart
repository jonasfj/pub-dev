import 'dart:convert';
import 'dart:io';
import 'package:pub_dartdoc_data/blob.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pub_worker-test-');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('Simple files in blob', () async {
    final blobFile = File('${tmp.path}/test.blob');

    final b = IndexedBlobBuilder(blobFile.openWrite());
    await b.addFile('README.md', Stream.value([0, 0]));
    await b.addFile('hello.txt', Stream.value([1, 2, 3, 4, 5]));
    await b.addFile('lib/src/test-a.dart', Stream.value([100]));
    await b.addFile('lib/src/test-b.dart', Stream.value([101]));

    final index = await b.buildIndex('42');

    expect(index.blobId, equals('42'));

    expect(
      () => index.lookup('missing-file'),
      throwsA(isA<FileRangeNotFoundException>()),
    );

    final blob = await blobFile.readAsBytes();
    void expectFile(String path, List<int> data) {
      final range = index.lookup(path);
      expect(blob.sublist(range.start, range.end), equals(data));
    }

    json.decode(utf8.decode(index.asBytes()));

    expectFile('README.md', [0, 0]);
    expectFile('hello.txt', [1, 2, 3, 4, 5]);
    expectFile('hello.txt', [1, 2, 3, 4, 5]);
    expectFile('lib/src/test-a.dart', [100]);
    expectFile('lib/src/test-b.dart', [101]);
  });
}
