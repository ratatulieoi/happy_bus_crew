import 'dart:convert';
import 'dart:math';

import 'trip_period.dart';

export 'trip_period.dart';

/// Satu baris pengeluaran extra: nama item dan harga rupiah.
///
/// Extra selalu berupa daftar berpasangan nama-harga agar setiap
/// pengeluaran tercatat rinci, bukan satu angka gabungan.
class ExtraExpense {
  final String id;
  final String name;
  final int amount;

  ExtraExpense({String? id, required this.name, required this.amount})
      : id = id ?? createId();

  static final _random = Random.secure();
  static String createId() =>
      base64UrlEncode(List<int>.generate(16, (_) => _random.nextInt(256)));

  ExtraExpense copyWith({String? name, int? amount}) => ExtraExpense(
      id: id, name: name ?? this.name, amount: amount ?? this.amount);

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'amount': amount};

  factory ExtraExpense.fromMap(Map<String, dynamic> map) {
    final name = map['name'];
    final amount = map['amount'];
    if (name is! String || amount is! int) {
      throw const FormatException('Invalid extra expense');
    }
    final id = map['id'];
    if (id != null && (id is! String || id.isEmpty)) {
      throw const FormatException('Invalid extra identity');
    }
    return ExtraExpense(id: id as String?, name: name.trim(), amount: amount);
  }
}

/// Model data untuk Laporan Pertanggungjawaban Crew.
///
/// Satu [Report] berisi seluruh field pada form: info header, kilometer,
/// field keuangan (uang saku, BBM, uang makan, pembayaran tagihan, daftar extra),
/// serta data tanda tangan crew.

class Report {
  int? id;
  DateTime tanggalBuat; // kapan laporan ini dibuat/diisi

  // --- Info header (kiri) ---
  String hariTglBerangkat; // "Senin, 01/01/2024"
  String jamBerangkat; // "08:00"
  String hariTglKembali; // "Rabu, 03/01/2024"
  String noPolisi; // "B 1234 XX"
  String namaTamu; // nama tamu, diisi saat input tampering tersedia
  String pengemudi; // nama sopir
  String kernet; // nama kernet/asisten
  // Retained for reports saved before separate trip counts were available.
  TripType tripType;
  final int? _legacyLuarKotaCount;
  final int? _legacyDalamKotaCount;

  // null retains legacy counts; [] explicitly clears the period breakdown.
  final List<TripPeriod>? tripPeriods;

  int? get luarKotaCount => _countDays(TripType.luarKota, _legacyLuarKotaCount);
  int? get dalamKotaCount =>
      _countDays(TripType.dalamKota, _legacyDalamKotaCount);

  int? _countDays(TripType type, int? legacy) {
    final periods = tripPeriods;
    if (periods == null) return legacy;
    if (periods.isEmpty) return null;
    return periods
        .where((period) => period.type == type)
        .fold<int>(0, (sum, period) => sum + period.days);
  }

  bool get hasTripCounts => luarKotaCount != null && dalamKotaCount != null;

  // --- Kilometer ---
  int kmAwal;
  int kmAkhir;

  // --- Keuangan ---
  int uangSaku;
  int bbm;
  static const mealAllowancePerDay = 40000;
  static int countMealDays(Iterable<TripPeriod> periods) =>
      periods.fold(0, (sum, period) => sum + period.days);
  static int automaticMealAllowance(Iterable<TripPeriod> periods) =>
      mealAllowancePerDay * countMealDays(periods);

  int get mealDays => countMealDays(tripPeriods ?? const <TripPeriod>[]);
  final int uangMakan;
  // Explicit because a manually entered amount can equal the automatic amount.
  final bool uangMakanIsManual;
  int pembayaranTagihan;

  /// Daftar pengeluaran extra, masing-masing bernama dan berharga.
  /// Total extra adalah jumlah seluruh harga dan dihitung tepat sekali.
  final List<ExtraExpense> extras;

