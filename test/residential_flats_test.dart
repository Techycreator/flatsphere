import 'package:flatsphere/backend/attendance_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner with two flats in association A and one in B sees only A flats, once each', () {
    final rows = [
      {'flat_id': 'f1', 'association_id': 'A', 'flats': {'number': '3D'}},
      {'flat_id': 'f2', 'association_id': 'A', 'flats': {'number': '4B'}},
      {'flat_id': 'f2', 'association_id': 'A', 'flats': {'number': '4B'}},
      {'flat_id': 'f3', 'association_id': 'B', 'flats': {'number': 'A-102'}},
      {'flat_id': null, 'association_id': 'A', 'flats': null},
    ];
    expect(AttendanceRepo.residentialFlatsFrom(rows, 'A'), [('f1', '3D'), ('f2', '4B')]);
    expect(AttendanceRepo.residentialFlatsFrom(rows, 'B'), [('f3', 'A-102')]);
  });
}
