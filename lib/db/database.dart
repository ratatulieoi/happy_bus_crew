import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/report.dart';
import '../models/report_attachment.dart';

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
      version: 15,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE reports (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            tanggal_buat       TEXT    NOT NULL,
            hari_tgl_berangkat TEXT    NOT NULL DEFAULT '',
            jam_berangkat      TEXT    NOT NULL DEFAULT '',
            hari_tgl_kembali   TEXT    NOT NULL DEFAULT '',
            no_polisi          TEXT    NOT NULL DEFAULT '',
            nama_tamu          TEXT    NOT NULL DEFAULT '',
            pengemudi          TEXT    NOT NULL DEFAULT '',
            kernet             TEXT    NOT NULL DEFAULT '',
            trip_type          TEXT    NOT NULL DEFAULT '',
            luar_kota_count    INTEGER CHECK (luar_kota_count >= 0),
            dalam_kota_count   INTEGER CHECK (dalam_kota_count >= 0),
            trip_periods       TEXT,
            km_awal            INTEGER NOT NULL DEFAULT 0,
            km_akhir           INTEGER NOT NULL DEFAULT 0,
            uang_saku          INTEGER NOT NULL DEFAULT 0,
            bbm                INTEGER NOT NULL DEFAULT 0,
            uang_makan         INTEGER NOT NULL DEFAULT 0,
            uang_makan_manual  INTEGER NOT NULL DEFAULT 0,
            pembayaran_tagihan INTEGER NOT NULL DEFAULT 0,
            extra              INTEGER NOT NULL DEFAULT 0,
            extra_details      TEXT    NOT NULL DEFAULT '[]',
            nama_crew          TEXT    NOT NULL DEFAULT '',
            catatan            TEXT    NOT NULL DEFAULT '',
            has_guest_allowance INTEGER NOT NULL DEFAULT 0,
            guest_uang_saku    INTEGER NOT NULL DEFAULT 0,
            guest_tol          INTEGER NOT NULL DEFAULT 0,
            guest_penyeberangan INTEGER NOT NULL DEFAULT 0,
            guest_parkir       INTEGER NOT NULL DEFAULT 0,
            guest_extra_details TEXT   NOT NULL DEFAULT '[]',
            guest_catatan      TEXT    NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE report_attachments (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            report_id INTEGER NOT NULL,
            file_path TEXT    NOT NULL,
            expense_type TEXT,
            extra_id TEXT,
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
        if (oldVersion < 5) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN catatan TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 7) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN extra_details TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 8) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN trip_type TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 9) {
          // NULL means unrecorded, not zero trips. Keep the old category intact.
          await db.execute(
              'ALTER TABLE reports ADD COLUMN luar_kota_count INTEGER CHECK (luar_kota_count >= 0)');
          await db.execute(
              'ALTER TABLE reports ADD COLUMN dalam_kota_count INTEGER CHECK (dalam_kota_count >= 0)');
        }
        if (oldVersion < 10) {
          await db.execute(
              'ALTER TABLE reports ADD COLUMN pembayaran_tagihan INTEGER NOT NULL DEFAULT 0');
          final columns = await db.rawQuery('PRAGMA table_info(reports)');
          if (columns.any((column) => column['name'] == 'tagihan')) {
            await db.execute('UPDATE reports SET tagihan = 0');
          }
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE reports ADD COLUMN trip_periods TEXT');
        }
        if (oldVersion < 12) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN nama_tamu TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 13) {
          await db.execute(
              'ALTER TABLE reports ADD COLUMN has_guest_allowance INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE reports ADD COLUMN guest_uang_saku INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE reports ADD COLUMN guest_tol INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE reports ADD COLUMN guest_penyeberangan INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE reports ADD COLUMN guest_parkir INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              "ALTER TABLE reports ADD COLUMN guest_extra_details TEXT NOT NULL DEFAULT '[]'");
          await db.execute(
              "ALTER TABLE reports ADD COLUMN guest_catatan TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 14) {
          await db.execute(
              'ALTER TABLE reports ADD COLUMN uang_makan_manual INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 15) {
          // Existing photos remain unassigned; never guess their expense.
          await db.execute(
              'ALTER TABLE report_attachments ADD COLUMN expense_type TEXT');
          await db.execute(
              'ALTER TABLE report_attachments ADD COLUMN extra_id TEXT');
        }
      },
    );
    return _db!;
  }

  /// Commit report fields and the complete ordered receipt list together.
  /// A failed transaction leaves both the report and its old links unchanged.
  Future<int> saveReportWithAttachments(
      Report report, List<ReportAttachment> attachments) async {
    final database = await db;
    return database.transaction((txn) async {
      final int id;
      if (report.id == null) {
        id = await txn.insert('reports', report.toMap());
      } else {
        id = report.id!;
        final updated = await txn.update('reports', report.toMap(),
            where: 'id = ?', whereArgs: [id]);
        if (updated != 1) throw StateError('Report no longer exists');
        await txn.delete('report_attachments',
            where: 'report_id = ?', whereArgs: [id]);
      }
      for (final attachment in attachments) {
        await txn.insert('report_attachments', {
          'report_id': id,
          ...attachment.toMap(),
        });
      }
      return id;
    });
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
    await database
        .update('reports', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  /// Hapus laporan beserta lampirannya.
  Future<void> deleteReport(int id) async {
    final database = await db;
    await database
        .delete('report_attachments', where: 'report_id = ?', whereArgs: [id]);
    await database.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  /// Ambil satu laporan.
  Future<Report?> getReport(int id) async {
    final database = await db;
    final rows =
        await database.query('reports', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Report.fromMap(rows.first);
  }

  /// Ambil seluruh laporan — diurutkan terbaru di atas.
  /// Falls back to insertion order when timestamps are equal or missing,
  /// so dashboard cards stay stable across identical saves.
  Future<List<Report>> getAllReports() async {
    final database = await db;
    final rows =
        await database.query('reports', orderBy: 'tanggal_buat DESC, id DESC');
    return rows.map(Report.fromMap).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ------------------------------------------------ Attachment helpers

  /// Simpan foto dan pemilik pengeluarannya untuk sebuah laporan.
  Future<void> insertAttachment(
      int reportId, ReportAttachment attachment) async {
    final database = await db;
    await database.insert('report_attachments', {
      'report_id': reportId,
      ...attachment.toMap(),
    });
  }

  /// Ambil foto dalam urutan penambahan, beserta pemilik pengeluarannya.
  Future<List<ReportAttachment>> getAttachments(int reportId) async {
    final database = await db;
    final rows = await database.query(
      'report_attachments',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'id ASC',
    );
    return rows.map(ReportAttachment.fromMap).toList();
  }

  /// Hapus semua lampiran untuk sebuah laporan.
  Future<void> deleteAttachments(int reportId) async {
    final database = await db;
    await database.delete('report_attachments',
        where: 'report_id = ?', whereArgs: [reportId]);
  }
}
