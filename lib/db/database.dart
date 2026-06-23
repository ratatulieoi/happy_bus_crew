import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/report.dart';

/// Helper SQLite untuk menyimpan laporan crew secara lokal di perangkat.
///
/// Satu tabel [reports] berisi semua data termasuk field keuangan.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'happy_bus.db'),
      version: 2,
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
            uang_saku          INTEGER NOT NULL DEFAULT 0,
            bbm                INTEGER NOT NULL DEFAULT 0,
            uang_makan         INTEGER NOT NULL DEFAULT 0,
            extra              INTEGER NOT NULL DEFAULT 0,
            tagihan            INTEGER NOT NULL DEFAULT 0,
            nama_crew          TEXT    NOT NULL DEFAULT ''
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migration: drop old tables and recreate
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS line_items');
          await db.execute('DROP TABLE IF EXISTS reports');
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
              uang_saku          INTEGER NOT NULL DEFAULT 0,
              bbm                INTEGER NOT NULL DEFAULT 0,
              uang_makan         INTEGER NOT NULL DEFAULT 0,
              extra              INTEGER NOT NULL DEFAULT 0,
              tagihan            INTEGER NOT NULL DEFAULT 0,
              nama_crew          TEXT    NOT NULL DEFAULT ''
            )
          ''');
        }
      },
    );
    return _db!;
  }

  /// Simpan laporan baru. Mengembalikan id baru.
  Future<int> insertReport(Report r) async {
    final database = await db;
    return await database.insert('reports', r.toMap());
  }

  /// Perbarui laporan yang sudah ada.
  Future<void> updateReport(Report r) async {
    assert(r.id != null);
    final database = await db;
    await database.update('reports', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  /// Hapus laporan.
  Future<void> deleteReport(int id) async {
    final database = await db;
    await database.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  /// Ambil satu laporan.
  Future<Report?> getReport(int id) async {
    final database = await db;
    final rows = await database.query('reports', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Report.fromMap(rows.first);
  }

  /// Ambil seluruh laporan — diurutkan terbaru di atas.
  Future<List<Report>> getAllReports() async {
    final database = await db;
    final rows = await database.query('reports', orderBy: 'tanggal_buat DESC');
    return rows.map(Report.fromMap).toList();
  }
}
