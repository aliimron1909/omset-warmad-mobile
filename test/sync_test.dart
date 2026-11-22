import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:warmad_mobile/data/api.dart';
import 'package:warmad_mobile/data/sync.dart';
import 'package:warmad_mobile/data/warung.dart';
import 'package:warmad_mobile/domain/models.dart';

class FakeClient extends http.BaseClient {
  final List<Map<String, dynamic>> queue = [];
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requests.add(Map<String, dynamic>.from(jsonDecode(req.body)));
    final body = queue.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class MemoryStore implements SyncStore {
  LocalState state;
  MemoryStore(this.state);

  @override
  Future<LocalState> load() async => state;

  @override
  Future<void> save(LocalState value) async => state = value;
}

void main() {
  test('pull menggabungkan data lokal lalu push dengan baseRev', () async {
    final client = FakeClient()
      ..queue.addAll([
        {
          'ok': true,
          'peran': 'pemilik',
          'rev': 7,
          'warung': [
            {
              'id': 'w1',
              'settings': {'nama': 'Warung Server', 'pct': 10},
              'records': [
                {
                  'date': '2026-11-01',
                  'cycle': 1,
                  'day': 1,
                  'omset': 100000,
                  'expense': ''
                }
              ],
              'cycleKontrakOptions': {'1': 'prorata'},
              'cycleJagaModes': {'1': 'pemilik_1_karyawan'},
              'cycleNames': {},
              'cycleStok': {},
              'cyclePenjaga': {}
            }
          ],
          'akses': [],
        },
        {'ok': true, 'rev': 8, 'warung': 1},
      ]);

    final store = MemoryStore(LocalState(
      key: 'PMK123',
      device: 'device-1',
      warung: [
        WarungData(id: 'w1')..records = [
            OmRecord(
                date: '2026-11-02',
                cycle: 1,
                day: 2,
                omset: 200000)
          ],
      ],
    ));

    final engine = SyncEngine(api: ApiClient(client: client), store: store);
    final out = await engine.sync();

    expect(out.ok, isTrue);
    expect(client.requests.length, 2);
    expect(client.requests[0]['action'], 'pull');
    expect(client.requests[1]['action'], 'syncAll');
    expect(client.requests[1]['baseRev'], 7);
    expect(store.state.rev, 8);
    expect(store.state.warung.single.records.length, 2);
    expect(store.state.warung.single.kontrakOptions[1], 'prorata');
    expect(store.state.warung.single.jagaModes[1], 'pemilik_1_karyawan');
  });

  test('konflik memicu pull ulang sekali', () async {
    final client = FakeClient()
      ..queue.addAll([
        {
          'ok': true,
          'peran': 'pemilik',
          'rev': 7,
          'warung': [],
        },
        {'ok': false, 'conflict': true, 'rev': 9, 'error': 'conflict'},
        {
          'ok': true,
          'peran': 'pemilik',
          'rev': 9,
          'warung': [],
        },
        {'ok': true, 'rev': 10},
      ]);
    final store = MemoryStore(
        LocalState(key: 'PMK123', device: 'device-1'));
    final out = await SyncEngine(
            api: ApiClient(client: client), store: store)
        .sync();

    expect(out.ok, isTrue);
    expect(client.requests.length, 4);
    expect(client.requests[2]['action'], 'pull');
    expect(store.state.rev, 10);
  });

  test('tombstone mencegah siklus kosong terhapus hidup kembali saat pull', () async {
    final client = FakeClient()
      ..queue.addAll([
        {
          'ok': true,
          'peran': 'pemilik',
          'rev': 5,
          'warung': [
            {
              'id': 'w1',
              'settings': {'nama': 'W', 'pct': 10},
              'records': [],
              'cycleKontrakOptions': {'2': 'prorata'},
              'cycleJagaModes': {'2': 'solo'},
              'cycleNames': {'2': {'k1': 'A'}},
              'cycleStok': {'2': {'awal': 100}},
              'cyclePenjaga': {}
            }
          ],
          'akses': [],
        },
        {'ok': true, 'rev': 6, 'warung': 1},
      ]);

    final w = WarungData(id: 'w1')
      ..deletedCycles = [2]
      ..kontrakOptions = {}
      ..jagaModes = {}
      ..cycleNames = {}
      ..cycleStok = {}
      ..cyclePenjaga = {};
    final store = MemoryStore(LocalState(key: 'PMK1', device: 'd1', warung: [w]));
    final out = await SyncEngine(api: ApiClient(client: client), store: store).sync();

    expect(out.ok, isTrue);
    final lw = store.state.warung.single;
    expect(lw.kontrakOptions.containsKey(2), isFalse);
    expect(lw.jagaModes.containsKey(2), isFalse);
    expect(lw.cycleNames.containsKey(2), isFalse);
    expect(lw.cycleStok.containsKey(2), isFalse);
    expect(lw.deletedCycles, contains(2));
  });
}
