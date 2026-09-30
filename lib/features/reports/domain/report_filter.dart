/// Advanced filter criteria for inventory reports (Phase 23).
///
/// All fields are optional. Null means "no filter" for that criterion.
/// Filters are combined with AND logic.
class ReportFilter {
  const ReportFilter({
    this.categoryIds,
    this.locationIds,
    this.conditions,
    this.minValueCents,
    this.maxValueCents,
    this.privacyLevels,
    this.archiveStates,
    this.acquiredAfter,
    this.acquiredBefore,
    this.searchText,
  });

  /// Only include items in these categories.
  final Set<String>? categoryIds;

  /// Only include items in these locations.
  final Set<String>? locationIds;

  /// Only include items with these conditions.
  final Set<String>? conditions;

  /// Minimum value in cents (inclusive).
  final int? minValueCents;

  /// Maximum value in cents (inclusive).
  final int? maxValueCents;

  /// Only include items with these privacy levels.
  final Set<String>? privacyLevels;

  /// Only include items with these archive states.
  final Set<String>? archiveStates;

  /// Only include items acquired on or after this date.
  final DateTime? acquiredAfter;

  /// Only include items acquired on or before this date.
  final DateTime? acquiredBefore;

  /// Case-insensitive search across name, brand, model, notes.
  final String? searchText;

  /// Returns true if no filters are set.
  bool get isEmpty =>
      categoryIds == null &&
      locationIds == null &&
      conditions == null &&
      minValueCents == null &&
      maxValueCents == null &&
      privacyLevels == null &&
      archiveStates == null &&
      acquiredAfter == null &&
      acquiredBefore == null &&
      (searchText == null || searchText!.isEmpty);

  /// Returns true if any filters are set.
  bool get isNotEmpty => !isEmpty;
}
