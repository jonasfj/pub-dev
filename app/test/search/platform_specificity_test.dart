// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import 'package:pub_dartlang_org/search/index_simple.dart';
import 'package:pub_dartlang_org/search/platform_specificity.dart';
import 'package:pub_dartlang_org/search/search_service.dart';
import 'package:pub_dartlang_org/shared/platform.dart';

void main() {
  group('specificity score', () {
    final String empty = null;
    final String flutter = 'flutter';
    final String web = 'web';
    final String other = 'other';

    test('empty or null values', () {
      expect(scorePlatformSpecificity(null, empty), 1.0);
      expect(scorePlatformSpecificity([], empty), 1.0);
      expect(scorePlatformSpecificity([], null), 1.0);
      expect(scorePlatformSpecificity([], flutter), 0.8);
      expect(scorePlatformSpecificity([], other), 0.9);
      expect(scorePlatformSpecificity([], web), 0.9);
    });

    test('single', () {
      expect(scorePlatformSpecificity(['flutter'], null), 1.0);
      expect(scorePlatformSpecificity(['flutter'], flutter), 1.0);
      expect(scorePlatformSpecificity(['other'], other), 0.95);
      expect(scorePlatformSpecificity(['web'], web), 1.0);
    });

    test('two platforms', () {
      expect(scorePlatformSpecificity(['flutter', 'other'], null), 1.0);
      expect(scorePlatformSpecificity(['flutter', 'other'], flutter), 0.9);
      expect(scorePlatformSpecificity(['flutter', 'other'], other), 1.0);
      expect(scorePlatformSpecificity(['flutter', 'other'], web), 0.95);
    });

    test('all platforms', () {
      expect(scorePlatformSpecificity(KnownPlatforms.all, null), 1.0);
      expect(scorePlatformSpecificity(KnownPlatforms.all, flutter), 0.8);
      expect(scorePlatformSpecificity(KnownPlatforms.all, other), 0.95);
      expect(scorePlatformSpecificity(KnownPlatforms.all, web), 0.9);
    });
  });

  group('platform rank', () {
    SimplePackageIndex index;

    setUpAll(() async {
      index = SimplePackageIndex();
      await index.addPackage(PackageDocument(
        package: 'json_0',
      ));
      await index.addPackage(PackageDocument(
        package: 'json_1',
        platforms: ['flutter'],
      ));
      await index.addPackage(PackageDocument(
        package: 'json_2',
        platforms: ['flutter', 'other'],
      ));
      await index.addPackage(PackageDocument(
        package: 'json_3',
        platforms: KnownPlatforms.all,
      ));
      await index.merge();
    });

    test('text search without platform', () async {
      final PackageSearchResult withoutPlatform =
          await index.search(SearchQuery.parse(query: 'json'));
      expect(json.decode(json.encode(withoutPlatform)), {
        'indexUpdated': isNotNull,
        'totalCount': 4,
        'packages': [
          {
            'package': 'json_0',
            'score': closeTo(0.29, 0.01),
          },
          {
            'package': 'json_1',
            'score': closeTo(0.29, 0.01),
          },
          {
            'package': 'json_2',
            'score': closeTo(0.29, 0.01),
          },
          {
            'package': 'json_3',
            'score': closeTo(0.29, 0.01),
          },
        ],
      });
    });

    test('text search with platform', () async {
      final PackageSearchResult withPlatform =
          await index.search(SearchQuery.parse(
        query: 'json',
        platform: 'flutter',
      ));
      expect(json.decode(json.encode(withPlatform)), {
        'indexUpdated': isNotNull,
        'totalCount': 3,
        'packages': [
          {
            'package': 'json_1',
            'score': closeTo(0.2967, 0.0001),
          },
          {
            'package': 'json_2',
            'score': closeTo(0.2670, 0.0001),
          },
          {
            'package': 'json_3',
            'score': closeTo(0.2374, 0.0001),
          },
        ],
      });
    });
  });
}
