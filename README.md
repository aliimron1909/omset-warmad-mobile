# Omset-WarMad Mobile

Versi native Flutter dari [Omset-WarMad](https://github.com/aliimron1909/omset-warmad).

Repositori web asli **tidak diubah** dan tetap dipakai sebagai panel admin.

## Prinsip
- Backend yang sama: `/api/sync`, `/api/lisensi`, `/api/stok`, `/api/akun`.
- Package id `com.rffamily.warmad`, ditandatangani dengan keystore yang sama seperti `assetlinks.json`.
- Aturan bisnis diport dari `index.html` v4.0.4 dan diuji dengan golden vector dari `tests/`.

## Menjalankan
```bash
flutter pub get
flutter test
flutter run
```

## Build rilis
Letakkan `android.keystore` di root dan isi `.env` (lihat `.env.example`), lalu:
```bash
flutter build apk --release
flutter build appbundle --release
```

Kunci dan password **tidak pernah** boleh di-commit.
