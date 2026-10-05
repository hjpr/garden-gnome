# Ground texture plan, round 2

Status: BUILT and installed (round 2). This supersedes the "Still required" list in README.md and the six-variant atlas contract described there.

What shipped:
- Three variants per ground (3072 × 1024 atlas), plus 4× and 16× smaller copies (`_atlas_mid`, `_atlas_far`) that the shader reads when zoomed out.
- Every ground repeats every 5 ft.
- Edge fades on bed and lawn shapes are halved.
- Picks: round2/picks.json. Candidates and review sheets: round2/. Generator: tools/render-art/gen_ground.py. Build: tools/render-art/texture_banks.py.
- Spend: about $2.40 for 37 generations.

Lessons from round 2:
- Never give clover-05 to the model as a reference for clover. It returns the anchor itself (about 2% RMSE, same flower positions).
- The anchor works as a style reference for other materials.
- Clover kept its scale only with clover-05's original over-specified prompt.
- Soil prompts that used the clover reference sometimes produced brown "leaves". The prepped-soil prompt now asks for angular clods, no leaves.

## Lessons from round 1

1. We asked the model for a scale and it didn't deliver one. Requests for "tiny leaves, hundreds of strokes" at 1024 px came back with inconsistent sizes. Over-dense requests also produced the dithered, screen-like texture.
2. Feeding a generated image back in as the reference made each generation worse (pattern screening, repeated compositions). Errors compound across generations.
3. Clover/grass at 4 to 7 m per repeat on a 1024 tile works out to 146 to 256 texels per metre. That is blurry at close zoom and over-detailed at the default zoom. The shader has no mipmaps, so busy tiles shimmer when zoomed out.
4. Variants that differ in feature size or contrast show up as hex-cell quilting and smeared blends, even after colour matching.
5. Prompt words tripped the provider's copyright filter (HTTP 400). We spent $7.63 on generations; $5.16 of the $15 correction budget is used.

## Principle

The model's job is style. Scale is handled by our code. Generate freely, measure the result, and resample it to one house scale. Prefer shrinking to enlarging.

## 1. House scale (fixed before any generation)

Zoom range (logical px per metre) = 30 × 100 / camera height in ft:
5 ft = 600, 20 ft = 150, 100 ft (start) = 30, 500 ft = 6. DPR 2 doubles the device pixels.

Agreed with the user:

- Design zoom: full zoom (5 ft camera, 600 px/m), where the 0.5 ft grid shows about 10 × 10 cells in a normal window.
- One 1024 px tile fills that whole 10 × 10 grid: 1024 px = 5 ft (1.524 m), about 672 texels/m, 914 logical px on screen at full zoom.
- Style over realism: a coarse, detailed, pleasing texture, not real size.
- Scale reference: raw/crimson_clover-05.png as generated. Whole leaf about 65 px (about 0.7 of a grid cell), leaflet about 28 px, flower head about 20 × 28 px. See plan/clover05-full-zoom-grid.png.
- Hex anti-tiling hides 5 ft repeats. Six variants per material is still 24 MB.
- At DPR 2, full zoom magnifies the source about 1.8×. Flat painted shapes tolerate this.

Target feature size per 1024 tile (median, measured), matched to clover-05's visual density:

| Material      | Feature             | Texels  | Grid cells |
|---------------|---------------------|---------|------------|
| Clover        | trifoliate leaf     | ~65     | ~0.7       |
| Wild grass    | blade clump         | ~70     | ~0.75      |
| Lawn          | tuft                | ~45     | ~0.5       |
| Dirt / soil   | clod                | ~25     | ~0.25      |
| Loam          | crumb               | ~20     | ~0.2       |

The model drew clover-05 at this scale without being pushed. Most generations should need only small resampling, and upscaling should be rare.

## 2. Generation

- Use ONE style anchor per family: a crop of proofs/cover-crops.png (greens) and of the current soil (browns). Never use a generated image as a reference.
- Ask for the density the model draws cleanly: about 15 leaves (or clumps/clods at the table's size) across the frame, as clover-05 did. Don't ask for "hundreds of tiny" anything; that is what caused the screening. When in doubt, aim slightly coarse, because shrinking a little is safer than enlarging.
- For variety, give each variant a new prompt seed or wording. Don't edit a previous output.
- Keep prompts plain ("hand-painted illustration, flat matte shapes, soft two-tone shading, no outlines"). Avoid medium and brand words that trip filters.
- Pilot cost check: Gemini Flash Image (~$0.067) vs a 2K-native model (Gemini Pro Image / Recraft gave 2048). Native 2K would let us reach density without upscaling.

## 3. Normalise (local, scripted: extend tools/render-art/texture_banks.py)

1. Measure the feature size automatically from the radial power spectrum or autocorrelation. Cross-check it by eye on one sheet.
2. Scale factor s = target texels / measured texels.
   - s ≤ 1: Lanczos downscale (preferred).
   - 1 < s ≤ 1.5: Lanczos upscale.
   - s > 1.5: crop the cleanest region, then upscale with a local AI upscaler (Real-ESRGAN anime model, suited to flat painted art). If it still looks soft, reject.
3. Crop or tile to 1024 px (2 m). A downscaled source smaller than 1024 is reflected/mosaicked only if it is seamless; otherwise reject.
4. Seamless pass: half-offset blend (already written).
5. Bank match: mean colour and contrast to the bank median (the colour-matching experiment, moved into the tested pipeline).

## 4. Automatic QA gates (run before a human looks)

- Scale: median feature size within ±15% of the target.
- Screening: no sharp isolated peaks in the high-frequency spectrum (catches halftone, dithering and moiré).
- Vignette/border: edge band vs centre luminance within 4%.
- Direction: the spectrum is roughly isotropic, so no upright grass or rows.
- Duplicates: low correlation between variants.

Survivors go on one contact sheet per material at hero zoom, and a person picks.

## 5. Renderer changes

- Far LOD (now required, not optional): at the 100 ft start view a 5 ft tile is only 46 px, about 22× minification, so the detailed art will shimmer without it. Use a pre-blurred quarter-size atlas. The shader mixes toward it as texels per screen pixel rise above 1, then toward the mean colour at the widest zoom. This fixes zoomed-out shimmer.
- Set each material's metres from the house scale (5 ft = 1.524 m per tile for every material), not by hand.
- Keep blend bands narrow. Matched variants make the blends invisible; the blend can't fix mismatched variants.

## 6. Acceptance

Render real shader proofs at 30, 150 and 600 px/m at DPR 2 (terrain_proofs_test). Then check in the user's browser. Only then install the atlases.

## Order

1. Write the scale tooling and QA gates, then run them on the round-1 raw/ set. This is free and tells us which existing tiles survive.
2. Paid pilot: lawn + wild grass, 4 generations each (about $0.55), through the whole pipeline to shader proofs.
3. Once the pilot passes: clover, then re-check the soils at the house scale, then the far LOD in the shader.
