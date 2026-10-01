import 'package:drift/drift.dart';

import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/belonging_repository.dart';

/// Details captured when a belonging leaves the user's life.
class DispositionDetails {
  const DispositionDetails({
    this.priceCents,
    this.currencyCode,
    this.recipient,
    this.method,
    this.notes,
    this.date,
  });

  final int? priceCents;
  final String? currencyCode;
  final String? recipient;
  final String? method;
  final String? notes;
  final DateTime? date;
}

/// Phase 13: Item lifecycle domain logic.
///
/// Builds on the Phase 9 archive states with rich acquisition and
/// disposition tracking, plus lifecycle summaries (ownership duration,
/// item age, value retention).
class LifecycleService {
  LifecycleService(KeepItDatabase db)
    : _belongings = BelongingRepository(db),
      _history = BelongingHistoryRepository(db);

  final BelongingRepository _belongings;
  final BelongingHistoryRepository _history;

  /// Records how and when the item entered the user's life.
  Future<void> recordAcquisition({
    required String belongingId,
    String? acquisitionType,
    DateTime? acquisitionDate,
  }) async {
    if (acquisitionType != null) {
      assert(BelongingAcquisitionType.all.contains(acquisitionType));
    }
    await _belongings.update(
      belongingId,
      BelongingsCompanion(
        acquisitionType: Value(acquisitionType),
        acquisitionDate: Value(acquisitionDate),
      ),
    );
    final typeLabel = acquisitionType != null
        ? BelongingAcquisitionType.labelOf(acquisitionType).toLowerCase()
        : 'details updated';
    await _history.log(
      belongingId: belongingId,
      eventType: BelongingHistoryEvent.note,
      title: 'Acquired ($typeLabel)',
      details: acquisitionDate != null
          ? 'Acquired on ${_formatDate(acquisitionDate)}'
          : null,
    );
  }

  /// Marks the item as sold with sale details.
  Future<void> markSold({
    required String belongingId,
    required DispositionDetails details,
  }) async {
    await _markDisposed(
      belongingId: belongingId,
      archiveState: BelongingArchiveState.sold,
      eventType: BelongingHistoryEvent.sold,
      details: details.copyWith(
        method: details.method ?? BelongingDispositionMethod.sold,
      ),
      title: 'Marked as sold',
    );
  }

  /// Marks the item as donated with donation details.
  Future<void> markDonated({
    required String belongingId,
    required DispositionDetails details,
  }) async {
    await _markDisposed(
      belongingId: belongingId,
      archiveState: BelongingArchiveState.donated,
      eventType: BelongingHistoryEvent.donated,
      details: details.copyWith(
        method: details.method ?? BelongingDispositionMethod.donated,
      ),
      title: 'Marked as donated',
    );
  }

  /// Marks the item as disposed with disposal details.
  Future<void> markDisposed({
    required String belongingId,
    required DispositionDetails details,
  }) async {
    await _markDisposed(
      belongingId: belongingId,
      archiveState: BelongingArchiveState.disposed,
      eventType: BelongingHistoryEvent.disposed,
      details: details,
      title: 'Marked as disposed',
    );
  }

  Future<void> _markDisposed({
    required String belongingId,
    required String archiveState,
    required String eventType,
    required DispositionDetails details,
    required String title,
  }) async {
    final now = DateTime.now();
    await _belongings.update(
      belongingId,
      BelongingsCompanion(
        archiveState: Value(archiveState),
        archivedAt: Value(now),
        dispositionDate: Value(details.date ?? now),
        dispositionPriceCents: Value(details.priceCents),
        dispositionCurrencyCode: Value(details.currencyCode),
        dispositionRecipient: Value(details.recipient),
        dispositionMethod: Value(details.method),
        dispositionNotes: Value(details.notes),
      ),
    );

    final parts = <String>[];
    if (details.recipient != null && details.recipient!.isNotEmpty) {
      parts.add('to ${details.recipient}');
    }
    if (details.priceCents != null) {
      final currency = details.currencyCode ?? 'USD';
      parts.add('for ${_formatCurrency(details.priceCents!, currency)}');
    }
    if (details.method != null) {
      parts.add('(${BelongingDispositionMethod.labelOf(details.method)})');
    }

    await _history.log(
      belongingId: belongingId,
      eventType: eventType,
      title: parts.isEmpty ? title : '$title ${parts.join(' ')}',
      details: details.notes,
    );
  }

  /// Returns a human-readable lifecycle summary for the item.
  ///
  /// Examples: "Owned for 2 years", "Acquired Mar 2023, sold Jan 2025".
  LifecycleSummary summarize(Belonging belonging) {
    final acquisitionDate = belonging.acquisitionDate ?? belonging.createdAt;
    final endDate = belonging.dispositionDate ?? DateTime.now();
    final duration = endDate.difference(acquisitionDate);

    final isRetired = BelongingArchiveState.isRetired(belonging.archiveState);

    return LifecycleSummary(
      acquisitionType: belonging.acquisitionType,
      acquisitionDate: belonging.acquisitionDate,
      ownershipDuration: duration,
      isRetired: isRetired,
      dispositionDate: belonging.dispositionDate,
      dispositionMethod: belonging.dispositionMethod,
      dispositionRecipient: belonging.dispositionRecipient,
      dispositionPriceCents: belonging.dispositionPriceCents,
      dispositionCurrencyCode: belonging.dispositionCurrencyCode,
      originalValueCents: belonging.valueCents,
      originalCurrencyCode: belonging.currencyCode,
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _formatCurrency(int cents, String currency) =>
      '$currency ${(cents / 100).toStringAsFixed(2)}';
}

/// A computed lifecycle summary for display.
class LifecycleSummary {
  const LifecycleSummary({
    this.acquisitionType,
    this.acquisitionDate,
    required this.ownershipDuration,
    required this.isRetired,
    this.dispositionDate,
    this.dispositionMethod,
    this.dispositionRecipient,
    this.dispositionPriceCents,
    this.dispositionCurrencyCode,
    this.originalValueCents,
    this.originalCurrencyCode,
  });

  final String? acquisitionType;
  final DateTime? acquisitionDate;
  final Duration ownershipDuration;
  final bool isRetired;
  final DateTime? dispositionDate;
  final String? dispositionMethod;
  final String? dispositionRecipient;
  final int? dispositionPriceCents;
  final String? dispositionCurrencyCode;
  final int? originalValueCents;
  final String? originalCurrencyCode;

  /// Human-readable ownership duration, e.g. "2 years, 3 months".
  String get durationLabel {
    final days = ownershipDuration.inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    if (months < 12) return '$months month${months == 1 ? '' : 's'}';
    final years = months ~/ 12;
    final remainingMonths = months % 12;
    if (remainingMonths == 0) return '$years year${years == 1 ? '' : 's'}';
    return '$years year${years == 1 ? '' : 's'}, $remainingMonths month${remainingMonths == 1 ? '' : 's'}';
  }

  /// Value retention: sale price vs original value as a percentage.
  /// Null when either value is missing.
  double? get valueRetentionPercent {
    if (dispositionPriceCents == null || originalValueCents == null) {
      return null;
    }
    if (originalValueCents == 0) return null;
    return (dispositionPriceCents! / originalValueCents!) * 100;
  }
}

extension on DispositionDetails {
  DispositionDetails copyWith({String? method}) => DispositionDetails(
    priceCents: priceCents,
    currencyCode: currencyCode,
    recipient: recipient,
    method: method ?? this.method,
    notes: notes,
    date: date,
  );
}
