import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_card.dart';
import '../../../shared/widgets/keepit_chip.dart';
import 'deadline_form_screen.dart';

enum _Segment { overdue, upcoming, later, done }

String _segmentLabel(_Segment segment) {
  switch (segment) {
    case _Segment.overdue:
      return 'Overdue';
    case _Segment.upcoming:
      return 'Upcoming';
    case _Segment.later:
      return 'Later';
    case _Segment.done:
      return 'Done';
  }
}

/// The Deadlines tab: Overdue / Upcoming / Later / Done segments over
/// the user's deadlines.
class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({
    super.key,
    required this.deadlineRepository,
    required this.purchaseRepository,
  });

  static const String routePath = '/deadlines';

  final DeadlineRepository deadlineRepository;
  final PurchaseRepository purchaseRepository;

  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  _Segment _segment = _Segment.upcoming;

  _Segment _segmentOf(Deadline deadline, DateTime todayStart) {
    if (deadline.isDone) return _Segment.done;
    final dueStart = DateTime(
      deadline.dueDate.year,
      deadline.dueDate.month,
      deadline.dueDate.day,
    );
    if (dueStart.isBefore(todayStart)) return _Segment.overdue;
    if (dueStart.difference(todayStart).inDays <= 7) return _Segment.upcoming;
    return _Segment.later;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return Scaffold(
      appBar: AppBar(title: const Text('Deadlines')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _filterChips(),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<Deadline>>(
              stream:
                  widget.deadlineRepository.watchUpcoming(includeDone: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load deadlines.'),
                  );
                }
                final deadlines = (snapshot.data ?? const <Deadline>[])
                    .where((d) => _segmentOf(d, todayStart) == _segment)
                    .toList();
                if (deadlines.isEmpty) {
                  return EmptyState(
                    icon: Icons.event_available_outlined,
                    headline: 'No ${_segmentLabel(_segment).toLowerCase()} deadlines',
                    body: _segment == _Segment.upcoming
                        ? 'Deadlines due within the next 7 days will appear here.'
                        : _segment == _Segment.overdue
                            ? 'Great news! You have no overdue deadlines.'
                            : _segment == _Segment.done
                                ? 'Completed deadlines will be archived here.'
                                : 'Deadlines due more than a week away will appear here.',
                  );
                }
                return FutureBuilder<Map<String, Purchase>>(
                  future: _purchaseMap(),
                  builder: (context, purchaseSnapshot) {
                    final purchases =
                        purchaseSnapshot.data ?? const <String, Purchase>{};
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: deadlines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final deadline = deadlines[index];
                        return _DeadlineTile(
                          deadline: deadline,
                          todayStart: todayStart,
                          purchase: deadline.relatedPurchaseId == null
                              ? null
                              : purchases[deadline.relatedPurchaseId],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/deadlines/new'),
        icon: const Icon(Icons.add),
        label: const Text('Deadline'),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _Segment.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final segment = _Segment.values[index];
          final selected = _segment == segment;
          return KeepitFilterChip(
            label: _segmentLabel(segment),
            selected: selected,
            onSelected: (_) => setState(() => _segment = segment),
          );
        },
      ),
    );
  }

  Future<Map<String, Purchase>> _purchaseMap() async {
    final purchases = await widget.purchaseRepository.getAll();
    return {for (final p in purchases) p.id: p};
  }
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({
    required this.deadline,
    required this.todayStart,
    this.purchase,
  });

  final Deadline deadline;
  final DateTime todayStart;
  final Purchase? purchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueDate = deadline.dueDate;
    final dueStart = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final daysLeft = dueStart.difference(todayStart).inDays;
    final isOverdue = !deadline.isDone && daysLeft < 0;

    final subtitle = StringBuffer(
      DateFormat.yMMMd().format(dueDate),
    );
    if (deadline.dueTime != null) subtitle.write(' · ${deadline.dueTime}');
    if (purchase != null) subtitle.write(' · ${purchase!.productName}');
    if (deadline.repeatRule != 'none') {
      subtitle.write(' · ${repeatLabel(deadline.repeatRule)}');
    }

    final Color statusColor;
    final IconData statusIcon;
    final String statusBadgeText;
    final Color statusBadgeBg;

    if (deadline.isDone) {
      statusColor = AppColors.mintAccent;
      statusIcon = Icons.check_circle_rounded;
      statusBadgeText = 'Done';
      statusBadgeBg = AppColors.mintAccent.withAlpha(24);
    } else if (isOverdue) {
      statusColor = AppColors.urgent;
      statusIcon = Icons.warning_amber_rounded;
      statusBadgeText = '${-daysLeft}d overdue';
      statusBadgeBg = AppColors.urgent.withAlpha(24);
    } else if (daysLeft == 0) {
      statusColor = AppColors.warning;
      statusIcon = Icons.today_rounded;
      statusBadgeText = 'Due today';
      statusBadgeBg = AppColors.warning.withAlpha(24);
    } else if (daysLeft == 1) {
      statusColor = AppColors.warning;
      statusIcon = Icons.event_rounded;
      statusBadgeText = 'Due tomorrow';
      statusBadgeBg = AppColors.warning.withAlpha(24);
    } else if (daysLeft <= 7) {
      statusColor = AppColors.mintAccent;
      statusIcon = Icons.event_outlined;
      statusBadgeText = 'In ${daysLeft}d';
      statusBadgeBg = AppColors.mintAccent.withAlpha(24);
    } else {
      statusColor = theme.colorScheme.onSurfaceVariant;
      statusIcon = Icons.calendar_today_outlined;
      statusBadgeText = DateFormat.MMMd().format(dueDate);
      statusBadgeBg = theme.colorScheme.surfaceContainerHighest.withAlpha(80);
    }

    return KeepitCard(
      onTap: () => context.push('/deadlines/${deadline.id}'),
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
              statusIcon,
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
                  deadline.title,
                  style: deadline.isDone
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        )
                      : theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusBadgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusBadgeText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
