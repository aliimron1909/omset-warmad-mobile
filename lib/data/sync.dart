// Engine sinkronisasi lokal <-> server, mengikuti protokol api/sync.js.
/// Strategi konflik: pull -> gabungkan -> push dengan baseRev; bila server
/// berubah, ulangi sekali dengan data terbaru (sama seperti web app).
import 'dart:convert';

import 'api.dart';
import 'warung.dart';

class LocalState {
  int? rev;
  String? key;
  String? device;
  String role; // 'pemilik' | 'karyawan'
  bool premium;
  List<String> deletedWarung;
  List<WarungData> warung;
  List<Map<String, dynamic>> akses;
  DateTime? lastSync;

  LocalState({
    this.rev,
    this.key,
    this.device,
    this.role = 'pemilik',
    this.premium = false,
    List<String>? deletedWarung,
    List<WarungData>? warung,
    List<Map<String, dynamic>>? akses,
    this.lastSync,
  })  : deletedWarung = deletedWarung ?? <String>[],
        warung = warung ?? <WarungData>[],
        akses = akses ?? <Map<String, dynamic>>[];

  factory LocalState.fromJson(Map<String, dynamic> j) => LocalState(
        rev: j['rev'] == null ? null : (j['rev'] as num).toInt(),
        key: j['key'] as String?,
        device: j['device'] as String?,
        role: (j['role'] as String?) ?? 'pemilik',
        premium: (j['premium'] as bool?) ?? false,
        deletedWarung: ((j['deletedWarung'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        warung: ((j['warung'] as List?) ?? [])
            .map((e) => WarungData.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        akses: ((j['akses'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        lastSync: j['lastSync'] == null
            ? null
            : DateTime.tryParse(j['lastSync'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rev': rev,
        'key': key,
        'device': device,
        'role': role,
        'premium': premium,
        'deletedWarung': deletedWarung,
        'warung': warung.map((e) => e.toJson()).toList(),
        'akses': akses,
        'lastSync': lastSync?.toIso8601String(),
      };

  String serialize() => jsonEncode(toJson());

  static LocalState deserialize(String raw) =>
      LocalState.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
}

abstract class SyncStore {
  Future<LocalState> load();
  Future<void> save(LocalState state);
}

class SyncOutcome {
  final bool ok;
  final String message;
  final bool revoked;
  final bool conflict;

  const SyncOutcome({
    required this.ok,
    required this.message,
    this.revoked = false,
    this.conflict = false,
  });
}

class SyncEngine {
  SyncEngine({required this.api, required this.store});

  final ApiClient api;
  final SyncStore store;

  Future<SyncOutcome> sync({int attempts = 2}) async {
    final st = await store.load();
    final key = st.key;
    final device = st.device;
    if (key == null || key.isEmpty || device == null || device.isEmpty) {
      return const SyncOutcome(ok: false, message: 'Kode akses belum diisi');
    }

    for (var attempt = 0; attempt < attempts; attempt++) {
      final pull = await _pull(key, device, st);
      if (!pull.ok) return pull;

      await store.save(st);
      final outcome = await _push(key, device, st);
      if (outcome.ok || !outcome.conflict) return outcome;
      // Konflik: ulangi pull untuk menggabungkan revisi terbaru server.
    }
    return const SyncOutcome(
      ok: false,
      conflict: true,
      message: 'Data di server sudah berubah. Silakan coba lagi.',
    );
  }

  Future<SyncOutcome> _pull(String key, String device, LocalState st) async {
    final r = await api.syncPull(key, device);
    if (r['ok'] != true) {
      return SyncOutcome(
        ok: false,
        message: (r['error'] as String?) ?? 'Gagal mengambil data server',
        revoked: r['revoked'] == true,
      );
    }
    st.role = (r['peran'] as String?) ?? 'pemilik';
    st.premium = r['premium'] == true;
    if (r['rev'] != null) st.rev = (r['rev'] as num).toInt();

    final rawWarung = (r['warung'] as List?) ?? [];
    for (final item in rawWarung) {
      if (item is! Map<String, dynamic>) continue;
      final rw = WarungData.fromJson(item);
      if (st.deletedWarung.contains(rw.id)) continue;

      final idx = st.warung.indexWhere((w) => w.id == rw.id);
      final isNew = idx < 0;
      final local = isNew ? WarungData(id: rw.id) : st.warung[idx];

      // Catatan: gabungkan berdasarkan tanggal, lokal menang untuk tanggal sama.
      final dates = local.records.map((x) => x.date).toSet();
      for (final rec in rw.records) {
        if (!dates.contains(rec.date)) local.records.add(rec);
      }
      local.records.sort((a, b) => a.date.compareTo(b.date));

      // Pengaturan per siklus: lokal menang (Object.assign({}, remote, local)).
      local.kontrakOptions = {...rw.kontrakOptions, ...local.kontrakOptions};
      local.jagaModes = {...rw.jagaModes, ...local.jagaModes};
      local.cycleNames = {...rw.cycleNames, ...local.cycleNames};
      local.cycleStok = {...rw.cycleStok, ...local.cycleStok};
      local.cyclePenjaga = {...rw.cyclePenjaga, ...local.cyclePenjaga};

      // Nama warung: ambil dari server hanya bila lokal masih kosong/default.
      if (isNew ||
          local.settings.nama.isEmpty ||
          local.settings.nama == 'Warung Saya') {
        local.settings = rw.settings;
      }

      if (isNew) {
        st.warung.add(local);
      } else {
        st.warung[idx] = local;
      }
    }

    final rawAkses = r['akses'] as List?;
    if (rawAkses != null) {
      st.akses = rawAkses
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const SyncOutcome(ok: true, message: 'Data tersinkron');
  }

  Future<SyncOutcome> _push(String key, String device, LocalState st) async {
    final body = <String, dynamic>{
      'action': st.role == 'karyawan' ? 'syncStaff' : 'syncAll',
      'key': key,
      'device': device,
      'warung': st.warung.map((w) => w.toJson()).toList(),
    };
    if (st.role != 'karyawan') {
      body['premium'] = st.premium;
      if (st.rev != null) body['baseRev'] = st.rev;
    }

    final r = await api.post('/api/sync', body);
    if (r['ok'] != true) {
      return SyncOutcome(
        ok: false,
        message: (r['error'] as String?) ?? 'Gagal menyimpan ke server',
        conflict: r['conflict'] == true,
      );
    }
    if (r['rev'] != null) st.rev = (r['rev'] as num).toInt();
    st.lastSync = DateTime.now();
    await store.save(st);
    return const SyncOutcome(ok: true, message: 'Tersimpan');
  }
}
