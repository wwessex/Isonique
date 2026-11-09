# Aperture test results

## Baseline, 9 November 2026

- `make test` passed 41 XCTest cases on arm64 macOS 27.3 (26C5035r), Xcode 27.2, Swift 6.4.2. Coverage includes generated still images, library round trips, original hashes, export, geometry, tone, organization and verified backup/restore.
- The existing release configuration targets macOS 14+ and explicitly builds Apple Silicon. Only this macOS native version exists. Intel, older macOS runtime, camera/tether hardware, real RAW fixtures, HDR/wide-gamut display accuracy and VoiceOver are untested at baseline.
- Existing build history is in [VALIDATION.md](../VALIDATION.md). A screenshot verifies startup rendering; interactive tests are recorded separately when performed.

## Core persistence, Trash and multiple libraries

- `make test` passed 47 XCTest cases. Added import metadata and album round trip, symlink copy, malformed sidecar and save rollback/retry, safe library creation, Trash backup/restart, workspace selection, undo/redo and failed workspace write tests.
- `make build` passed arm64 release compilation, staged strict ad-hoc signature verification and archive generation. The native launch probe reported one visible arm64 Isonique window.
- Exercised the native import picker and sheet with a synthetic PNG. Command-Delete hid it from All Photos, the Trash sidebar showed it, and Put Back cleared Trash. Shift-Command-N created a separate empty library, then File → Open Isonique Library switched back and showed the restored photo. Verified source and stored copy SHA-256 matched and the two catalogues contained one and zero photos respectively.
- A sync conflict produced 16 untracked duplicate files during the pass. Verified each against Git and preserved them outside the repository in `checks/isonique-sync-duplicates`. SwiftPM initially compiled the duplicate Swift sources. Normal builds resumed after relocation.
- Photo Trash retains original files and is included in backup. Finder Trash handoff and folder, album, and version Trash remain pending. Catalogue format 1 remains readable by older builds, which ignore the photo Trash field.

## Referenced originals and missing-file recovery

- `make test` passed 50 cases. New tests cover referenced import without managed copies, move detection, wrong-file rejection, relink and export across a renamed extension, consolidation with an injected catalogue failure, backup/restore with an offline reference, missing managed file restoration and history across a relink.
- Catalogue version 2 is selected when the first referenced original is imported. This build reads managed-only version 1, while older builds reject version 2. Backup manifest format remains 1. Backups retain referenced paths and copy managed originals, including originals in photo Trash. Integrity Check validates available referenced bytes and reports a missing reference as a failure.
- References use absolute filesystem paths and the permissions of the native desktop process. Removable-drive mount/unmount UI refresh is connected to macOS notifications. Physical drive ejection, network volumes and File Provider recovery are untested.
- The arm64 release and signed archive built. The app launched with a visible window and a synthetic offline reference. Native interaction capture returned ScreenCaptureKit error -3811 during the follow-up, so relink and consolidation interactions are covered by core/workspace tests in this pass.
- A 3472 × 1994 startup capture was inspected. The offline photo card displayed its warning and referenced badge, and the histogram reported that the original was unavailable.

## Import job progress and cancellation

- `make test` passed 52 cases. A deterministic cancellation after the first of three fixtures verified progress counts, no second copy, an intact source and a persisted project with its one committed photo. A separate test covered folder enumeration, continued import after a malformed image, and no empty project after duplicate/failure-only intake.
- Cancellation takes effect between files or directory entries. The current file's copy, hash checks and catalogue write finish together. RAW + JPEG pairs with both committed members are linked before the job reports completion.
- Import-job arm64 release compilation, strict staged signing and archive generation passed. The interactive cancel control was not exercised against a large input.

## Compound Smart Albums and Advanced Search

- `make test` passed 56 cases. Added All/Any and exact keyword tests, normalized extensions, leap-day and absent capture dates, original availability, saved rule compatibility, live browser/album membership, Undo and reopening the catalogue.
- Advanced albums or project-scoped Smart Albums select catalogue version 2. Older simple albums keep their existing semantics. Date rules use day precision, with capture dates taken from EXIF and import dates displayed in the Mac’s local time zone.

## Shared flip and tone rendering

