import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatsphere/backend/export_bundle.dart';

void main() {
  test('export zip has a csv per table, json and readme', () {
    final zip = ZipDecoder().decodeBytes(
      buildExportZip({
        'association': {'id': 'a1', 'name': 'Test'},
        'flats': [
          {'id': 'f1', 'number': 'A-1'},
          {'id': 'f2', 'number': 'A-2', 'sqft': 900},
        ],
        'empty': [],
        'exported_at': '2026-01-01',
      }),
    );
    final names = zip.files.map((f) => f.name).toList();
    expect(names, containsAll(['csv/flats.csv', 'csv/association.csv', 'data.json', 'README.txt']));
    expect(names.contains('csv/empty.csv'), isFalse);
    final flats = utf8.decode(zip.findFile('csv/flats.csv')!.content as List<int>);
    expect(flats.split('\r\n').first, '"id","number","sqft"');
    expect(flats, contains('"900"'));
  });
}
