import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/keepit_database.dart';
import '../../../../core/utilities/money.dart';
import '../../../../shared/widgets/status_badge.dart';

/// One purchase row: thumbnail placeholder, name, store · date, price and
/// status badge. Used by the purchases list and the home "recent" section.
class PurchaseListTile extends StatelessWidget {
  const PurchaseListTile({
    super.key,
    required this.purchase,
    this.onTap,
  });

  final Purchase purchase;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = purchase.purchaseDate;
    final dateLabel =
        date == null ? 'No date' : DateFormat.yMMMd().format(date);
    final store = purchase.store?.trim();
    final subtitle = [
      if (store != null && store.isNotEmpty) store,
      dateLabel,
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.shopping_bag_outlined,
          color: scheme.onSecondaryContainer,
          semanticLabel: 'Purchase',
        ),
      ),
      title: Text(
        purchase.productName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(purchase.priceCents, purchase.currencyCode),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          StatusBadge(status: purchase.status),
        ],
      ),
      onTap: onTap,
    );
  }
}
