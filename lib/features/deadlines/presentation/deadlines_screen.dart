import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
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

/// The real Deadlines tab: Overdue / Upcoming / Later / Done segments over
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_Segment>(
              segments: [
                for (final segment in _Segment.values)
                  ButtonSegment(
                    value: segment,
                    label: Text(_segmentLabel(segment)),
                  ),
              ],
              selected: {_segment},
              onSelectionChanged: (selection) =>
                  setState(() => _segment = selection.first),
              showSelectedIcon: false,
            ),
          ),
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
                  return Center(
                    child: Text(
                      'No ${_segmentLabel(_segment).toLowerCase()} deadlines.',
                    ),
                  );
                }
                return FutureBuilder<Map<String, Purchase>>(
                  future: _purchaseMap(),
                  builder: (context, purchaseSnapshot) {
                    final purchases =
                        purchaseSnapshot.data ?? const <String, Purchase>{};
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: deadlines.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
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

    return Card(
      child: ListTile(
        leading: Icon(
          deadline.isDone
              ? Icons.check_circle
              : isOverdue
                  ? Icons.warning_amber
                  : Icons.event_outlined,
          color: deadline.isDone
              ? theme.colorScheme.primary
              : isOverdue
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          deadline.title,
          style: deadline.isDone
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(subtitle.toString()),
        trailing: isOverdue
            ? Text(
                '${-daysLeft}d overdue',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
        onTap: () => context.push('/deadlines/${deadline.id}'),
      ),
    );
  }
}
