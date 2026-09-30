import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utilities/money.dart';
import '../../../../shared/services/duplicate_detector.dart';

/// "Possible duplicate" dialog shown before saving a purchase when
/// [DuplicateDetector] finds candidates.
///
/// Never merges or deletes — the user picks "View" on an existing record
/// or "Create anyway". "Cancel" aborts the save entirely.
class DuplicateDialog extends StatelessWidget {
  const DuplicateDialog({
    super.key,
    required this.candidates,
    required this.onViewExisting,
    required this.onCreateAnyway,
  });

  final List<DuplicateCandidate> candidates;
  final void Function(String purchaseId) onViewExisting;
  final VoidCallback onCreateAnyway;

  @override
  Widget build(BuildContext context) {
    final shown = candidates.take(3).toList();
    return AlertDialog(
      icon: const Icon(Icons.content_copy_outlined),
      title: const Text('Possible duplicate'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'These existing purchases look similar. Open one to check, '
              'or create your new entry anyway.',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: shown.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final candidate = shown[index];
                  final purchase = candidate.purchase;
                  final date = purchase.purchaseDate;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      purchase.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if ((purchase.store ?? '').isNotEmpty)
                          purchase.store!,
                        if (date != null) DateFormat.yMMMd().format(date),
                        formatMoney(
                          purchase.priceCents,
                          purchase.currencyCode,
                        ),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () => onViewExisting(purchase.id),
                      child: const Text('View'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: onCreateAnyway,
          child: const Text('Create anyway'),
        ),
      ],
    );
  }
}
