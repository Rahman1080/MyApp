import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/keepit_database.dart';
import '../../core/database/repositories/belonging_history_repository.dart';
import '../../core/database/repositories/belonging_photo_repository.dart';
import '../../core/database/repositories/belonging_repository.dart';
import '../../core/database/repositories/category_repository.dart';
import '../../core/database/repositories/deadline_repository.dart';
import '../../core/database/repositories/document_repository.dart';
import '../../core/database/repositories/location_repository.dart';
import '../../core/database/repositories/move_item_repository.dart';
import '../../core/database/repositories/move_repository.dart';
import '../../core/database/repositories/place_repository.dart';
import '../../core/database/repositories/product_repository.dart';
import '../../core/database/repositories/purchase_repository.dart';
import '../../core/database/repositories/receipt_repository.dart';
import '../../core/database/repositories/refund_repository.dart';
import '../../core/database/repositories/reminder_repository.dart';
import '../../core/database/repositories/return_deadline_repository.dart';
import '../../core/database/repositories/service_record_repository.dart';
import '../../core/database/repositories/tag_repository.dart';
import '../../core/database/repositories/warranty_repository.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_coordinator.dart';
import '../../core/security/pin_lock_service.dart';
import '../../features/belongings/presentation/belonging_detail_screen.dart';
import '../../features/belongings/presentation/belonging_form_screen.dart';
import '../../features/belongings/presentation/belongings_screen.dart';
import '../../features/belongings/presentation/lifetime_record_screen.dart';
import '../../features/belongings/domain/item_lifetime_service.dart';
import '../../features/belongings/domain/lifecycle_service.dart';
import '../../features/ask/domain/ask_service.dart';
import '../../features/ask/presentation/ask_screen.dart';
import '../../features/household/domain/household_dashboard_service.dart';
import '../../features/household/presentation/household_dashboard_screen.dart';
import '../../features/organize/domain/smart_organization_service.dart';
import '../../features/organize/presentation/organize_screen.dart';
import '../../features/sync/presentation/sync_screen.dart';
import '../../features/deadlines/presentation/deadline_detail_screen.dart';
import '../../features/deadlines/presentation/deadline_form_screen.dart';
import '../../features/deadlines/presentation/deadlines_screen.dart';
import '../../features/documents/domain/document_service.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/locations/presentation/location_form_screen.dart';
import '../../features/locations/presentation/locations_screen.dart';
import '../../features/purchases/presentation/purchase_detail_screen.dart';
import '../../features/purchases/presentation/purchase_form_screen.dart';
import '../../features/purchases/presentation/purchases_screen.dart';
import '../../features/receipts/presentation/receipt_scan_screen.dart';
import '../../features/reports/domain/evidence_export_service.dart';
import '../../features/reports/domain/pdf_report_builder.dart';
import '../../features/reports/domain/report_service.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/moves/domain/move_service.dart';
import '../../features/moves/presentation/move_detail_screen.dart';
import '../../features/moves/presentation/moves_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../features/settings/presentation/set_pin_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/warranties/presentation/warranties_screen.dart';
import '../../features/warranties/presentation/warranty_form_screen.dart';
import '../../shared/services/backup_service.dart';
import '../../shared/services/global_search.dart';
import '../../shared/services/location_service.dart';
import '../../shared/widgets/coming_soon_screen.dart';
import 'app_shell.dart';

