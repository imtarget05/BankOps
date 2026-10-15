import 'package:kho_tra_sua/src/core/util/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for CWE-1236 (CSV / spreadsheet formula injection).
///
/// A cell whose value begins with `=`, `+`, `@`, TAB or CR is interpreted as a
/// formula by Excel / Google Sheets when the CSV is pasted in. `CsvExport` must
/// neutralise those leads so exported data can never execute.
void main() {
  group('CsvExport — formula injection (CWE-1236)', () {
    test('prefixes a leading "=" so it is not a formula', () {
      expect(CsvExport.encode(['v'], [['=1+1']]), "v\n'=1+1\n");
    });

    test('prefixes a leading "@" formula', () {
      expect(CsvExport.encode(['v'], [['@SUM(A1:A9)']]), "v\n'@SUM(A1:A9)\n");
    });

    test('prefixes a leading "+"', () {
      expect(CsvExport.encode(['v'], [['+1']]), "v\n'+1\n");
    });

    test('prefixes a non-numeric "-" sum expression', () {
      expect(CsvExport.encode(['v'], [['-1+1']]), "v\n'-1+1\n");
    });

    test('neutralises the classic DDE payload', () {
      final csv = CsvExport.encode(['v'], [["=cmd|'/c calc'!A1"]]);
      expect(csv.startsWith("v\n'=cmd|"), isTrue, reason: csv);
    });

    test('prefixes a leading TAB', () {
      expect(CsvExport.encode(['v'], [['\tHIDDEN']]), "v\n'\tHIDDEN\n");
    });

    test('a neutralised cell is still quoted when it contains a comma', () {
      expect(CsvExport.encode(['v'], [['=a,b']]), "v\n\"'=a,b\"\n");
    });

    test('plain negative numbers are preserved (not mangled)', () {
      expect(CsvExport.encode(['v'], [[-1234]]), 'v\n-1234\n');
      expect(CsvExport.encode(['v'], [['-1000.50']]), 'v\n-1000.50\n');
    });

    test('ordinary values are untouched', () {
      expect(CsvExport.encode(['name'], [['Kho trung tâm']]), 'name\nKho trung tâm\n');
    });

    test('null becomes an empty cell', () {
      expect(CsvExport.encode(['a', 'b'], [[null, 'x']]), 'a,b\n,x\n');
    });

    test('pre-existing quoting rules still hold (comma + double quote)', () {
      expect(CsvExport.encode(['v'], [['a,b']]), 'v\n"a,b"\n');
      expect(CsvExport.encode(['v'], [['a"b']]), 'v\n"a""b"\n');
    });
  });
}
