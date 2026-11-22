// Perhitungan bagi hasil, gaji, kontrak, dan selisih stok.
/// Port langsung dari fungsi calc()/guardsOf() di index.html v4.0.4.
import 'cycle.dart';
import 'models.dart';

String modeOf(int c, Map<int, String> jm, String defMode) {
  if (jm.containsKey(c)) return jm[c]!;
  final keys = jm.keys.where((k) => k < c).toList()..sort((a, b) => b.compareTo(a));
  return keys.isEmpty ? defMode : jm[keys.first]!;
}

String nameOf(int c, String f, Map<int, Map<String, String>> cn,
    AppSettings s) {
  final keys = cn.keys
      .where((k) => k <= c && (cn[k]?[f] ?? '').isNotEmpty)
      .toList()
    ..sort((a, b) => b.compareTo(a));
  if (keys.isNotEmpty) return cn[keys.first]![f]!;
  return f == 'k1' ? s.k1 : s.k2;
}

CustomGuards? pgOf(int c, Map<int, CustomGuards> pg) {
  if (pg.containsKey(c)) return pg[c];
  final keys = pg.keys.where((k) => k < c).toList()..sort((a, b) => b.compareTo(a));
  return keys.isEmpty ? null : pg[keys.first];
}

({double pp, List<Guard> list}) guardsOf(
  int c,
  AppSettings s,
  Map<int, String> jm,
  Map<int, Map<String, String>> cn,
  Map<int, CustomGuards> pg,
) {
  final m = modeOf(c, jm, s.defMode);
  List<Guard> leg(List<String> fs, double pp) => fs
      .map((f) => Guard(n: nameOf(c, f, cn, s), t: 'bagi', g: 0))
      .toList();

  if (m == 'pemilik_suami_istri') return (pp: 100, list: <Guard>[]);
  if (m == 'pemilik_1_karyawan') return (pp: 75, list: leg(['k1'], 75));
  if (m == 'karyawan_suami_istri') return (pp: 50, list: leg(['k1'], 50));
  if (m == 'dua_karyawan') return (pp: 50, list: leg(['k1', 'k2'], 50));

  final p = pgOf(c, pg) ?? const CustomGuards(pp: 50, list: []);
  if (m == 'suami_istri_gaji') {
    final g = p.list.isEmpty ? null : p.list.first;
    return (
      pp: 100,
      list: [
        Guard(
          n: (g?.n ?? '').trim().isEmpty ? nameOf(c, 'k1', cn, s) : g!.n.trim(),
          t: 'gaji',
          g: g?.g ?? 0,
        )
      ],
    );
  }
  return (pp: p.pp, list: p.list);
}

class ResolvedGuard {
  final String n;
  final String t;
  final double gFull;
  final double base;
  final double stk;
  final double total;

  const ResolvedGuard({
    required this.n,
    required this.t,
    required this.gFull,
    required this.base,
    required this.stk,
    required this.total,
  });
}

class CalcResult {
  final String mode;
  final double omset;
  final double tab;
  final int days;
  final int len;
  final bool ended;
  final CycleSpan? sp;
  final double pr;
  final double kontrak;
  final double net;
  final double gajiTotal;
  final int nBagi;
  final double pp;
  final List<ResolvedGuard> guards;
  final double boss;
  final double bossShare;
  final ({double awal, double akhir, double sel, String note})? stok;
  final double stBoss;
  final double bossT;
  final String? start;
  final String? end;

  const CalcResult({
    required this.mode,
    required this.omset,
    required this.tab,
    required this.days,
    required this.len,
    required this.ended,
    required this.sp,
    required this.pr,
    required this.kontrak,
    required this.net,
    required this.gajiTotal,
    required this.nBagi,
    required this.pp,
    required this.guards,
    required this.boss,
    required this.bossShare,
    required this.stok,
    required this.stBoss,
    required this.bossT,
    required this.start,
    required this.end,
  });
}

