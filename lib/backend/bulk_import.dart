import 'dart:convert';

import '../models/models.dart';
import 'backend.dart' show roleFromDb;

const flatsTemplateHeader = ['number', 'block', 'type', 'sqft', 'occupancy', 'car_number', 'bike_number', 'parking_slot'];
const membersTemplateHeader = ['full_name', 'email', 'mobile', 'role', 'flat_number'];

const flatsTemplateSample = [
  ['A-101', 'A', '2BHK', '1050', 'owner_occupied', 'KL07AB1234', '', 'P-12'],
];
const membersTemplateSample = [
  ['Asha Nair', 'asha@example.com', '9876543210', 'owner', 'A-101'],
  ['Ravi Kumar', 'ravi@example.com', '9876500000', 'resident', 'A-101'],
];

String csvCell(String value) {
  // Leading = + - @ would run as a formula in spreadsheets; the prefix keeps the cell as text.
  final safe = RegExp(r'^[=+\-@]').hasMatch(value) && double.tryParse(value) == null ? "'$value" : value;
  return '"${safe.replaceAll('"', '""')}"';
}

String toCsv(List<String> header, Iterable<List<String>> rows) =>
    [header, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n');

String stringifyCell(Object? v) => switch (v) {
  null => '',
  String s => s,
  num _ || bool _ => '$v',
  _ => jsonEncode(v),
};

/// RFC 4180 style parser: quoted cells, doubled quotes, CRLF or LF, optional BOM.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var started = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
    started = false;
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"' && !started) {
      quoted = true;
      started = true;
    } else if (c == ',') {
      endCell();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(c);
      started = true;
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

class ImportRow<T> {
  const ImportRow(this.line, this.value, this.error);
  final int line;
  final T? value;
  final String? error;
}

List<Map<String, String>> _records(String csv, List<String> required, List<String> optional) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) throw const FormatException('The file is empty');
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  final missing = [for (final h in required) if (!header.contains(h)) h];
  if (missing.isNotEmpty) throw FormatException('Missing column(s): ${missing.join(', ')}');
  return [
    for (final r in rows.skip(1))
      {for (var i = 0; i < header.length; i++) header[i]: i < r.length ? r[i].trim() : ''},
  ];
}

const maxImportRows = 500;

List<ImportRow<FlatInfo>> parseFlatsCsv(String csv) {
  final records = _records(csv, const ['number'], flatsTemplateHeader);
  if (records.length > maxImportRows) throw const FormatException('At most $maxImportRows rows per file');
  final seen = <String>{};
  return [
    for (var i = 0; i < records.length; i++) _flatRow(i + 2, records[i], seen),
  ];
}

ImportRow<FlatInfo> _flatRow(int line, Map<String, String> r, Set<String> seen) {
  final number = r['number'] ?? '';
  if (number.isEmpty || number.length > 24) return ImportRow(line, null, 'Flat number is required (max 24 characters)');
  if (!seen.add(number.toLowerCase())) return ImportRow(line, null, 'Duplicate flat number $number in the file');
  final sqftText = r['sqft'] ?? '';
  final sqft = sqftText.isEmpty ? null : int.tryParse(sqftText);
  if (sqftText.isNotEmpty && (sqft == null || sqft <= 0)) return ImportRow(line, null, 'sqft must be a whole number');
  final occ = switch ((r['occupancy'] ?? '').toLowerCase().replaceAll(' ', '_')) {
    '' || 'owner_occupied' || 'owner' => Occupancy.ownerOccupied,
    'rented' || 'tenant' => Occupancy.rented,
    'vacant' => Occupancy.vacant,
    _ => null,
  };
  if (occ == null) return ImportRow(line, null, 'occupancy must be owner_occupied, rented or vacant');
  String? opt(String k) => (r[k] ?? '').isEmpty ? null : r[k];
  return ImportRow(
    line,
    FlatInfo(
      number: number,
      block: r['block'] ?? '',
      type: (r['type'] ?? '').isEmpty ? '2BHK' : r['type']!,
      sqft: sqft,
      occupancy: occ,
      carNumber: opt('car_number'),
      bikeNumber: opt('bike_number'),
      parkingSlot: opt('parking_slot'),
    ),
    null,
  );
}

List<ImportRow<Person>> parseMembersCsv(String csv) {
  final records = _records(csv, const ['full_name', 'email', 'role'], membersTemplateHeader);
  if (records.length > maxImportRows) throw const FormatException('At most $maxImportRows rows per file');
  final seen = <String>{};
  return [
    for (var i = 0; i < records.length; i++) _memberRow(i + 2, records[i], seen),
  ];
}

ImportRow<Person> _memberRow(int line, Map<String, String> r, Set<String> seen) {
  final name = r['full_name'] ?? '';
  final email = (r['email'] ?? '').toLowerCase();
  if (name.isEmpty) return ImportRow(line, null, 'Name is required');
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return ImportRow(line, null, 'Invalid email');
  final role = roleFromDb((r['role'] ?? '').toLowerCase().replaceAll(' ', '_'));
  if (role == null) return ImportRow(line, null, 'Unknown role "${r['role']}"');
  if (role == Role.admin) return ImportRow(line, null, 'The Admin role cannot be imported');
  final flat = r['flat_number'] ?? '';
  if ((role == Role.owner || role == Role.resident) && flat.isEmpty) {
    return ImportRow(line, null, 'flat_number is required for owners and residents');
  }
  if (!seen.add('$email|${role.name}|${flat.toLowerCase()}')) return ImportRow(line, null, 'Duplicate row in the file');
  return ImportRow(
    line,
    Person(id: '', name: name, email: email, role: role, mobile: r['mobile'], flatNumber: flat.isEmpty ? null : flat),
    null,
  );
}
