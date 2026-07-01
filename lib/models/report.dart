/// Model data untuk Laporan Pertanggungjawaban Crew.
///
/// Satu [Report] berisi seluruh field pada form: info header, kilometer,
/// field keuangan (uang saku, BBM, uang makan, extra, tagihan),
/// serta data tanda tangan crew.

class Report {
  int? id;
  DateTime tanggalBuat; // kapan laporan ini dibuat/diisi

  // --- Info header (kiri) ---
  String hariTglBerangkat; // "Senin, 01/01/2024"
  String jamBerangkat; // "08:00"
  String hariTglKembali; // "Rabu, 03/01/2024"
  String noPolisi; // "B 1234 XX"
  String pengemudi; // nama sopir
  String kernet; // nama kernet/asisten

  // --- Kilometer ---
  int kmAwal;
  int kmAkhir;

  // --- Keuangan ---
  int uangSaku;
  int bbm;
  int uangMakan;
  int extra;
  int tagihan;

  // --- Tanda tangan ---
  String namaCrew; // nama pembuat laporan (penanda tangan)

  // --- Catatan (opsional) ---
  String catatan;

  Report({
    this.id,
    DateTime? tanggalBuat,
    required this.hariTglBerangkat,
    required this.jamBerangkat,
    required this.hariTglKembali,
    required this.noPolisi,
    required this.pengemudi,
    required this.kernet,
    required this.kmAwal,
    required this.kmAkhir,
    required this.uangSaku,
    required this.bbm,
    required this.uangMakan,
    required this.extra,
    required this.tagihan,
    required this.namaCrew,
    this.catatan = '',
  }) : tanggalBuat = tanggalBuat ?? DateTime.now();

  /// Total pengeluaran = BBM + Uang Makan + Extra + Tagihan.
  int get totalPengeluaran => bbm + uangMakan + extra + tagihan;

  /// Sisa = Uang Saku - total pengeluaran.
  int get sisa => uangSaku - totalPengeluaran;

  /// Jumlah KM yang ditempuh.
  int get jarakTempuh => kmAkhir - kmAwal;

  /// Label ringkas untuk ditampilkan di daftar laporan (Home).
  String get ringkas =>
      '${noPolisi.isEmpty ? "-" : noPolisi} • ${pengemudi.isEmpty ? "-" : pengemudi}';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal_buat': tanggalBuat.toIso8601String(),
      'hari_tgl_berangkat': hariTglBerangkat,
      'jam_berangkat': jamBerangkat,
      'hari_tgl_kembali': hariTglKembali,
      'no_polisi': noPolisi,
      'pengemudi': pengemudi,
      'kernet': kernet,
      'km_awal': kmAwal,
      'km_akhir': kmAkhir,
      'uang_saku': uangSaku,
      'bbm': bbm,
      'uang_makan': uangMakan,
      'extra': extra,
      'tagihan': tagihan,
      'nama_crew': namaCrew,
      'catatan': catatan,
    };
  }

  factory Report.fromMap(Map<String, dynamic> map) {
    return Report(
      id: map['id'] as int?,
      tanggalBuat: DateTime.tryParse(map['tanggal_buat'] as String? ?? '') ??
          DateTime.now(),
      hariTglBerangkat: map['hari_tgl_berangkat'] as String? ?? '',
      jamBerangkat: map['jam_berangkat'] as String? ?? '',
      hariTglKembali: map['hari_tgl_kembali'] as String? ?? '',
      noPolisi: map['no_polisi'] as String? ?? '',
      pengemudi: map['pengemudi'] as String? ?? '',
      kernet: map['kernet'] as String? ?? '',
      kmAwal: map['km_awal'] as int? ?? 0,
      kmAkhir: map['km_akhir'] as int? ?? 0,
      uangSaku: map['uang_saku'] as int? ?? 0,
      bbm: map['bbm'] as int? ?? 0,
      uangMakan: map['uang_makan'] as int? ?? 0,
      extra: map['extra'] as int? ?? 0,
      tagihan: map['tagihan'] as int? ?? 0,
      namaCrew: map['nama_crew'] as String? ?? '',
      catatan: map['catatan'] as String? ?? '',
    );
  }

  /// Salinan dengan satu field diubah — mempermudah update dari form.
  Report copyWith({
    int? id,
    DateTime? tanggalBuat,
    String? hariTglBerangkat,
    String? jamBerangkat,
    String? hariTglKembali,
    String? noPolisi,
    String? pengemudi,
    String? kernet,
    int? kmAwal,
    int? kmAkhir,
    int? uangSaku,
    int? bbm,
    int? uangMakan,
    int? extra,
    int? tagihan,
    String? namaCrew,
    String? catatan,
  }) {
    return Report(
      id: id ?? this.id,
      tanggalBuat: tanggalBuat ?? this.tanggalBuat,
      hariTglBerangkat: hariTglBerangkat ?? this.hariTglBerangkat,
      jamBerangkat: jamBerangkat ?? this.jamBerangkat,
      hariTglKembali: hariTglKembali ?? this.hariTglKembali,
      noPolisi: noPolisi ?? this.noPolisi,
      pengemudi: pengemudi ?? this.pengemudi,
      kernet: kernet ?? this.kernet,
      kmAwal: kmAwal ?? this.kmAwal,
      kmAkhir: kmAkhir ?? this.kmAkhir,
      uangSaku: uangSaku ?? this.uangSaku,
      bbm: bbm ?? this.bbm,
      uangMakan: uangMakan ?? this.uangMakan,
      extra: extra ?? this.extra,
      tagihan: tagihan ?? this.tagihan,
      namaCrew: namaCrew ?? this.namaCrew,
      catatan: catatan ?? this.catatan,
    );
  }
}
