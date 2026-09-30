/// Maps a notification payload (`'<entityType>:<entityId>'`) to an app route.
///
/// Returns null when the payload is missing, malformed, or cannot be
/// resolved to an existing entity. Pure async logic — no widget code — so it
/// is unit-testable.
Future<String?> routeForPayload(
  String? payload, {
  required Future<String?> Function(String warrantyId) purchaseIdForWarranty,
  required Future<String?> Function(String returnDeadlineId)
      purchaseIdForReturnDeadline,
}) async {
  if (payload == null || payload.isEmpty) return null;
  final separator = payload.indexOf(':');
  if (separator < 0) return null;
  final type = payload.substring(0, separator);
  final id = payload.substring(separator + 1);
  if (id.isEmpty) return null;

  switch (type) {
    case 'deadline':
      return '/deadlines/$id';
    case 'warranty':
      final purchaseId = await purchaseIdForWarranty(id);
      return purchaseId != null ? '/purchases/$purchaseId' : '/purchases/warranties';
    case 'return_deadline':
      final purchaseId = await purchaseIdForReturnDeadline(id);
      return purchaseId != null ? '/purchases/$purchaseId' : '/purchases';
    default:
      return null;
  }
}
