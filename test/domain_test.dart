import 'package:flutter_test/flutter_test.dart';
import 'package:warmad_mobile/domain/calc.dart';
import 'package:warmad_mobile/domain/cycle.dart';
import 'package:warmad_mobile/domain/models.dart';

void main() {
  group('sistem siklus', () {
    test('bulan kalender: November 30, Desember 31, Februari 28', () {
      final cr = [CycleRule(n: 3, s: '2026-11-01', d: 1)];
      expect(cycSpan(3, cr)!.toString(),
          '{"s":"2026-11-01","e":"2026-11-30","len":30}');
      expect(cycSpan(4, cr)!.len, 31);
      expect(cycSpan(6, cr)!.len, 28);
      expect(cycleOfDate('2026-12-15', cr), 4);
      expect(cycleOfDate('2027-02-28', cr), 6);
      expect(cycleOfDate('2026-11-01', cr), 3);
    });

    test('serah tanggal 5: 5 Nov - 4 Des, lalu 5 Des - 4 Jan', () {
      final cr = [CycleRule(n: 2, s: '2026-11-05', d: 5)];
      expect(cycSpan(2, cr)!.toString(),
          '{"s":"2026-11-05","e":"2026-12-04","len":30}');
      expect(cycSpan(3, cr)!.toString(),
          '{"s":"2026-12-05","e":"2027-01-04","len":31}');
      expect(cycleOfDate('2026-12-04', cr), 2);
      expect(cycleOfDate('2026-12-05', cr), 3);
      expect(cycleOfDate('2026-11-03', cr), isNull);
    });

    test('mulai di tengah periode: siklus pertama lebih pendek', () {
      final cr = [CycleRule(n: 1, s: '2026-11-20', d: 5)];
      expect(cycSpan(1, cr)!.len, 15);
    });

    test('serah tanggal 31 di bulan pendek memakai hari terakhir', () {
      final cr = [CycleRule(n: 1, s: '2027-01-31', d: 31)];
      expect(cycSpan(1, cr)!.toString(),
          '{"s":"2027-01-31","e":"2027-02-27","len":28}');
      expect(cycSpan(2, cr)!.toString(),
          '{"s":"2027-02-28","e":"2027-03-30","len":31}');
    });

    test('tanpa aturan: 30 hari tetap manual', () {
      expect(cycSpan(1, []), isNull);
      expect(cycleOfDate('2026-11-10', []), isNull);
    });

    test('pindah dari 30 hari ke tanggal serah', () {
      final cr = [
        CycleRule(n: 1, s: '2026-10-01', d: 0),
        CycleRule(n: 3, s: '2026-11-05', d: 5),
      ];
      expect(cycSpan(2, cr), isNull);
      expect(cycleOfDate('2026-10-20', cr), isNull);
      expect(cycleOfDate('2026-11-10', cr), 3);
    });

    test('ganti tanggal serah: siklus lama dipotong sebelum aturan baru', () {
      final cr = [
        CycleRule(n: 1, s: '2026-10-05', d: 5),
        CycleRule(n: 2, s: '2026-11-01', d: 1),
      ];
      expect(cycSpan(1, cr)!.toString(),
          '{\"s\":\"2026-10-05\",\"e\":\"2026-10-31\",\"len\":27}');
      expect(cycleOfDate('2026-11-02', cr), 2);
    });
  });

  group('perhitungan bagi hasil', () {
    test('siklus 31 hari penuh: kontrak penuh, pemilik 1.005.000', () {
      final s = AppSettings(
        cr: [CycleRule(n: 3, s: '2026-11-01', d: 1)],
        pct: 10,
        kontrak: 300000,
        defMode: 'pemilik_1_karyawan',
        k1: 'Budi',
        k2: 'Sari',
      );
      final rs = List<OmRecord>.generate(
        31,
        (i) => OmRecord(
          date: '2026-12-${(i + 1).toString().padLeft(2, '0')}',
          cycle: 4,
          day: i + 1,
          omset: 400000,
        ),
      );
      final x = calc(4,
          records: rs,
          s: s,
          jm: {},
          cn: {},
          pg: {},
          ko: {},
          sk: {},
          today: '2026-12-31');

      expect(x.len, 31);
      expect(x.days, 31);
      expect(x.ended, isTrue);
      expect(x.kontrak, 300000);
      expect(x.tab, 1240000);
      expect(x.bossT.round(), 1005000);
      expect(x.guards.single.total.round(), 235000);
    });

    test('gaji prorata memakai panjang siklus bulan berjalan', () {
      final s = AppSettings(
        cr: [CycleRule(n: 7, s: '2026-12-01', d: 1)],
        pct: 10,
        kontrak: 300000,
        defMode: 'pemilik_1_karyawan',
      );
      final rs = List<OmRecord>.generate(
        10,
        (i) => OmRecord(
          date: '2026-12-${(i + 1).toString().padLeft(2, '0')}',
          cycle: 7,
          day: i + 1,
          omset: 100000,
        ),
      );
      final x = calc(7,
          records: rs,
          s: s,
          jm: {7: 'suami_istri_gaji'},
          cn: {},
          pg: {
            7: CustomGuards(
              pp: 50,
              list: const [Guard(n: 'Sari', t: 'gaji', g: 3000000)],
            )
          },
          ko: {},
          sk: {},
          today: '2026-12-15');

      expect(x.len, 31);
      expect(x.ended, isFalse);
      expect((x.gajiTotal - 3000000 * 10 / 31).abs(), lessThan(1));
      expect(x.mode, 'suami_istri_gaji');
      expect(x.guards.single.n, 'Sari');
    });
  });
}
