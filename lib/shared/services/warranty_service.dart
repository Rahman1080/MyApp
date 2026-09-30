/// Warranty expiry math. Pure Dart — no database, no clock access;
/// callers pass `now` explicitly so the logic is fully testable.
enum WarrantyStatus {
  /// Expiry is in the future and beyond the expiring-soon threshold.
  active,

  /// Expiry is within [expiringSoonThresholdDays] days (default 30).
  expiringSoon,

  /// Expiry has passed.
  expired,
}

/// A warranty duration, as commonly printed on receipts and warranty cards
/// ("90 days", "12 months", "2 years").
class WarrantyDuration {
  const WarrantyDuration({this.days = 0, this.months = 0, this.years = 0});

  const WarrantyDuration.days(int days) : this(days: days);
  const WarrantyDuration.months(int months) : this(months: months);
  const WarrantyDuration.years(int years) : this(years: years);

  final int days;
  final int months;
  final int years;

  bool get isZero => days == 0 && months == 0 && years == 0;

  @override
  String toString() {
    final parts = <String>[];
    if (years > 0) parts.add('$years year${years == 1 ? '' : 's'}');
    if (months > 0) parts.add('$months month${months == 1 ? '' : 's'}');
    if (days > 0) parts.add('$days day${days == 1 ? '' : 's'}');
    return parts.isEmpty ? 'no duration' : parts.join(', ');
  }
}

/// Adds a [WarrantyDuration] to [date], clamping month-end overflow
/// (Jan 31 + 1 month -> Feb 28/29).
DateTime addWarrantyDuration(DateTime date, WarrantyDuration duration) {
  var year = date.year + duration.years;
  var month = date.month + duration.months;
  year += (month - 1) ~/ 12;
  month = (month - 1) % 12 + 1;

  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDayOfMonth ? lastDayOfMonth : date.day;

  // Calendar-day arithmetic via the DateTime constructor (which normalizes
  // out-of-range days in calendar terms). Never use .add(Duration(days: n))
  // here: absolute-duration addition shifts the wall-clock hour across DST
  // transitions in local timezones.
  return DateTime(
    year,
    month,
    day + duration.days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

/// Resolves the effective expiry date for a warranty row:
/// explicit [expirationDate] wins, otherwise [startDate] + [durationMonths].
/// Returns null when there is not enough information.
DateTime? warrantyExpiryDate({
  DateTime? startDate,
  int? durationMonths,
  DateTime? expirationDate,
}) {
  if (expirationDate != null) return expirationDate;
  if (startDate != null && durationMonths != null && durationMonths > 0) {
    return addWarrantyDuration(
      startDate,
      WarrantyDuration.months(durationMonths),
    );
  }
  return null;
}

/// Whole days from [now] until [expiry], date-granularity.
/// Positive = remaining, 0 = expires today, negative = expired.
int warrantyDaysRemaining(DateTime expiry, DateTime now) {
  final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
  final nowDay = DateTime(now.year, now.month, now.day);
  return expiryDay.difference(nowDay).inDays;
}

WarrantyStatus warrantyStatus({
  required DateTime expiry,
  required DateTime now,
  int expiringSoonThresholdDays = 30,
}) {
  final remaining = warrantyDaysRemaining(expiry, now);
  if (remaining < 0) return WarrantyStatus.expired;
  if (remaining <= expiringSoonThresholdDays) return WarrantyStatus.expiringSoon;
  return WarrantyStatus.active;
}
