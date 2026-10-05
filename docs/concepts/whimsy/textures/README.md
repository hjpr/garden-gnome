# Ground texture round

Open `index.html` for all 36 source candidates with individual review notes.

## Current state

Latest bounded model comparison: open `model-pilot/index.html`. Recraft V4 Styles Pro and FLUX.3 each generated two grass and two clover attempts using identical prompts/references. All eight calls succeeded for $0.516 total, but neither model held both independence and within-pair consistency. Generation is paused again, as requested. The full correction-phase spend, including this separate pilot, is $5.1643215 of $15. Original image settings are restored; runtime artwork is unchanged. Pilot outputs are separate from the 36 current source candidates and the bank manifest's cost/count totals below.

The renderer supports six independent images per material, with the existing world-space hex-cell rotation, blending, detail-preserving contrast and macro color variation. The artwork is incomplete and has NOT been installed. Existing runtime textures remain in use. Pocket Garden is the selected Home direction, but the Home UI is not implemented in this pass.

The user removed OpenRouter's cumulative key cap and authorized $15 for corrections. The active key's read-only budget endpoint confirmed the cap was removed. No provider or model setting was changed. Paid generation is now paused for renderer review: numerous ordinary soil and botanical prompts received HTTP 400 copyright/trademark-filter errors, and successful generations did not consistently hold the requested scale/style.

Generated: 36 current 1024 × 1024 source candidates, 113 successful originals preserved in total. The correction round added 69 images for $4.6483215; the complete texture study's reported successful-generation cost is $7.6342. Model: `google/gemini-3.1-flash-image`. Failed requests did not report a reliable nonzero cost. All 113 file hashes and their cost ledger were reconciled after merging the three correction manifests.

Review: 20 keep candidates, 15 rework and 1 discard. Keep is a source-art verdict, not final production approval. Loam has a complete fine-scale source set. Dirt has six independent candidates, but the smoother new 04/06 still need blended cohesion review. The other four banks remain incomplete.

| Material | Keep candidates | Rework / discard |
|---|---:|---:|
| Wild grass | 3 | 3 |
| Lawn | 2 | 4 |
| Dirt | 6 | 0 |
| Prepared soil | 1 | 5 |
| Loam | 6 | 0 |
| Crimson clover | 2 | 4 |

Visual problems include upright grass, changing leaf/aggregate scale, oversized loam clods, bordered or mixed-species clover, mismatched color and near-duplicate compositions. Exact unique hashes do not establish useful independent variation. All current candidates were reviewed in material contact sheets by the parent after generation.

## Art files

- `raw/`: current sources; six numbered files per material. Superseded outputs are retained in the subordinate rejected directory.
- `review/`: six labeled contact sheets plus style guides.
- `generation-manifest.json`: prompts, costs, dimensions, keep/rework decisions, exclusion flags, failures and near-duplicate findings.
- `index.html`: comparison board. Shows failures rather than treating file count as completion.

No production atlas or final-art shader proof is claimed. `candidate-assets/` contains six conditioned atlases exclusively for experimental Flutter review, including rejected sources so their defects can be judged after blending. These are NOT runtime assets and must not be copied into the app. Candidate renders belong in `candidate-rendered/`, separate from the final `rendered/` destination.

## Renderer

The optional atlas contract is a 3072 × 2048 image containing six 1024 × 1024 tiles, in three columns and two rows, row-major order. Filenames are `{material}_atlas.jpg` under `flutter/assets/render/`.

Manual bilinear filtering wraps each tap inside its selected tile. A separate hash stream chooses the variant for a world-space cell; panning, zooming and repainting do not choose new variants. Loam retains its previous rotation restriction and row lighting treatment. Current ground coverage scales are preserved; crimson clover provisionally uses 4 m per tile and needs botanical-scale review.

Missing, corrupt or incorrectly sized atlases fall back to the existing single texture. If the fragment shader is unavailable or `?ground=tiled` is requested, the renderer uses legacy textures rather than exposing atlas seams.

Clover is resolved through the Seed Vault variety's exact crop ID, not its display name. Only `crimson-clover` selects its artwork. Unknown/deleted varieties, other cover types and missing artwork retain the generic green cover appearance. Planned/undated clover uses a representative canopy, not simulated current maturity. A termination on or before the garden's current day suppresses the clover canopy, reverting to generic cover rendering rather than implying a new bare-soil lifecycle.

