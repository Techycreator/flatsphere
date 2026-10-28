import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'bulk_import.dart';

/// Turns the association export (JSON) into a ZIP: one CSV per table, the full JSON, and a README.
Uint8List buildExportZip(Map<String, dynamic> data, {DateTime? now}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final tables = <String, int>{};
  for (final entry in data.entries) {
    final v = entry.value;
    final List<Map<String, dynamic>> rows = switch (v) {
      List l => [for (final r in l) if (r is Map) Map<String, dynamic>.from(r)],
      Map m when entry.key == 'association' => [Map<String, dynamic>.from(m)],
      _ => const [],
    };
    if (rows.isEmpty) continue;
    final columns = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!columns.contains(k)) columns.add(k);
      }
    }
    add(
      'csv/${entry.key}.csv',
      toCsv(columns, [for (final r in rows) [for (final c in columns) stringifyCell(r[c])]]),
    );
    tables[entry.key] = rows.length;
  }
  add('data.json', const JsonEncoder.withIndent(' ').convert(data));
  add(
    'README.txt',
    [
      'Flatsphere association export',
      'Exported at: ${(now ?? DateTime.now()).toIso8601String()}',
      '',
      'csv/   One UTF-8 CSV file per table (header row = column names). IDs are UUIDs and link tables together',
      '       (for example flat_id points to the id column in flats.csv). Nested values are stored as JSON text.',
      'data.json   The same data in one JSON file.',
      '',
      'Not included: uploaded files (photos, voice notes, documents), ID proofs, the audit log and passwords.',
      'Download those separately from the app before the association is closed.',
      '',
      'Tables and row counts:',
      for (final e in tables.entries) '  ${e.key}: ${e.value}',
    ].join('\n'),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
