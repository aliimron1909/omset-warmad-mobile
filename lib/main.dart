import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/local_store.dart';
import 'data/sync.dart';
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
  String _cycleSel = 'running'; // running | all | <cycle number>
  int _tab = 0;
  String? _activeWarungId;

  @override
  void initState() {
    super.initState();
    _engine = SyncEngine(api: api, store: widget.store);
    _activeWarungId = widget.state.warung.isNotEmpty ? widget.state.warung.first.id : null;
  }

  WarungData? get _activeWarung {
    final st = widget.state;
    if (st.warung.isEmpty) return null;
    final id = _activeWarungId;
    return st.warung.firstWhere((w) => w.id == id, orElse: () => st.warung.first);
  }

  Future<void> _sync() async {
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
          const _PlaceholderTab(title: 'Pengaturan', icon: Icons.settings),
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
              leading: Icon(st.premium ? Icons.workspace_premium : Icons.cloud_done),
              title: Text(st.premium ? 'Premium aktif' : 'Akun gratis'),
              subtitle: Text(
                st.lastSync == null
                    ? 'Belum pernah sinkron'
                    : 'Sinkron terakhir: ${st.lastSync!.toLocal()}',
              ),
              trailing: st.premium
                  ? Text('rev ${st.rev ?? '-'}')
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

class InputTab extends StatefulWidget {
  const InputTab({
    super.key,
    required this.state,
    required this.store,
    required this.activeWarung,
    required this.onWarungChanged,
    required this.onSaved,
    required this.rupiah,
  });

  final LocalState state;
  final SyncStore store;
  final WarungData? activeWarung;
  final ValueChanged<String> onWarungChanged;
  final Future<void> Function() onSaved;
  final String Function(num) rupiah;

  @override
  State<InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  final _omsetCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _cycleCtrl = TextEditingController();
  final _dayCtrl = TextEditingController();
  late String _date;
  String? _editDate;

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
    }
  }

  @override
  void dispose() {
    _omsetCtrl.dispose();
    _expCtrl.dispose();
    _cycleCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  String _dayName(String iso) {
    const names = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return names[d.weekday - 1];
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
        final maxCycle = w.records.isEmpty
            ? 1
            : w.records.map((r) => r.cycle).reduce((a, b) => a > b ? a : b);
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
    });
  }

  void _clearForm() {
    setState(() {
      _editDate = null;
      _date = _today();
      _omsetCtrl.clear();
      _expCtrl.clear();
    });
    final w = widget.activeWarung;
    if (w != null) _syncCycleDay(w, _date);
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
    final autoCycle = ac ?? (w.records.isEmpty ? 1 : w.records.map((r) => r.cycle).reduce((a, b) => a > b ? a : b));
    final autoDay = ac != null && autoSp != null ? (diffD(autoSp.s, _date) + 1).clamp(1, 31) : 1;
    final cycle = int.tryParse(_cycleCtrl.text.trim()) ?? autoCycle;
    final day = (int.tryParse(_dayCtrl.text.trim()) ?? autoDay).clamp(1, 31);

    final rec = OmRecord(
      date: _date,
      cycle: cycle,
      day: day.clamp(1, 31),
      omset: omset.toDouble(),
      expense: _expCtrl.text.trim(),
    );

    w.records.removeWhere((r) => r.date == _editDate || r.date == rec.date);
    w.records.add(rec);
    w.records.sort((a, b) => a.date.compareTo(b.date));
    await widget.onSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tersimpan')));
    _clearForm();
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

  Widget _recentTile(WarungData w, OmRecord r) {
    return Card(
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
    final cycle = int.tryParse(_cycleCtrl.text.trim()) ?? (ac ?? (w.records.isEmpty ? 1 : w.records.map((r) => r.cycle).reduce((a, b) => a > b ? a : b)));
    final day = int.tryParse(_dayCtrl.text.trim()) ?? 1;
    final existing = w.records.where((r) => r.date == _date && r.date != _editDate).toList();
    final miss = _missingDates(w, cycle);
    final preview = _parseRp(_omsetCtrl.text) * w.settings.pct / 100;
    final runningCycle = cycleOfDate(_today(), w.settings.cr) ??
        (w.records.isEmpty ? 1 : w.records.map((r) => r.cycle).reduce((a, b) => a > b ? a : b));
    final recent = w.records.where((r) => r.cycle == runningCycle).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                      color: const Color(0xFFF3F7F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFB7D1CB)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF0F5C4D)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tanggal ini sudah memiliki catatan',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F5C4D))),
                              const SizedBox(height: 2),
                              Text('Omset tercatat ${widget.rupiah(existing.first.omset)}. Anda bisa mengedit catatan yang sudah ada.',
                                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _loadForEdit(w, existing.first),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit Catatan'),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
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
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Siklus Ke-',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dayCtrl,
                        keyboardType: TextInputType.number,
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
                const SizedBox(height: 12),
                TextField(
                  controller: _omsetCtrl,
                  keyboardType: TextInputType.number,
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
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Catatan Pengeluaran (informatif)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
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
                      OutlinedButton(onPressed: _clearForm, child: const Text('Batal')),
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
          child: recent.length > 10
              ? ExpansionTile(
                  initiallyExpanded: true,
                  title: Text('Riwayat Terbaru · Siklus $runningCycle',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  subtitle: Text('${recent.length} catatan'),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    if (recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Belum ada catatan omset pada siklus berjalan.'),
                      )
                    else
                      ...recent.map((r) => _recentTile(w, r)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Riwayat Terbaru · Siklus $runningCycle',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        subtitle: Text('${recent.length} catatan'),
                      ),
                      if (recent.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Belum ada catatan omset pada siklus berjalan.'),
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
