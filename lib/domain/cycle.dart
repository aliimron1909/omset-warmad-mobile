// Sistem siklus: 30 hari tetap, bulan kalender, dan tanggal serah terima.
/// Port langsung dari index.html (Omset-WarMad v4.0.4).
import 'models.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _parse(String s) => DateTime.parse('${s}T00:00:00');

int _dim(int y, int m) => DateTime(y, m + 1, 0).day;

String _addD(String dt, int n) => _iso(_parse(dt).add(Duration(days: n)));

int _diffD(String a, String b) =>
    _parse(b).difference(_parse(a)).inDays.round();

/// Periode satu siklus untuk tanggal [dt] dengan tanggal serah [d].
({String s, String e}) periodOf(String dt, int d) {
  final parts = dt.split('-').map(int.parse).toList();
  final y = parts[0], m = parts[1], dd = parts[2];
  int cl(int Y, int M) => d < _dim(Y, M) ? d : _dim(Y, M);

  var sy = y, sm = m;
  if (dd < cl(y, m)) {
    sm--;
    if (sm < 1) {
      sm = 12;
      sy--;
    }
  }
  var ny = sy, nm = sm + 1;
  if (nm > 12) {
    nm = 1;
    ny++;
  }
  return (
    s: '$sy-${sm.toString().padLeft(2, '0')}-'
        '${cl(sy, sm).toString().padLeft(2, '0')}',
    e: _addD(
        '$ny-${nm.toString().padLeft(2, '0')}-'
        '${cl(ny, nm).toString().padLeft(2, '0')}',
        -1),
  );
}

List<CycleRule> _seg(List<CycleRule> cr) {
  final rs = List<CycleRule>.from(cr);
  rs.sort((a, b) => a.n.compareTo(b.n));
  return rs;
}

CycleSpan? cycSpan(int c, List<CycleRule> cr) {
  final rs = _seg(cr);
  CycleRule? g;
  for (final x in rs) {
    if (x.n <= c) g = x;
  }
  if (g == null || g.d == 0) return null;

  var p = periodOf(g.s, g.d);
  var s = g.s, e = p.e;
  for (var i = g.n; i < c; i++) {
    p = periodOf(_addD(p.e, 1), g.d);
    s = p.s;
    e = p.e;
  }
  for (final nx in rs) {
    if (nx.n > c && nx.s.compareTo(e) <= 0) {
      e = _addD(nx.s, -1);
      break;
    }
  }
  return CycleSpan(s, e, _diffD(s, e) + 1);
}

int? cycleOfDate(String dt, List<CycleRule> cr) {
  final rs = _seg(cr);
  CycleRule? g;
  for (final x in rs) {
    if (x.s.compareTo(dt) <= 0) g = x;
  }
  if (g == null || g.d == 0) return null;

  var p = periodOf(g.s, g.d);
  var c = g.n;
  while (dt.compareTo(p.e) > 0) {
    p = periodOf(_addD(p.e, 1), g.d);
    c++;
  }
  return c;
}
