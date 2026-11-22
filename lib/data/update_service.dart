import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String tag;
  final String releaseUrl;
  final String? apkUrl;
  final String notes;
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tag,
    required this.releaseUrl,
    required this.apkUrl,
    required this.notes,
    required this.hasUpdate,
  });
}

class UpdateService {
  UpdateService({http.Client? client, this.owner = 'aliimron1909', this.repo = 'omset-warmad-mobile'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;
  static const _updateChannel = MethodChannel('warmad/update');

  Future<UpdateInfo> check(String currentVersion) async {
    final uri = Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');
    final res = await _client.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Omset-WarMad/$currentVersion',
    });
    if (res.statusCode != 200) {
      throw Exception('Gagal cek update (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').trim();
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    final releaseUrl = (j['html_url'] as String?) ?? 'https://github.com/$owner/$repo/releases';
    final notes = (j['body'] as String?) ?? '';
    String? apkUrl;
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = a['browser_download_url'] as String?;
            if (name.contains('arm64')) break;
          }
        }
      }
    }
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latest.isEmpty ? currentVersion : latest,
      tag: tag.isEmpty ? 'v$currentVersion' : tag,
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
      notes: notes.trim(),
      hasUpdate: _isNewer(latest, currentVersion),
    );
  }

  Future<File> downloadApk(String url, {void Function(int received, int total)? onProgress}) async {
    final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!await updatesDir.exists()) await updatesDir.create(recursive: true);
    final name = Uri.parse(url).pathSegments.isNotEmpty ? Uri.parse(url).pathSegments.last : 'update.apk';
    final file = File('${updatesDir.path}/$name');
    final req = http.Request('GET', Uri.parse(url));
    req.headers['User-Agent'] = 'Omset-WarMad-Updater';
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw Exception('Gagal mengunduh update (${res.statusCode})');
    }
    final total = res.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
    return file;
  }

  Future<void> installApk(File file) async {
    await _updateChannel.invokeMethod('installApk', {'path': file.path});
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String v) {
      final clean = v.split('+').first.split('-').first;
      return clean.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    }
    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }
}
