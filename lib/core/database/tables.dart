import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Returns a new v4 UUID string. Used as the client-side default for every
/// primary key so records stay stable across a future cloud-sync phase.
String newRecordId() => const Uuid().v4();

/// Well-known id of the default [Places] row ("My Home") created by the
/// v4 -> v5 migration and used as the SQL default for [Locations.placeId],
/// so existing users never have to create a place manually.
const String defaultPlaceId = 'place-default';

// ---------------------------------------------------------------------------
// App-level settings (single row, id = 'default').
// ---------------------------------------------------------------------------
class UserSettings extends Table {
  TextColumn get id => text()();
  // 'system' | 'light' | 'dark'
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  BoolColumn get appLockEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get biometricUnlockEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();
  // Master switch for all local reminder notifications. Default true; the
  // user can disable it in Settings (added in schema v2).
  BoolColumn get remindersEnabled =>
      boolean().withDefault(const Constant(true))();
  // Whether the user has accepted the in-app privacy policy (added in v2).
  BoolColumn get privacyPolicyAccepted =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Categories (built-in + user-defined).
// ---------------------------------------------------------------------------
class Categories extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text().unique()();
  TextColumn get iconName => text().nullable()();
  // ARGB color value, nullable so the theme can supply a fallback.
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Places — top-level physical properties (My Home, Parents' Home, Office,
// Storage Unit, ...). Added in schema v5 (Phase 10: home & household
// inventory). A place contains locations; the v4 -> v5 migration creates a
// default place ("My Home") and assigns every existing location to it, so
// existing users never have to create a place manually.
// ---------------------------------------------------------------------------
class Places extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Locations form a hierarchy: Home -> Bedroom -> Closet -> Top Shelf -> Box.
// ---------------------------------------------------------------------------
class Locations extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  TextColumn get parentLocationId => text().nullable().references(
    Locations,
    #id,
    onDelete: KeyAction.setNull,
  )();
  // The place this location belongs to. Non-null with a SQL default so the
  // v4 -> v5 migration backfills existing rows and new inserts without an
  // explicit place land in the default place. Deleting a place is
  // restricted while locations reference it (see PlaceRepository).
  // Added in schema v5.
  TextColumn get placeId => text()
      .references(Places, #id, onDelete: KeyAction.restrict)
      .withDefault(const Constant(defaultPlaceId))();
  TextColumn get notes => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Purchases — the central record of the app.
// ---------------------------------------------------------------------------
class Purchases extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get productName => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get store => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();
  // Money is stored as integer minor units (cents) to avoid float errors.
  IntColumn get priceCents => integer().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('USD'))();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get notes => text().nullable()();
  // active | return_available | return_approaching | return_expired |
  // refund_pending | refunded | warranty_active | warranty_expired
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Line items belonging to a purchase (e.g. individual products on a receipt).
// ---------------------------------------------------------------------------
class Products extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get purchaseId =>
      text().references(Purchases, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get priceCents => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Receipts — one per purchase, produced by scanning or manual entry.
// ---------------------------------------------------------------------------
class Receipts extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get purchaseId =>
      text().unique().references(Purchases, #id, onDelete: KeyAction.cascade)();
  // Local file path of the receipt image. Never uploaded automatically.
  TextColumn get imagePath => text().nullable()();
  TextColumn get store => text().nullable()();
  DateTimeColumn get receiptDate => dateTime().nullable()();
  IntColumn get subtotalCents => integer().nullable()();
  IntColumn get taxCents => integer().nullable()();
  IntColumn get totalCents => integer().nullable()();
  TextColumn get receiptNumber => text().nullable()();
  // Raw OCR output kept for transparency; never logged or uploaded.
  TextColumn get rawOcrText => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Warranties — zero or one per purchase.
// ---------------------------------------------------------------------------
class Warranties extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get purchaseId =>
      text().unique().references(Purchases, #id, onDelete: KeyAction.cascade)();
  // Direct link to a belonging (Phase 14). Nullable for legacy warranties
  // that are only linked via purchase.
  TextColumn get belongingId =>
      text().nullable().references(Belongings, #id, onDelete: KeyAction.setNull)();
  TextColumn get provider => text().nullable()();
  TextColumn get warrantyNumber => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get expirationDate => dateTime().nullable()();
  IntColumn get durationMonths => integer().nullable()();
  TextColumn get documentPath => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Return deadlines — zero or one per purchase.
// ---------------------------------------------------------------------------
class ReturnDeadlines extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get purchaseId =>
      text().unique().references(Purchases, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get deadlineDate => dateTime()();
  // The return window the deadline was derived from, in days. Null = custom.
  IntColumn get returnPeriodDays => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Refunds — zero or one per purchase.
// ---------------------------------------------------------------------------
class Refunds extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get purchaseId =>
      text().unique().references(Purchases, #id, onDelete: KeyAction.cascade)();
  // requested | pending | received
  TextColumn get status => text().withDefault(const Constant('requested'))();
  IntColumn get amountCents => integer().nullable()();
  DateTimeColumn get requestDate => dateTime().nullable()();
  DateTimeColumn get expectedDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Deadlines — not limited to purchases (registration, passport, bills...).
// ---------------------------------------------------------------------------
class Deadlines extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get title => text()();
  DateTimeColumn get dueDate => dateTime()();
  // Optional 'HH:mm' 24h string.
  TextColumn get dueTime => text().nullable()();
  // 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom'
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get notes => text().nullable()();
  TextColumn get relatedPurchaseId => text().nullable().references(
    Purchases,
    #id,
    onDelete: KeyAction.setNull,
  )();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Belongings — physical items with a (hierarchical) location.
// Phase 9 turns "My Stuff" into a full personal-property inventory: an item
// can optionally link to a purchase (which in turn exposes that purchase's
// receipt and warranty), carry several photos, a condition, an archive
// state, a serial number and model, and a lightweight history timeline.
// ---------------------------------------------------------------------------
class Belongings extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  // Model name/number, e.g. "QN90C" or "Air M2 2022". Added in schema v4.
  TextColumn get model => text().nullable()();
  // Manufacturer serial number. Added in schema v4.
  TextColumn get serialNumber => text().nullable()();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get locationId => text().nullable().references(
    Locations,
    #id,
    onDelete: KeyAction.setNull,
  )();
  // True for containers (boxes, folders, bins): a belonging that can itself
  // hold other belongings. Added in schema v5.
  BoolColumn get isContainer => boolean().withDefault(const Constant(false))();
  // The container this item is stored inside, if any. An item inside a
  // container derives its physical location from that container, so
  // [locationId] is cleared when an item is placed in a container.
  // Self-reference with SET NULL; cycles are prevented in
  // [BelongingRepository]. Added in schema v5.
  TextColumn get containerId => text().nullable().references(
    Belongings,
    #id,
    onDelete: KeyAction.setNull,
  )();
  // Optional link to the purchase this item came from. Setting it surfaces
  // that purchase (and its receipt/warranty) on the item detail screen,
  // and the item on the purchase detail screen. Added in schema v4.
  TextColumn get purchaseId => text().nullable().references(
    Purchases,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get photoPath => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  // Optional estimated value in integer minor units (cents) plus an
  // ISO 4217 currency code, e.g. 24999 + 'USD'. Added in schema v3.
  IntColumn get valueCents => integer().nullable()();
  TextColumn get currencyCode => text().nullable()();
  // Explicit "I don't know the value" flag, distinct from "no value
  // entered". Added in schema v4.
  BoolColumn get valueUnknown => boolean().withDefault(const Constant(false))();
  // 'new' | 'like_new' | 'good' | 'fair' | 'poor' | 'unknown'.
  // Added in schema v4.
  TextColumn get condition => text().nullable()();
  // Lifecycle state: 'owned' | 'archived' | 'sold' | 'donated' | 'disposed'.
  // Archiving hides the item from the default list instead of deleting it.
  // Added in schema v4.
  TextColumn get archiveState => text().withDefault(const Constant('owned'))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  // Acquisition: how and when the item entered the user's life.
  // Added in schema v7.
  TextColumn get acquisitionType => text().nullable()();
  DateTimeColumn get acquisitionDate => dateTime().nullable()();
  // Disposition: details recorded when the item leaves (sold/donated/disposed).
  // Added in schema v7.
  DateTimeColumn get dispositionDate => dateTime().nullable()();
  IntColumn get dispositionPriceCents => integer().nullable()();
  TextColumn get dispositionCurrencyCode => text().nullable()();
  TextColumn get dispositionRecipient => text().nullable()();
  TextColumn get dispositionMethod => text().nullable()();
  TextColumn get dispositionNotes => text().nullable()();
  // Phase 15: privacy level ('private' | 'shared'), defaults to 'private'.
  TextColumn get privacyLevel =>
      text().withDefault(const Constant('private'))();
  // Phase 15: household member who owns/uses this item (nullable).
  TextColumn get ownerMemberId => text().nullable().references(
        HouseholdMembers,
        #id,
        onDelete: KeyAction.setNull,
      )();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// BelongingPhotos — a small on-device gallery per item. The legacy single
// `photo_path` on belongings stays as the cover photo. Added in schema v4.
// ---------------------------------------------------------------------------
class BelongingPhotos extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get belongingId =>
      text().references(Belongings, #id, onDelete: KeyAction.cascade)();
  // Local file path. Photos stay on-device by default.
  TextColumn get filePath => text()();
  TextColumn get caption => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// BelongingHistory — lightweight timeline of what happened to an item.
// Entries are created automatically for important actions (added, moved,
// archived, document attached, ...) and users can add their own notes.
// Added in schema v4.
// ---------------------------------------------------------------------------
class BelongingHistory extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get belongingId =>
      text().references(Belongings, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get occurredAt => dateTime().withDefault(currentDateAndTime)();
  // 'created' | 'purchased' | 'moved' | 'warranty_added' | 'document_added' |
  // 'photo_added' | 'archived' | 'unarchived' | 'sold' | 'donated' |
  // 'disposed' | 'quantity_changed' | 'condition_changed' | 'value_changed' |
  // 'note'
  TextColumn get eventType => text()();
  // Short human-readable summary, e.g. "Moved from Bedroom to Garage".
  TextColumn get title => text()();
  TextColumn get details => text().nullable()();
  TextColumn get relatedEntityType => text().nullable()();
  TextColumn get relatedEntityId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Documents — PDFs/images attached to purchases or belongings. Local only.
// ---------------------------------------------------------------------------
class Documents extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get title => text()();
  // Local file path. Documents stay on-device by default.
  TextColumn get filePath => text()();
  TextColumn get mimeType => text().nullable()();
  // receipt | warranty | manual | invoice | contract | registration | other
  TextColumn get documentType => text().withDefault(const Constant('other'))();
  IntColumn get fileSizeBytes => integer().nullable()();
  TextColumn get purchaseId => text().nullable().references(
    Purchases,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get belongingId => text().nullable().references(
    Belongings,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Reminders — one row per scheduled local notification.
// entityType: purchase | deadline | warranty | return_deadline | custom
// ---------------------------------------------------------------------------
class Reminders extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get title => text()();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get entityType => text().withDefault(const Constant('custom'))();
  TextColumn get entityId => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  // 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly'
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Tags.
// ---------------------------------------------------------------------------
class Tags extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text().unique()();
  IntColumn get colorValue => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Normalized tag links: (entityType, entityId) <-> tag.
// ---------------------------------------------------------------------------
class TagLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {tagId, entityType, entityId},
  ];
}

/// Extra (non-unique) indices created in [KeepItDatabase.migration.onCreate].
/// Kept next to the tables so the schema stays reviewable in one place.
const List<String> keepItIndices = [
  'CREATE INDEX idx_purchases_status ON purchases (status)',
  'CREATE INDEX idx_purchases_purchase_date ON purchases (purchase_date)',
  'CREATE INDEX idx_products_purchase_id ON products (purchase_id)',
  'CREATE INDEX idx_deadlines_due_date ON deadlines (due_date)',
  'CREATE INDEX idx_deadlines_is_done ON deadlines (is_done)',
  'CREATE INDEX idx_belongings_name ON belongings (name)',
  'CREATE INDEX idx_belongings_location_id ON belongings (location_id)',
  'CREATE INDEX idx_belongings_purchase_id ON belongings (purchase_id)',
  'CREATE INDEX idx_belongings_archive_state ON belongings (archive_state)',
  'CREATE INDEX idx_belongings_container_id ON belongings (container_id)',
  'CREATE INDEX idx_belonging_photos_belonging ON belonging_photos (belonging_id)',
  'CREATE INDEX idx_belonging_history_belonging ON belonging_history (belonging_id, occurred_at)',
  'CREATE INDEX idx_locations_parent ON locations (parent_location_id)',
  'CREATE INDEX idx_locations_place_id ON locations (place_id)',
  'CREATE INDEX idx_documents_purchase_id ON documents (purchase_id)',
  'CREATE INDEX idx_documents_belonging_id ON documents (belonging_id)',
  'CREATE INDEX idx_reminders_remind_at ON reminders (remind_at)',
  'CREATE INDEX idx_reminders_entity ON reminders (entity_type, entity_id)',
  'CREATE INDEX idx_tag_links_entity ON tag_links (entity_type, entity_id)',
  'CREATE INDEX idx_return_deadlines_date ON return_deadlines (deadline_date)',
  'CREATE INDEX idx_warranties_expiration ON warranties (expiration_date)',
  'CREATE INDEX idx_moves_status ON moves (status)',
  'CREATE INDEX idx_move_items_move ON move_items (move_id, status)',
  'CREATE INDEX idx_move_items_belonging ON move_items (belonging_id)',
  'CREATE INDEX IF NOT EXISTS idx_service_records_belonging ON service_records (belonging_id, service_date)',
  'CREATE INDEX IF NOT EXISTS idx_warranty_claims_warranty ON warranty_claims (warranty_id, claim_date)',
  'CREATE INDEX IF NOT EXISTS idx_warranties_belonging ON warranties (belonging_id)',
  'CREATE INDEX IF NOT EXISTS idx_belongings_owner_member ON belongings (owner_member_id)',
  'CREATE INDEX IF NOT EXISTS idx_refunds_status ON refunds (status)',
];

// ---------------------------------------------------------------------------
// Moves — Phase 12 "Moving Mode". A move tracks relocating belongings from
// one place to another: what is packed, in transit, delivered, and unpacked.
// Added in schema v6.
// ---------------------------------------------------------------------------

/// A relocation project: moving belongings from one place to another.
///
/// Status flow: 'planning' -> 'packing' -> 'in_transit' -> 'unpacking' ->
/// 'completed'. Any non-completed status can go to 'cancelled'.
class Moves extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  // Where belongings are moving from / to. Nullable: a move can be just
  // "pack up this storage unit" without a fixed destination yet.
  TextColumn get fromPlaceId =>
      text().nullable().references(Places, #id, onDelete: KeyAction.setNull)();
  TextColumn get toPlaceId =>
      text().nullable().references(Places, #id, onDelete: KeyAction.setNull)();
  TextColumn get status => text().withDefault(const Constant('planning'))();
  DateTimeColumn get moveDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// One belonging participating in a [Moves] relocation, with its packing
/// status and optional box label.
///
/// Status flow: 'to_pack' -> 'packed' -> 'in_transit' -> 'delivered' ->
/// 'unpacked'. 'unpacked' is terminal. Added in schema v6.
class MoveItems extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get moveId =>
      text().references(Moves, #id, onDelete: KeyAction.cascade)();
  TextColumn get belongingId =>
      text().references(Belongings, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text().withDefault(const Constant('to_pack'))();
  // User-assigned box label, e.g. "Box 3" or "Kitchen - fragile".
  TextColumn get boxLabel => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {moveId, belongingId},
  ];
}

// ---------------------------------------------------------------------------
// Service records — maintenance/service history per belonging.
// Added in schema v8 (Phase 14).
// ---------------------------------------------------------------------------
class ServiceRecords extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get belongingId =>
      text().references(Belongings, #id, onDelete: KeyAction.cascade)();
  // e.g. 'oil_change', 'repair', 'inspection', 'cleaning', 'other'.
  TextColumn get serviceType => text()();
  DateTimeColumn get serviceDate => dateTime()();
  TextColumn get provider => text().nullable()();
  IntColumn get costCents => integer().nullable()();
  TextColumn get currencyCode => text().nullable()();
  TextColumn get notes => text().nullable()();
  // When the next service of this type is due (optional).
  DateTimeColumn get nextServiceDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Warranty claims — claims filed against a warranty.
// Added in schema v8 (Phase 14).
// ---------------------------------------------------------------------------
class WarrantyClaims extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get warrantyId =>
      text().references(Warranties, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get claimDate => dateTime()();
  TextColumn get claimNumber => text().nullable()();
  // 'filed' | 'in_progress' | 'approved' | 'denied' | 'closed'.
  TextColumn get status => text().withDefault(const Constant('filed'))();
  TextColumn get description => text().nullable()();
  TextColumn get resolution => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Household members — local family/household members for sharing.
// Added in schema v9 (Phase 15). Local-only, no cloud.
// ---------------------------------------------------------------------------
class HouseholdMembers extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  // e.g. 'spouse', 'child', 'parent', 'roommate', 'other'.
  TextColumn get relationship => text().nullable()();
  // Color hex for avatar, e.g. '#FF5722'.
  TextColumn get colorHex => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
