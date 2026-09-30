import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Returns a new v4 UUID string. Used as the client-side default for every
/// primary key so records stay stable across a future cloud-sync phase.
String newRecordId() => const Uuid().v4();

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
// Locations form a hierarchy: Home -> Bedroom -> Closet -> Top Shelf -> Box.
// ---------------------------------------------------------------------------
class Locations extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  TextColumn get parentLocationId => text()
      .nullable()
      .references(Locations, #id, onDelete: KeyAction.setNull)();
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
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
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
  TextColumn get purchaseId => text()
      .references(Purchases, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get notes => text().nullable()();
  TextColumn get relatedPurchaseId => text()
      .nullable()
      .references(Purchases, #id, onDelete: KeyAction.setNull)();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Belongings — physical items with a (hierarchical) location.
// ---------------------------------------------------------------------------
class Belongings extends Table {
  TextColumn get id => text().clientDefault(newRecordId)();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get categoryId => text()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get locationId => text()
      .nullable()
      .references(Locations, #id, onDelete: KeyAction.setNull)();
  TextColumn get photoPath => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  // Optional estimated value in integer minor units (cents) plus an
  // ISO 4217 currency code, e.g. 24999 + 'USD'. Added in schema v3.
  IntColumn get valueCents => integer().nullable()();
  TextColumn get currencyCode => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  TextColumn get purchaseId => text()
      .nullable()
      .references(Purchases, #id, onDelete: KeyAction.cascade)();
  TextColumn get belongingId => text()
      .nullable()
      .references(Belongings, #id, onDelete: KeyAction.cascade)();
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
  'CREATE INDEX idx_locations_parent ON locations (parent_location_id)',
  'CREATE INDEX idx_documents_purchase_id ON documents (purchase_id)',
  'CREATE INDEX idx_documents_belonging_id ON documents (belonging_id)',
  'CREATE INDEX idx_reminders_remind_at ON reminders (remind_at)',
  'CREATE INDEX idx_reminders_entity ON reminders (entity_type, entity_id)',
  'CREATE INDEX idx_tag_links_entity ON tag_links (entity_type, entity_id)',
  'CREATE INDEX idx_return_deadlines_date ON return_deadlines (deadline_date)',
  'CREATE INDEX idx_warranties_expiration ON warranties (expiration_date)',
];
