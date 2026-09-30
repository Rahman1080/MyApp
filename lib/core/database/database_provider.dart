import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'keepit_database.dart';

/// Opens the production database file inside the app documents directory.
///
/// Uses [LazyDatabase] so the file system is only touched when the first
/// query runs. Any failure to resolve the directory surfaces as a database
/// error that [main] handles by showing an error screen instead of crashing.
LazyDatabase openKeepItDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'keepit.sqlite'));
    return NativeDatabase(file);
  });
}

/// Creates an isolated in-memory database. Used by tests and never in
/// production code.
///
/// Uses `closeStreamsSynchronously` so drift tears down query streams
/// immediately when the last listener detaches instead of scheduling an
/// internal timer: under `testWidgets`' fake async zone that timer never
/// fires, which would hang stream cancellations and [KeepItDatabase.close].
KeepItDatabase openInMemoryDatabase() {
  return KeepItDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}