Six full-resolution decoded RGBA atlases nominally use 144 MiB before engine/transient overhead. Loading and average-color extraction are sequential to limit transient buffers; duplicate legacy images are not decoded when the atlas succeeds. This is not a measured browser GPU-memory guarantee.

## Processing and promotion

The processor requires all 36 source files and a complete generation review manifest. Every current entry must have `verdict: keep` and `excluded: false`. It refuses installation before writing anything if any source is missing, excluded, undersized, nonsquare or an exact pixel duplicate. Reviews must not be changed merely to get past this guard.

Dependencies: Python, Pillow and NumPy. Run from the repo root in an environment with those packages:

    python tools/render-art/texture_banks.py \
      --study docs/concepts/whimsy/textures \
      --runtime flutter/assets/render

This command currently fails intentionally on excluded sources. Its edge-conditioning method blends against half-offset interior content one axis at a time and equalizes opposing boundary pixels. PNG edge equality is a numerical check, not a substitute for visual seam inspection after JPEG encoding and shader blending. Once the source set is corrected, inspect all processed repeat sheets and exported Flutter proofs before activating the library.

The processor writes six runtime JPEG atlases, a crimson-clover fallback tile, lossless conditioned study tiles, repeat previews and a processing manifest. Existing legacy ground files are preserved. Unit tests use explicitly synthetic fixtures; those fixtures are never used as the requested artwork.

## Verified

Parent execution:

- `npm run test`: 720 passed, 1 intentionally skipped optional export.
- `flutter analyze --no-pub`: no issues.
- `flutter build web --no-pub`: succeeded, including Wasm dry run; emitted a CupertinoIcons font-family warning.
- Processing tests cover boundary continuity, unchanged central detail, row-major atlas layout, invalid source sets, rejection of unreviewed/excluded art and preservation of existing runtime files.

The added actual compiled-shader raster tests cover all six variants for each material seed, filtering isolation, deterministic redraw/pan/zoom and atlas/legacy rendering equivalence. Final-art appearance and runtime memory/performance are not yet verified because the complete artwork is not accepted.

After all final runtime atlases are ready, export actual Flutter shader images and the mixed-ground scene:

    cd flutter
    flutter test --no-pub --dart-define=EXPORT_TERRAIN_PROOFS=true \
      test/presentation/terrain_proofs_test.dart

The opt-in exporter refuses incomplete atlases before writing any images. Outputs go to this directory's `rendered/` subdirectory. Normal tests do not write artwork.

## Remaining work

### Candidate renderer review

Open `candidate-rendered/index.html` for eight actual Flutter outputs with a before/after color-matching toggle. The parent inspected the overview, 160 px/m close scene and all six initial material maps. The original unmatched set remains in `candidate-rendered-unmatched/`; current candidate assets and outputs use experimental per-bank RGB mean matching and bounded contrast gains, recorded in `candidate-palette-experiment.json`. Original source files are unchanged.

Color matching largely removes the hexagonal tone islands visible in the first render, especially in soil and grass. It does not fix different leaf/blade sizes, grass painting styles, source borders, or repeated compositions. Grass and clover still fail close-view coherence. Loam is the strongest current bank. Nothing is installed or approved by this experiment.

Re-export the current isolated candidate assets from `flutter/` with:

    flutter test --no-pub --dart-define=EXPORT_TERRAIN_CANDIDATES=true \
      test/presentation/terrain_proofs_test.dart

Parent reran the candidate exporter: 5 tests passed; the final-runtime exporter was intentionally skipped. Ordinary proof tests passed with both export paths skipped. Candidate loading is fail-closed and uses an isolated memory bundle; final-art checks remain separate.

### Still required

1. Carry the color-matching experiment into the tested processing pipeline before final promotion. Candidate comparison is complete; no runtime promotion is authorized by it.
2. Correct the incomplete banks; match leaf/aggregate scale and palette across each six-tile bank. Use fresh compositions for near-duplicate failures rather than repeatedly editing the same arrangement. Provider refusals and inconsistent scale make continued blind retries unsuitable.
3. Condition and inspect all 36 tiles, JPEG atlas boundaries and repeated-area samples.
4. Export actual shader proofs; check the clover scale and the existing loam color lift against the new materials.
5. Inspect the complete scene in the browser and measure loading/rendering behavior before calling the terrain update complete.
