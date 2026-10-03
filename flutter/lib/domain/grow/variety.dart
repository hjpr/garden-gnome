import 'crop.dart';

/// A seed variety the gardener has on hand, recorded in the Seed Vault.
///
/// A variety belongs to one catalog crop and starts from that crop's
/// defaults. Any value typed here overrides the crop's; a null value
/// means "use the crop's". [resolve] gives the values to plan with.
class Variety {
  const Variety({
    required this.id,
    required this.cropId,
    required this.name,
    this.source,
    this.productCode,
    this.url,
    this.seedsOnHand,
    this.yearPacked,
    this.organic = false,
    this.notes = '',
    this.daysToMaturity,
    this.germinationDays,
    this.weeksToTransplant,
    this.sowing,
    this.inRowSpacingIn,
    this.betweenRowSpacingIn,
    this.harvestWindowDays,
  });

  final String id;
  final String cropId;

  /// The variety's own name, e.g. "Big Beef".
  final String name;

  /// Where the seed came from, e.g. "Johnny's".
  final String? source;
  final String? productCode;
  final String? url;

  /// How much seed is left, as the gardener counts it ("1 pkt", "500").
  final String? seedsOnHand;
  final int? yearPacked;
  final bool organic;
  final String notes;

  // Overrides of the crop's defaults.
  final IntRange? daysToMaturity;
  final IntRange? germinationDays;
  final IntRange? weeksToTransplant;
  final SowingMethod? sowing;
  final LengthRange? inRowSpacingIn;
  final LengthRange? betweenRowSpacingIn;
  final IntRange? harvestWindowDays;

  /// The values to plan with: this variety's where set, else [crop]'s.
  VarietyProfile resolve(Crop crop) => VarietyProfile(this, crop);

  Variety copyWith({
    String? id,
    String? cropId,
    String? name,
    String? Function()? source,
    String? Function()? productCode,
    String? Function()? url,
    String? Function()? seedsOnHand,
    int? Function()? yearPacked,
    bool? organic,
    String? notes,
    IntRange? Function()? daysToMaturity,
    IntRange? Function()? germinationDays,
    IntRange? Function()? weeksToTransplant,
    SowingMethod? Function()? sowing,
    LengthRange? Function()? inRowSpacingIn,
    LengthRange? Function()? betweenRowSpacingIn,
    IntRange? Function()? harvestWindowDays,
  }) => Variety(
    id: id ?? this.id,
    cropId: cropId ?? this.cropId,
    name: name ?? this.name,
    source: source == null ? this.source : source(),
    productCode: productCode == null ? this.productCode : productCode(),
    url: url == null ? this.url : url(),
    seedsOnHand: seedsOnHand == null ? this.seedsOnHand : seedsOnHand(),
    yearPacked: yearPacked == null ? this.yearPacked : yearPacked(),
    organic: organic ?? this.organic,
    notes: notes ?? this.notes,
    daysToMaturity: daysToMaturity == null
        ? this.daysToMaturity
        : daysToMaturity(),
    germinationDays: germinationDays == null
        ? this.germinationDays
        : germinationDays(),
    weeksToTransplant: weeksToTransplant == null
        ? this.weeksToTransplant
        : weeksToTransplant(),
    sowing: sowing == null ? this.sowing : sowing(),
    inRowSpacingIn: inRowSpacingIn == null
        ? this.inRowSpacingIn
        : inRowSpacingIn(),
    betweenRowSpacingIn: betweenRowSpacingIn == null
        ? this.betweenRowSpacingIn
        : betweenRowSpacingIn(),
    harvestWindowDays: harvestWindowDays == null
        ? this.harvestWindowDays
        : harvestWindowDays(),
  );
}

/// A variety's planning values, each taken from the variety where the
/// gardener set it and from its crop otherwise.
class VarietyProfile {
  VarietyProfile(this.variety, this.crop);

  final Variety variety;
  final Crop crop;

  String get id => variety.id;

  /// "Big Beef Tomatoes".
  String get displayName => '${variety.name} · ${crop.name}';

  SowingMethod get sowing => variety.sowing ?? crop.sowing;
  IntRange get daysToMaturity => variety.daysToMaturity ?? crop.daysToMaturity;
  IntRange? get germinationDays =>
      variety.germinationDays ?? crop.germinationDays;

  /// Weeks in the greenhouse before planting out. Crops the catalog lists
  /// as direct-sown but that the gardener chose to transplant get four.
  IntRange get weeksToTransplant =>
      variety.weeksToTransplant ??
      crop.weeksToTransplant ??
      const IntRange(3, 4);
  LengthRange get inRowSpacingIn =>
      variety.inRowSpacingIn ?? crop.inRowSpacingIn;
  LengthRange get betweenRowSpacingIn =>
      variety.betweenRowSpacingIn ?? crop.betweenRowSpacingIn;
  IntRange get harvestWindowDays =>
      variety.harvestWindowDays ?? crop.harvestWindowDays;

  /// Typical days from sowing in place to first harvest.
  ///
  /// When maturity is counted from transplant, sowing in place adds the
  /// time a transplant would have spent in the greenhouse, less the
  /// check a transplant suffers (about a third of it).
  int get daysFromDirectSowing {
    final dtm = daysToMaturity.mid;
    if (crop.maturityFrom != MaturityFrom.transplant) return dtm;
    return dtm + (weeksToTransplant.mid * 7 * 2 / 3).round();
  }

  /// Typical days from planting a transplant out to first harvest.
  int get daysFromTransplant {
    final dtm = daysToMaturity.mid;
    if (crop.maturityFrom == MaturityFrom.transplant) return dtm;
    // Counted from seeding: the greenhouse weeks are already behind it.
    final less = dtm - weeksToTransplant.mid * 7;
    return less < dtm ~/ 2 ? dtm ~/ 2 : less;
  }
}
