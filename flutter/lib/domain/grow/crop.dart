/// Crops as described by the bundled catalog (Johnny's Selected Seeds
/// Key Growing Information). A crop holds the defaults every variety of
/// it starts from; see variety.dart for what a gardener records.
library;

/// A whole-number range such as "5–7 days". [min] ≤ [max].
class IntRange {
  const IntRange(this.min, this.max) : assert(min <= max);

  const IntRange.single(int value) : this(value, value);

  final int min;
  final int max;

  /// The middle, rounded, for sums that need one number.
  int get mid => ((min + max) / 2).round();

  @override
  String toString() => min == max ? '$min' : '$min–$max';

  @override
  bool operator ==(Object other) =>
      other is IntRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// A length range in inches, retaining fractional catalog recommendations.
class LengthRange {
  const LengthRange(this.min, this.max) : assert(min <= max);

  const LengthRange.single(num value) : this(value, value);

  final num min;
  final num max;

  @override
  String toString() => min == max ? '$min' : '$min–$max';

  @override
  bool operator ==(Object other) =>
      other is LengthRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Whether a crop likes cool or warm weather.
enum Season {
  cool('Cool season'),
  warm('Warm season');

  const Season(this.label);

  final String label;
}

/// How much frost a crop takes. Drives how close to frost it may be
/// planted out in spring and still mature in fall.
enum FrostTolerance {
  tender('Frost tender'),
  halfHardy('Half-hardy'),
  hardy('Frost hardy');

  const FrostTolerance(this.label);

  final String label;

  /// Days before the first fall frost a crop must mature by. Hardy crops
  /// keep going through light frosts, so they may mature after it.
  int get fallMarginDays => switch (this) {
    tender => 14,
    halfHardy => 0,
    hardy => -14,
  };
}

/// How a crop is established.
enum SowingMethod {
  /// Started in the greenhouse and transplanted.
  transplant('Transplant'),

  /// Sown where it grows.
  direct('Direct sow'),

  /// Either way works.
  either('Either');

  const SowingMethod(this.label);

  final String label;

  bool get canDirectSow => this != transplant;
  bool get canTransplant => this != direct;
}

/// What days to maturity are counted from.
enum MaturityFrom {
  transplant('From transplant'),
  seeding('From seeding');

  const MaturityFrom(this.label);

  final String label;
}

/// One labelled part of the growing instructions, e.g. "CULTURE".
class CropSection {
  const CropSection(this.title, this.text);

  final String title;
  final String text;
}

/// A crop's defaults from the catalog.
class Crop {
  Crop({
    required this.id,
    required this.name,
    required this.category,
    required this.season,
    required this.frostTolerance,
    required this.sowing,
    required this.daysToMaturity,
    required this.plantOutWeeks,
    required this.inRowSpacingIn,
    required this.betweenRowSpacingIn,
    required this.harvestWindowDays,
    this.url,
    this.scientificName,
    this.germinationDays,
    this.weeksToTransplant,
    this.maturityFrom,
    this.fallCrop = false,
    this.overwinterWeeks,
    this.successionDays,
    this.sowingDepthIn,
    this.soilTempF,
    List<CropSection> sections = const [],
    Set<String> estimated = const {},
  }) : sections = List.unmodifiable(sections),
       estimated = Set.unmodifiable(estimated);

  final String id;
  final String name;

  /// "Vegetables" or "Herbs".
  final String category;
  final String? url;
  final String? scientificName;
  final Season season;
  final FrostTolerance frostTolerance;
  final SowingMethod sowing;
  final IntRange? germinationDays;

  /// Weeks from sowing in the greenhouse to planting out.
  final IntRange? weeksToTransplant;
  final IntRange daysToMaturity;
  final MaturityFrom? maturityFrom;

  /// The spring planting-out window in weeks from the average last spring
  /// frost; negative is before it.
  final IntRange plantOutWeeks;

  /// Whether a late-summer sowing for a fall harvest is usual.
  final bool fallCrop;

  /// For crops planted in fall to overwinter in the ground, such as
  /// garlic: the best planting weeks from the first fall frost.
  final IntRange? overwinterWeeks;

  /// Days between succession sowings, if the crop is sown in succession.
  final int? successionDays;
  final LengthRange inRowSpacingIn;
  final LengthRange betweenRowSpacingIn;

  /// How many days one planting keeps yielding once it first matures.
  final IntRange harvestWindowDays;
  final double? sowingDepthIn;
  final IntRange? soilTempF;

  /// Growing instructions, in page order.
  final List<CropSection> sections;

  /// Names of values filled in by judgement rather than read from the
  /// source, so the screen can mark them as estimates.
  final Set<String> estimated;
}

/// A named variety available in the source catalog, not yet in the vault.
class CatalogVariety {
  const CatalogVariety({
    required this.id,
    required this.cropId,
    required this.name,
    this.url,
  });

  final String id;
  final String cropId;
  final String name;
  final String? url;
}

/// Every crop the app knows about, looked up by ID.
class CropCatalog {
  CropCatalog(
    Iterable<Crop> crops, {
    Iterable<CatalogVariety> varieties = const [],
    this.source = '',
    this.fetched = '',
  }) : crops = List.unmodifiable(
         [...crops]..sort((a, b) => a.name.compareTo(b.name)),
       ),
       varieties = List.unmodifiable(
         [...varieties]..sort((a, b) {
           final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
           return name != 0 ? name : a.cropId.compareTo(b.cropId);
         }),
       ),
       _byId = {for (final c in crops) c.id: c};

  static final empty = CropCatalog(const []);

  /// Sorted by name.
  final List<Crop> crops;
  final List<CatalogVariety> varieties;
  final String source;
  final String fetched;
  final Map<String, Crop> _byId;

  Crop? operator [](String id) => _byId[id];

  /// Categories in first-seen order of the sorted list.
  List<String> get categories => {for (final c in crops) c.category}.toList();
}
