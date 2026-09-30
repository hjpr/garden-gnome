import 'package:flutter/services.dart';

import '../domain/grow/crop.dart';
import 'crop_catalog_codec.dart';

/// Loads crop defaults and named varieties bundled with the app.
Future<CropCatalog> loadBundledCatalog() async => decodeCropCatalog(
  await rootBundle.loadString('assets/catalog/crops.json'),
  varietiesText: await rootBundle.loadString('assets/catalog/varieties.json'),
);
