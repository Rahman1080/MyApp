import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/return_deadline_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../purchases/presentation/purchase_detail_screen.dart';
import '../../purchases/presentation/widgets/purchase_list_tile.dart';
import '../../settings/presentation/settings_screen.dart';
import 'home_view_model.dart';

/// Home tab: "what needs my attention?" overview, driven by real data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.purchaseRepository,
    required this.warrantyRepository,
    required this.returnDeadlineRepository,
    required this.deadlineRepository,
  });

  static const String routePath = '/home';

  final PurchaseRepository purchaseRepository;
  final WarrantyRepository warrantyRepository;
  final ReturnDeadlineRepository returnDeadlineRepository;
  final DeadlineRepository deadlineRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _model = HomeViewModel(
    purchaseRepository: widget.purchaseRepository,
    warrantyRepository: widget.warrantyRepository,
    returnDeadlineRepository: widget.returnDeadlineRepository,
    deadlineRepository: widget.deadlineRepository,
  );

  @override
  void initState() {
    super.initState();
    _model.init();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KeepIt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(SettingsScreen.routePath),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _model,
        builder: (context, _) {
          if (_model.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_model.totalPurchases == 0) {
            return _newUserEmptyState(context);
          }
          return _dashboard(context);
        },
      ),
    );
  }

  Widget _newUserEmptyState(BuildContext context) {
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      headline: 'Welcome to KeepIt',
      body: 'Keep track of what you buy, where the receipt is, and when you '
          'need to act — everything stays privately on this device.',
      actionLabel: 'Add your first purchase',
      onAction: () => context.push('/purchases/new'),
    );
  }

  Widget _dashboard(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _greeting(theme),
        const SizedBox(height: 16),
        _statsRow(),
        const SizedBox(height: 16),
        _attentionSection(theme),
        const SizedBox(height: 16),
        _recentSection(theme),
        const SizedBox(height: 16),
        Text('Quick actions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _quickActions(),
      ],
    );
  }

  Widget _greeting(ThemeData theme) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          _model.attentionCount == 0
              ? 'You are all caught up.'
              : '${_model.attentionCount} thing${_model.attentionCount == 1 ? '' : 's'} need${_model.attentionCount == 1 ? 's' : ''} your attention.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.receipt_long_outlined,
            value: '${_model.totalPurchases}',
            label: 'Purchases',
            onTap: () => context.go('/purchases'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.verified_outlined,
            value: '${_model.activeWarrantyCount}',
            label: 'Warranties',
            onTap: null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.event_outlined,
            value: '${_model.dueThisWeekCount}',
            label: 'Due this week',
            onTap: null,
          ),
        ),
      ],
    );
  }

  Widget _attentionSection(ThemeData theme) {
    final items = _model.attentionItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Needs attention', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              title: Text(
                'You are all caught up',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Deadlines, warranties and returns will surface here.',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _attentionTile(theme, items[i]),
                  if (i < items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _attentionTile(ThemeData theme, AttentionItem item) {
    final color = item.severity == AttentionSeverity.critical
        ? theme.colorScheme.error
        : const Color(0xFFB25E09);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(item.icon, color: color),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle:
          Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: item.purchaseId == null
          ? null
          : const Icon(Icons.chevron_right),
      onTap: item.purchaseId == null
          ? null
          : () => context.push(
                PurchaseDetailScreen.routePathFor(item.purchaseId!),
              ),
    );
  }

  Widget _recentSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent purchases', style: theme.textTheme.titleMedium),
            TextButton(
              onPressed: () => context.go('/purchases'),
              child: const Text('See all'),
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < _model.recentPurchases.length; i++) ...[
                PurchaseListTile(
                  purchase: _model.recentPurchases[i],
                  onTap: () => context.push(
                    PurchaseDetailScreen.routePathFor(
                      _model.recentPurchases[i].id,
                    ),
                  ),
                ),
                if (i < _model.recentPurchases.length - 1)
                  const Divider(height: 1, indent: 72),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _QuickAction(
          icon: Icons.add_shopping_cart,
          label: 'Add purchase',
          onTap: () => context.push('/purchases/new'),
        ),
        _QuickAction(
          icon: Icons.document_scanner_outlined,
          label: 'Scan receipt',
          onTap: () => _scanReceipt(context),
        ),
        _QuickAction(
          icon: Icons.event_outlined,
          label: 'Add deadline',
          onTap: () => context.push('/deadlines/new'),
        ),
        _QuickAction(
          icon: Icons.inventory_2_outlined,
          label: 'Add belonging',
          onTap: () => context.push('/stuff/new'),
        ),
      ],
    );
  }

  /// "Scan receipt" needs a purchase to attach the receipt to: let the user
  /// pick one, or create a purchase first.
  Future<void> _scanReceipt(BuildContext context) async {
    final purchases = await widget.purchaseRepository.getAll();
    if (!context.mounted) return;
    if (purchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a purchase first, then scan its receipt.'),
        ),
      );
      context.push('/purchases/new');
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Which purchase is this receipt for?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: purchases.length,
                itemBuilder: (_, index) {
                  final purchase = purchases[index];
                  return ListTile(
                    leading: const Icon(Icons.shopping_bag_outlined),
                    title: Text(purchase.productName),
                    subtitle: purchase.store == null
                        ? null
                        : Text(purchase.store!),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(purchase.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      context.push('/scan?purchaseId=${Uri.encodeComponent(selected)}');
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                semanticsLabel: '$value $label',
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
