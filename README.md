# Happy Bus — Laporan Pertanggungjawaban Crew

Aplikasi Android untuk membuat **Laporan Pertanggungjawaban Crew** dalam format PDF.
Dibuat dengan **Flutter**, menyimpan laporan secara lokal (SQLite), dan mengekspor ke PDF A4.

> Bahasa: Bahasa Indonesia · Mata uang: Rupiah (Rp) · Offline (tanpa server)

## Branch `lpj-only`

Branch ini berasal dari `main` dan mempertahankan tampilan Flutter terbaru untuk laporan pertanggungjawaban crew. Semua data disimpan secara offline tanpa backend atau konfigurasi online.

- Saat pertama membuka aplikasi, pengguna harus menambahkan satu bus dengan nama dan nomor polisi. Tidak ada enam slot bawaan.
- Menu **Daftar bus** menyediakan tambah bus, ubah identitas bus, dan pilih bus untuk laporan baru.
- **KM awal** dan **KM akhir** diisi manual pada setiap laporan. Keduanya tetap tampil di PDF. Tidak ada pelacakan kilometer, pengisian otomatis dari laporan sebelumnya, atau perhitungan jarak tempuh.
- Pelacakan oli, pengingat ganti oli, dan pencatatan ganti oli tidak tersedia.
- Laporan lama, lampiran struk, dan ekspor PDF tetap tersedia. Mengubah identitas bus tidak mengubah nomor polisi pada laporan lama.

Database versi 6 menambahkan tabel bus dan memindahkan identitas bus yang sudah tersimpan dari pengaturan lama. Pengaturan oli lama diabaikan. Migrasi tidak menghapus laporan, nilai KM manual, atau lampiran.

---

## ✨ Fitur

- **Form lengkap** sesuai contoh laporan asli:
  - Hari/Tgl Berangkat, Jam, Hari/Tgl Kembali, No. Polisi, Pengemudi, Kernet
  - KM Awal & KM Akhir sebagai isian manual
  - Uang saku, BBM, uang makan, extra, dan tagihan
  - Total & selisih (surplus/defisit) dihitung otomatis
  - Nama crew untuk tanda tangan
- **Pratinjau PDF** langsung di layar
- **Simpan** PDF ke perangkat (folder `HappyBus/`)
- **Bagikan** PDF (WhatsApp, email, dll.)
- **Cetak** langsung via printer
- **Daftar laporan tersimpan** — lihat, ubah, atau hapus

---

## 🛠 Persyaratan

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **>= 3.0.0** (Dart >= 3.0)
- Android Studio (atau command-line tools Android) untuk build APK
- Sebuah perangkat Android atau emulator

Cek instalasi:
```bash
flutter --version
flutter doctor
```

---

## 🚀 Menjalankan / Build

### 1. Pasang dependensi
```bash
cd happy_bus_crew
flutter pub get
```

### 2. Jalankan di emulator/perangkat (debug)
```bash
flutter run
```

### 3. Build APK (release)
```bash
flutter build apk --release
```
APK hasil build ada di:
```
build/app/outputs/flutter-apk/app-release.apk
```
Kirim file `.apk` tersebut ke HP Android, pasang, dan jalankan.

---

## 📁 Struktur Proyek

```
happy_bus_crew/
├── pubspec.yaml
├── README.md
├── assets/
│   └── logo.png              # logo placeholder — GANTI dengan logo asli
└── lib/
    ├── main.dart             # entry point + tema
    ├── models/
    │   └── report.dart       # model Report & LineItem
    ├── db/
    │   └── database.dart     # helper SQLite (CRUD)
    ├── utils/
    │   └── format.dart       # format Rupiah & tanggal Indonesia
    ├── pdf/
    │   └── report_pdf.dart   # builder dokumen PDF (layout laporan)
    └── screens/
        ├── bus_list_screen.dart # tambah, ubah, dan pilih bus
        ├── home_screen.dart  # daftar laporan
        ├── form_screen.dart  # form input semua field
        └── preview_screen.dart # pratinjau PDF + simpan/bagikan/cetak
```

---

## 🎨 Mengganti Logo

Ganti file `assets/logo.png` dengan logo **Happy Bus** asli (format PNG, transparan,
disarankan ukuran persegi ≥ 256×256 px). Tidak perlu mengubah kode — logo otomatis
dipakai di header PDF.

---

## 🔧 Kustomisasi Umum

| Yang ingin diubah          | File terkait |
|----------------------------|--------------|
| Warna tema aplikasi        | `lib/main.dart` (ColorSchemeSeed) |
| Logo & nama "Happy Bus"    | `assets/logo.png`, `lib/pdf/report_pdf.dart` |
| Label/judul pada PDF       | `lib/pdf/report_pdf.dart` |
| Format tanggal/mata uang   | `lib/utils/format.dart` |
| Skema database             | `lib/db/database.dart` |

---

## ❓ Pemecahan Masalah

**`flutter` tidak dikenal** — pasang Flutter SDK dulu, lalu jalankan `flutter doctor`.

**Build APK gagal (license)** — jalankan `flutter doctor --android-licenses` dan setujui.

**Permission penyimpanan** — jika tombol "Simpan" gagal di Android 11+,
pastikan izin penyimpanan diaktifkan di pengaturan aplikasi.

---

## 📄 Lisensi

Aplikasi ini dibuat sesuai permintaan untuk **Happy Bus**. Bebas dimodifikasi.
