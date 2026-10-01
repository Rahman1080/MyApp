import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_chip.dart';
import '../../../shared/widgets/keepit_search_bar.dart';
import 'purchase_detail_screen.dart';
import 'widgets/purchase_list_tile.dart';

/// Purchases tab: "What did I buy?" — searchable, filterable, sortable list
/// with full CRUD behind the detail and form screens.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.purchaseRepository});

  static const String routePath = '/purchases';

  final PurchaseRepository purchaseRepository;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

enum _SortOrder { newest, oldest, priceHigh, priceLow }

class _PurchasesScreenState extends State<PurchasesScreen> {
  static const List<String?> _statusFilters = [
    null, // All
    'active',
    'returned',
    'refunded',
    'exchanged',
  ];

  String? _statusFilter;
  _SortOrder _sortOrder = _SortOrder.newest;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          PopupMenuButton<_SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sortOrder,
            onSelected: (order) => setState(() => _sortOrder = order),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SortOrder.newest,
                child: Text('Newest first'),
              ),
              PopupMenuItem(
                value: _SortOrder.oldest,
                child: Text('Oldest first'),
              ),
              PopupMenuItem(
                value: _SortOrder.priceHigh,
                child: Text('Price: high to low'),
              ),
              PopupMenuItem(
                value: _SortOrder.priceLow,
                child: Text('Price: low to high'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          KeepitSearchBar(
            hintText: 'Search purchases by product, store...',
            onChanged: (value) =>
                setState(() => _searchQuery = value.trim().toLowerCase()),
          ),
          _filterChips(),
          const SizedBox(height: 4),
          Expanded(child: _purchaseList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/purchases/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add purchase'),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _statusFilters.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final status = _statusFilters[index];
          final selected = _statusFilter == status;
          return KeepitFilterChip(
            label: status == null ? 'All' : _statusLabel(status),
            selected: selected,
            onSelected: (_) => setState(() => _statusFilter = status),
          );
        },
      ),
    );
  }

  Widget _purchaseList() {
    return StreamBuilder<List<Purchase>>(
      stream: widget.purchaseRepository.watchAll(status: _statusFilter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Could not load purchases. Your data is safe — try reopening the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        final purchases = _applySearchAndSort(snapshot.data ?? []);
        if (purchases.isEmpty) {
          return _emptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: purchases.length,
          separatorBuilder: (_, i) =>
              const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final purchase = purchases[index];
            return PurchaseListTile(
              purchase: purchase,
              onTap: () => context.push(
                PurchaseDetailScreen.routePathFor(purchase.id),
              ),
            );
          },
        );
      },
    );
  }

  List<Purchase> _applySearchAndSort(List<Purchase> purchases) {
    var filtered = purchases;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) {
        final haystack =
            '${p.productName} ${p.store ?? ''} ${p.notes ?? ''}'.toLowerCase();
        return haystack.contains(_searchQuery);
      }).toList();
    }
    switch (_sortOrder) {
      case _SortOrder.newest:
        filtered.sort(_byNewest);
      case _SortOrder.oldest:
        filtered.sort((a, b) => _byNewest(b, a));
      case _SortOrder.priceHigh:
        filtered.sort(
          (a, b) => (b.priceCents ?? -1).compareTo(a.priceCents ?? -1),
        );
      case _SortOrder.priceLow:
        filtered.sort(
          (a, b) => (a.priceCents ?? -1).compareTo(b.priceCents ?? -1),
        );
    }
    return filtered;
  }

  static int _byNewest(Purchase a, Purchase b) {
    final dateCompare = _dateKey(b).compareTo(_dateKey(a));
    if (dateCompare != 0) return dateCompare;
    return b.createdAt.compareTo(a.createdAt);
  }

  static DateTime _dateKey(Purchase p) =>
      p.purchaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);

  Widget _emptyState() {
    final filtering = _searchQuery.isNotEmpty || _statusFilter != null;
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      headline: filtering ? 'No matching purchases' : 'No purchases yet',
      body: filtering
          ? 'Try a different search or filter.'
          : 'Add your first purchase to track receipts, return deadlines, '
              'warranties and refunds — all stored privately on this device.',
      actionLabel: filtering ? null : 'Add purchase',
      onAction: filtering ? null : () => context.push('/purchases/new'),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'returned':
        return 'Returned';
      case 'refunded':
        return 'Refunded';
      case 'exchanged':
        return 'Exchanged';
      default:
        return status;
    }
  }
}
