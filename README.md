# Happy Bus — Laporan Pertanggungjawaban Crew

Aplikasi Android untuk membuat **Laporan Pertanggungjawaban Crew** dalam format PDF.
Dibuat dengan **Flutter**, menyimpan laporan secara lokal (SQLite), dan mengekspor ke PDF A4.

> Bahasa: Bahasa Indonesia · Mata uang: Rupiah (Rp) · Offline (tanpa server)

## Branch `lpj-only`

Branch ini berasal dari `main` dan mempertahankan tampilan Flutter terbaru untuk laporan pertanggungjawaban crew. Semua data disimpan secara offline tanpa backend atau konfigurasi online.

- Saat pertama membuka aplikasi, pengguna harus menambahkan satu bus dengan nama dan nomor polisi. Tidak ada enam slot bawaan.
- Menu **Daftar bus** menyediakan tambah bus, ubah identitas bus, pilih bus, dan hapus bus yang belum digunakan dalam laporan. Penghapusan memerlukan konfirmasi. Bus dengan nomor polisi yang masih tercatat dalam laporan tidak dapat dihapus.
- Riwayat laporan menampilkan nama bus yang nomor polisinya cocok dengan daftar bus saat ini. Pencarian menerima nama bus, nomor polisi, nama crew, dan tanggal. Jika nomor polisi lama tidak lagi cocok, laporan tetap menampilkan nomor polisi dan pengemudi.
- **KM awal** dan **KM akhir** diisi manual pada setiap laporan. Keduanya tetap tampil di PDF. Tidak ada pelacakan kilometer, pengisian otomatis dari laporan sebelumnya, atau perhitungan jarak tempuh.
- Pelacakan oli, pengingat ganti oli, dan pencatatan ganti oli tidak tersedia.
- Laporan lama, lampiran gambar, dan ekspor PDF tetap tersedia. Mengubah identitas bus tidak mengubah nomor polisi pada laporan lama.

Database versi 9 menambahkan jumlah LK dan DK secara terpisah. Isian jumlah LK dan DK bersifat opsional; jika kosong, PDF menampilkan tanda `-`. Laporan lama tetap kosong untuk jumlah yang belum pernah dicatat, bukan dianggap 0 atau 1, dan tetap menampilkan kategori lama dari versi 8 jika ada. Database versi 10 memisahkan **Pembayaran tagihan** dari pengeluaran. Nilai Tagihan lama dikosongkan saat migrasi agar tidak dianggap sebagai pembayaran klien. Migrasi versi 7 menambahkan rincian Extra tanpa mengubah laporan lama, nilai KM manual, atau lampiran. Nominal Extra lama tampil sebagai satu item **Extra lama** yang dapat diganti namanya. Migrasi dari versi sebelum 6 tetap memindahkan identitas bus dari pengaturan lama dan mengabaikan pengaturan oli.

---

## ✨ Fitur

- **Form lengkap** sesuai contoh laporan asli:
  - Hari/Tgl Berangkat, Jam, Hari/Tgl Kembali, No. Polisi, Pengemudi, Kernet
  - Jumlah **Luar Kota (LK)** dan **Dalam Kota (DK)** dapat diisi terpisah, misalnya LK 3 dan DK 5 dalam satu laporan. Keduanya opsional. Nilai 0 berarti tidak ada perjalanan, sedangkan isian kosong tampil sebagai `-` di PDF.
  - KM Awal & KM Akhir sebagai isian manual
  - Uang saku dan rincian pengeluaran: BBM, uang makan, lalu Extra. **Pembayaran tagihan** dari klien dicatat terpisah sebagai uang tunai yang dibayarkan kepada crew, bukan sebagai pengeluaran dan tidak mengubah sisa uang saku.
  - Extra dapat berisi banyak item. Tombol **Tambah Extra** menambah baris nama dan harga dalam rupiah. Setiap baris wajib memiliki nama dan harga lebih dari nol, atau dihapus jika tidak digunakan.
  - Nama dan harga setiap Extra tersimpan di laporan dan tampil di PDF. Total Extra dihitung dari seluruh item.
  - Total & selisih (surplus/defisit) dihitung otomatis
  - Nama crew untuk tanda tangan
- **Pratinjau PDF** dengan pinch-to-zoom, ketuk dua kali, tombol perbesar dan perkecil, serta reset zoom. Panah halaman membuka setiap halaman laporan dan lampiran.
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

### Build melalui GitHub

Push ke `lpj-only` atau `main` menjalankan workflow **Build APK** dengan Flutter 3.27.4 dan Java 17. Workflow menjalankan analisis kode dan tes otomatis sebelum membuat APK Android.

1. Buka tab **Actions** di GitHub dan pilih run **Build APK** untuk commit yang ingin diuji.
2. Setelah run berhasil, unduh artifact **happy-bus-crew-apk**.
3. Ekstrak ZIP, lalu pasang `app-release.apk` pada HP Android.
4. Uji pengelolaan bus, penyimpanan laporan, kamera, dan ekspor PDF pada HP.

Workflow juga dapat dijalankan secara manual melalui **Run workflow**. Pilih branch `lpj-only` untuk build fitur ini tanpa mengubah `main`.

Tanpa keystore rilis, APK CI menggunakan kunci debug. Gunakan APK ini untuk pengujian perangkat, bukan distribusi produksi.

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
        ├── bus_list_screen.dart # tambah, ubah, pilih, dan hapus bus
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
