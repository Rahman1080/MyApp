import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/refund_repository.dart';
import '../../../core/database/repositories/return_deadline_repository.dart';
import '../../../core/database/repositories/service_record_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../shared/services/return_deadline_service.dart';
import '../../../shared/services/warranty_service.dart';

/// Severity of an attention item, driving its color.
enum AttentionSeverity { critical, warning, info }

/// One "needs your attention" row on the home screen.
class AttentionItem {
  AttentionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.severity,
    this.purchaseId,
    this.routePath,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AttentionSeverity severity;
  final String? purchaseId;
  final String? routePath;
}

/// A warranty with its computed expiry and the purchase it belongs to.
class ExpiringWarranty {
  ExpiringWarranty({
    required this.warranty,
    required this.expiry,
    required this.purchaseName,
  });

  final Warranty warranty;
  final DateTime expiry;
  final String purchaseName;
}

/// A return deadline with the purchase it belongs to.
class DatedReturn {
  DatedReturn({required this.deadline, required this.purchaseName});

  final ReturnDeadline deadline;
  final String purchaseName;
}

/// Aggregates everything the home dashboard shows.
///
/// Listens to the purchase, deadline and belongings streams so the dashboard
/// stays fresh when records change in other tabs; derived data (warranty expiry,
/// return windows, maintenance) is recomputed with pure-Dart services.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required PurchaseRepository purchaseRepository,
    required WarrantyRepository warrantyRepository,
    required ReturnDeadlineRepository returnDeadlineRepository,
    required DeadlineRepository deadlineRepository,
    BelongingRepository? belongingRepository,
    ServiceRecordRepository? serviceRecordRepository,
    RefundRepository? refundRepository,
  })  : _purchases = purchaseRepository,
        _warranties = warrantyRepository,
        _returnDeadlines = returnDeadlineRepository,
        _deadlines = deadlineRepository,
        _belongings = belongingRepository,
        _serviceRecords = serviceRecordRepository,
        _refunds = refundRepository;

  final PurchaseRepository _purchases;
  final WarrantyRepository _warranties;
  final ReturnDeadlineRepository _returnDeadlines;
  final DeadlineRepository _deadlines;
  final BelongingRepository? _belongings;
  final ServiceRecordRepository? _serviceRecords;
  final RefundRepository? _refunds;

  final List<StreamSubscription<Object?>> _subscriptions = [];

  bool loading = true;
  int totalPurchases = 0;
  int totalBelongings = 0;
  int incompleteBelongings = 0;
  List<Purchase> recentPurchases = [];
  Map<String, Purchase> purchasesById = {};
  Map<String, Belonging> belongingsById = {};

  int activeWarrantyCount = 0;
  List<ExpiringWarranty> expiringWarranties = [];

  List<DatedReturn> overdueReturns = [];
  List<DatedReturn> approachingReturns = [];

  List<Deadline> overdueDeadlines = [];
  List<Deadline> upcomingDeadlines = [];

  List<ServiceRecord> upcomingMaintenance = [];
  List<Refund> pendingRefunds = [];

  /// Flat list driving the "Needs attention" section, most urgent first.
  List<AttentionItem> get attentionItems {
    final items = <AttentionItem>[
      for (final r in overdueReturns)
        AttentionItem(
          icon: Icons.assignment_return_outlined,
          title: 'Return overdue: ${r.purchaseName}',
          subtitle:
              '${-returnDaysLeft(r.deadline.deadlineDate, DateTime.now())} days past the return date',
          severity: AttentionSeverity.critical,
          purchaseId: r.deadline.purchaseId,
          routePath: '/purchases/${r.deadline.purchaseId}',
        ),
      for (final d in overdueDeadlines)
        AttentionItem(
          icon: Icons.event_busy_outlined,
          title: d.title,
          subtitle: 'Was due ${_relativeDay(d.dueDate)}',
          severity: AttentionSeverity.critical,
          routePath: '/deadlines/${d.id}',
        ),
      for (final r in approachingReturns)
        AttentionItem(
          icon: Icons.assignment_return_outlined,
          title: 'Return soon: ${r.purchaseName}',
          subtitle:
              '${returnDaysLeft(r.deadline.deadlineDate, DateTime.now())} days left to return',
          severity: AttentionSeverity.warning,
          purchaseId: r.deadline.purchaseId,
          routePath: '/purchases/${r.deadline.purchaseId}',
        ),
      for (final w in expiringWarranties)
        AttentionItem(
          icon: Icons.verified_outlined,
          title: 'Warranty expiring: ${w.purchaseName}',
          subtitle:
              '${warrantyDaysRemaining(w.expiry, DateTime.now())} days of coverage left',
          severity: AttentionSeverity.warning,
          purchaseId: w.warranty.purchaseId,
          routePath: '/purchases/${w.warranty.purchaseId}',
        ),
      for (final m in upcomingMaintenance)
        AttentionItem(
          icon: Icons.build_outlined,
          title: 'Maintenance due: ${m.serviceType}',
          subtitle: m.nextServiceDate != null
              ? 'Scheduled for ${DateFormat.yMMMd().format(m.nextServiceDate!)}'
              : 'Service due soon',
          severity: AttentionSeverity.warning,
          routePath: '/stuff/${m.belongingId}',
        ),
      for (final ref in pendingRefunds)
        AttentionItem(
          icon: Icons.currency_exchange_outlined,
          title: 'Pending refund: ${purchasesById[ref.purchaseId]?.productName ?? "Purchase"}',
          subtitle: ref.amountCents != null
              ? '\$${(ref.amountCents! / 100).toStringAsFixed(2)} waiting for refund'
              : 'Status: ${ref.status}',
          severity: AttentionSeverity.warning,
          purchaseId: ref.purchaseId,
          routePath: '/purchases/${ref.purchaseId}',
        ),
      if (incompleteBelongings > 0)
        AttentionItem(
          icon: Icons.help_outline,
          title: '$incompleteBelongings item(s) without location',
          subtitle: 'Tap to organize your belongings',
          severity: AttentionSeverity.info,
          routePath: '/organize',
        ),
    ];
    return items;
  }

  int get attentionCount => attentionItems.length;

  int get dueThisWeekCount =>
      approachingReturns.length +
      upcomingDeadlines.length +
      upcomingMaintenance.length;

  Future<void> init() async {
    await _refresh();
    loading = false;
    notifyListeners();
    _subscriptions.addAll([
      _purchases.watchAll().skip(1).listen((_) => _refresh()),
      _deadlines.watchUpcoming().skip(1).listen((_) => _refresh()),
      _warranties.watchAll().skip(1).listen((_) => _refresh()),
      _returnDeadlines.watchAll().skip(1).listen((_) => _refresh()),
      if (_belongings != null)
        _belongings.watchAll().skip(1).listen((_) => _refresh()),
    ]);
  }

  bool _refreshing = false;
  bool _dirty = false;

  Future<void> _refresh() async {
    if (_refreshing) {
      _dirty = true;
      return;
    }
    _refreshing = true;
    do {
      _dirty = false;
      await _loadSnapshot(DateTime.now());
    } while (_dirty);
    _refreshing = false;
    notifyListeners();
  }

  Future<void> _loadSnapshot(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);

    final purchases = await _purchases.getAll();
    totalPurchases = purchases.length;
    recentPurchases = purchases.take(5).toList();
    purchasesById = {for (final p in purchases) p.id: p};

    if (_belongings != null) {
      final belongings = await _belongings.getAll();
      totalBelongings = belongings.length;
      incompleteBelongings = belongings.where((b) => b.locationId == null).length;
      belongingsById = {for (final b in belongings) b.id: b};
    }

    if (_serviceRecords != null) {
      upcomingMaintenance = await _serviceRecords.upcoming(asOf: now);
    }

    if (_refunds != null) {
      final allRefunds = await _refunds.getAll();
      pendingRefunds = allRefunds
          .where((r) => r.status == 'requested' || r.status == 'pending')
          .toList();
    }

    final warranties = await _warranties.getAll();
    activeWarrantyCount = 0;
    expiringWarranties = [];
    for (final w in warranties) {
      final expiry = warrantyExpiryDate(
        startDate: w.startDate,
        durationMonths: w.durationMonths,
        expirationDate: w.expirationDate,
      );
      if (expiry == null) continue;
      final status = warrantyStatus(expiry: expiry, now: now);
      if (status == WarrantyStatus.expired) continue;
      activeWarrantyCount++;
      if (status == WarrantyStatus.expiringSoon) {
        expiringWarranties.add(ExpiringWarranty(
          warranty: w,
          expiry: expiry,
          purchaseName: purchasesById[w.purchaseId]?.productName ?? 'Purchase',
        ));
      }
    }
    expiringWarranties.sort((a, b) => a.expiry.compareTo(b.expiry));

    final returns = await _returnDeadlines.getAll();
    overdueReturns = [];
    approachingReturns = [];
    for (final r in returns) {
      final daysLeft = returnDaysLeft(r.deadlineDate, now);
      final dated = DatedReturn(
        deadline: r,
        purchaseName: purchasesById[r.purchaseId]?.productName ?? 'Purchase',
      );
      if (daysLeft < 0) {
        overdueReturns.add(dated);
      } else if (daysLeft <= 7) {
        approachingReturns.add(dated);
      }
    }

    final openDeadlines = await _deadlines.getUpcoming();
    overdueDeadlines = [];
    upcomingDeadlines = [];
    for (final d in openDeadlines) {
      final dueDay = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day);
      final diff = dueDay.difference(today).inDays;
      if (diff < 0) {
        overdueDeadlines.add(d);
      } else if (diff <= 7) {
        upcomingDeadlines.add(d);
      }
    }
  }

  static String _relativeDay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'yesterday';
    return '$diff days ago';
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
