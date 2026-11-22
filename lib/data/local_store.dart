// Penyimpanan lokal berbasis file JSON di direktori privat aplikasi.
/// Memakai platform channel sehingga tidak memerlukan plugin tambahan.
import 'dart:io';

import 'package:flutter/services.dart';

import 'sync.dart';

class DeviceInfo {
  static const _channel = MethodChannel('warmad/device');

  static Future<String> androidId() async {
    try {
      return await _channel.invokeMethod<String>('getAndroidId') ?? '';
    } on MissingPluginException {
      return '';
    }
  }
}

class FileSyncStore implements SyncStore {
  FileSyncStore({this.fileName = 'warmad-state.json'});

  static const _channel = MethodChannel('warmad/storage');
  final String fileName;

  Future<File> get _file async {
    String dir;
    try {
      dir = await _channel.invokeMethod<String>('getDocumentsPath') ?? '.';
    } on MissingPluginException {
      dir = '.';
    }
    return File('$dir${Platform.pathSeparator}$fileName');
  }

  @override
  Future<LocalState> load() async {
    try {
      final f = await _file;
      if (!await f.exists()) return LocalState();
      return LocalState.deserialize(await f.readAsString());
    } catch (_) {
      // File rusak: jangan menggagalkan aplikasi, mulai dari keadaan kosong.
      return LocalState();
    }
  }

  @override
  Future<void> save(LocalState state) async {
    final f = await _file;
    await f.writeAsString(state.serialize());
  }
}
