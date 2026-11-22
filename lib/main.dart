import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/local_store.dart';
import 'data/sync.dart';
import 'data/warung.dart';
import 'domain/calc.dart';
import 'domain/cycle.dart';

final ApiClient api = ApiClient();
final SyncStore store = FileSyncStore();

void main() => runApp(const WarMadApp());

class WarMadApp extends StatelessWidget {
  const WarMadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omset-WarMad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5C4D)),
        useMaterial3: true,
      ),
      home: const Bootstrap(),
    );
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  LocalState? _state;
  String _device = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final loaded = await store.load();
    final id = await DeviceInfo.androidId();
    if (!mounted) return;
    setState(() {
      _state = loaded;
      _device = id;
      _state!.device ??= id.isEmpty ? 'unknown-device' : id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    if (st == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (st.key == null || st.key!.isEmpty) {
      return SetupPage(state: st, device: _device, store: store);
    }
    return HomePage(state: st, store: store);
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({
    super.key,
    required this.state,
    required this.device,
    required this.store,
  });

  final LocalState state;
  final String device;
  final SyncStore store;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _premiumLicense = false;
  String? _error;

  Future<void> _activate() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Kode wajib diisi');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_premiumLicense) {
        await _activatePremiumLicense(code);
      } else {
        await _activateAccessCode(code);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activatePremiumLicense(String code) async {
    final lic = await api.licActivate(code, widget.device);
    if (lic['ok'] != true) {
      setState(() => _error = (lic['error'] as String?) ?? 'Kode lisensi tidak valid');
      return;
    }
    // Kode lisensi premium harus ditukar menjadi Kode Pemilik untuk sync.
    final reg = await api.syncRegister(code, widget.device);
    if (reg['ok'] != true) {
      setState(() => _error =
          (reg['error'] as String?) ?? 'Lisensi aktif, tetapi gagal menyiapkan sync');
      return;
    }
    widget.state.key = (reg['key'] as String?) ?? code;
    widget.state.premium = true;
    await widget.store.save(widget.state);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(state: widget.state, store: widget.store),
      ),
    );
  }

  Future<void> _activateAccessCode(String code) async {
    final r = await api.syncRegister(code, widget.device);
    if (r['ok'] != true) {
      final msg = (r['error'] as String?) ?? 'Kode tidak valid';
      // Petunjuk jika pengguna memasukkan kode lisensi di mode warung/karyawan.
      if (msg.toLowerCase().contains('belum terdaftar untuk lisensi')) {
        setState(() {
          _error =
              '$msg\n\nJika ini kode lisensi premium, pilih "Lisensi Premium" di atas lalu aktifkan lagi.';
        });
        return;
      }
      setState(() => _error = msg);
      return;
    }
    widget.state.key = (r['key'] as String?) ?? code;
    await widget.store.save(widget.state);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(state: widget.state, store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivasi Omset-WarMad')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.storefront, size: 72, color: Color(0xFF0F5C4D)),
            const SizedBox(height: 16),
            const Text(
              'Aktifkan perangkat',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _premiumLicense
                  ? 'Masukkan kode lisensi premium Anda. Perangkat akan didaftarkan lalu disiapkan untuk sinkronisasi.'
                  : 'Masukkan kode akses warung/pemilik atau kode karyawan yang diberikan pemilik.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Kode Warung'),
                  icon: Icon(Icons.key),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Lisensi Premium'),
                  icon: Icon(Icons.workspace_premium),
                ),
              ],
              selected: {_premiumLicense},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() {
                        _premiumLicense = s.first;
                        _error = null;
                      }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: _premiumLicense ? 'Kode lisensi premium' : 'Kode akses',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(_premiumLicense ? Icons.workspace_premium : Icons.key),
              ),
              onSubmitted: (_) => _busy ? null : _activate(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _activate,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aktifkan'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.store});

  final LocalState state;
  final SyncStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SyncEngine _engine;
  bool _busy = false;
  String? _info;

  @override
  void initState() {
    super.initState();
    _engine = SyncEngine(api: api, store: widget.store);
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _info = null;
    });
    try {
      final out = await _engine.sync();
      if (!mounted) return;
      setState(() => _info = out.message);
    } catch (e) {
      if (mounted) setState(() => _info = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _rupiah(num n) =>
      'Rp${n.round().toString().replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final today = DateTime.now().toString().substring(0, 10);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omset-WarMad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _sync,
            tooltip: 'Sinkronkan',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _sync,
        child: const Icon(Icons.sync),
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_done),
                title: Text(st.premium ? 'Premium aktif' : 'Akun gratis'),
                subtitle: Text(
                  st.lastSync == null
                      ? 'Belum pernah sinkron'
                      : 'Sinkron terakhir: ${st.lastSync!.toLocal()}',
                ),
                trailing: Text('rev ${st.rev ?? '-'}'),
              ),
            ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_info!, style: const TextStyle(color: Colors.grey)),
              ),
            const SizedBox(height: 8),
            const Text('Rekap siklus berjalan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (st.warung.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Belum ada data. Tekan tombol sinkron untuk mengambil data dari server.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ...st.warung.map((w) => _WarungCard(
                  warung: w,
                  today: today,
                  rupiah: _rupiah,
                )),
          ],
        ),
      ),
    );
  }
}

class _WarungCard extends StatelessWidget {
  const _WarungCard({
    required this.warung,
    required this.today,
    required this.rupiah,
  });

  final WarungData warung;
  final String today;
  final String Function(num) rupiah;

  @override
  Widget build(BuildContext context) {
    final c = cycleOfDate(today, warung.settings.cr) ?? 1;
    final x = calc(
      c,
      records: warung.records,
      s: warung.settings,
      jm: warung.jagaModes,
      cn: warung.cycleNames,
      pg: warung.cyclePenjaga,
      ko: warung.kontrakOptions,
      sk: warung.cycleStok,
      today: today,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warung.settings.nama,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Siklus $c · ${x.days} dari ${x.len} hari'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Omset'),
                Text(rupiah(x.omset)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tabungan (${x.tab.toStringAsFixed(0)}%)'),
                Text(rupiah(x.tab)),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bagian pemilik',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(rupiah(x.bossT),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (x.stok != null)
              Text('Selisih stok: ${rupiah(x.stok!.sel)}',
                  style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
