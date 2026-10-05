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

/// What a winter window is for, from Johnny's Winter Growing Guide.
enum WinterUse {
  /// Sown late summer or fall, harvested through winter.
  winterHarvest('Winter harvest'),

  /// Sown in fall and left in place for the earliest spring harvest.
  overwinter('Overwinter');

  const WinterUse(this.label);

  final String label;
}

/// Protection a planting window depends on.
enum Structure {
  highTunnel('high tunnel'),
  lowTunnel('low tunnel');

  const Structure(this.label);

  final String label;
}

/// A sowing window from Johnny's winter charts, timed in weeks before the
/// last day with 10 hours of daylight (when growth all but stops), so its
/// dates depend on the farm's latitude.
class WinterWindow {
  const WinterWindow({
    required this.use,
    required this.structure,
    required this.transplant,
    required this.weeksBefore,
    this.tier,
    this.detail,
  });

  final WinterUse use;

  /// The protection Johnny's chart assumes.
  final Structure structure;

  /// Started as transplants, rather than sown in place.
  final bool transplant;

  /// Weeks before the last 10-hour day to sow.
  final IntRange weeksBefore;

  /// Johnny's reliability tier: 1 most reliable, 3 most challenging.
  final int? tier;

  /// What the chart row is about, e.g. "baby leaf" or "tatsoi".
  final String? detail;

  String? get tierLabel => switch (tier) {
    1 => 'most reliable',
    2 => 'dependable',
    3 => 'challenging',
    _ => null,
  };
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
    List<WinterWindow> winterWindows = const [],
  }) : sections = List.unmodifiable(sections),
       estimated = Set.unmodifiable(estimated),
       winterWindows = List.unmodifiable(winterWindows);

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

  /// Alternate winter sowings from Johnny's winter charts; empty for crops
  /// the charts do not cover.
  final List<WinterWindow> winterWindows;
}

/// One benefit column ticked for a cover crop in Johnny's comparison
/// chart, e.g. "Nitrogen fixation".
class CoverBenefit {
  const CoverBenefit(this.name, {this.secondYear = false});

  final String name;

  /// Only from the second year (biennials).
  final bool secondYear;
}

/// A cover crop as Johnny's Cover Crop Comparison Chart describes it.
///
/// Johnny's gives no frost-relative window, plant spacing or days to
/// maturity for cover crops, so they are kept in the Seed Vault only and
/// never planned on the calendars. Values are the chart's own text.
class CoverCrop {
  CoverCrop({
    required this.id,
    required this.name,
    required this.sowingSeason,
    required this.minGermTempF,
    required this.hardinessZone,
    required this.growthRate,
    required this.seedPer1000SqFt,
    required this.seedPerAcre,
    required this.sowingDepth,
    this.frostSeeding = false,
    this.url,
    List<CoverBenefit> benefits = const [],
    List<CropSection> sections = const [],
  }) : benefits = List.unmodifiable(benefits),
       sections = List.unmodifiable(sections);

  /// The Seed Vault category every cover crop is listed under.
  static const category = 'Cover crops';

  final String id;
  final String name;

  /// e.g. "Early Spring to Late Summer".
  final String sowingSeason;
  final int minGermTempF;

  /// A USDA zone ("4"), "Various" for mixes, or "not frost tolerant".
  final String hardinessZone;
  final String growthRate;
  final String seedPer1000SqFt;
  final String seedPerAcre;
  final String sowingDepth;

  /// Can be frost seeded (broadcast onto frozen ground in late winter).
  final bool frostSeeding;

  /// Johnny's growing notes page, when it has one.
  final String? url;
  final List<CoverBenefit> benefits;
  final List<CropSection> sections;

  /// [seedPer1000SqFt] as numbers, or null when the chart text cannot be
  /// read ("⅓–½ Lb.", "1½ Lb.", "1,500 seeds").
  SeedRate? get seedRate => SeedRate.parse(seedPer1000SqFt);
}

/// A sowing rate per 1,000 sq ft: pounds of seed, or a seed count.
class SeedRate {
  const SeedRate(this.min, this.max, {required this.seeds});

  final double min;
  final double max;

  /// Counted in seeds rather than pounds.
  final bool seeds;

  static const _fractions = {
    '½': 0.5,
    '⅓': 1 / 3,
    '⅔': 2 / 3,
    '¼': 0.25,
    '¾': 0.75,
    '⅛': 0.125,
  };