- `make test` passed 58 cases. Expanded tests cover both flip axes and cropped pixels, neutral legacy recipes, geometry and tone Stamp, saved recipes, directional brightness/vibrancy, sepia channel ordering, Undo/Redo, and unchanged original hashes.
- The generated 32 × 24 PNG round trip matched the preview's RGBA bytes within one 8-bit code value. Larger images, high-bit-depth profiles, HDR, and real RAW inputs remain unqualified.
- Brightness applies a midtone lift, vibrancy favors lower relative chroma, and sepia blends a tinted luminance treatment. These are independent sRGB operations. Historical Aperture vibrancy also protected skin tones.
- Follow-up native QA on a separately identified, signed test copy succeeded after the earlier capture failure. Relink opened a moved synthetic PNG in the viewer, Info showed its external location, and Consolidate changed storage to Managed while retaining the external file. Shift-Command-F opened Advanced Search, a filename rule updated the match count, and Save as Smart Album selected the album and displayed its photo. Photos → Flip Horizontally enabled Undo, and Command-Z enabled Redo.

## Keyboard review, labels and final release

- `make test` passed 60 XCTest cases. New tests cover culling under Unrated Only, persisted label and label-name settings, filter membership, Undo/Redo, and stable color values in compound searches.
- The native test accepted 4 for four stars and Command-4 for a green label. Typing a 5 into the Caption field preserved the four-star rating. Settings opened with Command-comma and accepted a multiword label name.
- The native macOS arm64 version was the only maintained app. Tests ran on Apple M5 Pro, 24 GB, macOS 27.3 and Xcode 27.2. No alternate platform, Intel runtime, macOS 14/15 runtime, actual camera/tether device, genuine RAW dataset, high-bit-depth export or calibrated wide-gamut/XDR measurement was available in this pass.
- The final `make build` passed. The app extracted from `build/Isonique.zip` passed strict signature verification, reported an arm64 executable, and rendered a 3472 × 1994 startup screenshot. Visual inspection confirmed the rated and labelled card, flip menu, adjustment controls and histogram. The launch emitted a non-blocking system sandbox-extension diagnostic and completed with exit status 0.
- Compared the synthetic input, moved reference and consolidated managed copy after native QA. All three SHA-256 hashes matched. The persisted catalogue had the expected color/rating and the saved Smart Album in their respective test libraries.

## Browsable versions and side-by-side comparison

- The baseline of 60 tests passed. With browsable versions and comparison, all 64 XCTest cases passed on the native arm64 macOS app.
- Version tests covered stable original identity in older catalogues, independent names and recipes, neutral and edited creation, identical original hashes, distinct PNG exports, duplicate import detection, one managed file in backup, restore, relinking and consolidating a family including Trash, invalid original relationships, and persistent creation Undo/Redo after a restart.
- Workspace tests covered comparison reference selection, swapping via the filmstrip selection action, ending comparison for crop, and discovering a sibling outside the current filter. First creation of a browsable version upgrades the catalogue to format 3. Formats 1 and 2 still load without relocating files.
- A signed QA copy of the release opened a disposable three-image catalogue in the native app. Option-V duplicated exposure +1.00, Option-G created a version at 0.00, and Option-O showed the neutral and edited versions side by side. Command-Return closed comparison and Command-Z / Shift-Command-Z removed and restored the new version. The arm64 release build and archive signing passed.

## Stack picks and collapsed stacks

- All 66 XCTest cases passed. New tests cover a manual stack’s first pick, persistent global and album-specific picks, collapsed presentation, filtered fallback, fallback while a pick is in Trash, Put Back, and Undo/Redo for album picks. Opening a stack from the sidebar bypasses the collapsed display.
- Stack preferences are stored per library in format 3. Existing stacks open expanded. Automatic stacking still uses the capture-time window and selects the first member by capture order.

## Native List Browser and final release

