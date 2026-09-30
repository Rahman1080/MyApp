/// Pure scheduling math for local notifications. No plugin calls here —
/// Phase 5 wires the resulting fire times into flutter_local_notifications.
class ReminderScheduler {
  /// Computes fire times for [offsets] before [dueDate].
  ///
  /// - [dueTime] is an optional 'HH:mm' 24h string applied to each fire time
  ///   (a daily "remind me at 9am" time). Invalid values are ignored.
  /// - Fire times that are not after [now] are skipped.
  /// - Result is sorted ascending with duplicates removed.
  static List<DateTime> computeFireTimes({
    required DateTime dueDate,
    String? dueTime,
    required List<Duration> offsets,
    required DateTime now,
  }) {
    final time = _parseDueTime(dueTime);
    final fires = <DateTime>{};

    for (final offset in offsets) {
      var fire = dueDate.subtract(offset);
      if (time != null) {
        fire = DateTime(fire.year, fire.month, fire.day, time.hour, time.minute);
      }
      if (fire.isAfter(now)) fires.add(fire);
    }

    final sorted = fires.toList()..sort();
    return sorted;
  }

  /// Next occurrence of a repeating deadline on/after [from], or null when
  /// [repeatRule] is 'none'/'custom'. Supports daily | weekly | monthly |
  /// yearly. Pure date math — the notification layer decides delivery.
  static DateTime? nextOccurrence({
    required DateTime dueDate,
    required String repeatRule,
    required DateTime from,
  }) {
    switch (repeatRule) {
      case 'daily':
        return _nextBy(dueDate, from, (d) => d.add(const Duration(days: 1)));
      case 'weekly':
        return _nextBy(dueDate, from, (d) => d.add(const Duration(days: 7)));
      case 'monthly':
        return _nextBy(dueDate, from, (d) => _addMonths(d, 1));
      case 'yearly':
        return _nextBy(dueDate, from, (d) => _addMonths(d, 12));
      case 'none':
      case 'custom':
        return null;
      default:
        return null;
    }
  }

  static DateTime _nextBy(
    DateTime due,
    DateTime from,
    DateTime Function(DateTime) step,
  ) {
    var candidate = due;
    var guard = 0;
    while (candidate.isBefore(from) && guard < 1200) {
      candidate = step(candidate);
      guard++;
    }
    return candidate;
  }

  static DateTime _addMonths(DateTime date, int months) {
    var year = date.year;
    var month = date.month + months;
    year += (month - 1) ~/ 12;
    month = (month - 1) % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day, date.hour, date.minute);
  }

  static ({int hour, int minute})? _parseDueTime(String? dueTime) {
    if (dueTime == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(dueTime.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }
}
