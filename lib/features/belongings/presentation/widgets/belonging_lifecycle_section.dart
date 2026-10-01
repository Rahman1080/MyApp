import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/belonging_meta.dart';
import '../../../../core/database/keepit_database.dart';
import '../../domain/lifecycle_service.dart';

/// "Lifecycle" section for the item detail screen: acquisition info,
/// ownership duration, and disposition details (if retired).
class BelongingLifecycleSection extends StatelessWidget {
  const BelongingLifecycleSection({
    super.key,
    required this.belonging,
    required this.lifecycleService,
    required this.onChanged,
  });

  final Belonging belonging;
  final LifecycleService lifecycleService;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = lifecycleService.summarize(belonging);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Lifecycle', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit lifecycle details',
              onPressed: () => _editLifecycle(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Row(
          icon: Icons.login_outlined,
          label: 'Acquired',
          value: _acquisitionLabel(summary),
        ),
        _Row(
          icon: Icons.schedule_outlined,
          label: 'Owned for',
          value: summary.durationLabel,
        ),
        if (summary.isRetired) ...[
          _Row(
            icon: Icons.logout_outlined,
            label: 'Left',
            value: _dispositionLabel(summary),
          ),
          if (summary.dispositionRecipient != null &&
              summary.dispositionRecipient!.isNotEmpty)
            _Row(
              icon: Icons.person_outline,
              label: 'Recipient',
              value: summary.dispositionRecipient!,
            ),
          if (summary.dispositionPriceCents != null)
            _Row(
              icon: Icons.attach_money_outlined,
              label: summary.dispositionMethod == 'sold'
                  ? 'Sale price'
                  : 'Value',
              value: _moneyLabel(summary),
            ),
          if (summary.valueRetentionPercent != null)
            _Row(
              icon: Icons.trending_down_outlined,
              label: 'Value retained',
              value: '${summary.valueRetentionPercent!.toStringAsFixed(0)}%',
            ),
        ],
      ],
    );
  }

  String _acquisitionLabel(LifecycleSummary summary) {
    final parts = <String>[];
    if (summary.acquisitionType != null) {
      parts.add(BelongingAcquisitionType.labelOf(summary.acquisitionType));
    }
    if (summary.acquisitionDate != null) {
      parts.add(DateFormat.yMMMd().format(summary.acquisitionDate!));
    }
    return parts.isEmpty ? 'Not recorded' : parts.join(' · ');
  }

  String _dispositionLabel(LifecycleSummary summary) {
    final parts = <String>[];
    if (summary.dispositionMethod != null) {
      parts.add(BelongingDispositionMethod.labelOf(summary.dispositionMethod));
    }
    if (summary.dispositionDate != null) {
      parts.add(DateFormat.yMMMd().format(summary.dispositionDate!));
    }
    return parts.isEmpty ? 'Not recorded' : parts.join(' · ');
  }

  String _moneyLabel(LifecycleSummary summary) {
    final cents = summary.dispositionPriceCents!;
    final currency = summary.dispositionCurrencyCode ?? 'USD';
    return '$currency ${(cents / 100).toStringAsFixed(2)}';
  }

  Future<void> _editLifecycle(BuildContext context) async {
    final result = await showDialog<_LifecycleEditResult>(
      context: context,
      builder: (dialogContext) => _LifecycleEditDialog(belonging: belonging),
    );
    if (result == null || !context.mounted) return;

    await lifecycleService.recordAcquisition(
      belongingId: belonging.id,
      acquisitionType: result.acquisitionType,
      acquisitionDate: result.acquisitionDate,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lifecycle details updated.')),
      );
    }
    onChanged();
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _LifecycleEditResult {
  _LifecycleEditResult({this.acquisitionType, this.acquisitionDate});

  final String? acquisitionType;
  final DateTime? acquisitionDate;
}

class _LifecycleEditDialog extends StatefulWidget {
  const _LifecycleEditDialog({required this.belonging});

  final Belonging belonging;

  @override
  State<_LifecycleEditDialog> createState() => _LifecycleEditDialogState();
}

class _LifecycleEditDialogState extends State<_LifecycleEditDialog> {
  String? _acquisitionType;
  DateTime? _acquisitionDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _acquisitionType = widget.belonging.acquisitionType;
    _acquisitionDate = widget.belonging.acquisitionDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lifecycle details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How was this item acquired?'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _acquisitionType,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Select…',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Not set')),
              for (final type in BelongingAcquisitionType.all)
                DropdownMenuItem(
                  value: type,
                  child: Text(BelongingAcquisitionType.labelOf(type)),
                ),
            ],
            onChanged: (value) => setState(() => _acquisitionType = value),
          ),
          const SizedBox(height: 16),
          const Text('When was it acquired?'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              _acquisitionDate != null
                  ? DateFormat.yMMMd().format(_acquisitionDate!)
                  : 'Pick a date',
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _acquisitionDate ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _acquisitionDate = picked);
              }
            },
          ),
          if (_acquisitionDate != null)
            TextButton(
              onPressed: () => setState(() => _acquisitionDate = null),
              child: const Text('Clear date'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting
              ? null
              : () {
                  setState(() => _submitting = true);
                  Navigator.of(context).pop(
                    _LifecycleEditResult(
                      acquisitionType: _acquisitionType,
                      acquisitionDate: _acquisitionDate,
                    ),
                  );
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