- All 67 XCTest cases passed. The list workspace test covers persisted layout, filtered multi-selection, culling and returning from the Viewer. Version thumbnail pixels matched the shared preview renderer at the same dimensions.
- Native QA exercised Control-L, single-row rating, Command-click selection, Command-K stacking, Shift-Command-Backslash album picks, and the persisted album and global covers. The first run found a crash when SwiftUI’s table removed a stack row. Passing explicit display values to the badge fixed it. The same collapse path and context-menu expansion passed on a rebuilt app. A subsequent focus fix made Escape return to the list after double-clicking a row.
- The final signed archive passed strict verification after extraction. Its arm64 executable opened a disposable format-3 library and produced a 3472 × 1994 screenshot showing distinct edited and neutral thumbnails. Five entries in that library matched the hashes of their three original files.
- The sole maintained variant is native Apple Silicon macOS. This run used an Apple M5 Pro with 24 GB, macOS 27.3 and Xcode 27.2. Earlier macOS runtimes, Intel, camera RAW and tether hardware, calibrated XDR, and large-library performance remain unverified.

## Local Dodge and Burn

- All 72 XCTest cases passed on the native Apple Silicon macOS app using Apple M5 Pro, 24 GB, macOS 27.3 and Xcode 27.2. This is the sole maintained variant. Earlier macOS runtimes, real camera RAW and high-bit-depth output remain unqualified for this checkpoint.
- Mask tests verified local lightening and darkening, falloff, independence from input sampling density on straight strokes, overlap, and erasing one mask while preserving the other. Geometry tests exercised crop, rotation, both flips, straighten, radial correction and an EXIF-rotated JPEG decoded at preview size.
- Full-size edited PNG exports matched the preview’s RGBA bytes with and without geometric adjustments. Five samples across a resized PNG differed from the reduced preview by at most two 8-bit code values in the red channel. Both the input file and managed original retained their original SHA-256 hashes.
- Workspace tests covered one Undo step per stroke, Redo, reset of one mask, stale photo selection, and persistence of both the recipe and edit history after reopening. A verified backup and restore retained the format-4 recipe and managed original hash. Older recipes load with empty masks. Built-in presets retain masks, and Stamp copies them only when their group is selected.
- Native QA opened the brush controls from Photos, then painted and erased on a disposable 480 × 320 PNG. The saved catalogue recorded one Burn stroke and one Burn erasure and upgraded to format 4. The original SHA-256 matched its catalogue entry. Undo and Redo were exercised through automated workspace tests.
- The arm64 app extracted from the release archive passed strict code signature verification. It reopened a copy of the brushed library and produced a 3472 × 1994 startup screenshot. macOS emitted the existing sandbox-extension diagnostic and the command completed with exit status 0.
- The brush canvas uses fit-to-window and updates processed pixels when the stroke ends. The source-aligned mask raster is capped at 2,048 pixels along the longest edge. Painting at pixel zoom, pressure and edge-aware brushing, and performance on long sessions with many strokes remain open.

## Viewer clipping warnings

- All 76 XCTest cases passed on the native Apple Silicon macOS app, the sole maintained variant. Testing used Apple M5 Pro, 24 GB, macOS 27.3 and Xcode 27.2. The arm64 release built successfully and the extracted app passed strict signature verification. Older macOS runtimes, HDR and high-resolution performance were outside this validation.
- Synthetic RGBA fixtures verified inclusive 100% and 0% boundaries, inclusive custom 80% and 20% boundaries, adjacent 8-bit code values, independent warning switches, mixed clipping, mask alignment and transparent and partially transparent pixels. The warning input reflects tonal edits and stays in the sRGB rendering space when proofing is active.
- PNG, JPEG, TIFF and original exports produced identical decoded pixels with warnings enabled and disabled. The edited PNG also matched the unmarked render, and original export matched the source file byte for byte. The workspace test verified preference persistence, threshold reset and that the switches leave catalogue bytes and edit history intact.
- Native QA on a signed copy exercised each View menu switch and Option-Shift-H, changed the Settings thresholds from 100%/0% to 90%/10%, and checked the Viewer at Fit and 100%. The near-white band gained a warning at 90%, red/blue/magenta overlays aligned with both comparison panes, and filmstrip thumbnails retained the original colors.
- Warnings describe the 8-bit preview at its current rendering resolution. Downsampling in Fit can change small clipped areas. The current presentation uses fixed colors and detects clipping before RGB proofing.
