import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';

/// Repository for service records (maintenance/service history per belonging).
class ServiceRecordRepository {
  ServiceRecordRepository(this._db);

  final KeepItDatabase _db;

  Future<String> create(ServiceRecordsCompanion entry) async {
    final id = entry.id.present ? entry.id.value : newRecordId();
    await _db.into(_db.serviceRecords).insert(entry.copyWith(id: Value(id)));
    return id;
  }

  Future<ServiceRecord?> getById(String id) async {
    return (_db.select(
      _db.serviceRecords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// All service records for a belonging, newest first.
  Future<List<ServiceRecord>> forBelonging(String belongingId) async {
    return (_db.select(_db.serviceRecords)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([(t) => OrderingTerm.desc(t.serviceDate)]))
        .get();
  }

  /// Service records with a future next_service_date (upcoming maintenance).
  Future<List<ServiceRecord>> upcoming({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    return (_db.select(_db.serviceRecords)
          ..where((t) => t.nextServiceDate.isNotNull())
          ..where((t) => t.nextServiceDate.isBiggerThanValue(now))
          ..orderBy([(t) => OrderingTerm.asc(t.nextServiceDate)]))
        .get();
  }

  Future<void> update(String id, ServiceRecordsCompanion entry) async {
    await (_db.update(_db.serviceRecords)..where((t) => t.id.equals(id))).write(
      entry.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.serviceRecords)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteForBelonging(String belongingId) async {
    await (_db.delete(
      _db.serviceRecords,
    )..where((t) => t.belongingId.equals(belongingId))).go();
  }
}
