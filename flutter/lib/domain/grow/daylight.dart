import 'dart:math' as math;

import 'day.dart';

/// Hours from sunrise to sunset at [latitude] degrees north on [day],
/// counting the sun as up while any of its disc shows (the usual 0.833°
/// for refraction and the disc's radius), as sunrise apps do.
double dayLength(double latitude, DateTime day) {
  final n = daysBetween(DateTime.utc(day.year), day) + 1;
  final declination = 23.44 * math.sin(2 * math.pi * (n - 81) / 365);
  double rad(double degrees) => degrees * math.pi / 180;
  final cosHour =
      (math.sin(rad(-0.833)) -
          math.sin(rad(latitude)) * math.sin(rad(declination))) /
      (math.cos(rad(latitude)) * math.cos(rad(declination)));
  if (cosHour <= -1) return 24;
  if (cosHour >= 1) return 0;
  return 2 * math.acos(cosHour) * 180 / math.pi / 15;
}

/// The short-day stretch around the winter solstice when days are under
/// [hours] long ("Persephone period" for 10 hours): growth nearly stops.
/// [start] is the first short day in the fall of [year], [end] the last
/// one before days lengthen again. Null when days never get that short
/// at [latitude] (roughly south of 32°N for 10 hours).
DayWindow? shortDays(double latitude, int year, {double hours = 10}) {
  // South of the equator (negative latitude) winter is around June.
  final solstice = DateTime.utc(year, latitude < 0 ? 6 : 12, 21);
  if (dayLength(latitude, solstice) >= hours) return null;
  var start = solstice;
  while (dayLength(latitude, addDays(start, -1)) < hours) {
    start = addDays(start, -1);
  }
  var end = solstice;
  while (dayLength(latitude, addDays(end, 1)) < hours) {
    end = addDays(end, 1);
  }
  return DayWindow(start, end);
}
