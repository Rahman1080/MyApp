import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/features/monetization/domain/entitlement_service.dart';

/// Phase 24: Monetization abstractions (core free).
void main() {
  group('Phase 24 Monetization', () {
    test('defaults to free tier', () {
      final service = EntitlementService();
      expect(service.currentTier, ProductTier.free);
    });

    test('all Phase 1-23 features available on free tier', () {
      final service = EntitlementService(tier: ProductTier.free);

      // Core features.
      expect(service.isFeatureAvailable(KeepitFeature.inventory), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.search), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.photos), isTrue);

      // Phase 9-15 features.
      expect(service.isFeatureAvailable(KeepitFeature.warranties), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.movingMode), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.lifecycleTracking), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.householdMembers), isTrue);

      // Phase 16-23 features.
      expect(service.isFeatureAvailable(KeepitFeature.askKeepit), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.smartOrganization), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.webCompanion), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.commandCenter), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.lifetimeRecord), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.advancedReports), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.csvExport), isTrue);
    });

    test('every feature except future premium is free', () {
      final service = EntitlementService(tier: ProductTier.free);

      // These are the only non-free features (future premium).
      const premiumFeatures = {
        KeepitFeature.cloudBackupPro,
        KeepitFeature.unlimitedDevices,
        KeepitFeature.prioritySupport,
      };

      for (final feature in KeepitFeature.values) {
        if (premiumFeatures.contains(feature)) {
          expect(
            service.isFeatureAvailable(feature),
            isFalse,
            reason: '$feature should require paid tier',
          );
        } else {
          expect(
            service.isFeatureAvailable(feature),
            isTrue,
            reason: '$feature should be free',
          );
        }
      }
    });

    test('pro tier includes free features', () {
      final service = EntitlementService(tier: ProductTier.pro);

      expect(service.isFeatureAvailable(KeepitFeature.inventory), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.cloudBackupPro), isTrue);
      expect(service.isFeatureAvailable(KeepitFeature.unlimitedDevices), isTrue);
    });

    test('family tier includes all features', () {
      final service = EntitlementService(tier: ProductTier.family);

      for (final feature in KeepitFeature.values) {
        expect(
          service.isFeatureAvailable(feature),
          isTrue,
          reason: '$feature should be available on family tier',
        );
      }
    });

    test('setTier updates access', () {
      final service = EntitlementService(tier: ProductTier.free);
      expect(service.isFeatureAvailable(KeepitFeature.cloudBackupPro), isFalse);

      service.setTier(ProductTier.pro);
      expect(service.isFeatureAvailable(KeepitFeature.cloudBackupPro), isTrue);
      expect(service.currentTier, ProductTier.pro);
    });

    test('requiredTierFor returns correct tier', () {
      final service = EntitlementService();
      expect(
        service.requiredTierFor(KeepitFeature.inventory),
        ProductTier.free,
      );
      expect(
        service.requiredTierFor(KeepitFeature.cloudBackupPro),
        ProductTier.pro,
      );
    });

    test('availableFeatures lists accessible features', () {
      final service = EntitlementService(tier: ProductTier.free);
      final available = service.availableFeatures;

      expect(available, contains(KeepitFeature.inventory));
      expect(available, isNot(contains(KeepitFeature.cloudBackupPro)));
    });
  });
}
