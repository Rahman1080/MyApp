import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../shared/services/warranty_service.dart';

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
            return const Center(
              child: Text('No warranties yet. Add one from a purchase.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
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
    final statusColor = status == WarrantyStatus.expired
        ? theme.colorScheme.error
        : status == WarrantyStatus.expiringSoon
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(purchaseName),
        subtitle: Text(
          [
            if (warranty.provider?.isNotEmpty == true) warranty.provider!,
            if (warranty.expirationDate != null)
              'Expires ${DateFormat.yMMMd().format(warranty.expirationDate!)}',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                switch (status) {
                  WarrantyStatus.active => 'Active',
                  WarrantyStatus.expiringSoon => 'Expiring soon',
                  WarrantyStatus.expired => 'Expired',
                },
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            if (daysLeft != null && status != WarrantyStatus.expired)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$daysLeft days left',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
        onTap: () => context.push('/purchases/warranties/${warranty.id}/edit'),
      ),
    );
  }
}
