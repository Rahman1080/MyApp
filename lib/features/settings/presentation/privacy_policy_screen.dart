import 'package:flutter/material.dart';

/// Plain-language privacy policy. Everything it says is a statement of the
/// app's actual behavior: offline-first, no accounts, no analytics, no
/// uploads — ever.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const routePath = '/settings/privacy';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'KeepIt privacy policy',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Last updated: September 2026',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _Section(
            title: 'The short version',
            body: 'KeepIt works completely offline. Everything you add — '
                'purchases, receipts, photos, documents, reminders — is '
                'stored only on this device. There are no accounts, no '
                'analytics, no ads, and nothing is ever uploaded '
                'automatically.',
          ),
          const _Section(
            title: 'On-device storage',
            body: 'Your data lives in a database and files inside the app’s '
                'private storage on this device. Other apps cannot read it, '
                'and KeepIt never sends it to a server. There is no server: '
                'there is no backend, no cloud sync, and no account system '
                'to sync to.',
          ),
          const _Section(
            title: 'Receipt scanning',
            body: 'When you scan a receipt, text recognition runs entirely '
                'on this device. The image is stored in the app’s private '
                'storage, and the recognized text is shown to you for '
                'confirmation — nothing is ever saved without your explicit '
                'approval, and nothing leaves the device.',
          ),
          const _Section(
            title: 'Photos and documents',
            body: 'Photos and documents you attach stay in the app’s private '
                'storage on this device. They are only copied somewhere else '
                'if you choose to export a backup yourself.',
          ),
          const _Section(
            title: 'Backups',
            body: 'Backups are ZIP files that you create explicitly from '
                'Settings → Back up now. You choose where to save them — '
                'your phone, a computer, a drive — and restoring one '
                'replaces everything in the app only after you confirm. '
                'KeepIt never makes or uploads backups on its own.',
          ),
          const _Section(
            title: 'Notifications',
            body: 'Reminders are scheduled by your device’s own notification '
                'system. No reminder content is sent anywhere; it is created '
                'and delivered locally.',
          ),
          const _Section(
            title: 'App lock',
            body: 'If you set an app-lock PIN, only a salted cryptographic '
                'hash of it is kept in your device’s secure storage (the '
                'Android Keystore or iOS Keychain). The PIN itself is never '
                'stored or logged. If you enable biometric unlock, '
                'verification is handled entirely by your device’s operating '
                'system.',
          ),
          const _Section(
            title: 'Your control',
            body: 'You can export your data any time with a backup, and you '
                'can permanently delete everything in Settings → Delete all '
                'data. Deleting removes the database and all stored files '
                'from this device. Backups you saved elsewhere are yours to '
                'delete.',
          ),
          const _Section(
            title: 'Changes to this policy',
            body: 'If this policy ever changes, the updated version will be '
                'shown in the app. Because the app works offline, we cannot '
                'notify you any other way — but the rule stays the same: '
                'your data stays on your device.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
