/// Product tiers for KEEPIT monetization (Phase 24).
///
/// The core principle: **all existing functionality is FREE**.
/// Tiers exist to enable future premium features without
/// paywalling anything that already works.
enum ProductTier {
  /// Free tier. Includes ALL current functionality.
  /// This is the default and must remain genuinely useful.
  free,

  /// Pro tier. For future premium features.
  /// No features are currently pro-only.
  pro,

  /// Family tier. For future household sharing premium features.
  /// No features are currently family-only.
  family,
}

/// Feature identifiers for entitlement checks.
///
/// Every feature in the app should have an entry here.
/// New features default to [ProductTier.free] unless explicitly
/// designated as premium during planning.
enum KeepitFeature {
  // Core inventory (always free).
  inventory,
  categories,
  locations,
  places,
  search,
  photos,
  documents,

  // Phase 9+ features (always free).
  purchaseTracking,
  warranties,
  serviceHistory,
  archiveStates,
  itemHistory,

  // Phase 10+ features (always free).
  containers,
  householdDashboard,

  // Phase 11+ features (always free).
  pdfReports,
  evidenceExport,

  // Phase 12+ features (always free).
  movingMode,

  // Phase 13+ features (always free).
  lifecycleTracking,

  // Phase 14+ features (always free).
  warrantyClaims,

  // Phase 15+ features (always free).
  householdMembers,
  privacyControls,

  // Phase 16+ features (always free).
  askKeepit,

  // Phase 17+ features (always free).
  syncFoundation,

  // Phase 18+ features (always free).
  smartOrganization,

  // Phase 19+ features (always free).
  productIntelligence,

  // Phase 20+ features (always free).
  webCompanion,

  // Phase 21+ features (always free).
  commandCenter,

  // Phase 22+ features (always free).
  lifetimeRecord,

  // Phase 23+ features (always free).
  advancedReports,
  csvExport,

  // Future premium features (not yet implemented).
  // These are placeholders for planning purposes.
  cloudBackupPro,
  unlimitedDevices,
  prioritySupport,
}

/// Entitlement service (Phase 24).
///
/// Central authority for feature access control.
/// 
/// **Core guarantee:** All features implemented through Phase 23
/// are available on [ProductTier.free]. This is enforced by
/// [isFeatureAvailable] and verified by tests.
///
/// Future premium features can be added to [KeepitFeature] and
/// mapped to [ProductTier.pro] or [ProductTier.family] in
/// [_featureTiers]. The service will then correctly gate them.
class EntitlementService {
  /// Creates an entitlement service for the given tier.
  ///
  /// Defaults to [ProductTier.free].
  EntitlementService({ProductTier tier = ProductTier.free}) : _tier = tier;

  ProductTier _tier;

  /// The user's current tier.
  ProductTier get currentTier => _tier;

  /// Updates the user's tier (e.g., after purchase).
  ///
  /// In a production app, this would be driven by
  /// platform purchase APIs (Google Play Billing, StoreKit).
  /// For now, it's a simple setter for testing and future integration.
  void setTier(ProductTier tier) {
    _tier = tier;
  }

  /// Returns true if the feature is available at the current tier.
  ///
  /// **Guarantee:** All Phase 1-23 features return true for
  /// [ProductTier.free]. This is the "core stays free" contract.
  bool isFeatureAvailable(KeepitFeature feature) {
    final requiredTier = _featureTiers[feature] ?? ProductTier.free;
    return _tierIndex(_tier) >= _tierIndex(requiredTier);
  }

  /// Returns the tier required for a feature.
  ProductTier requiredTierFor(KeepitFeature feature) {
    return _featureTiers[feature] ?? ProductTier.free;
  }

  /// Returns all features available at the current tier.
  List<KeepitFeature> get availableFeatures {
    return KeepitFeature.values
        .where(isFeatureAvailable)
        .toList();
  }

  /// Numeric index for tier comparison.
  /// Higher tiers include all lower tier features.
  int _tierIndex(ProductTier tier) {
    switch (tier) {
      case ProductTier.free:
        return 0;
      case ProductTier.pro:
        return 1;
      case ProductTier.family:
        return 2;
    }
  }

  /// Maps features to their required tiers.
  ///
  /// **All current features map to free.**
  /// Future premium features will map to pro or family.
  static const Map<KeepitFeature, ProductTier> _featureTiers = {
    // Core inventory - free.
    KeepitFeature.inventory: ProductTier.free,
    KeepitFeature.categories: ProductTier.free,
    KeepitFeature.locations: ProductTier.free,
    KeepitFeature.places: ProductTier.free,
    KeepitFeature.search: ProductTier.free,
    KeepitFeature.photos: ProductTier.free,
    KeepitFeature.documents: ProductTier.free,

    // Phase 9+ - free.
    KeepitFeature.purchaseTracking: ProductTier.free,
    KeepitFeature.warranties: ProductTier.free,
    KeepitFeature.serviceHistory: ProductTier.free,
    KeepitFeature.archiveStates: ProductTier.free,
    KeepitFeature.itemHistory: ProductTier.free,

    // Phase 10+ - free.
    KeepitFeature.containers: ProductTier.free,
    KeepitFeature.householdDashboard: ProductTier.free,

    // Phase 11+ - free.
    KeepitFeature.pdfReports: ProductTier.free,
    KeepitFeature.evidenceExport: ProductTier.free,

    // Phase 12+ - free.
    KeepitFeature.movingMode: ProductTier.free,

    // Phase 13+ - free.
    KeepitFeature.lifecycleTracking: ProductTier.free,

    // Phase 14+ - free.
    KeepitFeature.warrantyClaims: ProductTier.free,

    // Phase 15+ - free.
    KeepitFeature.householdMembers: ProductTier.free,
    KeepitFeature.privacyControls: ProductTier.free,

    // Phase 16+ - free.
    KeepitFeature.askKeepit: ProductTier.free,

    // Phase 17+ - free.
    KeepitFeature.syncFoundation: ProductTier.free,

    // Phase 18+ - free.
    KeepitFeature.smartOrganization: ProductTier.free,

    // Phase 19+ - free.
    KeepitFeature.productIntelligence: ProductTier.free,

    // Phase 20+ - free.
    KeepitFeature.webCompanion: ProductTier.free,

    // Phase 21+ - free.
    KeepitFeature.commandCenter: ProductTier.free,

    // Phase 22+ - free.
    KeepitFeature.lifetimeRecord: ProductTier.free,

    // Phase 23+ - free.
    KeepitFeature.advancedReports: ProductTier.free,
    KeepitFeature.csvExport: ProductTier.free,

    // Future premium - not yet implemented.
    // When implemented, these will check the user's actual tier.
    KeepitFeature.cloudBackupPro: ProductTier.pro,
    KeepitFeature.unlimitedDevices: ProductTier.pro,
    KeepitFeature.prioritySupport: ProductTier.family,
  };
}