CalcResult calc(
  int c, {
  required List<OmRecord> records,
  required AppSettings s,
  required Map<int, String> jm,
  required Map<int, Map<String, String>> cn,
  required Map<int, CustomGuards> pg,
  required Map<int, String> ko,
  required Map<int, CycleStok> sk,
  required String today,
}) {
  final rs = records
      .where((r) => r.cycle == c)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final omset = rs.fold<double>(0, (sum, r) => sum + r.omset);
  final tab = omset * s.pct / 100;
  final days = rs.length;

  final gd = guardsOf(c, s, jm, cn, pg);
  final L = gd.list;
  final pp = gd.pp;
  final nBagi = L.where((g) => g.t == 'bagi').length;
  final sp = cycSpan(c, s.cr);
  final len = sp?.len ?? 30;
  final ended = days >= len || (sp != null && today.compareTo(sp.e) > 0);
  final pr = (sp != null && ended) ? 1.0 : (days > len ? len : days) / len;

  final gajiTotal = L.where((g) => g.t == 'gaji')
      .fold<double>(0, (sum, g) => sum + g.g * pr);

  final opt = ko[c] ?? 'zero';
  var kontrak = nBagi == 0
      ? 0.0
      : opt == 'full'
          ? s.kontrak.toDouble()
          : opt == 'prorata'
              ? s.kontrak * pr
              : 0.0;
  if (ended && nBagi > 0) kontrak = s.kontrak.toDouble();

  final net = tab - gajiTotal - kontrak;
  final bossShare = nBagi > 0 ? net * pp / 100 : net;
  final boss = bossShare + kontrak;

  final guards = L
      .map((g) => ResolvedGuard(
            n: g.n,
            t: g.t,
            gFull: g.g,
            base: g.t == 'gaji'
                ? g.g * pr
                : (nBagi > 0 ? net * (100 - pp) / 100 / nBagi : 0.0),
            stk: 0,
            total: 0,
          ))
      .toList();

  final st = sk[c];
  final hasSt = st != null && st.awal != null && st.akhir != null;
  final sel = hasSt ? st.akhir! - st.awal! : 0.0;
  var sB = 0.0;
  if (hasSt) {
    if (sel >= 0) {
      if (nBagi > 0) {
        sB = sel * pp / 100;
        for (final g in guards) {
          if (g.t == 'bagi') {
            final i = guards.indexOf(g);
            guards[i] = ResolvedGuard(
              n: g.n,
              t: g.t,
              gFull: g.gFull,
              base: g.base,
              stk: sel * (100 - pp) / 100 / nBagi,
              total: g.base + sel * (100 - pp) / 100 / nBagi,
            );
          }
        }
      } else {
        sB = sel;
      }
    } else if (guards.isNotEmpty) {
      for (var i = 0; i < guards.length; i++) {
        final g = guards[i];
        guards[i] = ResolvedGuard(
          n: g.n,
          t: g.t,
          gFull: g.gFull,
          base: g.base,
          stk: sel / guards.length,
          total: g.base + sel / guards.length,
        );
      }
    } else {
      sB = sel;
    }
  }
  for (var i = 0; i < guards.length; i++) {
    final g = guards[i];
    guards[i] = ResolvedGuard(
      n: g.n,
      t: g.t,
      gFull: g.gFull,
      base: g.base,
      stk: g.stk,
      total: g.base + g.stk,
    );
  }

  return CalcResult(
    mode: modeOf(c, jm, s.defMode),
    omset: omset,
    tab: tab,
    days: days,
    len: len,
    ended: ended,
    sp: sp,
    pr: pr,
    kontrak: kontrak,
    net: net,
    gajiTotal: gajiTotal,
    nBagi: nBagi,
    pp: pp,
    guards: guards,
    boss: boss,
    bossShare: bossShare,
    stok: hasSt
        ? (awal: st.awal!, akhir: st.akhir!, sel: sel, note: st.note)
        : null,
    stBoss: sB,
    bossT: boss + sB,
    start: rs.isEmpty ? null : rs.first.date,
    end: rs.isEmpty ? null : rs.last.date,
  );
}
