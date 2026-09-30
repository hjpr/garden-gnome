import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/persistence/int_range_codec.dart';
import 'package:garden_gnome/persistence/length_range_codec.dart';

void main() {
  test('length ranges retain fractions, equality and display', () {
    const range = LengthRange(0.5, 1.25);
    expect(range.toString(), '0.5–1.25');
    expect(range, const LengthRange(0.5, 1.25));
    expect(range.hashCode, const LengthRange(0.5, 1.25).hashCode);
    expect(range, isNot(const LengthRange(0.5, 1.5)));
    expect(const LengthRange.single(0.75).toString(), '0.75');
  });

  test('catalog lengths accept singles and reversed fractional pairs', () {
    expect(decodeLengthRange(0.75), const LengthRange.single(0.75));
    expect(decodeLengthRange([2.5, 0.75]), const LengthRange(0.75, 2.5));
    expect(decodeLengthRange([2, 6]), const LengthRange(2, 6));
    for (final raw in [
      null,
      '1–2',
      [],
      [1],
      [1, '2'],
      double.nan,
      [0.5, double.infinity],
    ]) {
      expect(decodeLengthRange(raw), isNull, reason: '$raw');
    }
  });

  test('saved length pairs preserve old integers, fractions and absence', () {
    for (final range in [
      null,
      const LengthRange(2, 6),
      const LengthRange(0.75, 2.25),
    ]) {
      expect(strictLengthRange(encodeLengthRange(range)), range);
    }
    expect(encodeLengthRange(const LengthRange(2, 6)), [2, 6]);
    expect(encodeLengthRange(const LengthRange(0.75, 2.25)), [0.75, 2.25]);
  });

  test(
    'saved lengths still refuse malformed, reversed and nonfinite pairs',
    () {
      for (final raw in [
        0.75,
        '1–2',
        [],
        [1],
        [1, 2, 3],
        [1, '2'],
        [2.5, 0.75],
        [double.nan, 2],
        [1, double.infinity],
      ]) {
        expect(
          () => strictLengthRange(raw),
          throwsFormatException,
          reason: '$raw',
        );
      }
    },
  );

  test('day and week codecs remain whole-number ranges', () {
    expect(decodeRange([1.5, 2.5]), const IntRange(2, 3));
    expect(strictRange([3, 4]), const IntRange(3, 4));
    expect(() => strictRange([1.5, 2]), throwsFormatException);
    expect(encodeRange(const IntRange(3, 4)), [3, 4]);
  });
}
