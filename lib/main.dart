import 'package:fl_chart/fl_chart.dart';
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
  String _cycleSel = 'running'; // running | all | <cycle number>

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
      final r = await _engine.sync(state: widget.state);
      if (!mounted) return;
      setState(() => _info = r.message);
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

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final today = DateTime.now().toString().substring(0, 10);
    final allCycles = _allCycles();

    // Agregasi total seperti web r1()
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
            DropdownButtonFormField<String>(
              value: cycleItems.any((i) => i.value == _cycleSel) ? _cycleSel : 'running',
              decoration: const InputDecoration(
                labelText: 'Tampilkan siklus',
                border: OutlineInputBorder(),
              ),
              items: cycleItems,
              onChanged: (v) => setState(() => _cycleSel = v ?? 'running'),
            ),
            const SizedBox(height: 12),
            _TotalCard(
              boss: boss,
              bs: bs,
              kt: kt,
              sb: sb,
              nst: nst,
              anyBagi: anyBagi,
              rupiah: _rupiah,
            ),
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
              const Text('Pendapatan Karyawan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                title: Text('Detail per warung · $selLabel',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
      ),
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
