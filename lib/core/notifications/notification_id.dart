/// Derives a stable OS notification id from a reminder UUID.
///
/// Dart's [String.hashCode] is not stable across runs, so the first 8 hex
/// digits of the UUID are parsed instead: stable forever, and collisions are
/// astronomically unlikely at this scale (and harmless — the same id would
/// simply replace an equivalent notification).
int notificationIdFor(String reminderId) {
  final hex = reminderId.replaceAll('-', '');
  final head = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
  return int.parse(head, radix: 16);
}
