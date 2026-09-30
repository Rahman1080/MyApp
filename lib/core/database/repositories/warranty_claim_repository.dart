import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';

/// Repository for warranty claims.
class WarrantyClaimRepository {
  WarrantyClaimRepository(this._db);

  final KeepItDatabase _db;

  Future<String> create(WarrantyClaimsCompanion entry) async {
    final id = entry.id.present ? entry.id.value : newRecordId();
    await _db.into(_db.warrantyClaims).insert(entry.copyWith(id: Value(id)));
    return id;
  }

  Future<WarrantyClaim?> getById(String id) async {
    return (_db.select(
      _db.warrantyClaims,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// All claims for a warranty, newest first.
  Future<List<WarrantyClaim>> forWarranty(String warrantyId) async {
    return (_db.select(_db.warrantyClaims)
          ..where((t) => t.warrantyId.equals(warrantyId))
          ..orderBy([(t) => OrderingTerm.desc(t.claimDate)]))
        .get();
  }

  /// All claims for a belonging (via its warranties).
  Future<List<WarrantyClaim>> forBelonging(String belongingId) async {
    final warranties = await (_db.select(
      _db.warranties,
    )..where((t) => t.belongingId.equals(belongingId))).get();
    if (warranties.isEmpty) return [];

    final warrantyIds = warranties.map((w) => w.id).toList();
    return (_db.select(_db.warrantyClaims)
          ..where((t) => t.warrantyId.isIn(warrantyIds))
          ..orderBy([(t) => OrderingTerm.desc(t.claimDate)]))
        .get();
  }

  Future<void> updateStatus(String id, String status) async {
    await (_db.update(_db.warrantyClaims)..where((t) => t.id.equals(id))).write(
      WarrantyClaimsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> update(String id, WarrantyClaimsCompanion entry) async {
    await (_db.update(_db.warrantyClaims)..where((t) => t.id.equals(id))).write(
      entry.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.warrantyClaims)..where((t) => t.id.equals(id))).go();
  }
}
