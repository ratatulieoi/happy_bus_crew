import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Linux-only startup wiring. Android keeps the default sqflite plugin path.
///
/// Must run before any database access. Safe to call once at startup:
/// FFI init is idempotent and the factory assignment only happens on Linux.
Future<void> setupDesktopPlatform() async {
  if (!Platform.isLinux) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final support = await getApplicationSupportDirectory();
  final databasesPath = p.join(support.path, 'databases');
  await Directory(databasesPath).create(recursive: true);
  await databaseFactory.setDatabasesPath(databasesPath);
}
