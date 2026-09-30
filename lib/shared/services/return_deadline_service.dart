/// Return-window math. Pure Dart; callers pass `now` explicitly.
enum ReturnWindowStatus {
  /// The deadline is comfortably in the future.
  available,

  /// The deadline is within [approachingThresholdDays] days (default 7).
  approaching,

  /// The deadline has passed.
  expired,
}

/// Whole days from [now] until [deadline], date-granularity.
/// Positive = days left, 0 = last day, negative = overdue by that many days.
int returnDaysLeft(DateTime deadline, DateTime now) {
  final deadlineDay =
      DateTime(deadline.year, deadline.month, deadline.day);
  final nowDay = DateTime(now.year, now.month, now.day);
  return deadlineDay.difference(nowDay).inDays;
}

bool isReturnOverdue(DateTime deadline, DateTime now) =>
    returnDaysLeft(deadline, now) < 0;

ReturnWindowStatus returnWindowStatus({
  required DateTime deadline,
  required DateTime now,
  int approachingThresholdDays = 7,
}) {
  final left = returnDaysLeft(deadline, now);
  if (left < 0) return ReturnWindowStatus.expired;
  if (left <= approachingThresholdDays) return ReturnWindowStatus.approaching;
  return ReturnWindowStatus.available;
}

/// Derives a return deadline from a purchase date and a return window.
/// Returns null when there is no purchase date or no window.
DateTime? returnDeadlineFromWindow({
  required DateTime? purchaseDate,
  required int? returnPeriodDays,
}) {
  if (purchaseDate == null) return null;
  if (returnPeriodDays == null || returnPeriodDays <= 0) return null;
  return purchaseDate.add(Duration(days: returnPeriodDays));
}
