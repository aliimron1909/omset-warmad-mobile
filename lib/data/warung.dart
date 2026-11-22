// Satu warung dengan seluruh data lokalnya.
/// Kunci JSON mengikuti nama kolom di api/sync.js agar bisa dikirim apa adanya.
import '../domain/models.dart';

Map<int, T> _intKeyMap<T>(dynamic raw, T Function(dynamic) conv) {
  final out = <int, T>{};
  if (raw is! Map) return out;
  raw.forEach((k, v) {
    final n = int.tryParse(k.toString());
    if (n == null || v == null) return;
    out[n] = conv(v);
  });
  return out;
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : {});

Map<String, dynamic> _stringifyIntKeys<T>(
        Map<int, T> src, dynamic Function(T) conv) =>
    src.map((k, v) => MapEntry(k.toString(), conv(v)));

class WarungData {
  String id;
  AppSettings settings;
  List<OmRecord> records;
  Map<int, String> kontrakOptions;
  Map<int, String> jagaModes;
  Map<int, Map<String, String>> cycleNames;
  Map<int, CycleStok> cycleStok;
  Map<int, CustomGuards> cyclePenjaga;

  WarungData({
    required this.id,
    AppSettings? settings,
    List<OmRecord>? records,
    Map<int, String>? kontrakOptions,
    Map<int, String>? jagaModes,
    Map<int, Map<String, String>>? cycleNames,
    Map<int, CycleStok>? cycleStok,
    Map<int, CustomGuards>? cyclePenjaga,
  })  : settings = settings ?? AppSettings(),
        records = records ?? <OmRecord>[],
        kontrakOptions = kontrakOptions ?? <int, String>{},
        jagaModes = jagaModes ?? <int, String>{},
        cycleNames = cycleNames ?? <int, Map<String, String>>{},
        cycleStok = cycleStok ?? <int, CycleStok>{},
        cyclePenjaga = cyclePenjaga ?? <int, CustomGuards>{};

  factory WarungData.fromJson(Map<String, dynamic> j) {
    final names = _intKeyMap<Map<String, String>>(j['cycleNames'], (v) {
      final m = _asMap(v);
      return {
        'k1': (m['k1'] as String?) ?? '',
        'k2': (m['k2'] as String?) ?? '',
      };
    });
    return WarungData(
      id: (j['id'] as String?) ?? 'w1',
      settings: AppSettings.fromJson(
          (j['settings'] as Map?)?.cast<String, dynamic>() ?? {}),
      records: ((j['records'] as List?) ?? [])
          .map((e) => OmRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      kontrakOptions: _intKeyMap<String>(
          j['cycleKontrakOptions'], (v) => v.toString()),
      jagaModes: _intKeyMap<String>(j['cycleJagaModes'], (v) => v.toString()),
      cycleNames: names,
      cycleStok: _intKeyMap<CycleStok>(
          j['cycleStok'], (v) => CycleStok.fromJson(_asMap(v))),
      cyclePenjaga: _intKeyMap<CustomGuards>(
          j['cyclePenjaga'], (v) => CustomGuards.fromJson(_asMap(v))),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'settings': settings.toJson(),
        'records': records.map((e) => e.toJson()).toList(),
        // Server menyimpan nilai mentah (string), persis seperti web app.
        'cycleKontrakOptions': _stringifyIntKeys(kontrakOptions, (v) => v),
        'cycleJagaModes': _stringifyIntKeys(jagaModes, (v) => v),
        'cycleNames': _stringifyIntKeys(
            cycleNames, (v) => Map<String, dynamic>.from(v)),
        'cycleStok': _stringifyIntKeys(cycleStok, (v) => {
              'awal': v.awal,
              'akhir': v.akhir,
              'note': v.note,
            }),
        'cyclePenjaga': _stringifyIntKeys(cyclePenjaga, (v) => {
              'pp': v.pp,
              'list': v.list.map((g) => g.toJson()).toList(),
            }),
      };
}
