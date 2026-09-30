import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/grow/climate.dart';
import 'package:garden_gnome/domain/grow/crop.dart';
import 'package:garden_gnome/domain/reference_image.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/crop_catalog_codec.dart';

/// Models are snapshots: history, dirty tracking and caches all rely on
/// a value never changing once it exists. Lists handed in are copied and
/// nothing exposed can be written to.
void main() {
  test('a shape keeps its own copy of its rings', () {
    final segments = [const SegmentRef('line-1')];
    final hole = [const SegmentRef('line-2')];
    final shape = ClosedShape('shape-1', segments, holes: [hole]);
    segments.clear();
    hole.clear();
    expect(shape.segments, hasLength(1));
    expect(shape.holes.single, hasLength(1));
    expect(() => shape.segments.clear(), throwsUnsupportedError);
    expect(() => shape.holes.single.clear(), throwsUnsupportedError);
  });

  test('a geometry\'s stack and closed IDs cannot be written to', () {
    final geometry = Geometry(id: 'g', ownerLayerId: 'l');
    expect(() => geometry.stack.add('shape-9'), throwsUnsupportedError);
    expect(() => geometry.closedIds.add('shape-9'), throwsUnsupportedError);
  });

  test('a polygon region keeps its own corners', () {
    final corners = [const Vec(0, 0), const Vec(2, 0), const Vec(0, 2)];
    final region = PolygonRegion(corners);
    corners.clear();
    expect(region.area, 2);
    expect(() => region.corners.clear(), throwsUnsupportedError);
  });

  test('a reference image keeps its own picture, shared by its copies', () {
    final bytes = Uint8List.fromList([137, 80, 78, 71]);
    final image = ReferenceImage(
      id: 'image-1',
      bytes: bytes,
      mimeType: 'image/png',
      pixelWidth: 10,
      pixelHeight: 10,
      topLeft: Vec.zero,
      metresPerPixel: 1,
    );
    bytes[0] = 0;
    expect(image.bytes[0], 137);
    expect(() => image.bytes[0] = 1, throwsUnsupportedError);
    final moved = image.movedBy(const Vec(1, 1)).withLabel('Plan');
    expect(identical(moved.bytes, image.bytes), isTrue);
    expect(moved.label, 'Plan');
    expect(moved.withLabel('  ').label, isNull);
  });

  test('a crop copies caller-owned sections and estimates', () {
    const section = CropSection('CULTURE', 'Sow early.');
    final sections = [section];
    final estimated = {'harvestWindowDays'};
    final crop = Crop(
      id: 'lettuce',
      name: 'Lettuce',
      category: 'Vegetables',
      season: Season.cool,
      frostTolerance: FrostTolerance.hardy,
      sowing: SowingMethod.either,
      daysToMaturity: const IntRange(45, 55),
      plantOutWeeks: const IntRange(-4, 2),
      inRowSpacingIn: const LengthRange(8, 12),
      betweenRowSpacingIn: const LengthRange(12, 18),
      harvestWindowDays: const IntRange(7, 14),
      sections: sections,
      estimated: estimated,
    );
    sections.clear();
    estimated.clear();
    expect(crop.sections, [section]);
    expect(crop.estimated, {'harvestWindowDays'});
    expect(() => crop.sections.clear(), throwsUnsupportedError);
    expect(() => crop.sections[0] = section, throwsUnsupportedError);
    expect(() => crop.estimated.add('plantOutWeeks'), throwsUnsupportedError);
    expect(
      () => crop.estimated.remove('harvestWindowDays'),
      throwsUnsupportedError,
    );
  });

  test('the hardiness zone list and a decoded crop cannot be written to', () {
    expect(() => HardinessZone.all.clear(), throwsUnsupportedError);
    final catalog = decodeCropCatalog('''
      {"crops": [{
        "id": "lettuce", "name": "Lettuce", "season": "cool",
        "frostTolerance": "hardy", "sowing": "either",
        "daysToMaturity": [45, 55], "plantOutWeeks": [-4, 2],
        "inRowSpacingIn": [8, 12], "betweenRowSpacingIn": [12, 18],
        "sections": [{"title": "CULTURE", "text": "Sow early."}],
        "estimated": ["harvestWindowDays"]
      }]}
    ''');
    final crop = catalog['lettuce']!;
    expect(crop.sowing, SowingMethod.either);
    expect(() => crop.sections.clear(), throwsUnsupportedError);
    expect(() => crop.estimated.clear(), throwsUnsupportedError);
  });
}
