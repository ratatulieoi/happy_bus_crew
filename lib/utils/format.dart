import 'package:intl/intl.dart';

/// Format angka ke Rupiah, mis. 50000 -> "Rp 50.000".
String formatRupiah(int amount) {
  final fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  return fmt.format(amount);
}

/// Versi tanpa simbol, mis. 50000 -> "50.000". Berguna untuk input field.
String formatNumberId(int value) {
  return NumberFormat.decimalPattern('id_ID').format(value);
}

/// Parse teks input (boleh mengandung titik/koma) menjadi int.
int parseRupiahInput(String text) {
  final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(cleaned) ?? 0;
}

/// Tanggal panjang Indonesia, mis. "Senin, 1 Januari 2024".
String formatTanggalId(DateTime d) {
  return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(d);
}

/// Tanggal pendek Indonesia, mis. "01/01/2024".
String formatTanggalPendek(DateTime d) {
  return DateFormat('dd/MM/yyyy', 'id_ID').format(d);
}

/// Jam, mis. "08:30".
String formatJam(DateTime d) {
  return DateFormat('HH:mm', 'id_ID').format(d);
}
