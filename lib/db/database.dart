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
      version: 4,
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
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE report_attachments (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            report_id INTEGER NOT NULL,
            file_path TEXT    NOT NULL,
            FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS report_attachments (
              id        INTEGER PRIMARY KEY AUTOINCREMENT,
              report_id INTEGER NOT NULL,
              file_path TEXT    NOT NULL,
              FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
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

  /// Hapus laporan beserta lampirannya.
  Future<void> deleteReport(int id) async {
    final database = await db;
    await database.delete('report_attachments', where: 'report_id = ?', whereArgs: [id]);
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

  /// Ambil nilai setting berdasarkan key.
  Future<String?> getSetting(String key) async {
    final database = await db;
    final rows = await database.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Simpan nilai setting.
  Future<void> setSetting(String key, String value) async {
    final database = await db;
    await database.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ambil KM terakhir dari laporan yang terdaftar untuk plat tertentu.
  Future<int> getLatestKmForPlate(String plate) async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT MAX(km_akhir) as max_km FROM reports WHERE no_polisi = ?',
      [plate],
    );
    if (result.isEmpty || result.first['max_km'] == null) {
      return 0;
    }
    return result.first['max_km'] as int;
  }

  // ------------------------------------------------ Attachment helpers

  /// Simpan path lampiran foto untuk sebuah laporan.
  Future<void> insertAttachment(int reportId, String filePath) async {
    final database = await db;
    await database.insert('report_attachments', {
      'report_id': reportId,
      'file_path': filePath,
    });
  }

  /// Ambil semua path lampiran untuk sebuah laporan.
  Future<List<String>> getAttachments(int reportId) async {
    final database = await db;
    final rows = await database.query(
      'report_attachments',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => r['file_path'] as String).toList();
  }

  /// Hapus semua lampiran untuk sebuah laporan.
  Future<void> deleteAttachments(int reportId) async {
    final database = await db;
    await database.delete('report_attachments', where: 'report_id = ?', whereArgs: [reportId]);
  }
}
