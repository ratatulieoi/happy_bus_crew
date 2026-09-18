import 'dart:convert';

// Unspecified preserves reports created before trip types were recorded.
enum TripType {
  unspecified('', '-'),
  luarKota('luar_kota', 'Luar Kota'),
  dalamKota('dalam_kota', 'Dalam Kota');

  const TripType(this.value, this.label);
  final String value;
  final String label;

  static TripType fromValue(Object? value) => values.firstWhere(
        (type) => type.value == value,
        orElse: () => unspecified,
      );
}

/// Satu baris pengeluaran extra: nama item dan harga rupiah.
///
/// Extra selalu berupa daftar berpasangan nama-harga agar setiap
/// pengeluaran tercatat rinci, bukan satu angka gabungan.
class ExtraExpense {
  final String name;
  final int amount;

  const ExtraExpense({required this.name, required this.amount});

  Map<String, dynamic> toMap() => {'name': name, 'amount': amount};

  factory ExtraExpense.fromMap(Map<String, dynamic> map) {
    final name = map['name'];
    final amount = map['amount'];
    if (name is! String || amount is! int) {
      throw const FormatException('Invalid extra expense');
    }
    return ExtraExpense(name: name.trim(), amount: amount);
  }
}

/// Model data untuk Laporan Pertanggungjawaban Crew.
///
/// Satu [Report] berisi seluruh field pada form: info header, kilometer,
/// field keuangan (uang saku, BBM, uang makan, tagihan, daftar extra),
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
  // Retained for reports saved before separate trip counts were available.
  TripType tripType;
  final int? luarKotaCount;
  final int? dalamKotaCount;

  bool get hasTripCounts => luarKotaCount != null && dalamKotaCount != null;

  // --- Kilometer ---
  int kmAwal;
  int kmAkhir;

  // --- Keuangan ---
  int uangSaku;
  int bbm;
  int uangMakan;
  int tagihan;

  /// Daftar pengeluaran extra, masing-masing bernama dan berharga.
  /// Total extra adalah jumlah seluruh harga dan dihitung tepat sekali.
  final List<ExtraExpense> extras;

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
    required this.tagihan,
    required this.namaCrew,
    this.catatan = '',
    this.tripType = TripType.unspecified,
    this.luarKotaCount,
    this.dalamKotaCount,
    List<ExtraExpense>? extras,
  })  : assert(luarKotaCount == null || luarKotaCount >= 0),
        assert(dalamKotaCount == null || dalamKotaCount >= 0),
        tanggalBuat = tanggalBuat ?? DateTime.now(),
        extras = List.unmodifiable(extras ?? const <ExtraExpense>[]);

  /// Jumlah seluruh harga extra. Setiap harga dihitung tepat satu kali.
  int get extra => extras.fold(0, (sum, item) => sum + item.amount);

  /// Total pengeluaran = BBM + Uang Makan + Tagihan + jumlah Extra.
  int get totalPengeluaran => bbm + uangMakan + tagihan + extra;

  /// Sisa = Uang Saku - total pengeluaran.
  int get sisa => uangSaku - totalPengeluaran;

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
      'trip_type': tripType.value,
      'luar_kota_count': luarKotaCount,
      'dalam_kota_count': dalamKotaCount,
      'km_awal': kmAwal,
      'km_akhir': kmAkhir,
      'uang_saku': uangSaku,
      'bbm': bbm,
      'uang_makan': uangMakan,
      'extra': extra,
      'extra_details': jsonEncode([for (final item in extras) item.toMap()]),
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
      tripType: TripType.fromValue(map['trip_type']),
      luarKotaCount: map['luar_kota_count'] as int?,
      dalamKotaCount: map['dalam_kota_count'] as int?,
      kmAwal: map['km_awal'] as int? ?? 0,
      kmAkhir: map['km_akhir'] as int? ?? 0,
      uangSaku: map['uang_saku'] as int? ?? 0,
      bbm: map['bbm'] as int? ?? 0,
      uangMakan: map['uang_makan'] as int? ?? 0,
      tagihan: map['tagihan'] as int? ?? 0,
      extras: _extrasFromMap(map),
      namaCrew: map['nama_crew'] as String? ?? '',
      catatan: map['catatan'] as String? ?? '',
    );
  }

  /// Read named extras, or preserve a legacy total as an 'Extra lama' item.
  /// Reject malformed details as a whole rather than silently losing items.
  static List<ExtraExpense> _extrasFromMap(Map<String, dynamic> map) {
    final details = map['extra_details'];
    if (details is String && details.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is List) {
          final items = <ExtraExpense>[];
          for (final entry in decoded) {
            if (entry is! Map<String, dynamic>) {
              throw const FormatException('Invalid extra expense');
            }
            items.add(ExtraExpense.fromMap(entry));
          }
          // Rincian kosong atau rusak: lanjut ke angka lama agar total aman.
          if (items.isNotEmpty) return items;
        }
      } on FormatException {
        // Rincian rusak: gunakan angka lama di bawah agar total aman.
      }
    }
    final legacy = map['extra'] as int? ?? 0;
    if (legacy != 0) return [ExtraExpense(name: 'Extra lama', amount: legacy)];
    return const [];
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
    TripType? tripType,
    int? luarKotaCount,
    int? dalamKotaCount,
    int? kmAwal,
    int? kmAkhir,
    int? uangSaku,
    int? bbm,
    int? uangMakan,
    int? tagihan,
    List<ExtraExpense>? extras,
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
      tripType: tripType ?? this.tripType,
      luarKotaCount: luarKotaCount ?? this.luarKotaCount,
      dalamKotaCount: dalamKotaCount ?? this.dalamKotaCount,
      kmAwal: kmAwal ?? this.kmAwal,
      kmAkhir: kmAkhir ?? this.kmAkhir,
      uangSaku: uangSaku ?? this.uangSaku,
      bbm: bbm ?? this.bbm,
      uangMakan: uangMakan ?? this.uangMakan,
      tagihan: tagihan ?? this.tagihan,
      extras: extras ?? this.extras,
      namaCrew: namaCrew ?? this.namaCrew,
      catatan: catatan ?? this.catatan,
    );
  }
}
