# Build APK rilis

## Kenapa tidak bisa dibangun di mesin ARM64 lokal

Flutter 3.50.1 hanya mendistribusikan `gen_snapshot` untuk target Android/arm64
dalam bentuk biner **x86_64**. Mesin build saat ini adalah ARM64 (qroot), sehingga
biner itu harus dijalankan lewat emulator `qemu-x86_64-static`.

Hasil pengujian:

- `qemu-x86_64-static ... gen_snapshot --version` → berhasil.
- `qemu-x86_64-static ... gen_snapshot --snapshot_kind=app-aot-elf ...` → selalu
  gagal dengan `QEMU internal SIGSEGV {code=MAPERR, addr=0x20}`, baik untuk
  `app.dill` aplikasi maupun kernel "hello world" 8 MB.
- Percobaan `-cpu max`, `-one-insn-per-tb`, `QEMU_RESERVED_VA`,
  `QROOT_STUB_BLOCK_TARGET_SECCOMP=0`, dan `box64` 0.4.4 tidak membantu.

Memaksa memakai `gen_snapshot` ARM64 dari `engine/linux-arm64` menghasilkan
snapshot dengan konfigurasi `linux no-compressed-pointers`, yang ditolak VM
Android (`android compressed-pointers`) — inilah penyebab layar hitam pada APK
`v5.0.0`.

Kesimpulan: **build rilis harus dijalankan di host x86_64 asli** (GitHub Actions
`ubuntu-latest`, VM x86_64, atau mesin lokal x86_64).

## Cara build lewat GitHub Actions

Workflow: `.github/workflows/build-release.yml`.

Tambahkan empat repository secrets:

| Secret | Isi |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android.keystore` |
| `ANDROID_STORE_PASSWORD` | password keystore |
| `ANDROID_KEY_ALIAS` | alias kunci (lihat `android/key.properties`) |
| `ANDROID_KEY_PASSWORD` | password kunci |

Lalu jalankan **Actions → Build Release APK → Run workflow**, atau push tag `v*`.
Artifact APK bisa diunduh dari halaman run tersebut.

Workflow memakai Flutter 3.50.1 x86_64 native, JDK 17, Android SDK 35 dan NDK
28.2.13676358. Signing memakai keystore yang sama, sehingga SHA-256 signer tetap
`9C:94:A7:4A:2E:73:A1:B0:C9:F2:33:02:75:83:76:B0:4B:99:0B:DC:6B:74:DF:91:84:E2:FC:AE:86:7C:2D:47`
(sama dengan `assetlinks.json`).

## Cara build manual di host x86_64

```bash
# Siapkan keystore (jangan pernah di-commit)
cp /path/ke/android.keystore android/app/warmad-release.jks
cat > android/key.properties <<EOF
storeFile=app/warmad-release.jks
storePassword=...
keyAlias=...
keyPassword=...
EOF

flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64

# Verifikasi
$ANDROID_SDK_ROOT/build-tools/35.0.0/zipalign -c -v 4 \
  build/app/outputs/flutter-apk/app-release.apk
$ANDROID_SDK_ROOT/build-tools/35.0.0/apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

# Pasang
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Verifikasi setelah pasang

Pastikan logcat tidak lagi berisi:

```
CreateRootIsolate failed: Snapshot not compatible with the current VM configuration
```

Baris `libapp.so` harus berisi string konfigurasi `android compressed-pointers`:

```bash
strings -a <(unzip -p app-release.apk lib/arm64-v8a/libapp.so) | grep compressed-pointers
```
