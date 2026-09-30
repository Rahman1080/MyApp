import 'package:drift/drift.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';

/// Types of smart organization suggestions.
enum SuggestionType {
  /// Items with no location assigned.
  missingLocation,

  /// Items with no category.
  missingCategory,

  /// Items with no value recorded.
  missingValue,

  /// Items with potentially duplicate names.
  possibleDuplicate,

  /// Items with no tags.
  missingTags,
}

/// Status of a suggestion in the review workflow.
enum SuggestionStatus {
  /// Detected, awaiting user review.
  pending,

  /// User accepted — ready to apply.
  accepted,

  /// User rejected — will not be applied.
  rejected,

  /// Accepted and applied to the data.
  applied,
}

/// A smart organization suggestion.
class OrganizationSuggestion {
  const OrganizationSuggestion({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.belongingIds,
    this.status = SuggestionStatus.pending,
    this.proposedAction,
  });

  final String id;
  final SuggestionType type;
  final String title;
  final String description;
  final List<String> belongingIds;
  final SuggestionStatus status;
  final Map<String, dynamic>? proposedAction;

  OrganizationSuggestion copyWith({
    SuggestionStatus? status,
    Map<String, dynamic>? proposedAction,
  }) {
    return OrganizationSuggestion(
      id: id,
      type: type,
      title: title,
      description: description,
      belongingIds: belongingIds,
      status: status ?? this.status,
      proposedAction: proposedAction ?? this.proposedAction,
    );
  }
}

/// Smart Organization engine (Phase 18).
///
/// Detect → Suggest → Review → Confirm workflow:
/// 1. **Detect:** Scans inventory for organization opportunities
/// 2. **Suggest:** Generates actionable suggestions
/// 3. **Review:** User accepts or rejects each suggestion
/// 4. **Confirm:** Accepted suggestions are applied
///
/// All detection is rule-based and deterministic. No data is modified
/// until the user explicitly confirms.
class SmartOrganizationService {
  SmartOrganizationService(KeepItDatabase db)
    : _belongings = BelongingRepository(db);

  final BelongingRepository _belongings;

  /// Detects organization opportunities and returns suggestions.
  Future<List<OrganizationSuggestion>> detectSuggestions() async {
    final suggestions = <OrganizationSuggestion>[];
    final items = await _belongings.getAll();

    // 1. Items with no location.
    final noLocation = items.where((i) => i.locationId == null).toList();
    if (noLocation.isNotEmpty) {
      suggestions.add(OrganizationSuggestion(
        id: 'missing-location-${DateTime.now().millisecondsSinceEpoch}',
        type: SuggestionType.missingLocation,
        title: '${noLocation.length} item(s) have no location',
        description:
            'Assigning locations helps you find items quickly. '
            'Review each item to set its location.',
        belongingIds: noLocation.map((i) => i.id).toList(),
      ));
    }

    // 2. Items with no category.
    final noCategory = items.where((i) =>
        i.categoryId == null || i.categoryId!.isEmpty).toList();
    if (noCategory.isNotEmpty) {
      suggestions.add(OrganizationSuggestion(
        id: 'missing-category-${DateTime.now().millisecondsSinceEpoch}',
        type: SuggestionType.missingCategory,
        title: '${noCategory.length} item(s) have no category',
        description:
            'Categories help organize your inventory. '
            'Review each item to assign a category.',
        belongingIds: noCategory.map((i) => i.id).toList(),
      ));
    }

    // 3. Items with no value.
    final noValue = items
        .where((i) => i.valueUnknown || i.valueCents == null)
        .toList();
    if (noValue.isNotEmpty) {
      suggestions.add(OrganizationSuggestion(
        id: 'missing-value-${DateTime.now().millisecondsSinceEpoch}',
        type: SuggestionType.missingValue,
        title: '${noValue.length} item(s) have no value recorded',
        description:
            'Recording values helps with insurance reports. '
            'Review each item to add its estimated value.',
        belongingIds: noValue.map((i) => i.id).toList(),
      ));
    }

    // 4. Possible duplicates (same name, case-insensitive).
    final nameGroups = <String, List<Belonging>>{};
    for (final item in items) {
      final key = item.name.toLowerCase().trim();
      nameGroups.putIfAbsent(key, () => []).add(item);
    }
    final duplicates = nameGroups.values
        .where((group) => group.length > 1)
        .expand((group) => group)
        .toList();
    if (duplicates.isNotEmpty) {
      final duplicateNames = nameGroups.entries
          .where((e) => e.value.length > 1)
          .map((e) => '"${e.value.first.name}" (${e.value.length}x)')
          .join(', ');
      suggestions.add(OrganizationSuggestion(
        id: 'possible-duplicate-${DateTime.now().millisecondsSinceEpoch}',
        type: SuggestionType.possibleDuplicate,
        title: 'Possible duplicate items detected',
        description:
            'These items have the same name: $duplicateNames. '
            'Review to merge or keep separate.',
        belongingIds: duplicates.map((i) => i.id).toList(),
      ));
    }

    return suggestions;
  }

  /// Applies an accepted suggestion.
  ///
  /// The [action] map contains the specific changes to apply.
  /// For example: `{'locationId': 'loc-123'}` assigns all items
  /// in the suggestion to that location.
  Future<void> applySuggestion(
    OrganizationSuggestion suggestion,
    Map<String, dynamic> action,
  ) async {
    if (suggestion.status != SuggestionStatus.accepted) {
      throw StateError(
        'Suggestion must be accepted before applying. '
        'Current status: ${suggestion.status}',
      );
    }

    for (final belongingId in suggestion.belongingIds) {
      final companion = BelongingsCompanion(
        locationId: action['locationId'] != null
            ? Value(action['locationId'] as String?)
            : const Value.absent(),
        categoryId: action['categoryId'] != null
            ? Value(action['categoryId'] as String?)
            : const Value.absent(),
      );
      await _belongings.update(belongingId, companion);
    }
  }
}
