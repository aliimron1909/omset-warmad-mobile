// Klien REST untuk backend Omset-WarMad yang sudah ada.
/// Tidak ada perubahan server yang diperlukan.
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? 'https://www.omsetwarmad.click',
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    var uri = Uri.parse('$baseUrl$path');
    final payload = jsonEncode(body);
    const headers = {
      'Content-Type': 'text/plain;charset=utf-8',
      'Accept': 'application/json',
    };
    http.Response r;
    try {
      r = await _client
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 25));
      // Beberapa host mengembalikan 307/308 (mis. apex -> www). Ikuti sekali.
      if (_isRedirect(r.statusCode)) {
        final location = r.headers['location'];
        if (location != null && location.isNotEmpty) {
          uri = uri.resolve(location);
          r = await _client
              .post(uri, headers: headers, body: payload)
              .timeout(const Duration(seconds: 25));
        }
      }
    } on http.ClientException catch (e) {
      throw ApiException('Gagal menghubungi server: ${e.message}');
    } on Exception catch (e) {
      throw ApiException('Gagal menghubungi server: $e');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException('Server bermasalah (${r.statusCode})',
          status: r.statusCode);
    }
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) {
        throw ApiException('Balasan server tidak dikenali');
      }
      return decoded;
    } on FormatException {
      throw ApiException('Balasan server rusak');
    }
  }

  static bool _isRedirect(int status) => status == 307 || status == 308;

  // ---------- sync ----------
  Future<Map<String, dynamic>> syncRegister(String code, String device) =>
      post('/api/sync', {
        'action': 'register',
        'code': code,
        'device': device,
      });

  Future<Map<String, dynamic>> syncPull(String key, String device) =>
      post('/api/sync', {
        'action': 'pull',
        'key': key,
        'device': device,
      });

  Future<Map<String, dynamic>> syncAll({
    required String key,
    required String device,
    required bool premium,
    required int? baseRev,
    required List<Map<String, dynamic>> warung,
  }) =>
      post('/api/sync', {
        'action': 'syncAll',
        'key': key,
        'device': device,
        'premium': premium,
        if (baseRev != null) 'baseRev': baseRev,
        'warung': warung,
      });

  Future<Map<String, dynamic>> syncAccess({
    required String key,
    required String device,
    required String action,
    String? code,
    String? status,
  }) =>
      post('/api/sync', {
        'action': action,
        'key': key,
        'device': device,
        if (code != null) 'code': code,
        if (status != null) 'status': status,
      });

  // ---------- lisensi & pembayaran ----------
  Future<Map<String, dynamic>> licActivate(String code, String device) =>
      post('/api/lisensi', {
        'action': 'activate',
        'code': code,
        'device': device,
      });

  Future<Map<String, dynamic>> licCheck(String code, String device) =>
      post('/api/lisensi', {
        'action': 'check',
        'code': code,
        'device': device,
      });

  Future<Map<String, dynamic>> createOrder(String device) =>
      post('/api/lisensi', {'action': 'createOrder', 'device': device});

  Future<Map<String, dynamic>> checkOrder(String device, String order) =>
      post('/api/lisensi', {
        'action': 'checkOrder',
        'device': device,
        'order': order,
      });

  // ---------- akun (email OTP / Google) ----------
  Future<Map<String, dynamic>> akun(String action, String device,
          [Map<String, dynamic> extra = const {}]) =>
      post('/api/akun', {
        'action': action,
        'device': device,
        ...extra,
      });

  // ---------- stok ----------
  Future<Map<String, dynamic>> stok(String action, String device,
          [Map<String, dynamic> extra = const {}]) =>
      post('/api/stok', {
        'action': action,
        'device': device,
        ...extra,
      });
}
