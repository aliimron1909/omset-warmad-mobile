import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/api.dart';
import 'data/local_store.dart';
import 'data/sync.dart';
import 'data/update_service.dart';
import 'data/warung.dart';
import 'domain/calc.dart';
import 'domain/cycle.dart';
import 'domain/models.dart';

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
  String _mode = 'owner'; // premium | owner | employee
  String? _error;

  bool _looksLikeEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  Future<void> _activate() async {
    final raw = _controller.text.trim();
    final code = raw.toUpperCase();
    if (code.isEmpty) {
      if (_mode == 'owner') {
        await _startLocalFree();
        return;
      }
      setState(() => _error = 'Kode wajib diisi');
      return;
    }
    if (_mode == 'premium' && _looksLikeEmail(raw)) {
      setState(() => _error = 'Login dengan email/kode verifikasi belum tersedia di aplikasi ini. Silakan masukkan Kode Lisensi Premium. Untuk bantuan login email, hubungi admin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == 'premium') {
        await _activatePremiumLicense(code);
      } else {
        await _activateAccessCode(code, isEmployee: _mode == 'employee');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLocalFree() async {
    setState(() { _busy = true; _error = null; });
    try {
      widget.state.key = null;
      widget.state.premium = false;
      if (widget.state.warung.isEmpty) {
        widget.state.warung.add(WarungData(id: 'w1'));
      }
      await widget.store.save(widget.state);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomePage(state: widget.state, store: widget.store)),
      );
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

  Future<void> _activateAccessCode(String code, {required bool isEmployee}) async {
    final r = await api.syncRegister(code, widget.device);
    if (r['ok'] != true) {
      final msg = (r['error'] as String?) ?? 'Kode tidak valid';
      final low = msg.toLowerCase();
      if (low.contains('belum terdaftar untuk lisensi')) {
        setState(() {
          _error = '$msg\n\nJika ini kode lisensi premium, pilih opsi "Email atau Kode Premium" di atas lalu coba lagi.';
        });
        return;
      }
      if (low.contains('tidak ditemukan') || low.contains('not found') || low.contains('tidak valid') || low.contains('invalid')) {
        setState(() {
          _error = isEmployee
              ? 'Kode karyawan tidak ditemukan. Periksa kembali kode dari pemilik warung, pastikan kode belum dicabut, dan pemilik memiliki akses Premium aktif.'
              : 'Kode akses tidak ditemukan. Periksa kembali kode Anda. Jika ini kode lisensi premium, pilih opsi "Email atau Kode Premium".';
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

  Widget _modeCard({required String value, required IconData icon, required String title, required String desc}) {
    final selected = _mode == value;
    return Card(
      color: selected ? const Color(0xFFE6F2EF) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? const Color(0xFF0F5C4D) : const Color(0xFFDDDDDD), width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => setState(() { _mode = value; _error = null; }),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? const Color(0xFF0F5C4D) : Colors.grey[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: selected ? const Color(0xFF0F5C4D) : Colors.black87)),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: Color(0xFF0F5C4D), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = _mode == 'premium';
    final isEmployee = _mode == 'employee';
    final label = isPremium ? 'Email atau Kode Premium' : (isEmployee ? 'Kode Karyawan' : 'Kode Akses Pemilik/Warung');
    final icon = isPremium ? Icons.workspace_premium : (isEmployee ? Icons.badge_outlined : Icons.storefront);
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivasi Omset-WarMad')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.storefront, size: 72, color: Color(0xFF0F5C4D)),
          const SizedBox(height: 16),
          const Text(
            'Aktifkan perangkat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Pilih jenis akses Anda untuk melanjutkan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _modeCard(
            value: 'premium',
            icon: Icons.workspace_premium,
            title: 'Email atau Kode Premium',
            desc: 'Untuk pengguna yang sudah memiliki lisensi premium. Masukkan kode premium untuk mengaktifkan perangkat.',
          ),
          _modeCard(
            value: 'owner',
            icon: Icons.storefront_outlined,
            title: 'Pemilik Warung',
            desc: 'Gratis untuk 1 warung. Data disimpan di HP ini. Bisa hubungkan kode akses atau aktifkan Premium nanti dari Pengaturan.',
          ),
          _modeCard(
            value: 'employee',
            icon: Icons.badge_outlined,
            title: 'Karyawan',
            desc: 'Untuk karyawan yang sudah mendapat kode dari pemilik warung (fitur Premium). Bisa juga masuk lewat tautan yang dibagikan pemilik (jika tersedia).',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _mode == 'owner' ? 'Kode Akses (opsional)' : label,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(icon),
              helperText: _mode == 'owner' ? 'Kosongkan jika ingin mulai gratis dan simpan data di HP.' : null,
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
                : Text(_mode == 'owner' && _controller.text.trim().isEmpty ? 'Mulai Gratis (Simpan di HP)' : 'Aktifkan'),
          ),
        ],
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
  final UpdateService _updateService = UpdateService();
  bool _busy = false;
  String? _info;
  String _cycleSel = 'running'; // running | all | <cycle number>
  int _tab = 0;
  String? _activeWarungId;
  String _appVersion = '';
  UpdateInfo? _updateInfo;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _engine = SyncEngine(api: api, store: widget.store);
    _activeWarungId = widget.state.warung.isNotEmpty ? widget.state.warung.first.id : null;
    _initVersionAndCheckUpdate();
  }

  Future<void> _initVersionAndCheckUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
    await _checkUpdate(manual: false);
  }

  Future<void> _checkUpdate({required bool manual}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final current = _appVersion.isNotEmpty ? _appVersion : (await PackageInfo.fromPlatform()).version;
      final info = await _updateService.check(current);
      if (!mounted) return;
      setState(() {
        _appVersion = current;
        _updateInfo = info;
      });
      if (info.hasUpdate) {
        _showUpdateDialog(info);
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aplikasi sudah versi terbaru')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cek update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update tersedia'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Versi saat ini: v${info.currentVersion}'),
              Text('Versi terbaru: v${info.latestVersion}'),
              const SizedBox(height: 12),
              const Text('Catatan rilis:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(info.notes.isEmpty ? 'Tidak ada catatan rilis.' : info.notes),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nanti')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _installUpdate(info);
            },
            child: const Text('Unduh & Pasang'),
          ),
        ],
      ),
    );
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) {
      final fallback = Uri.parse(info.releaseUrl);
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    double progress = 0;
    String status = 'Menyiapkan unduhan...';
    bool done = false;
    String? err;
    StateSetter? setD;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sd) {
        setD = sd;
        return AlertDialog(
          title: const Text('Mengunduh update'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(status),
            const SizedBox(height: 12),
            if (err == null) LinearProgressIndicator(value: done ? 1 : (progress > 0 ? progress : null)),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!, style: const TextStyle(color: Color(0xFFC0392B), fontSize: 13)),
            ],
          ]),
          actions: [
            if (err != null) TextButton(onPressed: () async {
              final fb = Uri.parse(info.releaseUrl);
              await launchUrl(fb, mode: LaunchMode.externalApplication);
            }, child: const Text('Buka Browser')),
            if (err != null || done) TextButton(onPressed: () => Navigator.pop(ctx), child: Text(done ? 'Tutup' : 'Batal')),
          ],
        );
      }),
    );
    try {
      final file = await _updateService.downloadApk(url, onProgress: (r, t) {
        final p = t > 0 ? r / t : 0.0;
        final mb = (r / 1048576).toStringAsFixed(1);
        final mbt = t > 0 ? (t / 1048576).toStringAsFixed(1) : '?';
        setD?.call(() { progress = p; status = 'Mengunduh $mb / $mbt MB'; });
      });
      setD?.call(() { progress = 1; status = 'Membuka pemasang...'; done = true; });
      await _updateService.installApk(file);
    } catch (e) {
      setD?.call(() { err = e.toString(); status = 'Gagal memperbarui'; });
    }
  }

  WarungData? get _activeWarung {
    final st = widget.state;
    if (st.warung.isEmpty) return null;
    final id = _activeWarungId;
    return st.warung.firstWhere((w) => w.id == id, orElse: () => st.warung.first);
  }

  Future<void> _sync() async {
    final hasKey = (widget.state.key ?? '').isNotEmpty;
    if (!hasKey) {
      setState(() => _info = 'Mode lokal: data tersimpan di HP. Hubungkan kode akses atau aktifkan Premium untuk sync cloud.');
      return;
    }
    setState(() {
      _busy = true;
      _info = null;
    });
    try {
      final r = await _engine.sync(state: widget.state);
      if (!mounted) return;
      setState(() {
        _info = r.message;
        _activeWarungId ??= widget.state.warung.isNotEmpty ? widget.state.warung.first.id : null;
      });
    } catch (e) {
      if (mounted) setState(() => _info = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _rupiah(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      b.write(s[i]);
      if (pos > 1 && pos % 3 == 1) b.write('.');
    }
    return 'Rp$b';
  }

  List<int> _allCycles() {
    final set = <int>{};
    for (final w in widget.state.warung) {
      for (final r in w.records) {
        set.add(r.cycle);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  List<int> _cyclesFor(WarungData w, String today) {
    if (_cycleSel == 'all') {
      final cs = w.records.map((r) => r.cycle).toSet().toList()..sort();
      if (cs.isNotEmpty) return cs;
      return [cycleOfDate(today, w.settings.cr) ?? 1];
    }
    if (_cycleSel == 'running') {
      return [cycleOfDate(today, w.settings.cr) ?? 1];
    }
    final n = int.tryParse(_cycleSel);
    return [n ?? (cycleOfDate(today, w.settings.cr) ?? 1)];
  }

  Future<void> _showPremiumDialog() async {
    final controller = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Aktifkan Lisensi Premium'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Kode lisensi premium',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final code = controller.text.trim().toUpperCase();
                      if (code.isEmpty) {
                        setD(() => error = 'Kode lisensi wajib diisi');
                        return;
                      }
                      setD(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final dev = widget.state.device ?? '';
                        final lic = await api.licActivate(code, dev);
                        if (lic['ok'] != true) {
                          setD(() {
                            error = (lic['error'] as String?) ?? 'Kode lisensi tidak valid';
                            busy = false;
                          });
                          return;
                        }
                        final reg = await api.syncRegister(code, dev);
                        if (reg['ok'] == true) {
                          widget.state.key = (reg['key'] as String?) ?? widget.state.key;
                        }
                        widget.state.premium = true;
                        await widget.store.save(widget.state);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (mounted) {
                          setState(() => _info = 'Lisensi premium aktif');
                          _sync();
                        }
                      } catch (e) {
                        setD(() {
                          error = e.toString();
                          busy = false;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aktifkan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Dashboard', 'Input', 'Rekap', 'Pengaturan'];
    return Scaffold(
      appBar: AppBar(title: Text('Omset-WarMad · ${titles[_tab]}')),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _sync,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: 'Input'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Rekap'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildDashboard(),
          _buildInput(),
          const _PlaceholderTab(title: 'Rekap', icon: Icons.receipt_long),
          _SettingsTab(
            appVersion: _appVersion,
            updateInfo: _updateInfo,
            checking: _checkingUpdate,
            onCheckUpdate: () => _checkUpdate(manual: true),
            state: widget.state,
            activeWarung: _activeWarung,
            onWarungChanged: (id) => setState(() => _activeWarungId = id),
            onSaved: () async {
              await widget.store.save(widget.state);
              if (mounted) setState(() => _info = 'Pengaturan tersimpan');
              _sync();
            },
            store: widget.store,
            onInstallUpdate: _installUpdate,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final st = widget.state;
    final today = DateTime.now().toString().substring(0, 10);
    final allCycles = _allCycles();

    double boss = 0, bs = 0, kt = 0, sb = 0, omset = 0, tab = 0, sel = 0;
    var nst = 0;
    var anyBagi = false;
    final guardAgg = <String, _GuardAgg>{};
    final daily = <String, double>{};
    final perCycle = <int, double>{};

    for (final w in st.warung) {
      final selected = _cyclesFor(w, today);
      for (final c in selected) {
        final x = calc(
          c,
          records: w.records,
          s: w.settings,
          jm: w.jagaModes,
          cn: w.cycleNames,
          pg: w.cyclePenjaga,
          ko: w.kontrakOptions,
          sk: w.cycleStok,
          today: today,
        );
        boss += x.bossT;
        bs += x.bossShare;
        kt += x.kontrak;
        sb += x.stBoss;
        omset += x.omset;
        tab += x.tab;
        if (x.nBagi > 0 || x.gajiTotal == 0) anyBagi = true;
        if (x.stok != null) {
          sel += x.stok!.sel;
          nst++;
        }
        for (final g in x.guards) {
          final a = guardAgg.putIfAbsent(g.n, () => _GuardAgg(g.n));
          a.base += g.base;
          a.stk += g.stk;
          a.types.add(g.t);
        }
      }
      for (final r in w.records) {
        if (selected.contains(r.cycle)) {
          daily[r.date] = (daily[r.date] ?? 0) + r.omset;
        }
      }
    }
    for (final c in allCycles) {
      double cOmset = 0;
      for (final w in st.warung) {
        cOmset += calc(
          c,
          records: w.records,
          s: w.settings,
          jm: w.jagaModes,
          cn: w.cycleNames,
          pg: w.cyclePenjaga,
          ko: w.kontrakOptions,
          sk: w.cycleStok,
          today: today,
        ).omset;
      }
      perCycle[c] = cOmset;
    }
    final dailyDates = daily.keys.toList()..sort();

    final cycleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'running', child: Text('Siklus berjalan')),
      const DropdownMenuItem(value: 'all', child: Text('Semua siklus')),
      ...allCycles.map((c) => DropdownMenuItem(value: '$c', child: Text('Siklus $c'))),
    ];

    final selLabel = _cycleSel == 'running'
        ? 'Siklus berjalan'
        : _cycleSel == 'all'
            ? 'Semua siklus'
            : 'Siklus $_cycleSel';

    return RefreshIndicator(
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(st.premium ? Icons.workspace_premium : ((st.key ?? '').isNotEmpty ? Icons.cloud_done : Icons.phone_android)),
              title: Text(st.premium ? 'Premium aktif' : ((st.key ?? '').isNotEmpty ? 'Akun gratis' : 'Gratis (Data di HP)')),
              subtitle: Text(
                st.premium || (st.key ?? '').isNotEmpty
                    ? (st.lastSync == null
                        ? 'Belum pernah sinkron'
                        : () {
                            final t = st.lastSync!.toLocal();
                            String p2(int n) => n.toString().padLeft(2, '0');
                            return 'Sinkron terakhir: ${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
                          }())
                    : 'Data tersimpan di perangkat ini. Hubungkan kode untuk sync cloud.',
              ),
              trailing: st.premium
                  ? null
                  : TextButton(
                      onPressed: _busy ? null : _showPremiumDialog,
                      child: const Text('Aktifkan Lisensi Premium'),
                    ),
            ),
          ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_info!, style: const TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: cycleItems.any((i) => i.value == _cycleSel) ? _cycleSel : 'running',
            decoration: InputDecoration(
              labelText: 'Tampilkan siklus',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            items: cycleItems,
            onChanged: (v) => setState(() => _cycleSel = v ?? 'running'),
          ),
          const SizedBox(height: 12),
          _TotalCard(boss: boss, bs: bs, kt: kt, sb: sb, nst: nst, anyBagi: anyBagi, rupiah: _rupiah),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _SmallStat(label: 'Omset Kotor', value: _rupiah(omset))),
              const SizedBox(width: 8),
              Expanded(child: _SmallStat(label: 'Tabungan', value: _rupiah(tab))),
            ],
          ),
          if (nst > 0) ...[
            const SizedBox(height: 8),
            _SmallStat(
              label: 'Selisih Stok',
              value: '${sel < 0 ? '-' : '+'} ${_rupiah(sel.abs())}',
              valueColor: sel >= 0 ? const Color(0xFF1F9D55) : const Color(0xFFC0392B),
            ),
          ],
          if (guardAgg.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Pendapatan Karyawan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...guardAgg.values.map((g) => _GuardCard(agg: g, rupiah: _rupiah, nst: nst)),
          ],
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Omset Harian',
            child: _DailyChart(dates: dailyDates, values: daily, rupiah: _rupiah),
          ),
          const SizedBox(height: 8),
          _ChartCard(
            title: 'Omset Per-Siklus',
            child: st.premium
                ? _CycleChart(cycles: allCycles, values: perCycle, rupiah: _rupiah)
                : const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Grafik perbandingan per siklus khusus Premium.'),
                  ),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text('Detail per warung · $selLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${st.warung.length} warung'),
              initiallyExpanded: false,
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                if (st.warung.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Belum ada data. Tekan tombol sinkron untuk mengambil data dari server.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ...st.warung.map((w) => _WarungCard(
                      warung: w,
                      today: today,
                      rupiah: _rupiah,
                      cycles: _cyclesFor(w, today),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return InputTab(
      state: widget.state,
      store: widget.store,
      activeWarung: _activeWarung,
      onWarungChanged: (id) => setState(() => _activeWarungId = id),
      onSaved: () async {
        await widget.store.save(widget.state);
        if (mounted) setState(() => _info = 'Tersimpan');
        _sync();
      },
      rupiah: _rupiah,
      syncInfo: _info,
      syncing: _busy,
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Segera hadir', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({
    required this.appVersion,
    required this.updateInfo,
    required this.checking,
    required this.onCheckUpdate,
    required this.state,
    required this.activeWarung,
    required this.onWarungChanged,
    required this.onSaved,
    required this.store,
    required this.onInstallUpdate,
  });

  final String appVersion;
  final UpdateInfo? updateInfo;
  final bool checking;
  final VoidCallback onCheckUpdate;
  final LocalState state;
  final WarungData? activeWarung;
  final ValueChanged<String> onWarungChanged;
  final Future<void> Function() onSaved;
  final SyncStore store;
  final Future<void> Function(UpdateInfo info) onInstallUpdate;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  String _mode = '30'; // 30 | calendar | handover
  final _handoverCtrl = TextEditingController(text: '1');
  final _startCtrl = TextEditingController();
  final _cycleNCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _loadFromWarung();
  }

  @override
  void didUpdateWidget(covariant _SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeWarung?.id != widget.activeWarung?.id) _loadFromWarung();
  }

  @override
  void dispose() {
    _handoverCtrl.dispose();
    _startCtrl.dispose();
    _cycleNCtrl.dispose();
    super.dispose();
  }

  void _loadFromWarung() {
    final w = widget.activeWarung;
    final cr = (w != null && w.settings.cr.isNotEmpty) ? w.settings.cr.first : null;
    if (cr == null || cr.d == 0) {
      _mode = '30';
      _handoverCtrl.text = '1';
      _startCtrl.text = _today();
      _cycleNCtrl.text = cr?.n.toString() ?? '1';
    } else if (cr.d == 1) {
      _mode = 'calendar';
      _handoverCtrl.text = '1';
      _startCtrl.text = cr.s;
      _cycleNCtrl.text = cr.n.toString();
    } else {
      _mode = 'handover';
      _handoverCtrl.text = cr.d.toString();
      _startCtrl.text = cr.s;
      _cycleNCtrl.text = cr.n.toString();
    }
    setState(() {});
  }

  String _today() => DateTime.now().toString().substring(0, 10);

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_startCtrl.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _startCtrl.text = picked.toString().substring(0, 10));
  }

  Future<void> _saveCycleRule() async {
    final w = widget.activeWarung;
    if (w == null) return;
    final n = int.tryParse(_cycleNCtrl.text.trim()) ?? 1;
    final s = _startCtrl.text.trim().isEmpty ? _today() : _startCtrl.text.trim();
    int d = 0;
    if (_mode == 'calendar') d = 1;
    if (_mode == 'handover') d = (int.tryParse(_handoverCtrl.text.trim()) ?? 1).clamp(1, 31);
    w.settings.cr = [CycleRule(n: n < 1 ? 1 : n, s: s, d: d)];
    await widget.onSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aturan siklus disimpan')));
  }

  Future<void> _connectAccessCode() async {
    final ctrl = TextEditingController();
    String? err;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Hubungkan Kode Akses'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Masukkan kode akses pemilik/warung untuk sync cloud.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Kode akses', border: OutlineInputBorder())),
          if (err != null) ...[const SizedBox(height: 8), Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12))],
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: busy ? null : () async {
            final code = ctrl.text.trim().toUpperCase();
            if (code.isEmpty) { setD(() => err = 'Kode wajib diisi'); return; }
            setD(() { busy = true; err = null; });
            try {
              final r = await api.syncRegister(code, widget.state.device ?? '');
              if (r['ok'] != true) { setD(() { err = (r['error'] as String?) ?? 'Kode tidak valid'; busy = false; }); return; }
              widget.state.key = (r['key'] as String?) ?? code;
              await widget.onSaved();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kode akses terhubung. Sync akan berjalan.')));
            } catch (e) { setD(() { err = e.toString(); busy = false; }); }
          }, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Hubungkan')),
        ],
      )),
    );
  }

  Future<void> _activatePremium() async {
    final ctrl = TextEditingController();
    String? err;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Aktifkan Lisensi Premium'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Masukkan kode lisensi premium Anda.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Kode lisensi premium', border: OutlineInputBorder())),
          if (err != null) ...[const SizedBox(height: 8), Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12))],
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: busy ? null : () async {
            final code = ctrl.text.trim().toUpperCase();
            if (code.isEmpty) { setD(() => err = 'Kode wajib diisi'); return; }
            setD(() { busy = true; err = null; });
            try {
              final lic = await api.licActivate(code, widget.state.device ?? '');
              if (lic['ok'] != true) { setD(() { err = (lic['error'] as String?) ?? 'Kode lisensi tidak valid'; busy = false; }); return; }
              final reg = await api.syncRegister(code, widget.state.device ?? '');
              if (reg['ok'] == true) widget.state.key = (reg['key'] as String?) ?? widget.state.key;
              widget.state.premium = true;
              await widget.onSaved();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lisensi premium aktif')));
            } catch (e) { setD(() { err = e.toString(); busy = false; }); }
          }, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Aktifkan')),
        ],
      )),
    );
  }

  Future<void> _logout() async {
    bool deleteLocal = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Anda akan keluar dari sesi/aktivasi di perangkat ini dan kembali ke halaman awal.'),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteLocal,
            onChanged: (v) => setD(() => deleteLocal = v == true),
            title: const Text('Hapus juga data lokal di perangkat ini', style: TextStyle(fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      )),
    );
    if (ok != true || !mounted) return;
    final st = widget.state;
    st.key = null;
    st.premium = false;
    st.rev = null;
    st.lastSync = null;
    st.role = 'pemilik';
    st.akses = [];
    if (deleteLocal) {
      st.warung = [WarungData(id: 'w1')];
      st.deletedWarung = [];
    }
    await widget.store.save(st);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SetupPage(state: st, device: st.device ?? '', store: widget.store)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUpdate = widget.updateInfo?.hasUpdate == true;
    final w = widget.activeWarung;
    final hasKey = (widget.state.key ?? '').isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Akun & Sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  widget.state.premium
                      ? 'Premium aktif. Data dapat disinkronkan ke cloud.'
                      : hasKey
                          ? 'Akun terhubung. Data dapat disinkronkan ke cloud.'
                          : 'Mode lokal gratis: data tersimpan di HP ini. Hubungkan kode akses atau aktifkan Premium untuk sync cloud.',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (!widget.state.premium)
                    FilledButton.icon(onPressed: _activatePremium, icon: const Icon(Icons.workspace_premium), label: const Text('Aktifkan Lisensi Premium')),
                  if (!hasKey)
                    OutlinedButton.icon(onPressed: _connectAccessCode, icon: const Icon(Icons.key), label: const Text('Hubungkan Kode Akses')),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aturan Siklus', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (widget.state.warung.length > 1)
                  DropdownButtonFormField<String>(
                    value: w?.id,
                    decoration: InputDecoration(labelText: 'Warung', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: widget.state.warung.map((x) => DropdownMenuItem(value: x.id, child: Text(x.settings.nama))).toList(),
                    onChanged: (v) { if (v != null) widget.onWarungChanged(v); },
                  ),
                if (widget.state.warung.length > 1) const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: InputDecoration(labelText: 'Mode siklus', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: const [
                    DropdownMenuItem(value: '30', child: Text('30 hari tetap (manual)')),
                    DropdownMenuItem(value: 'calendar', child: Text('Bulan kalender')),
                    DropdownMenuItem(value: 'handover', child: Text('Tanggal serah terima')),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? '30'),
                ),
                const SizedBox(height: 12),
                if (_mode == 'handover')
                  TextField(
                    controller: _handoverCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Tanggal serah terima (1-31)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                if (_mode == 'handover') const SizedBox(height: 12),
                InkWell(
                  onTap: _pickStart,
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: 'Tanggal mulai aturan', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), suffixIcon: const Icon(Icons.calendar_today)),
                    child: Text(_startCtrl.text.isEmpty ? _today() : _startCtrl.text),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cycleNCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Nomor siklus mulai', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 12),
                Text(
                  _mode == '30'
                      ? 'Mode 30 hari: Siklus/Hari diisi manual. Gunakan "Siklus Baru" di Tab Input untuk memulai siklus berikutnya.'
                      : _mode == 'calendar'
                          ? 'Mode kalender: Siklus berjalan dari tanggal 1 sampai akhir bulan.'
                          : 'Mode serah terima: Siklus berjalan dari tanggal serah sampai sehari sebelum tanggal yang sama bulan berikutnya.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: w == null ? null : _saveCycleRule, icon: const Icon(Icons.save), label: const Text('Simpan Aturan Siklus')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aplikasi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Versi aplikasi'),
                  subtitle: Text(widget.appVersion.isEmpty ? '-' : 'v${widget.appVersion}'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(hasUpdate ? Icons.system_update : Icons.verified_outlined,
                      color: hasUpdate ? Colors.orange : Colors.green),
                  title: Text(hasUpdate ? 'Update tersedia' : 'Status update'),
                  subtitle: Text(hasUpdate
                      ? 'Versi terbaru: v${widget.updateInfo?.latestVersion}'
                      : (widget.updateInfo == null ? 'Belum dicek' : 'Aplikasi sudah terbaru')),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.checking ? null : widget.onCheckUpdate,
                  icon: widget.checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(widget.checking ? 'Mengecek...' : 'Cek Update'),
                ),
                if (hasUpdate) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.updateInfo == null ? null : () => widget.onInstallUpdate(widget.updateInfo!),
                    icon: const Icon(Icons.download),
                    label: const Text('Unduh & Pasang Update'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tentang update', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Aplikasi mengecek update dari GitHub Releases saat dibuka. '
                  'Anda juga bisa cek manual lewat tombol di atas. '
                  'Saat update tersedia, aplikasi dapat mengunduh dan memasang pembaruan langsung dari aplikasi.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Sesi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC0392B), side: const BorderSide(color: Color(0xFFC0392B))),
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InputTab extends StatefulWidget {
  const InputTab({
    super.key,
    required this.state,
    required this.store,
    required this.activeWarung,
    required this.onWarungChanged,
    required this.onSaved,
    required this.rupiah,
    this.syncInfo,
    this.syncing = false,
  });

  final LocalState state;
  final SyncStore store;
  final WarungData? activeWarung;
  final ValueChanged<String> onWarungChanged;
  final Future<void> Function() onSaved;
  final String Function(num) rupiah;
  final String? syncInfo;
  final bool syncing;

  @override
  State<InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  final _omsetCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _cycleCtrl = TextEditingController();
  final _dayCtrl = TextEditingController();
  final _stokAwalCtrl = TextEditingController();
  final _stokAkhirCtrl = TextEditingController();
  final _stokNoteCtrl = TextEditingController();
  final _cycleFocus = FocusNode();
  final _dayFocus = FocusNode();
  final _omsetFocus = FocusNode();
  final _expFocus = FocusNode();
  final _stokAwalFocus = FocusNode();
  final _stokAkhirFocus = FocusNode();
  final _stokNoteFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _recentKeys = {};
  late String _date;
  String? _editDate;
  int? _stokCycleLoaded;
  int? _historyCycle;
  String? _scrollToDate;

  String _today() => DateTime.now().toString().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _date = _today();
  }

  @override
  void didUpdateWidget(covariant InputTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeWarung?.id != widget.activeWarung?.id) {
      _editDate = null;
      _date = _today();
      _omsetCtrl.clear();
      _expCtrl.clear();
      _cycleCtrl.clear();
      _dayCtrl.clear();
      _stokAwalCtrl.clear();
      _stokAkhirCtrl.clear();
      _stokNoteCtrl.clear();
      _stokCycleLoaded = null;
      _historyCycle = null;
      _scrollToDate = null;
    }
  }

  @override
  void dispose() {
    _omsetCtrl.dispose();
    _expCtrl.dispose();
    _cycleCtrl.dispose();
    _dayCtrl.dispose();
    _stokAwalCtrl.dispose();
    _stokAkhirCtrl.dispose();
    _stokNoteCtrl.dispose();
    _cycleFocus.dispose();
    _dayFocus.dispose();
    _omsetFocus.dispose();
    _expFocus.dispose();
    _stokAwalFocus.dispose();
    _stokAkhirFocus.dispose();
    _stokNoteFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _dayName(String iso) {
    const names = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return names[d.weekday - 1];
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _queueScrollToDate(String date) {
    _scrollToDate = date;
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushScrollToDate());
  }

  void _flushScrollToDate() {
    final d = _scrollToDate;
    if (d == null) return;
    final ctx = _recentKeys[d]?.currentContext;
    if (ctx != null) {
      _scrollToDate = null;
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.2);
    }
  }

  void _syncCycleDay(WarungData w, String date) {
    final ac = cycleOfDate(date, w.settings.cr);
    if (ac != null) {
      final sp = cycSpan(ac, w.settings.cr);
      final day = sp == null ? 1 : diffD(sp.s, date) + 1;
      _cycleCtrl.text = '$ac';
      _dayCtrl.text = '$day';
    } else {
      if (_editDate != null) {
        final old = w.records.firstWhere((r) => r.date == _editDate,
            orElse: () => OmRecord(date: date, cycle: 1, day: 1, omset: 0));
        _cycleCtrl.text = '${old.cycle}';
        _dayCtrl.text = '${old.day}';
      } else {
        final maxCycle = _allCycleNos(w).last;
        final inC = w.records.where((r) => r.cycle == maxCycle).length;
        _cycleCtrl.text = '$maxCycle';
        _dayCtrl.text = '${(inC + 1).clamp(1, 31)}';
      }
    }
  }

  String _fmtRp(String raw) {
    final v = raw.replaceAll(RegExp(r'\D'), '');
    if (v.isEmpty) return '';
    final n = int.parse(v);
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      b.write(s[i]);
      if (pos > 1 && pos % 3 == 1) b.write('.');
    }
    return 'Rp$b';
  }

  int _parseRp(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0;

  String _fmtNum(String raw) {
    final v = raw.replaceAll(RegExp(r'[^0-9-]'), '');
    if (v.isEmpty || v == '-') return v;
    final neg = v.startsWith('-');
    final digits = v.replaceAll('-', '');
    if (digits.isEmpty) return neg ? '-' : '';
    final n = int.tryParse(digits) ?? 0;
    final s = n.toString();
    final b = StringBuffer();
    if (neg) b.write('-');
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      b.write(s[i]);
      if (pos > 1 && pos % 3 == 1) b.write('.');
    }
    return b.toString();
  }

  double? _parseNum(String s) {
    final t = s.trim().replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _loadStokForCycle(WarungData w, int cycle) {
    if (_stokCycleLoaded == cycle) return;
    final st = w.cycleStok[cycle];
    _stokAwalCtrl.text = st?.awal == null ? '' : _fmtNum(st!.awal!.round().toString());
    _stokAkhirCtrl.text = st?.akhir == null ? '' : _fmtNum(st!.akhir!.round().toString());
    _stokNoteCtrl.text = st?.note ?? '';
    _stokCycleLoaded = cycle;
  }

  void _setStokForCycle(WarungData w, int cycle) {
    final awal = _parseNum(_stokAwalCtrl.text);
    final akhir = _parseNum(_stokAkhirCtrl.text);
    final note = _stokNoteCtrl.text.trim();
    if (awal == null && akhir == null && note.isEmpty) {
      w.cycleStok.remove(cycle);
    } else {
      w.cycleStok[cycle] = CycleStok(awal: awal, akhir: akhir, note: note);
    }
  }

  List<String> _missingDates(WarungData w, int cycle) {
    final rs = w.records.where((r) => r.cycle == cycle).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (rs.isEmpty) return [];
    final sp = cycSpan(cycle, w.settings.cr);
    final have = w.records.map((r) => r.date).toSet();
    final out = <String>[];
    final t = _today();
    final lim = (sp != null && sp.e.compareTo(t) < 0) ? sp.e : t;
    var d = DateTime.parse('${sp != null ? sp.s : rs.first.date}T00:00:00');
    final limD = DateTime.parse('${lim}T00:00:00');
    while (!d.isAfter(limD)) {
      final iso = d.toString().substring(0, 10);
      if (!have.contains(iso)) out.add(iso);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  void _loadForEdit(WarungData w, OmRecord r) {
    setState(() {
      _editDate = r.date;
      _date = r.date;
      _omsetCtrl.text = _fmtRp(r.omset.round().toString());
      _expCtrl.text = r.expense;
      _cycleCtrl.text = '${r.cycle}';
      _dayCtrl.text = '${r.day}';
      _stokCycleLoaded = null;
    });
    _loadStokForCycle(w, r.cycle);
    _scrollToTop();
  }

  void _clearForm({String? scrollBackDate, int? scrollBackCycle}) {
    setState(() {
      _editDate = null;
      _date = _today();
      _omsetCtrl.clear();
      _expCtrl.clear();
      if (scrollBackCycle != null) _historyCycle = scrollBackCycle;
    });
    final w = widget.activeWarung;
    if (w != null) {
      _syncCycleDay(w, _date);
      final c = int.tryParse(_cycleCtrl.text.trim()) ?? _lastCycle(w);
      _stokCycleLoaded = null;
      _loadStokForCycle(w, c);
    }
    if (scrollBackDate != null) {
      _queueScrollToDate(scrollBackDate);
    }
  }

  void _cancelEdit(WarungData w) {
    final backDate = _editDate;
    int? backCycle;
    if (backDate != null) {
      final rec = w.records.where((r) => r.date == backDate).toList();
      if (rec.isNotEmpty) backCycle = rec.first.cycle;
    }
    _clearForm(scrollBackDate: backDate, scrollBackCycle: backCycle);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _date = picked.toString().substring(0, 10);
        if (_editDate != null && _editDate != _date) {
          _editDate = null;
          _omsetCtrl.clear();
          _expCtrl.clear();
        }
      });
      final w = widget.activeWarung;
      if (w != null) _syncCycleDay(w, _date);
    }
  }

  String _nextDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return _today();
    return d.add(const Duration(days: 1)).toString().substring(0, 10);
  }

  Future<void> _save(WarungData w) async {
    final omset = _parseRp(_omsetCtrl.text);
    if (omset <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi omset yang valid')));
      return;
    }
    final existing = w.records.where((r) => r.date == _date && r.date != _editDate).isNotEmpty;
    if (existing) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tanggal ini sudah terisi')));
      return;
    }

    final ac = cycleOfDate(_date, w.settings.cr);
    final autoSp = ac != null ? cycSpan(ac, w.settings.cr) : null;
    final autoCycle = ac ?? _allCycleNos(w).last;
    final autoDay = ac != null && autoSp != null ? (diffD(autoSp.s, _date) + 1).clamp(1, 31) : 1;
    final cycleRaw = _cycleCtrl.text.trim();
    final dayRaw = _dayCtrl.text.trim();
    final cycle = int.tryParse(cycleRaw);
    final day = int.tryParse(dayRaw);
    if (cycle == null || cycle < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Siklus harus angka >= 1')));
      return;
    }
    final maxDay = (ac != null && autoSp != null) ? autoSp.len : 31;
    if (day == null || day < 1 || day > maxDay) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hari harus 1-$maxDay')));
      return;
    }

    if (_editDate != null) {
      final old = w.records.where((r) => r.date == _editDate).toList();
      final oldRec = old.isNotEmpty ? old.first : null;
      final movedDate = _editDate != _date;
      final movedCycle = oldRec != null && oldRec.cycle != cycle;
      if (movedDate || movedCycle) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pindahkan catatan?'),
            content: Text(
              movedDate && movedCycle
                  ? 'Catatan akan dipindah dari $_editDate (Siklus ${oldRec?.cycle}) ke $_date (Siklus $cycle). Rekap dan bagi hasil akan berubah. Lanjutkan?'
                  : movedDate
                      ? 'Catatan akan dipindah dari $_editDate ke $_date. Rekap dapat berubah. Lanjutkan?'
                      : 'Catatan akan dipindah ke Siklus $cycle. Rekap dan bagi hasil akan berubah. Lanjutkan?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lanjutkan')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    final rec = OmRecord(
      date: _date,
      cycle: cycle,
      day: day,
      omset: omset.toDouble(),
      expense: _expCtrl.text.trim(),
    );

    _setStokForCycle(w, cycle);
    w.records.removeWhere((r) => r.date == _editDate || r.date == rec.date);
    w.records.add(rec);
    w.records.sort((a, b) => a.date.compareTo(b.date));
    await widget.onSaved();
    if (!mounted) return;
    final savedDate = rec.date;
    final savedCycle = rec.cycle;
    final next = _nextDate(_date);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Tersimpan'),
      action: next.compareTo(_today()) <= 0
          ? SnackBarAction(
              label: 'Isi tanggal berikutnya',
              onPressed: () {
                setState(() {
                  _editDate = null;
                  _date = next;
                  _omsetCtrl.clear();
                  _expCtrl.clear();
                  _scrollToDate = null;
                });
                _syncCycleDay(w, next);
                final c = int.tryParse(_cycleCtrl.text.trim()) ?? cycle;
                _stokCycleLoaded = null;
                _loadStokForCycle(w, c);
                _scrollToTop();
              },
            )
          : null,
    ));
    _clearForm(scrollBackDate: savedDate, scrollBackCycle: savedCycle);
  }

  Future<void> _delete(WarungData w, String date) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text('Hapus catatan tanggal $date?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    w.records.removeWhere((r) => r.date == date);
    await widget.onSaved();
    if (!mounted) return;
    if (_editDate == date) _clearForm();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Catatan dihapus')));
  }

  List<int> _allCycleNos(WarungData w) {
    final s = <int>{};
    for (final r in w.records) s.add(r.cycle);
    s.addAll(w.jagaModes.keys);
    s.addAll(w.cycleNames.keys);
    s.addAll(w.cyclePenjaga.keys);
    s.addAll(w.cycleStok.keys);
    s.addAll(w.kontrakOptions.keys);
    if (s.isEmpty) s.add(1);
    final list = s.toList()..sort();
    return list;
  }

  int _lastCycle(WarungData w) {
    final all = _allCycleNos(w);
    return all.last;
  }

  Future<void> _newCycle(WarungData w) async {
    final lc = _lastCycle(w);
    final cnt = w.records.where((r) => r.cycle == lc).length;
    if (cnt < 30) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Siklus Baru'),
          content: Text(cnt > 0
              ? 'Siklus $lc baru $cnt hari (belum 30 hari). Yakin ingin memulai siklus baru?'
              : 'Siklus $lc masih kosong (belum ada catatan). Yakin ingin membuat siklus baru?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buat Siklus Baru')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final c = lc + 1;
    final prevMode = w.jagaModes[lc] ?? w.settings.defMode;
    w.jagaModes[c] = prevMode;
    if (w.cycleNames[lc] != null) w.cycleNames[c] = Map<String, String>.from(w.cycleNames[lc]!);
    if (w.cyclePenjaga[lc] != null) {
      final prev = w.cyclePenjaga[lc]!;
      w.cyclePenjaga[c] = CustomGuards(pp: prev.pp, list: prev.list.map((g) => Guard(n: g.n, t: g.t, g: g.g)).toList());
    }
    w.deletedCycles.remove(c);
    await widget.onSaved();
    if (!mounted) return;
    final auto = cycleOfDate(_date, w.settings.cr) != null;
    if (!auto) {
      setState(() {
        _editDate = null;
        _omsetCtrl.clear();
        _expCtrl.clear();
        _cycleCtrl.text = '$c';
        _dayCtrl.text = '1';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siklus $c dibuat. Silakan isi omset untuk siklus baru.')));
    } else {
      _syncCycleDay(w, _date);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siklus $c disiapkan. Siklus aktif tetap mengikuti tanggal.')));
    }
  }

  bool _canDeleteCycle(WarungData w, int c) {
    if (w.records.any((r) => r.cycle == c)) return false;
    final prev = _allCycleNos(w).where((x) => x < c).fold<int?>(null, (p, x) => p == null || x > p ? x : p);
    if (prev == null) return false;
    final prevCnt = w.records.where((r) => r.cycle == prev).length;
    return prevCnt < 30;
  }

  Future<void> _deleteCycle(WarungData w, int c) async {
    if (w.records.any((r) => r.cycle == c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Siklus ini sudah berisi catatan')));
      return;
    }
    final prev = _allCycleNos(w).where((x) => x < c).fold<int?>(null, (p, x) => p == null || x > p ? x : p);
    if (prev == null || w.records.where((r) => r.cycle == prev).length >= 30) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Siklus sebelumnya sudah 30 hari, siklus tidak bisa dihapus')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus Siklus $c?'),
        content: Text('Hapus Siklus $c yang masih kosong? Mode dan nama karyawan siklus ini ikut terhapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus Siklus')),
        ],
      ),
    );
    if (ok != true) return;
    w.jagaModes.remove(c);
    w.kontrakOptions.remove(c);
    w.cycleNames.remove(c);
    w.cycleStok.remove(c);
    w.cyclePenjaga.remove(c);
    if (!w.deletedCycles.contains(c)) w.deletedCycles.add(c);
    await widget.onSaved();
    if (!mounted) return;
    _syncCycleDay(w, _date);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siklus $c dihapus')));
  }

  Widget _recentTile(WarungData w, OmRecord r) {
    final key = _recentKeys.putIfAbsent(r.date, () => GlobalKey());
    return Container(
      key: key,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFE6F2EF),
            child: Text('${r.day}', style: const TextStyle(fontSize: 12, color: Color(0xFF0F5C4D), fontWeight: FontWeight.bold)),
          ),
          title: Text(r.date, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${_dayName(r.date)} · Siklus ${r.cycle}${r.expense.isNotEmpty ? ' · ${r.expense}' : ''}'),
          trailing: Wrap(
            spacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(widget.rupiah(r.omset), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _loadForEdit(w, r)),
              IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _delete(w, r.date)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final w = widget.activeWarung;
    if (w == null) {
      return const Center(child: Text('Belum ada warung. Sinkronkan dulu dari Dashboard.'));
    }

    if (_cycleCtrl.text.isEmpty || _dayCtrl.text.isEmpty) _syncCycleDay(w, _date);
    final ac = cycleOfDate(_date, w.settings.cr);
    final auto = ac != null;
    final sp = auto ? cycSpan(ac!, w.settings.cr) : null;
    final cycle = int.tryParse(_cycleCtrl.text.trim()) ?? (ac ?? _allCycleNos(w).last);
    final day = int.tryParse(_dayCtrl.text.trim()) ?? 1;
    final existing = w.records.where((r) => r.date == _date && r.date != _editDate).toList();
    final miss = _missingDates(w, cycle);
    final preview = _parseRp(_omsetCtrl.text) * w.settings.pct / 100;
    final lc = _lastCycle(w);
    final canDel = _canDeleteCycle(w, lc);
    final allCycles = _allCycleNos(w);
    final lastCycle = allCycles.last;
    final historyCycle = (_historyCycle != null && allCycles.contains(_historyCycle)) ? _historyCycle! : lastCycle;
    _historyCycle = historyCycle;
    final recent = w.records.where((r) => r.cycle == historyCycle).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    _loadStokForCycle(w, cycle);
    final stokAwal = _parseNum(_stokAwalCtrl.text);
    final stokAkhir = _parseNum(_stokAkhirCtrl.text);
    final stokSelisih = (stokAwal != null && stokAkhir != null) ? (stokAkhir - stokAwal) : null;
    final syncBad = !widget.syncing && (widget.syncInfo ?? '').toLowerCase().contains('gagal');

    WidgetsBinding.instance.addPostFrameCallback((_) => _flushScrollToDate());
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        if (syncBad)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE57373))),
            child: Row(children: [
              const Icon(Icons.sync_problem, color: Color(0xFFC0392B), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Belum tersinkron: ${widget.syncInfo}', style: const TextStyle(color: Color(0xFFC0392B), fontSize: 12))),
            ]),
          ),
        if (st.warung.length > 1)
          DropdownButtonFormField<String>(
            value: w.id,
            decoration: InputDecoration(labelText: 'Warung', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: st.warung.map((x) => DropdownMenuItem(value: x.id, child: Text(x.settings.nama))).toList(),
            onChanged: (v) { if (v != null) widget.onWarungChanged(v); },
          ),
        if (st.warung.length > 1) const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_editDate == null ? 'Input Omset' : 'Edit Catatan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (miss.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF2A900)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tanggal terlewat', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...miss.take(5).map((d) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(child: Text(d)),
                                  TextButton(
                                    onPressed: () {
                                      setState(() { _date = d; _editDate = null; _omsetCtrl.clear(); _expCtrl.clear(); });
                                      _syncCycleDay(w, d);
                                    },
                                    child: const Text('Isi Tanggal Ini'),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Tanggal Operasional',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(_date),
                  ),
                ),
                if (existing.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE6C96A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF8A6D00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tanggal ini sudah memiliki catatan',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF8A6D00))),
                              const SizedBox(height: 2),
                              Text('Omset tercatat ${widget.rupiah(existing.first.omset)}. Anda bisa mengedit catatan yang sudah ada.',
                                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _loadForEdit(w, existing.first),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit Catatan'),
                                  style: TextButton.styleFrom(foregroundColor: Color(0xFF8A6D00), padding: EdgeInsets.zero),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cycleCtrl,
                        focusNode: _cycleFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _dayFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'Siklus Ke-',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (_) { _stokCycleLoaded = null; setState(() {}); },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dayCtrl,
                        focusNode: _dayFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _omsetFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'Hari Ke-${auto && sp != null ? ' (1–${sp.len})' : ''}',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (auto && sp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Siklus $cycle: ${sp.s} s/d ${sp.e} (${sp.len} hari). Otomatis mengikuti tanggal, bisa diedit.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0F5C4D))),
                  ),
                if (!auto)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Mode 30 hari tetap: Siklus/Hari diisi manual. Gunakan "Siklus Baru" untuk memulai siklus berikutnya.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0F5C4D))),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _newCycle(w),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Siklus Baru'),
                    ),
                    if (canDel)
                      OutlinedButton.icon(
                        onPressed: () => _deleteCycle(w, lc),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFC0392B)),
                        label: Text('Hapus Siklus $lc (kosong)', style: const TextStyle(color: Color(0xFFC0392B))),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFC0392B))),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _omsetCtrl,
                  focusNode: _omsetFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _expFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Omset Hari Ini',
                    hintText: 'Rp 0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) {
                    final f = _fmtRp(v);
                    if (f != v) {
                      _omsetCtrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                    }
                    setState(() {});
                  },
                ),
                const SizedBox(height: 4),
                Text('Tabungan ${w.settings.pct}%: ${widget.rupiah(preview)}',
                    style: const TextStyle(color: Color(0xFF0F5C4D))),
                const SizedBox(height: 12),
                TextField(
                  controller: _expCtrl,
                  focusNode: _expFocus,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _stokAwalFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Catatan Pengeluaran (informatif)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text('Stok Siklus $cycle', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _stokAwalCtrl,
                        focusNode: _stokAwalFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _stokAkhirFocus.requestFocus(),
                        decoration: InputDecoration(labelText: 'Stok Awal', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        onChanged: (v) {
                          final f = _fmtNum(v);
                          if (f != v) _stokAwalCtrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _stokAkhirCtrl,
                        focusNode: _stokAkhirFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _stokNoteFocus.requestFocus(),
                        decoration: InputDecoration(labelText: 'Stok Akhir', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        onChanged: (v) {
                          final f = _fmtNum(v);
                          if (f != v) _stokAkhirCtrl.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _stokNoteCtrl,
                  focusNode: _stokNoteFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(w),
                  decoration: InputDecoration(labelText: 'Catatan Stok (opsional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                if (stokSelisih != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Selisih Stok: ${stokSelisih >= 0 ? '+' : ''}${_fmtNum(stokSelisih.round().toString())}',
                    style: TextStyle(color: stokSelisih < 0 ? const Color(0xFFC0392B) : const Color(0xFF0F5C4D), fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _save(w),
                        child: Text(_editDate == null ? 'Simpan Omset' : 'Simpan Perubahan'),
                      ),
                    ),
                    if (_editDate != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: () => _cancelEdit(w), child: const Text('Batal')),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _delete(w, _editDate!),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC0392B), side: const BorderSide(color: Color(0xFFC0392B))),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Riwayat Terbaru', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${recent.length} catatan', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<int>(
                        value: historyCycle,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Siklus',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: allCycles.reversed.map((c) => DropdownMenuItem(value: c, child: Text('Siklus $c'))).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _historyCycle = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Belum ada catatan omset pada siklus ini.'),
                  )
                else if (recent.length > 10)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: true,
                    title: Text('Tampilkan ${recent.length} catatan', style: const TextStyle(fontSize: 13)),
                    children: recent.map((r) => _recentTile(w, r)).toList(),
                  )
                else
                  ...recent.map((r) => _recentTile(w, r)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.boss,
    required this.bs,
    required this.kt,
    required this.sb,
    required this.nst,
    required this.anyBagi,
    required this.rupiah,
  });

  final double boss;
  final double bs;
  final double kt;
  final double sb;
  final int nst;
  final bool anyBagi;
  final String Function(num) rupiah;

  @override
  Widget build(BuildContext context) {
    final stokLabel = nst > 0 ? ' & Stok' : '';
    final stokBreak = nst > 0 ? ' ${sb < 0 ? '-' : '+'} Stok ${rupiah(sb.abs())}' : '';
    return Card(
      color: const Color(0xFF0F5C4D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Pendapatan Pemilik Warung (+ Kontrak$stokLabel)',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              rupiah(boss),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${anyBagi ? 'Bagi hasil' : 'Sisa setelah gaji'} ${rupiah(bs)} + Kontrak ${rupiah(kt)}$stokBreak',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
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
    required this.cycles,
  });

  final WarungData warung;
  final String today;
  final String Function(num) rupiah;
  final List<int> cycles;

  @override
  Widget build(BuildContext context) {
    double boss = 0, bs = 0, kt = 0, sb = 0, omset = 0, tab = 0;
    var nst = 0;
    var anyBagi = false;
    int days = 0, len = 0;
    for (final c in cycles) {
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
      boss += x.bossT;
      bs += x.bossShare;
      kt += x.kontrak;
      sb += x.stBoss;
      omset += x.omset;
      tab += x.tab;
      days += x.days;
      len += x.len;
      if (x.nBagi > 0 || x.gajiTotal == 0) anyBagi = true;
      if (x.stok != null) nst++;
    }

    final cycleLabel = cycles.length == 1
        ? 'Siklus ${cycles.first}'
        : '${cycles.length} siklus';
    final stokBreak = nst > 0 ? ' ${sb < 0 ? '-' : '+'} Stok ${rupiah(sb.abs())}' : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warung.settings.nama,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('$cycleLabel · $days dari $len hari'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('Omset'), Text(rupiah(omset))],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('Tabungan'), Text(rupiah(tab))],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pendapatan pemilik',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(rupiah(boss),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Text(
              '${anyBagi ? 'Bagi hasil' : 'Sisa setelah gaji'} ${rupiah(bs)} + Kontrak ${rupiah(kt)}$stokBreak',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}


class _GuardAgg {
  _GuardAgg(this.name);
  final String name;
  double base = 0;
  double stk = 0;
  final Set<String> types = {};
  double get total => base + stk;
}

class _GuardCard extends StatelessWidget {
  const _GuardCard({required this.agg, required this.rupiah, required this.nst});
  final _GuardAgg agg;
  final String Function(num) rupiah;
  final int nst;

  @override
  Widget build(BuildContext context) {
    final t = agg.total;
    final typeLabel = agg.types.length > 1
        ? 'Gaji & bagi hasil'
        : (agg.types.contains('gaji') ? 'Gaji' : 'Bagi hasil');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(agg.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(rupiah(t),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: t < 0 ? const Color(0xFFC0392B) : null,
                    )),
              ],
            ),
            Text(
              '$typeLabel ${rupiah(agg.base)}${nst > 0 ? ' ${agg.stk < 0 ? '-' : '+'} Stok ${rupiah(agg.stk.abs())}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (t < 0)
              Text('Kurang bayar ke pemilik ${rupiah(-t)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: child),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.dates, required this.values, required this.rupiah});
  final List<String> dates;
  final Map<String, double> values;
  final String Function(num) rupiah;

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) return const Center(child: Text('Belum ada data omset harian'));
    final spots = <FlSpot>[];
    for (var i = 0; i < dates.length; i++) {
      spots.add(FlSpot(i.toDouble(), (values[dates[i]] ?? 0) / 1000.0));
    }
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}jt' : '${v.toStringAsFixed(0)}rb',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: dates.length > 6 ? (dates.length / 6).ceilToDouble() : 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= dates.length) return const SizedBox.shrink();
                final d = dates[i];
                final label = d.length >= 10 ? '${d.substring(8,10)}/${d.substring(5,7)}' : d;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF0F5C4D),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0x330F5C4D)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((t) {
              final i = t.x.toInt();
              final date = i >= 0 && i < dates.length ? dates[i] : '';
              return LineTooltipItem('$date\n${rupiah(t.y * 1000)}', const TextStyle(color: Colors.white));
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _CycleChart extends StatelessWidget {
  const _CycleChart({required this.cycles, required this.values, required this.rupiah});
  final List<int> cycles;
  final Map<int, double> values;
  final String Function(num) rupiah;

  @override
  Widget build(BuildContext context) {
    if (cycles.isEmpty) return const Center(child: Text('Belum ada data siklus'));
    final maxY = cycles.map((c) => (values[c] ?? 0) / 1000.0).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}jt' : '${v.toStringAsFixed(0)}rb',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= cycles.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('S${cycles[i]}', style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < cycles.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (values[cycles[i]] ?? 0) / 1000.0,
                color: const Color(0xFFF2A900),
                width: cycles.length > 8 ? 12 : 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) {
              final i = group.x;
              final c = i >= 0 && i < cycles.length ? cycles[i] : 0;
              return BarTooltipItem('Siklus $c\n${rupiah(rod.toY * 1000)}', const TextStyle(color: Colors.white));
            },
          ),
        ),
      ),
    );
  }
}
