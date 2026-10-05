# Home and crop-art concepts

Open `index.html` directly in a browser. Round 1 is a preserved visual comparison study, not an application update. Its original artifacts are contained in this directory.

## Selected direction

Pocket Garden is the chosen Home direction. The illustration in `proofs/cover-crops.png` is the style reference for subsequent ground and botanical artwork: matte hand-painted foliage with clear shapes, not pixel art or sculpted clay.

The next texture round covers six independent large variants each for wild grass, lawn, dirt, prepared soil, loam and crimson clover. Variants share density, scale and palette, then use deterministic world-anchored selection, rotation and blending. The Home implementation remains a separate step; the other work screens retain their layouts.

See `textures/index.html` for the next round. The six-variant renderer is implemented and tested. After the user removed the provider spend cap, 69 additional images were generated for $4.65. Loam now has six fine-scale source candidates; dirt has six independent candidates needing blended cohesion review. Grass, prepared soil and clover remain incomplete. Experimental candidate atlases are isolated from runtime assets for actual-renderer review. No new runtime texture banks have been installed.

## Round 1

- Pocket Garden: hand-painted nostalgia and a small garden diorama. Recommended Home direction; fits the existing illustrated soil.
- Field Station: pixel-art indie simulation inside a quiet software frame. Strong silhouettes but a deliberate departure from the painted terrain.
- Garden Village: original matte-clay life-sim warmth. A bolder Home alternative. Corrected second proof removes duplicate navigation and generated cabinet lettering.

The three illustrations preserve Seed Vault, Plan and Grow as the real work destinations. Farm name, counts and greeting copy are examples. Model-rendered logos and lettering are not approved production artwork. The layouts are desktop concept pictures, not responsive implementations.

## Files

- `index.html`: comparison board, review notes and actual-CSS-size crop previews. No remote dependencies; can be opened from disk.
- `proofs/`: eight original generations, three labeled crop sheets and one soil comparison composite.
- `samples/{pocket,field,village}/`: twelve 256 × 256 RGBA exploratory cutouts per style. These are not runtime-ready sprites.
- `generation-manifest.json`: model, returned cost, dimensions, verdict and visible issues for each generation.
- `catalog-art-inventory.csv`: every crop and cover-crop ID in the current bundled catalogs, with sample coverage and production status. No source catalog was edited.
- `build_study.py`: reproducible local processing and asset validation. Requires Python and Pillow; run `python build_study.py` in an environment with Pillow. Font rendering uses DejaVu Sans.

The processing script regenerates derived artwork and the inventory, not the original generated images or manually authored HTML. If the source catalog changes, reconcile the board's displayed counts with the regenerated inventory.

## Generation record

Model: `google/gemini-3.1-flash-image` (Nano Banana 2), through OpenRouter. No provider or model configuration was changed. Eight generation calls including one image-to-image correction, total reported cost $0.540329. Landscape requests were 16:9; delivered images are 1376 × 768, so the returned dimensions are slightly different from exact 16:9. Square sheets are 1024 × 1024.

Review: 3 keep as direction, 4 rework for production, 1 discard. Keep means a useful concept reference, not a deployable image or an approved layout.

Prompts were grounded in the actual app palette, the three tool names and Home summary semantics. Shared exclusions: no game currency, energy, quests, streaks, sales banners, fake weather, character avatars or inaccessible illustrated-only controls. Requested top-down plants rather than harvested produce; inspection found that this constraint was not reliably obeyed.

## Sample coverage

The current catalog contains 109 vegetable entries and 37 herb entries. The separate cover catalog contains 26 entries. The inventory therefore contains 172 unique `(catalog, crop_id)` pairs.

Twelve vegetable IDs were sampled in all three styles: tomatoes, carrots, lettuce, broccoli, peppers, onions, beets, kale, cucumber, bush-bean, corn-sweet and cabbage.

Six cover IDs were sampled in a single texture sheet: crimson-clover, winter-rye, buckwheat, hairy-vetch, mustard-cover-crop and peas-and-oats-mix.

There are 36 exploratory individual plant images, six cover texture studies and zero production-ready catalog assets. Herbs and all other catalog entries remain unsampled. Do not treat pelleted or greenhouse entries as new botanical types automatically; propose explicit asset aliases only after reviewing their growth habits.

## Processing limits

The painted and pixel generations returned four rows instead of the requested three, including duplicates. Cells were selected after visual inspection; the invented purple specimen was excluded. The sculpted generation returned twelve cells, but some leaves crossed cell boundaries. Small disconnected neighboring fragments were removed.

Near-white backgrounds were converted to alpha and un-matted for preview, then the artwork was fit within a 224 px area on a 256 px square. This is optical normalization for a style comparison, not a measured root anchor or botanical diameter. Small details and pale leaf edges need manual mask review before production. Pixel cutouts are not a correctly authored common-resolution pixel atlas.

The soil composite uses `flutter/assets/render/prepped_soil.jpg`. It is an offline Pillow composite at equal plant sizes and fixed positions, not a screenshot or behavior test of the actual renderer. No geometry or agronomic spacing should be inferred from it.

## Before implementation

### Home

Use native Flutter controls and the current theme for typography, farm name, tool labels and counts. Treat illustration as decoration. Do not bake navigation, focus, hover or live data into a picture. Keep tools usable while assets load and when assets fail. Preserve existing empty summaries such as “Nothing growing”; counts must not be invented to fit the art.

For a compact view, shorten the scene and stack existing tool cards; never require panning through artwork to find the tools. Keep generous target sizes and visible keyboard focus. Optional animation should be subtle, not block navigation, and respect reduced-motion preferences. A rendered garden is decorative unless a later scope explicitly makes it a truthful thumbnail of the user's plan.

### Plant renderer

The current plant painter uses the existing `PlantLayout` positions and draws circles, with line fallbacks when plants are too small or layout counts are high (`flutter/lib/presentation/canvas/plant_painter.dart`). Only Render mode should gain pictures. Preserve Wire mode, positions, size semantics, counts, selection, clipping and low-zoom fallback behavior.

Artwork must be truly overhead, with consistent upper-left form shading and roots underground. Fit the visible canopy to the existing size footprint using explicit anchor and padding metadata. Add assets through the existing asynchronous `RenderAssets` loading pattern with deterministic missing-art fallback. Test zoom, selection, edge beds, dense plantings, missing images and document reloads. No change to saved records or spacing just to accommodate prettier artwork.

Correct a pilot set before scaling out: tomato, carrot, lettuce, cabbage, bean and corn stress different silhouettes. Judge over light canvas and dark soil at 24, 32 and 64 px. Root crops should show foliage, not a floating underground vegetable. Produce icons, if later wanted for Seed Vault, are a separate camera/art family.

The initial library should depict representative plants, not claim current maturity or flowering. Stage-specific art requires explicit reliable application state. Repetition variants should be stable per plant, not re-randomized during repaint, and should not rotate a strong baked-in directional shadow.

### Cover crops

The current Render mode uses prepared soil with a translucent green wash (`render_painter.dart`). The six new texture pictures are not yet seamless; rectangular backplates and overhanging leaves need replacement with edge-safe material. Use the existing ground texture/blending architecture, stable world scale and zone clipping. Review mixes as mixes, not aliases to one constituent crop. Test repeated tiles in a multi-tile grid before calling them seamless, and preserve technical overlays above them.

## Remaining decisions

The Home direction and ground illustration reference are selected above. Individual vegetable sprites still need corrected pilot artwork and an approved asset contract before full-catalog production. Round 1 does not replace the existing UI or install its exploratory sprites.
