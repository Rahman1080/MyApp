import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/refund_repository.dart';
import '../../../core/database/repositories/return_deadline_repository.dart';
import '../../../core/database/repositories/service_record_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_card.dart';
import '../../../shared/widgets/keepit_section.dart';
import '../../../shared/widgets/keepit_stat_card.dart';
import '../../purchases/presentation/purchase_detail_screen.dart';
import '../../purchases/presentation/widgets/purchase_list_tile.dart';
import '../../settings/presentation/settings_screen.dart';
import 'home_view_model.dart';

/// Home tab: "what needs my attention?" command center, driven by real data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.purchaseRepository,
    required this.warrantyRepository,
    required this.returnDeadlineRepository,
    required this.deadlineRepository,
    this.belongingRepository,
    this.serviceRecordRepository,
    this.refundRepository,
  });

  static const String routePath = '/home';

  final PurchaseRepository purchaseRepository;
  final WarrantyRepository warrantyRepository;
  final ReturnDeadlineRepository returnDeadlineRepository;
  final DeadlineRepository deadlineRepository;
  final BelongingRepository? belongingRepository;
  final ServiceRecordRepository? serviceRecordRepository;
  final RefundRepository? refundRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _model = HomeViewModel(
    purchaseRepository: widget.purchaseRepository,
    warrantyRepository: widget.warrantyRepository,
    returnDeadlineRepository: widget.returnDeadlineRepository,
    deadlineRepository: widget.deadlineRepository,
    belongingRepository: widget.belongingRepository,
    serviceRecordRepository: widget.serviceRecordRepository,
    refundRepository: widget.refundRepository,
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
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: AppColors.mintAccent,
                shape: BoxShape.circle,
              ),
            ),
            const Text(
              'KEEPIT',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search everything',
            onPressed: () => context.push('/search'),
          ),
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
          if (_model.totalPurchases == 0 && _model.totalBelongings == 0) {
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
      body: 'Keep track of what you buy, where things are stored, warranties, '
          'and deadlines — everything stays privately on this device.',
      actionLabel: 'Add your first purchase',
      onAction: () => context.push('/purchases/new'),
    );
  }

  Widget _dashboard(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _greeting(),
        const SizedBox(height: 12),
        _statsGrid(),
        _attentionSection(),
        _recentSection(),
        const KeepitSection(title: 'Quick actions'),
        _quickActions(),
      ],
    );
  }

  Widget _greeting() {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    final attentionCount = _model.attentionCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: -0.3,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                attentionCount == 0
                    ? 'All caught up'
                    : '$attentionCount item${attentionCount == 1 ? '' : 's'} need your attention',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: attentionCount == 0
                      ? AppColors.mintAccent
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: KeepitStatCard(
              icon: Icons.receipt_long_outlined,
              value: '${_model.totalPurchases}',
              label: 'Purchases',
              onTap: () => context.go('/purchases'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeepitStatCard(
              icon: Icons.inventory_2_outlined,
              value: '${_model.totalBelongings}',
              label: 'My Stuff',
              onTap: () => context.go('/stuff'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeepitStatCard(
              icon: Icons.verified_outlined,
              value: '${_model.activeWarrantyCount}',
              label: 'Warranties',
              onTap: () => context.push('/purchases/warranties'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeepitStatCard(
              icon: Icons.event_outlined,
              value: '${_model.dueThisWeekCount}',
              label: 'Due soon',
              onTap: () => context.go('/deadlines'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attentionSection() {
    final theme = Theme.of(context);
    final items = _model.attentionItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeepitSection(
          title: 'Needs attention',
          trailing: items.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.urgent.withAlpha(28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: AppColors.urgent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
        if (items.isEmpty)
          KeepitCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.mintAccent.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.mintAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You are all caught up',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Approaching deadlines and warranties will surface here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _attentionTile(theme, items[i]),
                  if (i < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: theme.colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _attentionTile(ThemeData theme, AttentionItem item) {
    final Color badgeColor = switch (item.severity) {
      AttentionSeverity.critical => AppColors.urgent,
      AttentionSeverity.warning => AppColors.warning,
      AttentionSeverity.info => AppColors.mintAccent,
    };

    final destination = item.routePath ??
        (item.purchaseId != null ? PurchaseDetailScreen.routePathFor(item.purchaseId!) : null);

    return InkWell(
      onTap: destination != null ? () => context.push(destination) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeColor.withAlpha(24),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 20, color: badgeColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (destination != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recentSection() {
    final purchases = _model.recentPurchases;
    if (purchases.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeepitSection(
          title: 'Recent purchases',
          actionLabel: 'See all',
          onAction: () => context.go('/purchases'),
        ),
        KeepitCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < purchases.length; i++) ...[
                PurchaseListTile(
                  purchase: purchases[i],
                  onTap: () => context.push(
                    PurchaseDetailScreen.routePathFor(purchases[i].id),
                  ),
                ),
                if (i < purchases.length - 1)
                  Divider(
                    height: 1,
                    indent: 72,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _actionPill(
            icon: Icons.add_shopping_cart,
            label: 'Add purchase',
            onTap: () => context.push('/purchases/new'),
          ),
          _actionPill(
            icon: Icons.document_scanner_outlined,
            label: 'Scan receipt',
            onTap: () => _scanReceipt(context),
          ),
          _actionPill(
            icon: Icons.event_outlined,
            label: 'Add deadline',
            onTap: () => context.push('/deadlines/new'),
          ),
          _actionPill(
            icon: Icons.inventory_2_outlined,
            label: 'Add belonging',
            onTap: () => context.push('/stuff/new'),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Scan receipt" needs a purchase to attach the receipt to.
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