  static SeedRate? parse(String text) {
    final t = text.replaceAll(',', '').trim().toLowerCase();
    final seeds = t.endsWith('seeds');
    if (!seeds && !t.endsWith('lb.') && !t.endsWith('lb')) return null;
    final numbers = t
        .replaceAll(RegExp(r'\s*(lb\.?|seeds)$'), '')
        .split(RegExp(r'\s*[–-]\s*'));
    final values = [for (final n in numbers) _number(n)];
    if (values.isEmpty || values.length > 2 || values.contains(null)) {
      return null;
    }
    final lo = values.first!, hi = values.last!;
    return lo <= hi ? SeedRate(lo, hi, seeds: seeds) : null;
  }

  /// "1½", "⅓", "2" or "1500".
  static double? _number(String text) {
    final m = RegExp(r'^(\d*)([½⅓⅔¼¾⅛]?)$').firstMatch(text.trim());
    if (m == null || (m[1]!.isEmpty && m[2]!.isEmpty)) return null;
    return (m[1]!.isEmpty ? 0 : int.parse(m[1]!)) + (_fractions[m[2]] ?? 0);
  }

  /// How much seed [squareMetres] of ground needs, e.g. "≈ 0.6–0.9 lb",
  /// "≈ 3–5 oz" under a quarter pound, or "≈ 120 seeds".
  String amountFor(double squareMetres) {
    final thousands = squareMetres * 10.7639 / 1000;
    final lo = min * thousands, hi = max * thousands;
    String range(double a, double b, String unit, int digits) {
      String f(double v) => v.toStringAsFixed(digits);
      return f(a) == f(b) ? '≈ ${f(a)} $unit' : '≈ ${f(a)}–${f(b)} $unit';
    }

    if (seeds) return range(lo, hi, 'seeds', 0);
    if (hi < 0.25) return range(lo * 16, hi * 16, 'oz', 1);
    return range(lo, hi, 'lb', hi < 10 ? 1 : 0);
  }
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
    Iterable<CoverCrop> coverCrops = const [],
    Iterable<CatalogVariety> varieties = const [],
    this.source = '',
    this.fetched = '',
  }) : crops = List.unmodifiable(
         [...crops]..sort((a, b) => a.name.compareTo(b.name)),
       ),
       coverCrops = List.unmodifiable(
         [...coverCrops]..sort((a, b) => a.name.compareTo(b.name)),
       ),
       varieties = List.unmodifiable(
         [...varieties]..sort((a, b) {
           final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
           return name != 0 ? name : a.cropId.compareTo(b.cropId);
         }),
       ),
       _byId = {for (final c in crops) c.id: c},
       _coverById = {for (final c in coverCrops) c.id: c},
       _productUrls = {
         for (final v in varieties)
           if (v.url != null) _productKey(v.cropId, v.name): v.url!,
       };

  static final empty = CropCatalog(const []);

  /// Sorted by name.
  final List<Crop> crops;

  /// Seed Vault only: never planned on the calendars.
  final List<CoverCrop> coverCrops;

  /// Named varieties of crops and cover crops.
  final List<CatalogVariety> varieties;
  final String source;
  final String fetched;
  final Map<String, Crop> _byId;
  final Map<String, CoverCrop> _coverById;
  final Map<String, String> _productUrls;

  static String _productKey(String cropId, String name) =>
      '$cropId|${name.trim().toLowerCase()}';

  Crop? operator [](String id) => _byId[id];

  CoverCrop? coverCrop(String id) => _coverById[id];

  /// Whether [id] is a crop or a cover crop.
  bool knows(String id) => _byId.containsKey(id) || _coverById.containsKey(id);

  String? nameOf(String id) => _byId[id]?.name ?? _coverById[id]?.name;

  String? categoryOf(String id) =>
      _byId[id]?.category ??
      (_coverById.containsKey(id) ? CoverCrop.category : null);

  /// The source's product page for the variety of [cropId] called [name],
  /// to reorder it, or null when the catalog does not list it.
  String? productUrlOf(String cropId, String name) =>
      _productUrls[_productKey(cropId, name)];

  /// Categories in first-seen order of the sorted list, then cover crops.
  List<String> get categories => [
    ...{for (final c in crops) c.category},
    if (coverCrops.isNotEmpty) CoverCrop.category,
  ];
}
