import 'package:garden_gnome/domain/grow/crop.dart';

/// Small hand-made crops for the growing-tool tests, so the tests do not
/// depend on the scraped catalog's numbers.
final testTomato = Crop(
  id: 'tomatoes',
  name: 'Tomatoes',
  category: 'Vegetables',
  season: Season.warm,
  frostTolerance: FrostTolerance.tender,
  sowing: SowingMethod.transplant,
  germinationDays: const IntRange(5, 7),
  weeksToTransplant: const IntRange(5, 6),
  daysToMaturity: const IntRange(70, 80),
  maturityFrom: MaturityFrom.transplant,
  plantOutWeeks: const IntRange(1, 4),
  inRowSpacingIn: const LengthRange(18, 24),
  betweenRowSpacingIn: const LengthRange(48, 60),
  harvestWindowDays: const IntRange(60, 90),
);

final testLettuce = Crop(
  id: 'lettuce',
  name: 'Lettuce',
  category: 'Vegetables',
  season: Season.cool,
  frostTolerance: FrostTolerance.halfHardy,
  sowing: SowingMethod.either,
  germinationDays: const IntRange(2, 7),
  weeksToTransplant: const IntRange(3, 4),
  daysToMaturity: const IntRange(45, 55),
  maturityFrom: MaturityFrom.seeding,
  plantOutWeeks: const IntRange(-4, 2),
  fallCrop: true,
  inRowSpacingIn: const LengthRange(8, 12),
  betweenRowSpacingIn: const LengthRange(12, 18),
  harvestWindowDays: const IntRange(7, 14),
);

final testBean = Crop(
  id: 'bush-bean',
  name: 'Bush Beans',
  category: 'Vegetables',
  season: Season.warm,
  frostTolerance: FrostTolerance.tender,
  sowing: SowingMethod.direct,
  daysToMaturity: const IntRange(50, 60),
  maturityFrom: MaturityFrom.seeding,
  plantOutWeeks: const IntRange(1, 8),
  inRowSpacingIn: const LengthRange(2, 4),
  betweenRowSpacingIn: const LengthRange(18, 30),
  harvestWindowDays: const IntRange(14, 21),
);

/// A cover crop: Seed Vault only, never on the calendars.
final testRye = CoverCrop(
  id: 'winter-rye',
  name: 'Winter Rye',
  sowingSeason: 'Anytime (Fall for Grain)',
  minGermTempF: 34,
  hardinessZone: '3',
  growthRate: 'Medium',
  seedPer1000SqFt: '2–3 Lb.',
  seedPerAcre: '60–150 Lb.',
  sowingDepth: '¾–1½"',
  benefits: const [CoverBenefit('Erosion control')],
);

const bigBeefUrl = 'https://www.johnnyseeds.com/big-beef-5.html';

final testCatalog = CropCatalog(
  [testTomato, testLettuce, testBean],
  coverCrops: [testRye],
  varieties: const [
    CatalogVariety(
      id: 'big-beef',
      cropId: 'tomatoes',
      name: 'Big Beef',
      url: bigBeefUrl,
    ),
    CatalogVariety(
      id: 'rye',
      cropId: 'winter-rye',
      name: 'Winter Rye (Common)',
      url: 'https://www.johnnyseeds.com/winter-rye-968G.html',
    ),
    CatalogVariety(id: 'sun-gold', cropId: 'tomatoes', name: 'Sun Gold'),
    CatalogVariety(id: 'little-gem', cropId: 'lettuce', name: 'Little Gem'),
    CatalogVariety(id: 'provider', cropId: 'bush-bean', name: 'Provider'),
  ],
);
