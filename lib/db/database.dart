import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/report.dart';

/// Helper SQLite untuk menyimpan laporan crew secara lokal di perangkat.
///
/// Dua tabel:
/// - [reports]   : metadata laporan (header, KM, penanda tangan)
/// - [line_items]: baris pendapatan/pengeluaran yang terhubung via `report_id`
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'happy_bus.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE reports (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            tanggal_buat       TEXT    NOT NULL,
            hari_tgl_berangkat TEXT    NOT NULL DEFAULT '',
            jam_berangkat      TEXT    NOT NULL DEFAULT '',
            hari_tgl_kembali   TEXT    NOT NULL DEFAULT '',
            no_polisi          TEXT    NOT NULL DEFAULT '',
            pengemudi          TEXT    NOT NULL DEFAULT '',
            kernet             TEXT    NOT NULL DEFAULT '',
            km_awal            INTEGER NOT NULL DEFAULT 0,
            km_akhir           INTEGER NOT NULL DEFAULT 0,
            nama_crew          TEXT    NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE line_items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            report_id   INTEGER NOT NULL,
            type        TEXT    NOT NULL,   -- 'pendapatan' | 'pengeluaran'
            keterangan  TEXT    NOT NULL DEFAULT '',
            jumlah      INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
          )
        ''');
      },
    );
    return _db!;
  }

  /// Simpan laporan baru. Mengembalikan id baru.
  Future<int> insertReport(Report r) async {
    final database = await db;
    final id = await database.insert('reports', r.toMap());
    await _insertItems(database, id, r);
    return id;
  }

  /// Perbarui laporan yang sudah ada (beserta seluruh itemnya).
  Future<void> updateReport(Report r) async {
    assert(r.id != null);
    final database = await db;
    await database.update('reports', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    await database.delete('line_items', where: 'report_id = ?', whereArgs: [r.id]);
    await _insertItems(database, r.id!, r);
  }

  /// Hapus laporan beserta itemnya.
  Future<void> deleteReport(int id) async {
    final database = await db;
    await database.delete('line_items', where: 'report_id = ?', whereArgs: [id]);
    await database.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  /// Ambil satu laporan lengkap (termasuk item pendapatan/pengeluaran).
  Future<Report?> getReport(int id) async {
    final database = await db;
    final rows = await database.query('reports', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final pendapatan = await database.query('line_items',
        where: 'report_id = ? AND type = ?', whereArgs: [id, 'pendapatan']);
    final pengeluaran = await database.query('line_items',
        where: 'report_id = ? AND type = ?', whereArgs: [id, 'pengeluaran']);
    return Report.fromMap(
      rows.first,
      pendapatan: pendapatan.map(LineItem.fromMap).toList(),
      pengeluaran: pengeluaran.map(LineItem.fromMap).toList(),
    );
  }

  /// Ambil seluruh laporan (ringkas) — diurutkan terbaru di atas.
  Future<List<Report>> getAllReports() async {
    final database = await db;
    final rows = await database.query('reports', orderBy: 'tanggal_buat DESC');
    final List<Report> out = [];
    for (final row in rows) {
      final id = row['id'] as int;
      final pendapatan = await database.query('line_items',
          where: 'report_id = ? AND type = ?', whereArgs: [id, 'pendapatan']);
      final pengeluaran = await database.query('line_items',
          where: 'report_id = ? AND type = ?', whereArgs: [id, 'pengeluaran']);
      out.add(Report.fromMap(
        row,
        pendapatan: pendapatan.map(LineItem.fromMap).toList(),
        pengeluaran: pengeluaran.map(LineItem.fromMap).toList(),
      ));
    }
    return out;
  }

  Future<void> _insertItems(Database database, int reportId, Report r) async {
    for (final item in r.pendapatan) {
      await database.insert('line_items', item.toMap(reportId: reportId, type: 'pendapatan'));
    }
    for (final item in r.pengeluaran) {
      await database.insert('line_items', item.toMap(reportId: reportId, type: 'pengeluaran'));
    }
  }
}
