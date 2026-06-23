/// Model data untuk Laporan Pertanggungjawaban Crew.
///
/// Satu [Report] berisi seluruh field pada form: info header, kilometer,
/// daftar item pendapatan & pengeluaran, total otomatis, serta data
/// tanda tangan crew.

/// Satu baris item (pendapatan atau pengeluaran).
class LineItem {
  int? id;
  String keterangan;
  int jumlah; // dalam Rupiah penuh (mis. 50000)

  LineItem({
    this.id,
    required this.keterangan,
    required this.jumlah,
  });

  Map<String, dynamic> toMap({int? reportId, required String type}) {
    return {
      if (id != null) 'id': id,
      if (reportId != null) 'report_id': reportId,
      'type': type, // 'pendapatan' | 'pengeluaran'
      'keterangan': keterangan,
      'jumlah': jumlah,
    };
  }

  factory LineItem.fromMap(Map<String, dynamic> map) {
    return LineItem(
      id: map['id'] as int?,
      keterangan: map['keterangan'] as String? ?? '',
      jumlah: map['jumlah'] as int? ?? 0,
    );
  }
}

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

  // --- Daftar item ---
  List<LineItem> pendapatan;
  List<LineItem> pengeluaran;

  // --- Tanda tangan ---
  String namaCrew; // nama pembuat laporan (penanda tangan)

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
    required this.pendapatan,
    required this.pengeluaran,
    required this.namaCrew,
  }) : tanggalBuat = tanggalBuat ?? DateTime.now();

  /// Total seluruh baris pendapatan.
  int get totalPendapatan =>
      pendapatan.fold(0, (sum, e) => sum + e.jumlah);

  /// Total seluruh baris pengeluaran.
  int get totalPengeluaran =>
      pengeluaran.fold(0, (sum, e) => sum + e.jumlah);

  /// Selisih = pendapatan - pengeluaran.
  int get selisih => totalPendapatan - totalPengeluaran;

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
      'nama_crew': namaCrew,
    };
  }

  factory Report.fromMap(
    Map<String, dynamic> map, {
    List<LineItem> pendapatan = const [],
    List<LineItem> pengeluaran = const [],
  }) {
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
      namaCrew: map['nama_crew'] as String? ?? '',
      pendapatan: List<LineItem>.from(pendapatan),
      pengeluaran: List<LineItem>.from(pengeluaran),
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
    List<LineItem>? pendapatan,
    List<LineItem>? pengeluaran,
    String? namaCrew,
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
      pendapatan: pendapatan ?? this.pendapatan,
      pengeluaran: pengeluaran ?? this.pengeluaran,
      namaCrew: namaCrew ?? this.namaCrew,
    );
  }
}
