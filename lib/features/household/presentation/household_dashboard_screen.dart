import 'package:flutter/material.dart';

import '../../../core/utilities/money.dart';
import '../domain/household_dashboard_service.dart';

/// Phase 21 UI — Household Command Center.
///
/// A read-only dashboard aggregating household data:
/// - Totals (items, estimated value)
/// - Privacy breakdown (shared vs private)
/// - Per-member summaries (items, value, shared/private)
/// - Per-location summaries
///
/// Nothing here modifies data; it is purely informational.
class HouseholdDashboardScreen extends StatefulWidget {
  const HouseholdDashboardScreen({
    super.key,
    required this.dashboardService,
  });

  static const routePath = '/household-dashboard';

  final HouseholdDashboardService dashboardService;

  @override
  State<HouseholdDashboardScreen> createState() =>
      _HouseholdDashboardScreenState();
}

class _HouseholdDashboardScreenState
    extends State<HouseholdDashboardScreen> {
  HouseholdDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dashboard = await widget.dashboardService.getDashboard();
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Household Command Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dashboard == null
              ? const Center(child: Text('Could not load dashboard.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildTotals(),
                      const SizedBox(height: 16),
                      _buildPrivacy(),
                      const SizedBox(height: 16),
                      _buildMembers(),
                      const SizedBox(height: 16),
                      _buildLocations(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTotals() {
    final d = _dashboard!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _bigStat('${d.totalItems}', 'Items'),
            _bigStat(
              formatMoney(d.totalValueCents, 'USD'),
              'Est. value',
            ),
            _bigStat('${d.memberSummaries.length}', 'Members'),
          ],
        ),
      ),
    );
  }

  Widget _bigStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPrivacy() {
    final p = _dashboard!.privacyBreakdown;
    final total = p.total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Expanded(
                      flex: p.sharedCount,
                      child: Container(
                        height: 12,
                        color: Colors.blue,
                      ),
                    ),
                    Expanded(
                      flex: p.privateCount,
                      child: Container(
                        height: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _privacyRow(
              Colors.blue,
              'Shared',
              p.sharedCount,
            ),
            _privacyRow(
              Colors.orange,
              'Private',
              p.privateCount,
            ),
            if (p.unassignedCount > 0)
              _privacyRow(
                Colors.grey,
                'No owner assigned',
                p.unassignedCount,
              ),
          ],
        ),
      ),
    );
  }

  Widget _privacyRow(Color color, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMembers() {
    final members = _dashboard!.memberSummaries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Members',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No household members yet'),
              subtitle: Text(
                'Add members to track who owns what.',
              ),
            ),
          )
        else
          ...members.map(
            (m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    m.member.name.isNotEmpty
                        ? m.member.name[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(m.member.name),
                subtitle: Text(
                  '${m.sharedCount} shared · ${m.privateCount} private',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${m.itemCount} items',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatMoney(m.totalValueCents, 'USD'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocations() {
    final locations = _dashboard!.locationSummaries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Locations',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (locations.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No locations yet'),
            ),
          )
        else
          ...locations.map(
            (l) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(l.location.name),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${l.itemCount} items',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatMoney(l.totalValueCents, 'USD'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
