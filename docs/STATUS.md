# Status Implementasi

## Sudah siap
- Toolchain Flutter 3.50.1 + Dart 3.14 (ARM64), JDK 17, Android SDK 35.
- Keystore lama diverifikasi: SHA-256 sama persis dengan `assetlinks.json`.
- Identitas Android: `com.rffamily.warmad`, signing release aktif.
- Golden vector domain (siklus + bagi hasil) diport ke Dart — **7 test lulus**.
- Engine sinkronisasi `pull → merge → push(baseRev)` + retry konflik — **2 test lulus**.
- Penyimpanan lokal JSON via platform channel, device ID dari `ANDROID_ID`.
- UI awal: aktivasi kode akses, sync manual, rekap siklus per warung.
- `.gitignore` menutup `.env`, `*.keystore`, `android/key.properties`.

## Build release
- `flutter build apk --release --target-platform android-arm64` **pernah** berhasil
  di mesin ini, menghasilkan `Omset-WarMad-v5.0.0-arm64-release.apk` (21 MB,
  ABI arm64-v8a, signed v2+v3, zipalign OK, SHA-256 APK
  `373c20a833e79ad2268d034e25bc4615f79e3dc1791b28bf476a55b9dd2ea49c`).
- **APK v5.0.0 cacat dan jangan dipakai.** `libapp.so`-nya dihasilkan oleh
  `gen_snapshot` Linux ARM64 sehingga berisi konfigurasi
  `release ... arm64 linux no-compressed-pointers`. VM Android membutuhkan
  `... arm64 android compressed-pointers`, maka `CreateRootIsolate failed` dan
  layar hitam.
- Perbaikan: versi dinaikkan ke **5.0.1+2**, build rilis dipindah ke host x86_64
  asli. Detail lengkap ada di [`docs/BUILD_RELEASE.md`](BUILD_RELEASE.md).
- Workflow GitHub Actions sudah disiapkan: `.github/workflows/build-release.yml`.

## Sedang dikerjakan
- Build ulang v5.0.1 di runner x86_64 (butuh akses repository GitHub / mesin x86_64).
- Setelah APK baru jadi: pasang ulang di Poco F7 dan cek logcat tidak ada
  `CreateRootIsolate failed`.

## Masih tertunda (sesuai rencana 3–5 bulan)
- Fase 2: Drift/SQLite, `WorkManager` sync otomatis, notifikasi tutup aplikasi.
- Fase 3: Login email OTP + Google Sign-In (butuh Android client ID dari SHA-1 `45:EC:B3:3D:E6:C6:8C:1F:76:A9:AA:12:EF:1F:4B:2F:41:93:7D:E6`).
- Fase 4: Modul lengkap — input omset, stok, karyawan, lisensi/Midtrans, ekspor PDF/Excel, chart, tema.
- Fase 5: Uji perangkat nyata, Play Store internal testing, monitoring.
- Konfirmasi env produksi: `MIDTRANS_ENV`, `HARGA`, `ADMIN_PASSWORD`, `SESSION_SECRET`, `ADMIN_TOTP_SECRET`.

## Catatan lingkungan build
Mesin ini berbasis ARM64 dengan runtime qroot. Flutter resmi hanya mendistribusikan
tool x86_64, sehingga dilakukan penyesuaian lokal:
- Dart SDK ARM64 dari `dart-archive` menggantikan Dart SDK bawaan.
- AAPT2 x86_64 dibungkus `qemu-x86_64-static`.
- `gen_snapshot` Android yang benar (x86_64) sudah dipasang sebagai wrapper QEMU,
  tetapi QEMU 8.2.2 selalu crash (`MAPERR addr=0x20`) saat menjalankan kompilasi
  AOT sungguhan. Lihat `docs/BUILD_RELEASE.md`.
Penyesuaian ini **hanya di mesin build**, bukan bagian dari aplikasi/repo.