  // --- Guest allowance ---
  bool hasGuestAllowance;
  int guestUangSaku;
  int guestTol;
  int guestPenyeberangan;
  int guestParkir;
  final List<ExtraExpense> guestExtras;
  String guestCatatan;

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
    required this.namaTamu,
    required this.pengemudi,
    required this.kernet,
    required this.kmAwal,
    required this.kmAkhir,
    required this.uangSaku,
    required this.bbm,
    int? uangMakan,
    this.uangMakanIsManual = false,
    required this.pembayaranTagihan,
    required this.namaCrew,
    this.catatan = '',
    this.tripType = TripType.unspecified,
    int? luarKotaCount,
    int? dalamKotaCount,
    List<TripPeriod>? tripPeriods,
    bool resetTripData = false,
    List<ExtraExpense>? extras,
    this.hasGuestAllowance = false,
    this.guestUangSaku = 0,
    this.guestTol = 0,
    this.guestPenyeberangan = 0,
    this.guestParkir = 0,
    List<ExtraExpense>? guestExtras,
    this.guestCatatan = '',
  })  : assert(luarKotaCount == null || luarKotaCount >= 0),
        assert(dalamKotaCount == null || dalamKotaCount >= 0),
        _legacyLuarKotaCount = resetTripData
            ? null
            : tripPeriods == null
                ? luarKotaCount
                : null,
        _legacyDalamKotaCount = resetTripData
            ? null
            : tripPeriods == null
                ? dalamKotaCount
                : null,
        tripPeriods = resetTripData
            ? const <TripPeriod>[]
            : tripPeriods == null
                ? null
                : List.unmodifiable(tripPeriods),
        uangMakan = uangMakanIsManual
            ? uangMakan ?? 0
            : automaticMealAllowance(resetTripData ? [] : tripPeriods ?? []),
        tanggalBuat = tanggalBuat ?? DateTime.now(),
        extras = List.unmodifiable(extras ?? const <ExtraExpense>[]),
        guestExtras = List.unmodifiable(guestExtras ?? const <ExtraExpense>[]);

  /// Jumlah seluruh harga extra. Setiap harga dihitung tepat satu kali.
  int get extra => extras.fold(0, (sum, item) => sum + item.amount);

  /// Total pengeluaran = BBM + uang makan + jumlah Extra.
  /// Pembayaran tagihan klien dicatat terpisah dan tidak mengurangi sisa.
  int get totalPengeluaran => bbm + uangMakan + extra;

  /// Sisa = Uang Saku - total pengeluaran.
  int get sisa => uangSaku - totalPengeluaran;

  int get guestExtraTotal =>
      guestExtras.fold(0, (sum, item) => sum + item.amount);

  int get guestTotalPengeluaran =>
      guestTol + guestPenyeberangan + guestParkir + guestExtraTotal;

  int get guestSisa => guestUangSaku - guestTotalPengeluaran;

  bool get hasGuestData =>
      hasGuestAllowance ||
      guestUangSaku != 0 ||
      guestTol != 0 ||
      guestPenyeberangan != 0 ||
      guestParkir != 0 ||
      guestExtras.isNotEmpty ||
      guestCatatan.isNotEmpty;

  /// Label ringkas untuk ditampilkan di daftar laporan (Home).
  String get ringkas =>
      '${noPolisi.isEmpty ? "-" : noPolisi} • ${namaTamu.trim().isEmpty ? "-" : namaTamu.trim()}';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tanggal_buat': tanggalBuat.toIso8601String(),
      'hari_tgl_berangkat': hariTglBerangkat,
      'jam_berangkat': jamBerangkat,
      'hari_tgl_kembali': hariTglKembali,
      'no_polisi': noPolisi,
      'nama_tamu': namaTamu,
      'pengemudi': pengemudi,
      'kernet': kernet,
      'trip_type': tripType.value,
      'luar_kota_count': luarKotaCount,
      'dalam_kota_count': dalamKotaCount,
      'trip_periods': tripPeriods == null
          ? null
          : jsonEncode([for (final period in tripPeriods!) period.toMap()]),
      'km_awal': kmAwal,
      'km_akhir': kmAkhir,
      'uang_saku': uangSaku,
      'bbm': bbm,
      'uang_makan': uangMakan,
      'uang_makan_manual': uangMakanIsManual ? 1 : 0,
      'extra': extra,
      'extra_details': jsonEncode([for (final item in extras) item.toMap()]),
      'pembayaran_tagihan': pembayaranTagihan,
      'nama_crew': namaCrew,
      'catatan': catatan,
      'has_guest_allowance': hasGuestAllowance ? 1 : 0,
      'guest_uang_saku': guestUangSaku,
      'guest_tol': guestTol,
      'guest_penyeberangan': guestPenyeberangan,
      'guest_parkir': guestParkir,
      'guest_extra_details':
          jsonEncode([for (final item in guestExtras) item.toMap()]),
      'guest_catatan': guestCatatan,
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
      namaTamu: map['nama_tamu'] as String? ?? '',
      pengemudi: map['pengemudi'] as String? ?? '',
      kernet: map['kernet'] as String? ?? '',
      tripType: TripType.fromValue(map['trip_type']),
      luarKotaCount: map['luar_kota_count'] as int?,
      dalamKotaCount: map['dalam_kota_count'] as int?,
      tripPeriods: _periodsFromMap(map['trip_periods']),
      kmAwal: map['km_awal'] as int? ?? 0,
      kmAkhir: map['km_akhir'] as int? ?? 0,
      uangSaku: map['uang_saku'] as int? ?? 0,
      bbm: map['bbm'] as int? ?? 0,
      uangMakan: map['uang_makan'] as int? ?? 0,
      uangMakanIsManual: map['uang_makan_manual'] == 1,
      pembayaranTagihan: map['pembayaran_tagihan'] as int? ?? 0,
      extras: _extrasFromMap(map),
      namaCrew: map['nama_crew'] as String? ?? '',
      catatan: map['catatan'] as String? ?? '',
      hasGuestAllowance:
          map['has_guest_allowance'] == 1 || map['has_guest_allowance'] == true,
      guestUangSaku: map['guest_uang_saku'] as int? ?? 0,
      guestTol: map['guest_tol'] as int? ?? 0,
      guestPenyeberangan: map['guest_penyeberangan'] as int? ?? 0,
      guestParkir: map['guest_parkir'] as int? ?? 0,
      guestExtras: _guestExtrasFromMap(map['guest_extra_details']),
      guestCatatan: map['guest_catatan'] as String? ?? '',
    );
  }

  static List<TripPeriod>? _periodsFromMap(Object? details) {
    // Null preserves legacy count fields; '[]' explicitly means no periods.
    if (details == null) return null;
    if (details is! String) return null;
    try {
      final decoded = jsonDecode(details);
      if (decoded is! List) return null;
      final periods = <TripPeriod>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid trip period');
        }
        periods.add(TripPeriod.fromMap(entry));
      }
      return periods;
    } on FormatException {
      // Keep stored totals rather than partially accepting corrupt details.
      return null;
    }
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

  /// Read guest extras, rejecting malformed details as a whole.
  static List<ExtraExpense> _guestExtrasFromMap(Object? details) {
    if (details is! String || details.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(details);
      if (decoded is! List) return const [];
      final items = <ExtraExpense>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid guest extra expense');
        }
        items.add(ExtraExpense.fromMap(entry));
      }
      return items;
    } on FormatException {
      return const [];
    }
  }

  /// Salinan dengan satu field diubah — mempermudah update dari form.
  Report copyWith({
    int? id,
    DateTime? tanggalBuat,
    String? hariTglBerangkat,
    String? jamBerangkat,
    String? hariTglKembali,
    String? noPolisi,
    String? namaTamu,
    String? pengemudi,
    String? kernet,
    TripType? tripType,
    // Null only preserves existing values; call copyWith with tripPeriods
    // to keep, clear, or replace computed counts.
    int? luarKotaCount,
    int? dalamKotaCount,
    List<TripPeriod>? tripPeriods,
    bool resetTripData = false,
    int? kmAwal,
    int? kmAkhir,
    int? uangSaku,
    int? bbm,
    int? uangMakan,
    bool? uangMakanIsManual,
    int? pembayaranTagihan,
    List<ExtraExpense>? extras,
    String? namaCrew,
    String? catatan,
    bool? hasGuestAllowance,
    int? guestUangSaku,
    int? guestTol,
    int? guestPenyeberangan,
    int? guestParkir,
    List<ExtraExpense>? guestExtras,
    String? guestCatatan,
  }) {
    return Report(
      id: id ?? this.id,
      tanggalBuat: tanggalBuat ?? this.tanggalBuat,
      hariTglBerangkat: hariTglBerangkat ?? this.hariTglBerangkat,
      jamBerangkat: jamBerangkat ?? this.jamBerangkat,
      hariTglKembali: hariTglKembali ?? this.hariTglKembali,
      noPolisi: noPolisi ?? this.noPolisi,
      namaTamu: namaTamu ?? this.namaTamu,
      pengemudi: pengemudi ?? this.pengemudi,
      kernet: kernet ?? this.kernet,
      tripType: tripType ?? this.tripType,
      luarKotaCount: resetTripData ? null : luarKotaCount ?? this.luarKotaCount,
      dalamKotaCount:
          resetTripData ? null : dalamKotaCount ?? this.dalamKotaCount,
      tripPeriods: resetTripData ? [] : tripPeriods ?? this.tripPeriods,
      kmAwal: kmAwal ?? this.kmAwal,
      kmAkhir: kmAkhir ?? this.kmAkhir,
      uangSaku: uangSaku ?? this.uangSaku,
      bbm: bbm ?? this.bbm,
      uangMakan: uangMakan ?? this.uangMakan,
      uangMakanIsManual: uangMakanIsManual ?? this.uangMakanIsManual,
      pembayaranTagihan: pembayaranTagihan ?? this.pembayaranTagihan,
      extras: extras ?? this.extras,
      namaCrew: namaCrew ?? this.namaCrew,
      catatan: catatan ?? this.catatan,
      hasGuestAllowance: hasGuestAllowance ?? this.hasGuestAllowance,
      guestUangSaku: guestUangSaku ?? this.guestUangSaku,
      guestTol: guestTol ?? this.guestTol,
      guestPenyeberangan: guestPenyeberangan ?? this.guestPenyeberangan,
      guestParkir: guestParkir ?? this.guestParkir,
      guestExtras: guestExtras ?? this.guestExtras,
      guestCatatan: guestCatatan ?? this.guestCatatan,
    );
  }
}
