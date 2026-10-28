import 'package:flutter_test/flutter_test.dart';
import 'package:flatsphere/backend/bulk_import.dart';
import 'package:flatsphere/models/models.dart';

void main() {
  test('parseCsv handles quotes, commas, CRLF and BOM', () {
    final rows = parseCsv('\uFEFFa,b\r\n"x, y","he said ""hi"""\n\n1,2');
    expect(rows, [
      ['a', 'b'],
      ['x, y', 'he said "hi"'],
      ['1', '2'],
    ]);
  });

  test('toCsv neutralises spreadsheet formulas and round-trips', () {
    final csv = toCsv(['n'], [
      ['=SUM(A1)'],
      ['-5'],
    ]);
    expect(csv, contains("\"'=SUM(A1)\""));
    expect(parseCsv(csv).last, ['-5']);
  });

  test('flats import validates rows', () {
    final rows = parseFlatsCsv(
      'number,block,sqft,occupancy,car_number\nA-1,A,1000,rented,KL07AB1\nA-1,A,,,\nB-2,B,abc,,\nC-3,C,,weird,\n',
    );
    expect(rows[0].value!.occupancy, Occupancy.rented);
    expect(rows[0].value!.carNumber, 'KL07AB1');
    expect(rows[1].error, contains('Duplicate'));
    expect(rows[2].error, contains('sqft'));
    expect(rows[3].error, contains('occupancy'));
  });

  test('members import validates rows and required columns', () {
    final rows = parseMembersCsv(
      'full_name,email,role,flat_number\nAsha,asha@x.com,owner,A-1\nBad,nope,owner,A-1\nNo Flat,n@x.com,resident,\nBoss,b@x.com,admin,\nSec,s@x.com,Joint Secretary,\n',
    );
    expect(rows[0].value!.role, Role.owner);
    expect(rows[1].error, 'Invalid email');
    expect(rows[2].error, contains('flat_number'));
    expect(rows[3].error, contains('Admin'));
    expect(rows[4].value!.role, Role.jointSecretary);
    expect(() => parseMembersCsv('full_name,email\nA,a@x.com'), throwsFormatException);
  });
}
