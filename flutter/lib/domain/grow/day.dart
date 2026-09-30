/// Calendar days for the growing tools.
///
/// Planting maths counts whole days, so every date here is midnight UTC.
/// That keeps "days between" exact across daylight-saving changes.
library;

/// [value]'s calendar day as midnight UTC.
DateTime dayOf(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// [day] moved by [days] (negative goes back).
DateTime addDays(DateTime day, int days) =>
    DateTime.utc(day.year, day.month, day.day + days);

/// Whole days from [from] to [to]; negative when [to] is earlier.
int daysBetween(DateTime from, DateTime to) =>
    dayOf(to).difference(dayOf(from)).inDays;

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short month name, 1 = "Jan".
String monthName(int month) => _monthNames[month - 1];

/// A short date such as "Oct 3".
String formatDay(DateTime day) => '${monthName(day.month)} ${day.day}';

/// A day of the year without the year, such as an average frost date.
class MonthDay implements Comparable<MonthDay> {
  const MonthDay(this.month, this.day)
    : assert(month >= 1 && month <= 12),
      assert(day >= 1 && day <= 31);

  final int month;
  final int day;

  /// This day in [year]. 31 Feb and similar roll into the next month.
  DateTime inYear(int year) => DateTime.utc(year, month, day);

  /// "04-15", the form stored in files.
  String get code =>
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  static MonthDay? tryParse(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match[1]!), day = int.parse(match[2]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return MonthDay(month, day);
  }

  @override
  String toString() => '${monthName(month)} $day';

  @override
  int compareTo(MonthDay other) =>
      month != other.month ? month - other.month : day - other.day;

  @override
  bool operator ==(Object other) =>
      other is MonthDay && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);
}

/// A span of whole calendar days, both ends included.
class DayWindow {
  DayWindow(DateTime start, DateTime end)
    : start = dayOf(start),
      end = dayOf(end);

  final DateTime start;
  final DateTime end;

  bool get isEmpty => end.isBefore(start);

  bool contains(DateTime day) {
    final d = dayOf(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool overlaps(DayWindow other) =>
      !other.end.isBefore(start) && !other.start.isAfter(end);

  DayWindow shift(int startDays, int endDays) =>
      DayWindow(addDays(start, startDays), addDays(end, endDays));

  @override
  String toString() => start == end
      ? formatDay(start)
      : '${formatDay(start)} – ${formatDay(end)}';

  @override
  bool operator ==(Object other) =>
      other is DayWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
