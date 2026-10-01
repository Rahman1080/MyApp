import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/warranty_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_card.dart';

/// Warranties list: every warranty with its purchase, status badge and
/// days-left. Reached from the Purchases tab; the form is per purchase.
class WarrantiesScreen extends StatelessWidget {
  const WarrantiesScreen({
    super.key,
    required this.warrantyRepository,
    required this.purchaseRepository,
  });

  static const String routePath = '/purchases/warranties';

  final WarrantyRepository warrantyRepository;
  final PurchaseRepository purchaseRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warranties')),
      body: FutureBuilder<_WarrantyListData>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load warranties.'));
          }
          final data = snapshot.data!;
          if (data.warranties.isEmpty) {
            return EmptyState(
              icon: Icons.verified_outlined,
              headline: 'No warranties yet',
              body:
                  'Keep track of coverage, receipts, and expiration dates for your purchases.',
              actionLabel: 'Add warranty',
              onAction: () => context.push('/purchases/warranties/new'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: data.warranties.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final warranty = data.warranties[index];
              final purchase = data.purchases[warranty.purchaseId];
              return _WarrantyTile(
                warranty: warranty,
                purchaseName: purchase?.productName ?? 'Unknown purchase',
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/purchases/warranties/new'),
        icon: const Icon(Icons.add),
        label: const Text('Warranty'),
      ),
    );
  }

  Future<_WarrantyListData> _load() async {
    final warranties = await warrantyRepository.getAll();
    final purchases = await purchaseRepository.getAll();
    return _WarrantyListData(
      warranties: warranties,
      purchases: {for (final p in purchases) p.id: p},
    );
  }
}

class _WarrantyListData {
  _WarrantyListData({required this.warranties, required this.purchases});

  final List<Warranty> warranties;
  final Map<String, Purchase> purchases;
}

class _WarrantyTile extends StatelessWidget {
  const _WarrantyTile({
    required this.warranty,
    required this.purchaseName,
  });

  final Warranty warranty;
  final String purchaseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final expiry = warrantyExpiryDate(
      startDate: warranty.startDate,
      durationMonths: warranty.durationMonths,
      expirationDate: warranty.expirationDate,
    );
    final status = expiry == null
        ? WarrantyStatus.active
        : warrantyStatus(expiry: expiry, now: now);
    final daysLeft = expiry == null
        ? null
        : warrantyDaysRemaining(expiry, now);

    final Color statusColor;
    final String statusLabel;

    switch (status) {
      case WarrantyStatus.active:
        statusColor = AppColors.mintAccent;
        statusLabel = 'Active';
        break;
      case WarrantyStatus.expiringSoon:
        statusColor = AppColors.warning;
        statusLabel = 'Expiring soon';
        break;
      case WarrantyStatus.expired:
        statusColor = AppColors.urgent;
        statusLabel = 'Expired';
        break;
    }

    final subtitleParts = [
      if (warranty.provider?.isNotEmpty == true) warranty.provider!,
      if (warranty.expirationDate != null)
        'Expires ${DateFormat.yMMMd().format(warranty.expirationDate!)}',
    ];

    return KeepitCard(
      onTap: () => context.push('/purchases/warranties/${warranty.id}/edit'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.verified_outlined,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchaseName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitleParts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              if (daysLeft != null && status != WarrantyStatus.expired) ...[
                const SizedBox(height: 3),
                Text(
                  '$daysLeft days left',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
