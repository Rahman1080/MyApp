// Shared constants for the Phase 9 personal-property inventory:
// item conditions, archive states and history event types.
//
// Stored in the database as short lowercase codes; [labels] maps them to
// the human-readable strings shown in the UI.

abstract final class BelongingCondition {
  static const String newCondition = 'new';
  static const String likeNew = 'like_new';
  static const String good = 'good';
  static const String fair = 'fair';
  static const String poor = 'poor';
  static const String unknown = 'unknown';

  static const List<String> all = [
    newCondition,
    likeNew,
    good,
    fair,
    poor,
    unknown,
  ];

  static const Map<String, String> labels = {
    newCondition: 'New',
    likeNew: 'Like new',
    good: 'Good',
    fair: 'Fair',
    poor: 'Poor',
    unknown: 'Unknown',
  };

  static String labelOf(String? code) => labels[code] ?? labels[unknown]!;
}

/// Lifecycle states for a belonging. 'owned' is the default; every other
/// state hides the item from the default "My Stuff" list instead of
/// deleting it. Deletion stays an explicit, separate action.
abstract final class BelongingArchiveState {
  static const String owned = 'owned';
  static const String archived = 'archived';
  static const String sold = 'sold';
  static const String donated = 'donated';
  static const String disposed = 'disposed';

  static const List<String> all = [owned, archived, sold, donated, disposed];

  static const Map<String, String> labels = {
    owned: 'Owned',
    archived: 'Archived',
    sold: 'Sold',
    donated: 'Donated',
    disposed: 'Disposed',
  };

  static String labelOf(String? code) => labels[code] ?? labels[owned]!;

  /// True when the item is no longer actively owned.
  static bool isRetired(String? code) => code != null && code != owned;
}

/// Event types recorded in [BelongingHistory].
abstract final class BelongingHistoryEvent {
  static const String created = 'created';
  static const String purchased = 'purchased';
  static const String moved = 'moved';
  static const String warrantyAdded = 'warranty_added';
  static const String documentAdded = 'document_added';
  static const String photoAdded = 'photo_added';
  static const String archived = 'archived';
  static const String unarchived = 'unarchived';
  static const String sold = 'sold';
  static const String donated = 'donated';
  static const String disposed = 'disposed';
  static const String quantityChanged = 'quantity_changed';
  static const String conditionChanged = 'condition_changed';
  static const String valueChanged = 'value_changed';
  static const String maintenance = 'maintenance';
  static const String note = 'note';
}

/// How a belonging entered the user's life. Stored as short codes.
abstract final class BelongingAcquisitionType {
  static const String purchased = 'purchased';
  static const String gifted = 'gifted';
  static const String inherited = 'inherited';
  static const String handmade = 'handmade';
  static const String found = 'found';
  static const String other = 'other';

  static const List<String> all = [
    purchased,
    gifted,
    inherited,
    handmade,
    found,
    other,
  ];

  static const Map<String, String> labels = {
    purchased: 'Purchased',
    gifted: 'Gifted',
    inherited: 'Inherited',
    handmade: 'Handmade',
    found: 'Found',
    other: 'Other',
  };

  static String labelOf(String? code) => labels[code] ?? 'Not set';
}

/// How a belonging left the user's life (for disposed items).
/// Sold/donated use the archive state; this captures the method detail.
abstract final class BelongingDispositionMethod {
  static const String sold = 'sold';
  static const String donated = 'donated';
  static const String givenAway = 'given_away';
  static const String recycled = 'recycled';
  static const String trashed = 'trashed';
  static const String lost = 'lost';
  static const String other = 'other';

  static const List<String> all = [
    sold,
    donated,
    givenAway,
    recycled,
    trashed,
    lost,
    other,
  ];

  static const Map<String, String> labels = {
    sold: 'Sold',
    donated: 'Donated',
    givenAway: 'Given away',
    recycled: 'Recycled',
    trashed: 'Thrown away',
    lost: 'Lost',
    other: 'Other',
  };

  static String labelOf(String? code) => labels[code] ?? 'Not set';
}
