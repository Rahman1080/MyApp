import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../database/keepit_database.dart';
import '../database/repositories/return_deadline_repository.dart';
import '../database/repositories/warranty_repository.dart';
import '../navigation/app_router.dart';
import '../notifications/notification_service.dart';
import '../notifications/payload_routing.dart';
import '../notifications/reminder_coordinator.dart';
import '../security/pin_lock_service.dart';
import '../theme/app_theme.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../shared/services/backup_service.dart';

/// The app widget. Built under [AppLockGate], which decides whether the user
/// sees the lock screen first.
class KeepItApp extends StatefulWidget {
  const KeepItApp({
    super.key,
    required this.database,
    required this.settingsRepository,
    required this.pinLock,
    required this.backupService,
    required this.themeModeListenable,
    required this.notificationService,
    required this.reminderCoordinator,
  });

  final KeepItDatabase database;
  final SettingsRepository settingsRepository;
  final PinLockService pinLock;
  final BackupService backupService;
  final ValueNotifier<ThemeMode> themeModeListenable;
  final NotificationService notificationService;
  final ReminderCoordinator reminderCoordinator;

  @override
  State<KeepItApp> createState() => _KeepItAppState();
}

class _KeepItAppState extends State<KeepItApp> {
  late final GoRouter _router = createAppRouter(
    database: widget.database,
    settingsRepository: widget.settingsRepository,
    pinLock: widget.pinLock,
    backupService: widget.backupService,
    themeModeListenable: widget.themeModeListenable,
    notificationService: widget.notificationService,
    reminderCoordinator: widget.reminderCoordinator,
  );
  late final WarrantyRepository _warrantyRepository =
      WarrantyRepository(widget.database);
  late final ReturnDeadlineRepository _returnDeadlineRepository =
      ReturnDeadlineRepository(widget.database);
  bool _privacyPromptShown = false;

  @override
  void initState() {
    super.initState();
    // Notification taps deep-link to the relevant deadline or purchase.
    widget.notificationService.onNotificationTap = _handleNotificationTap;
    // A notification that cold-launched the app is routed once the first
    // frame is up.
    widget.notificationService.launchPayload().then((payload) {
      if (payload != null && mounted) _handleNotificationTap(payload);
    }).catchError((_) {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowPrivacyPrompt());
  }

  Future<void> _handleNotificationTap(String? payload) async {
    final route = await routeForPayload(
      payload,
      purchaseIdForWarranty: (id) async =>
          (await _warrantyRepository.getById(id))?.purchaseId,
      purchaseIdForReturnDeadline: (id) async =>
          (await _returnDeadlineRepository.getById(id))?.purchaseId,
    );
    if (route != null && mounted) _router.go(route);
  }

  /// First-launch privacy notice. Shown once; accepting records the choice.
  /// "Read full policy" opens the policy screen and re-shows this dialog on
  /// return so the choice is still recorded.
  Future<void> _maybeShowPrivacyPrompt() async {
    if (_privacyPromptShown || !mounted) return;
    _privacyPromptShown = true;
    final accepted = await widget.settingsRepository
        .getPrivacyPolicyAccepted()
        .catchError((_) => true);
    if (!mounted || accepted) return;

    var done = false;
    while (!done) {
      if (!mounted) return;
      final choice = await showDialog<_PrivacyChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _PrivacyFirstRunDialog(),
      );
      if (!mounted) return;
      switch (choice) {
        case _PrivacyChoice.accept:
          await widget.settingsRepository.setPrivacyPolicyAccepted(true);
          await widget.settingsRepository.setOnboardingComplete(true);
          done = true;
        case _PrivacyChoice.readPolicy:
          await context.push(PrivacyPolicyScreen.routePath);
        case null:
          // Dismissed via back button: don't nag. The policy stays available
          // in Settings, and the prompt returns next launch.
          done = true;
      }
    }
  }

  @override
  void dispose() {
    widget.database.close().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeModeListenable,
      builder: (context, mode, _) {
        return MaterialApp.router(
          title: 'KeepIt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}

enum _PrivacyChoice { accept, readPolicy }

/// First-launch privacy notice. One decision: accepting records the choice.
/// The full policy lives in Settings → Privacy policy.
class _PrivacyFirstRunDialog extends StatelessWidget {
  const _PrivacyFirstRunDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your data stays yours'),
      content: const SingleChildScrollView(
        child: Text(
          'KeepIt works completely offline. Everything you add — purchases, '
          'receipts, photos, documents — is stored only on this device. '
          'There are no accounts, no analytics, and nothing is ever uploaded '
          'automatically. You can read the full policy any time in '
          'Settings → Privacy policy.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_PrivacyChoice.readPolicy),
          child: const Text('Read full policy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_PrivacyChoice.accept),
          child: const Text('I understand'),
        ),
      ],
    );
  }
}

/// Shown when the local database cannot be opened. Never a crash, never a
/// blank screen: the user gets an explanation and a way to retry.
class DatabaseErrorApp extends StatelessWidget {
  const DatabaseErrorApp({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepIt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        appBar: AppBar(title: const Text('KeepIt')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64),
                const SizedBox(height: 24),
                Text(
                  'Could not open your data',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'KeepIt stores everything on this device. The local '
                  'database could not be opened, so the app cannot start '
                  'safely. Your files were not modified.',
                  textAlign: TextAlign.center,
                ),
                if (kDebugMode && error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '$error',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
