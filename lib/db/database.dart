import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/bus.dart';
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
      version: 7,
      onCreate: (db, v) async {
        await _createBusTable(db);
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
            extra_details      TEXT    NOT NULL DEFAULT '[]',
            tagihan            INTEGER NOT NULL DEFAULT 0,
            nama_crew          TEXT    NOT NULL DEFAULT '',
            catatan            TEXT    NOT NULL DEFAULT ''
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
        if (oldVersion < 5) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN catatan TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 6) {
          await _createBusTable(db);
          await _importLegacyBuses(db);
        }
        if (oldVersion < 7) {
          await db.execute(
              "ALTER TABLE reports ADD COLUMN extra_details TEXT NOT NULL DEFAULT '[]'");
        }
      },
    );
    return _db!;
  }

  /// Commit report fields and the complete ordered receipt list together.
  /// A failed transaction leaves both the report and its old links unchanged.
  Future<int> saveReportWithAttachments(
      Report report, List<String> paths) async {
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
      for (final path in paths) {
        await txn.insert('report_attachments', {
          'report_id': id,
          'file_path': path,
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

  /// Ambil nilai setting berdasarkan key.
  Future<String?> getSetting(String key) async {
    final database = await db;
    final rows =
        await database.query('settings', where: 'key = ?', whereArgs: [key]);
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

  static Future<void> _createBusTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE buses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      plate TEXT NOT NULL COLLATE NOCASE UNIQUE
    )
  ''');

  // Import only saved bus identities. Never create placeholder buses or copy KM.
  static Future<void> _importLegacyBuses(DatabaseExecutor db) async {
    final rows = await db.query('settings');
    final settings = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final selected = int.tryParse(settings['selected_bus_index'] ?? '');
    final imported = <String, int>{};
    int? selectedId;
    for (var index = 0; index < 6; index++) {
      final name = settings['bus_${index}_name']?.trim() ?? '';
      final plate = settings['bus_${index}_plate']?.trim().toUpperCase() ?? '';
      if (name.isEmpty || plate.isEmpty) continue;
      final id = imported[plate] ??
          await db.insert('buses', {'name': name, 'plate': plate});
      imported[plate] = id;
      if (index == selected) selectedId = id;
    }
    if (imported.isNotEmpty) {
      await db.insert(
          'settings',
          {
            'key': 'selected_bus_id',
            'value': '${selectedId ?? imported.values.first}'
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Bus>> getBuses() async {
    final database = await db;
    return (await database.query('buses', orderBy: 'id ASC'))
        .map(Bus.fromMap)
        .toList();
  }

  Future<Bus?> getSelectedBus() async {
    final buses = await getBuses();
    if (buses.isEmpty) return null;
    final selected = int.tryParse(await getSetting('selected_bus_id') ?? '');
    return buses.firstWhere((bus) => bus.id == selected,
        orElse: () => buses.first);
  }

  Future<void> selectBus(int id) async {
    final database = await db;
    if ((await database.query('buses', where: 'id = ?', whereArgs: [id]))
        .isEmpty) {
      throw StateError('Bus tidak ditemukan.');
    }
    await setSetting('selected_bus_id', '$id');
  }

  /// Save bus identity and selection together, without changing past reports.
  Future<int> saveBus(
      {int? id, required String name, required String plate}) async {
    final cleanName = name.trim();
    final cleanPlate = plate.trim().toUpperCase();
    if (cleanName.isEmpty || cleanPlate.isEmpty) {
      throw ArgumentError('Nama dan nomor polisi wajib diisi.');
    }
    final database = await db;
    return database.transaction((txn) async {
      final data = {'name': cleanName, 'plate': cleanPlate};
      final int savedId;
      if (id == null) {
        savedId = await txn.insert('buses', data);
      } else {
        final updated =
            await txn.update('buses', data, where: 'id = ?', whereArgs: [id]);
        if (updated != 1) throw StateError('Bus tidak ditemukan.');
        savedId = id;
      }
      await txn.insert(
          'settings', {'key': 'selected_bus_id', 'value': '$savedId'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return savedId;
    });
  }

  /// Reports identify buses by plate, without a foreign key.
  Future<bool> isBusUsed(Bus bus) async => _isBusUsed(await db, bus);

  Future<bool> _isBusUsed(DatabaseExecutor executor, Bus bus) async {
    final used = await executor.query('reports',
        columns: ['id'],
        where: 'UPPER(TRIM(no_polisi)) = ?',
        whereArgs: [bus.plate.trim().toUpperCase()],
        limit: 1);
    return used.isNotEmpty;
  }

  /// Check report usage and delete the unused bus in one transaction.
  /// Past reports and attachments are never changed.
  Future<void> deleteBus(int id) async {
    final database = await db;
    await database.transaction((txn) async {
      final buses = await txn.query('buses', where: 'id = ?', whereArgs: [id]);
      if (buses.isEmpty) throw StateError('Bus tidak ditemukan.');
      if (await _isBusUsed(txn, Bus.fromMap(buses.first))) {
        throw StateError(
            'Bus ini memiliki laporan tersimpan dan tidak dapat dihapus.');
      }
      await txn.delete('buses', where: 'id = ?', whereArgs: [id]);
      final selected = await txn
          .query('settings', where: 'key = ?', whereArgs: ['selected_bus_id']);
      if (selected.isNotEmpty &&
          int.tryParse(selected.first['value'] as String) == id) {
        await txn.delete('settings',
            where: 'key = ?', whereArgs: ['selected_bus_id']);
      }
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
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
    await database.delete('report_attachments',
        where: 'report_id = ?', whereArgs: [reportId]);
  }
}
