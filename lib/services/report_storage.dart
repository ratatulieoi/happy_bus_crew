import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../models/report.dart';

class ReportStorage {
  /// Stage copies before changing any saved report or receipt association.
  /// Unique directories prevent an edited receipt order overwriting a source.
  static Future<int> save(Report report, List<File> attachments) async {
    Directory? staged;
    try {
      final paths = <String>[];
      if (attachments.isNotEmpty) {
        final documents = await getApplicationDocumentsDirectory();
        final root = Directory(p.join(documents.path, 'attachments'));
        await root.create(recursive: true);
        staged = await root.createTemp('report_');
        for (var i = 0; i < attachments.length; i++) {
          final source = attachments[i];
          final target =
              p.join(staged.path, 'struk_${i + 1}${p.extension(source.path)}');
          await source.copy(target);
          paths.add(target);
        }
      }
      return await DatabaseHelper.instance
          .saveReportWithAttachments(report, paths);
    } catch (_) {
      // Only delete files created by this attempt. Old saved receipts stay intact.
      if (staged != null) {
        try {
          await staged.delete(recursive: true);
        } on FileSystemException {
          // A cleanup failure must not hide the original save error.
        }
      }
      rethrow;
    }
  }
}