/// Application routes.
///
/// Repositories and notification services are constructed once per router
/// from the shared database and injected into screens — no globals, no
/// service locator.
GoRouter createAppRouter({
  required KeepItDatabase database,
  required SettingsRepository settingsRepository,
  required PinLockService pinLock,
  required BackupService backupService,
  required ValueNotifier<ThemeMode> themeModeListenable,
  required NotificationService notificationService,
  required ReminderCoordinator reminderCoordinator,
}) {
  final purchaseRepository = PurchaseRepository(database);
  final productRepository = ProductRepository(database);
  final warrantyRepository = WarrantyRepository(database);
  final receiptRepository = ReceiptRepository(database);
  final returnDeadlineRepository = ReturnDeadlineRepository(database);
  final refundRepository = RefundRepository(database);
  final deadlineRepository = DeadlineRepository(database);
  final categoryRepository = CategoryRepository(database);
  final reminderRepository = ReminderRepository(database);
  final documentRepository = DocumentRepository(database);
  final belongingRepository = BelongingRepository(database);
  final belongingPhotoRepository = BelongingPhotoRepository(database);
  final belongingHistoryRepository = BelongingHistoryRepository(database);
  final lifecycleService = LifecycleService(database);
  final tagRepository = TagRepository(database);
  final locationRepository = LocationRepository(database);
  final locationService = LocationService(database);
  final placeRepository = PlaceRepository(database);
  final globalSearchService = GlobalSearchService(database);
  final documentService =
      DocumentService(documentRepository: documentRepository);
  final reportService = ReportService(db: database);
  final pdfReportBuilder = PdfReportBuilder();
  final evidenceExportService = EvidenceExportService();
  final moveRepository = MoveRepository(database);
  final moveItemRepository = MoveItemRepository(database);
  final moveService = MoveService(
    db: database,
    moves: moveRepository,
    moveItems: moveItemRepository,
    belongings: belongingRepository,
    locations: locationRepository,
    locationService: locationService,
  );
  // Phase 16–22 UI services (domain logic already existed; these wire it
  // into user-facing screens).
  final askKeepitService = AskKeepitService(database);
  final smartOrganizationService = SmartOrganizationService(database);
  final householdDashboardService = HouseholdDashboardService(database);
  final itemLifetimeService = ItemLifetimeService(database);
  final serviceRecordRepository = ServiceRecordRepository(database);

  return GoRouter(
    initialLocation: HomeScreen.routePath,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: HomeScreen.routePath,
                name: 'home',
                builder: (context, state) => HomeScreen(
                  purchaseRepository: purchaseRepository,
                  warrantyRepository: warrantyRepository,
                  returnDeadlineRepository: returnDeadlineRepository,
                  deadlineRepository: deadlineRepository,
                  belongingRepository: belongingRepository,
                  serviceRecordRepository: serviceRecordRepository,
                  refundRepository: refundRepository,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PurchasesScreen.routePath,
                name: 'purchases',
                builder: (context, state) => PurchasesScreen(
                  purchaseRepository: purchaseRepository,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'purchase-new',
                    builder: (context, state) => PurchaseFormScreen(
                      purchaseRepository: purchaseRepository,
                      database: database,
                    ),
                  ),
                  GoRoute(
                    path: 'warranties',
                    name: 'warranties',
                    builder: (context, state) => WarrantiesScreen(
                      warrantyRepository: warrantyRepository,
                      purchaseRepository: purchaseRepository,
                    ),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: 'warranty-new',
                        builder: (context, state) => WarrantyFormScreen(
                          warrantyRepository: warrantyRepository,
                          purchaseRepository: purchaseRepository,
                          documentRepository: documentRepository,
                          reminderCoordinator: reminderCoordinator,
                          notificationService: notificationService,
                          initialPurchaseId:
                              state.uri.queryParameters['purchaseId'],
                        ),
                      ),
                      GoRoute(
                        path: ':warrantyId/edit',
                        name: 'warranty-edit',
                        builder: (context, state) => WarrantyFormScreen(
                          warrantyRepository: warrantyRepository,
                          purchaseRepository: purchaseRepository,
                          documentRepository: documentRepository,
                          reminderCoordinator: reminderCoordinator,
                          notificationService: notificationService,
                          warrantyId:
                              state.pathParameters['warrantyId'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: ':id',
                    name: 'purchase-detail',
                    builder: (context, state) => PurchaseDetailScreen(
                      purchaseId: state.pathParameters['id']!,
                      database: database,
                      purchaseRepository: purchaseRepository,
                      productRepository: productRepository,
                      warrantyRepository: warrantyRepository,
                      returnDeadlineRepository: returnDeadlineRepository,
                      refundRepository: refundRepository,
                      reminderRepository: reminderRepository,
                      reminderCoordinator: reminderCoordinator,
                      notificationService: notificationService,
                      belongingRepository: belongingRepository,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        name: 'purchase-edit',
                        builder: (context, state) => PurchaseFormScreen(
                          purchaseRepository: purchaseRepository,
                          database: database,
                          purchaseId: state.pathParameters['id'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: BelongingsScreen.routePath,
                name: 'stuff',
                builder: (context, state) => BelongingsScreen(
                  belongingRepository: belongingRepository,
                  locationRepository: locationRepository,
                  categoryRepository: categoryRepository,
                  locationService: locationService,
                  placeRepository: placeRepository,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'belonging-new',
                    builder: (context, state) => BelongingFormScreen(
                      belongingRepository: belongingRepository,
                      categoryRepository: categoryRepository,
                      locationRepository: locationRepository,
                      purchaseRepository: purchaseRepository,
                      tagRepository: tagRepository,
                      historyRepository: belongingHistoryRepository,
                    ),
                  ),
                  GoRoute(
                    path: 'locations',
                    name: 'locations',
                    builder: (context, state) => LocationsScreen(
                      locationRepository: locationRepository,
                      belongingRepository: belongingRepository,
                      locationService: locationService,
                      placeRepository: placeRepository,
                      initialLocationId:
                          state.uri.queryParameters['focus'],
                    ),
                    routes: [
                      GoRoute(
                        path: 'new',
                        name: 'location-new',
                        builder: (context, state) => LocationFormScreen(
                          locationRepository: locationRepository,
                          locationService: locationService,
                          placeRepository: placeRepository,
                          initialParentId:
                              state.uri.queryParameters['parentId'],
                          initialPlaceId:
                              state.uri.queryParameters['placeId'],
                        ),
                      ),
                      GoRoute(
                        path: ':locationId/edit',
                        name: 'location-edit',
                        builder: (context, state) => LocationFormScreen(
                          locationRepository: locationRepository,
                          locationService: locationService,
                          placeRepository: placeRepository,
                          locationId:
                              state.pathParameters['locationId'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: ':id',
                    name: 'belonging-detail',
                    builder: (context, state) => BelongingDetailScreen(
                      belongingId: state.pathParameters['id']!,
                      belongingRepository: belongingRepository,
                      locationRepository: locationRepository,
                      categoryRepository: categoryRepository,
                      documentService: documentService,
                      purchaseRepository: purchaseRepository,
                      receiptRepository: receiptRepository,
                      warrantyRepository: warrantyRepository,
                      tagRepository: tagRepository,
                      photoRepository: belongingPhotoRepository,
                      historyRepository: belongingHistoryRepository,
                      locationService: locationService,
                      placeRepository: placeRepository,
                      lifecycleService: lifecycleService,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        name: 'belonging-edit',
                        builder: (context, state) => BelongingFormScreen(
                          belongingRepository: belongingRepository,
                          categoryRepository: categoryRepository,
                          locationRepository: locationRepository,
                          purchaseRepository: purchaseRepository,
                          tagRepository: tagRepository,
                          historyRepository: belongingHistoryRepository,
                          belongingId: state.pathParameters['id'],
                        ),
                      ),
                      GoRoute(
                        path: 'lifetime',
                        name: 'belonging-lifetime',
                        builder: (context, state) => LifetimeRecordScreen(
                          lifetimeService: itemLifetimeService,
                          belongingId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DeadlinesScreen.routePath,
                name: 'deadlines',
                builder: (context, state) => DeadlinesScreen(
                  deadlineRepository: deadlineRepository,
                  purchaseRepository: purchaseRepository,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'deadline-new',
                    builder: (context, state) => DeadlineFormScreen(
                      deadlineRepository: deadlineRepository,
                      categoryRepository: categoryRepository,
                      purchaseRepository: purchaseRepository,
                      reminderRepository: reminderRepository,
                      reminderCoordinator: reminderCoordinator,
                      notificationService: notificationService,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    name: 'deadline-detail',
                    builder: (context, state) => DeadlineDetailScreen(
                      deadlineId: state.pathParameters['id']!,
                      deadlineRepository: deadlineRepository,
                      categoryRepository: categoryRepository,
                      purchaseRepository: purchaseRepository,
                      reminderRepository: reminderRepository,
                      reminderCoordinator: reminderCoordinator,
                      notificationService: notificationService,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        name: 'deadline-edit',
                        builder: (context, state) => DeadlineFormScreen(
                          deadlineRepository: deadlineRepository,
                          categoryRepository: categoryRepository,
                          purchaseRepository: purchaseRepository,
                          reminderRepository: reminderRepository,
                          reminderCoordinator: reminderCoordinator,
                          notificationService: notificationService,
                          deadlineId: state.pathParameters['id'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: SettingsScreen.routePath,
        name: 'settings',
        builder: (context, state) => SettingsScreen(
          settingsRepository: settingsRepository,
          pinLock: pinLock,
          backupService: backupService,
          themeModeListenable: themeModeListenable,
          notificationService: notificationService,
        ),
        routes: [
          GoRoute(
            path: 'pin',
            name: 'set-pin',
            builder: (context, state) {
              final modeParam = state.uri.queryParameters['mode'];
              return SetPinScreen(
                pinLock: pinLock,
                settingsRepository: settingsRepository,
                initialMode: switch (modeParam) {
                  'setup' => SetPinMode.setup,
                  'remove' => SetPinMode.remove,
                  _ => SetPinMode.change,
                },
              );
            },
          ),
          GoRoute(
            path: 'privacy',
            name: 'privacy-policy',
            builder: (context, state) => const PrivacyPolicyScreen(),
          ),
        ],
      ),
      GoRoute(
        path: SearchScreen.routePath,
        name: 'search',
        builder: (context, state) => SearchScreen(
          searchService: globalSearchService,
          locationRepository: locationRepository,
          locationService: locationService,
          placeRepository: placeRepository,
        ),
      ),
      GoRoute(
        path: ReportsScreen.routePath,
        name: 'reports',
        builder: (context, state) => ReportsScreen(
          reportService: reportService,
          pdfBuilder: pdfReportBuilder,
          exportService: evidenceExportService,
          placeRepository: placeRepository,
          locationRepository: locationRepository,
          categoryRepository: categoryRepository,
          belongingRepository: belongingRepository,
        ),
      ),
      GoRoute(
        path: MovesScreen.routePath,
        name: 'moves',
        builder: (context, state) => MovesScreen(
          moveRepository: moveRepository,
          placeRepository: placeRepository,
        ),
        routes: [
          GoRoute(
            path: ':id',
            name: 'move-detail',
            builder: (context, state) => MoveDetailScreen(
              moveId: state.pathParameters['id']!,
              moveRepository: moveRepository,
              moveItemRepository: moveItemRepository,
              belongingRepository: belongingRepository,
              locationRepository: locationRepository,
              placeRepository: placeRepository,
              moveService: moveService,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AskScreen.routePath,
        name: 'ask',
        builder: (context, state) => AskScreen(
          askService: askKeepitService,
        ),
      ),
      GoRoute(
        path: SyncScreen.routePath,
        name: 'sync',
        builder: (context, state) => SyncScreen(
          database: database,
        ),
      ),
      GoRoute(
        path: OrganizeScreen.routePath,
        name: 'organize',
        builder: (context, state) => OrganizeScreen(
          organizationService: smartOrganizationService,
          belongingRepository: belongingRepository,
          locationRepository: locationRepository,
          categoryRepository: categoryRepository,
        ),
      ),
      GoRoute(
        path: HouseholdDashboardScreen.routePath,
        name: 'household-dashboard',
        builder: (context, state) => HouseholdDashboardScreen(
          dashboardService: householdDashboardService,
        ),
      ),
      GoRoute(
        path: ReceiptScanScreen.routePath,
        name: 'scan',        builder: (context, state) {
          final purchaseId = state.uri.queryParameters['purchaseId'];
          if (purchaseId == null || purchaseId.isEmpty) {
            return const ComingSoonScreen(
              title: 'Scan receipt',
              message: 'Choose a purchase first, then scan its receipt.',
            );
          }
          return ReceiptScanScreen(
            purchaseId: purchaseId,
            database: database,
          );
        },
      ),
      GoRoute(
        path: ComingSoonScreen.routePath,
        name: 'coming-soon',
        builder: (context, state) => ComingSoonScreen(
          title: state.uri.queryParameters['title'] ?? 'Coming soon',
          message: state.uri.queryParameters['message'] ??
              'This feature is coming in a later phase.',
        ),
      ),
      // Redirects for legacy / alternative /belongings paths to /stuff
      GoRoute(
        path: '/belongings/:id/lifetime',
        redirect: (context, state) =>
            '/stuff/${state.pathParameters['id']}/lifetime',
      ),
      GoRoute(
        path: '/belongings/:id/edit',
        redirect: (context, state) =>
            '/stuff/${state.pathParameters['id']}/edit',
      ),
      GoRoute(
        path: '/belongings/:id',
        redirect: (context, state) =>
            '/stuff/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/belongings',
        redirect: (context, state) => '/stuff',
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('KeepIt'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(HomeScreen.routePath);
            }
          },
        ),
      ),
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
}
