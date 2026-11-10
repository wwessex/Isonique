# Isonique editing and Inspector comparison — 8 November 2026

This is a historical development record. For current coverage, see the [workflow comparison](docs/APERTURE_FEATURE_PARITY.md) and [test results](docs/APERTURE_TEST_RESULTS.md). The maintained application is the SwiftUI/AppKit macOS app. There are no independent web/PWA, Windows, iOS or Android variants in this repository.

## References checked

- Apple-authored Aperture Help, mirrored at [Apply standard adjustments](https://aperture.skydocu.com/en/make-image-adjustments/ways-to-perform-adjustments/apply-standard-adjustments/): tool strip and Lift/Stamp workflow, including illustrated HUDs.
- Apple-authored [Crop help](https://aperture.skydocu.com/en/make-image-adjustments/apply-specific-standard-adjustments/crop/): drag selection, aspect ratios, composition guides and apply/reset behavior.
- Apple-authored [Straighten help](https://aperture.skydocu.com/en/make-image-adjustments/apply-specific-standard-adjustments/straighten/): angle control, alignment grid and removal of blank corners.
- [PhotoJoseph's split-tone article and screenshots](https://photojoseph.com/tips/2013/7/1/creating-split-tones-aperture-3): saturation and separate RGB curves controls.
- [Marco Pollini's clone tutorial and screenshot descriptions](https://www.polliniphotolab.com/Articoli/Aperture/clonazione/clonazione.html): source selection, clone brush radius, softness and opacity.
- A local reference screenshot of Aperture: adjustment HUD, histogram, curves, levels, color and dodge brush.

The articles and help text were retrieved; direct high-resolution online screenshot downloads were unavailable through the available network paths. Image search returned the screenshots and their descriptions; the supplied screenshot was inspected locally. These references establish feature gaps, not pixel equivalence or compatibility with Apple's proprietary adjustment recipes.

## Implemented in this change

| Missing control | Current behavior |
| --- | --- |
| Dedicated editing strip | Select, rotate left/right, Crop, Straighten, Lift, Stamp, Original, Undo and Redo; horizontal scrolling at narrow widths. |
| Rotate | 90-degree steps in either direction, stored in the adjustment recipe. Changing orientation clears the prior crop. |
| Crop | Full uncropped preview, freeform drag selection, dimmed excluded region, thirds grid, centered square/4:3/3:2/16:9 presets, Cancel and Apply. Reopening Crop exposes excluded pixels; Full image then Apply removes the crop. |
| Straighten | -45 to +45 degree slider, angle readout, alignment grid, Level and Done. Trims blank corners. Changing angle clears the prior crop. |
| Lift/Stamp | Copies the supported adjustment recipe; Stamp applies only the groups selected in Inspector to one selected photo. Metadata and original pixels remain untouched. Clipboard is session-local. |
| Original comparison | Available directly from the editing strip. Disabled while composition tools are active. |
| Undo/Redo | Session history for photo edits, including metadata and geometry; buttons and Command-Z/Shift-Command-Z. |

Preview and full-resolution JPEG export share geometry processing, including the CPU rendering fallback. The older three-value adjustment recipe decodes with zero rotation, zero straightening and no crop. The catalogue format stays at version 1; this version reads old catalogues, but older app executables will ignore the new geometry fields.

## Remaining gaps

The app now exposes this inventory through Help → Features & Limits and the question-mark toolbar button. The separate native window includes search, a missing/limited-only filter and available-feature summaries. It also covers export restrictions, legacy recovery, session-only undo, RAW limitations and absent platforms. This change documents the gaps in the interface; it does not implement those unavailable tools.

Retouch/clone/heal, red-eye removal, localized adjustment brushes, histogram, curves, levels and multi-photo Stamp remain unimplemented. Selective Stamp groups are available; Lift captures all supported settings. Crop currently redraws a rectangle or applies a centered preset; it does not provide movable resize handles, a persistent aspect lock, custom pixel dimensions or portrait preset switching. Lift/Stamp copies supported adjustments only, without Apple's metadata-selection HUD. These controls are deliberately not presented as working tools.

## Validation

Seven XCTest cases pass, including old-recipe decoding, saved recipe round trips, matching CPU/preview/export dimensions, clockwise/counterclockwise pixel placement, top-left crop coordinates, opaque straighten corners and unchanged original hashes. The arm64 release build and staged bundle signature verification pass.

Only the native Apple Silicon macOS variant is present and checked on this host. Intel, macOS 14/15 runtime behavior, actual RAW cameras and physical mobile devices are not validated.

## Inspector expansion

Added Info / Adjustments / Library tabs, editable numeric values and individual reset buttons, warmth and tint, shadow lift and highlight reduction, four color/tone presets, geometry shortcuts and grouped Stamp checkboxes. Presets retain crop, rotation and straighten; unchecked Stamp groups retain the target values. Imported date and Reveal Managed Original are available under Info. Toolbar sorting supports filename, import date, rating and capture date in both directions; 2-star and 4-star minimum filters fill the previous gaps.

New tone controls use an independent shared 8-bit sRGB transform after exposure/color and before geometry in both rendering paths, including export. Warmth changes red/blue gain; tint adjusts green against magenta. Shadows lift dark tones and Highlights reduce bright tones using smooth luminance weighting. These are not reconstructed Apple RAW formulas and cannot recover clipped original data. Old catalogues decode missing fields to neutral values; older executables ignore the new fields. Catalogue version remains 1.

The latest validation supersedes the earlier seven-test count above: 11 tests pass, including persistence/export, legacy defaults, neutral rendering, directional tone effects, selective stamping and geometry preservation by presets. Screenshot inspected at 2880×1800; interactive menus, typing and Finder reveal were not automated. Only native Apple Silicon macOS is present; Intel and macOS 14/15 execution are untested.

## Rating-filter follow-up

The native filter added exact Unrated only and Rejected only choices alongside the star thresholds. Historical binary analysis informed the filter values and comparisons. See the [development provenance notes](MECHANICS.md) for scope and limitations.

## Library compatibility follow-up

Recovery and ordinary import now retain embedded IPTC captions/keywords and IPTC/XMP ratings. XMP ratings take precedence, use -1…5 bounds, and invalid values leave an unrated default. Existing duplicates retain user edits. Recovery distinguishes duplicate originals from unsupported images and lists unsupported paths; non-decoding failures propagate instead of being hidden in a skip count. The source remains read only and hash verified.

Help → Features & Limits now lists missing catalogue migration/hierarchy/relationships, referenced-file options, XML and sidecar import, vaults/merging/repair, camera import, RAW+JPEG pairing and import presets. The full library inventory is in COMPATIBILITY.md. Database-only metadata, versions and old edits remain unavailable. Embedded metadata can predate the current Aperture catalogue. No real user library was supplied.

## Ranked missing-feature and option lists

Help → Features & Limits starts with two separate numbered lists: exactly 10 missing features and exactly 10 missing options. Ranking reflects impact on everyday photo work, rather than a delivery commitment. Features cover migration, batch workflows, retouching, tonal tools, organization, referenced originals, backup/repair, camera capture, publishing and sync. Options cover export format/quality/metadata, crop precision, Stamp metadata, RAW+JPEG pairing, import presets, XML/XMP import, color/lens controls and persistent history. Search preserves the ranking numbers, and the existing limited/available summaries remain accessible. These entries document current gaps; they do not implement the unavailable capabilities.

## Implemented top five missing options — 8 November 2026

This section supersedes the earlier missing-option inventory for ranks 1–5. The native app now offers:

1. Export format: edited JPEG, PNG or TIFF, plus byte-for-byte unchanged original copies.
2. Export quality and size: JPEG quality, longest-edge pixels (0 means full size), proportional downsampling without enlargement, and named persistent presets with load/delete actions.
3. Export metadata: independent EXIF, IPTC and GPS checkboxes, all off by default. IPTC uses current caption, comma-separated keywords and rating. EXIF dimensions and orientation reflect the rendered image; maker notes are omitted to avoid stale embedded previews. Unchanged original copies retain all embedded metadata and bypass edits and metadata selections. Edited exports use the existing 8-bit sRGB renderer.
4. Crop precision: drag inside to move, drag corner handles to resize, draw outside to replace, remembered aspect lock, square/4:3/3:2/16:9 presets, portrait/landscape switching and exact pixel width/height. Pixel dimensions refer to the full-resolution rotated/straightened image; setting them establishes a new aspect. Crop boundaries round to pixels rather than expanding fractional edges.
5. Stamp metadata selection: caption, keywords and rating checkboxes in Inspector, off by default. Lift snapshots these values along with adjustments. Stamp replaces checked fields (including empty values), supports metadata-only Stamp, preserves identity/originals and participates in existing Undo/Redo.

No catalogue schema change: recipes retain normalized crop coordinates. Export preferences/presets and crop aspect preferences use per-user UserDefaults; the Lift clipboard and Stamp choices remain session-local. Earlier app versions can still read the catalogue.

## Implemented next five options — 9 November 2026

Ranks 6–10 now have native controls: RAW/JPEG separate/link/prefer import modes, catalogue naming prefixes and saved metadata presets, XMP sidecars and limited XML metadata import, RGB ICC viewer proof simulation and manual radial distortion correction, and optional persistent bounded Undo/Redo. See README → Next five options for the exact supported formats and limits. Earlier missing-option and session-history descriptions are superseded. Full Aperture migration, automatic camera lens profiles, CMYK/paper proofing and RAW codec validation remain unavailable.

## Batch and organization update — 9 November 2026

Missing-feature ranks 2 and 5 now have controls. Batch mode supports multi-selection, ratings, flags, tone presets, selective Stamp, album/project assignment and export with existing options. Undo operates per photo. Smart albums combine live minimum-rating, flag and text predicates; rules can be edited from their sidebar context menu. Explicit stacks group photos for sidebar browsing, with selected-member unstacking. Named editing versions save/restore/delete adjustment recipes without copying originals or metadata. Automatic stacking, collapsed stack covers and separate per-version metadata remain unavailable. Existing catalogues decode optional fields as absent; older executables can discard them. Back/Escape returns from a photo to its current grid; All Photos clears filters and opens the library grid, including when its sidebar row is already selected. The app starts in the grid. Only the native macOS application exists.

## Next five features — 9 November 2026

Implemented live edited-preview luminance histogram, black/white/gamma Levels, a three-control piecewise-linear master curve, capture-time auto stacking and slideshow playback. This supersedes the earlier statements that histogram/levels/curves, automatic stacking and slideshows are wholly absent. README documents controls, formulas and limits. Full library migration, retouching, referenced originals and backup/repair remain missing. New tools are independent implementations, not recovered Aperture algorithms.

## Remaining-feature pass: library protection — 9 November 2026

Detected missing backup/restore and integrity controls in the in-app inventory. Added File menu commands for verified Isonique backups, restore to a new separate folder, read-only catalogue/original integrity checking, and opening a verified existing library. Last opened/restored location is remembered. The guide now marks backup/repair as available with limits: legacy vaults, merging and automatic repair remain absent. Backup format and exclusions are documented in README. This supersedes the earlier statement that backup/restore are wholly absent. No Apple implementation or proprietary catalogue behavior is claimed.
