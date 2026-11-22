// Model data inti yang dipakai bersama seluruh aplikasi.
/// Sumber: index.html (Omset-WarMad v4.0.4).

class CycleRule {
  final int n; // siklus pertama yang memakai aturan ini
  final String s; // tanggal mulai (yyyy-MM-dd)
  final int d; // tanggal serah 1..31; 0 = 30 hari tetap

  const CycleRule({required this.n, required this.s, required this.d});

  factory CycleRule.fromJson(Map<String, dynamic> j) => CycleRule(
        n: (j['n'] as num).toInt(),
        s: j['s'] as String,
        d: (j['d'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'n': n, 's': s, 'd': d};
}

class OmRecord {
  final String date;
  final int cycle;
  final int day;
  final double omset;
  final String expense;

  const OmRecord({
    required this.date,
    required this.cycle,
    required this.day,
    required this.omset,
    this.expense = '',
  });

  factory OmRecord.fromJson(Map<String, dynamic> j) => OmRecord(
        date: j['date'] as String,
        cycle: (j['cycle'] as num).toInt(),
        day: (j['day'] as num).toInt(),
        omset: (j['omset'] as num).toDouble(),
        expense: (j['expense'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'cycle': cycle,
        'day': day,
        'omset': omset,
        'expense': expense,
      };
}

class CycleStok {
  final double? awal;
  final double? akhir;
  final String note;

  const CycleStok({this.awal, this.akhir, this.note = ''});

  factory CycleStok.fromJson(Map<String, dynamic> j) => CycleStok(
        awal: j['awal'] == null || j['awal'] == ''
            ? null
            : (j['awal'] as num).toDouble(),
        akhir: j['akhir'] == null || j['akhir'] == ''
            ? null
            : (j['akhir'] as num).toDouble(),
        note: (j['note'] as String?) ?? '',
      );
}

class Guard {
  final String n;
  final String t; // 'bagi' | 'gaji'
  final double g;

  const Guard({required this.n, required this.t, required this.g});

  Map<String, dynamic> toJson() => {'n': n, 't': t, 'g': g};
}

class CustomGuards {
  final double pp; // porsi pemilik dari bagi hasil (%)
  final List<Guard> list;

  const CustomGuards({required this.pp, required this.list});

  factory CustomGuards.fromJson(Map<String, dynamic> j) => CustomGuards(
        pp: j['pp'] == null || j['pp'] == ''
            ? 50
            : (j['pp'] as num).toDouble().clamp(0, 100).toDouble(),
        list: ((j['list'] as List?) ?? [])
            .map((e) => Guard(
                  n: ((e['n'] as String?) ?? '').trim().isEmpty
                      ? 'Penjaga'
                      : (e['n'] as String).trim(),
                  t: e['t'] == 'gaji' ? 'gaji' : 'bagi',
                  g: e['g'] == null ? 0.0 : (e['g'] as num).toDouble(),
                ))
            .toList(),
      );
}

class AppSettings {
  List<CycleRule> cr;
  String nama;
  int pct;
  int kontrak;
  String defMode;
  String k1;
  String k2;

  AppSettings({
    List<CycleRule>? cr,
    this.nama = 'Warung Saya',
    this.pct = 10,
    this.kontrak = 0,
    this.defMode = 'pemilik_1_karyawan',
    this.k1 = 'Karyawan 1',
    this.k2 = 'Karyawan 2',
  }) : cr = cr ?? <CycleRule>[];

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        cr: ((j['cr'] as List?) ?? [])
            .map((e) => CycleRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        nama: (j['nama'] as String?) ?? 'Warung Saya',
        pct: (j['pct'] as num?)?.toInt() ?? 10,
        kontrak: (j['kontrak'] as num?)?.toInt() ?? 0,
        defMode: (j['defMode'] as String?) ?? 'pemilik_1_karyawan',
        k1: (j['k1'] as String?) ?? 'Karyawan 1',
        k2: (j['k2'] as String?) ?? 'Karyawan 2',
      );

  Map<String, dynamic> toJson() => {
        'cr': cr.map((e) => e.toJson()).toList(),
        'nama': nama,
        'pct': pct,
        'kontrak': kontrak,
        'defMode': defMode,
        'k1': k1,
        'k2': k2,
      };
}

class CycleSpan {
  final String s;
  final String e;
  final int len;

  const CycleSpan(this.s, this.e, this.len);

  @override
  String toString() => '{"s":"$s","e":"$e","len":$len}';
}
