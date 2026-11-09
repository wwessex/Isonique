# Isonique test results

## Baseline, 9 November 2026

- `make test` passed 41 XCTest cases on arm64 macOS 27.3 (26C5035r), Xcode 27.2, Swift 6.4.2. Coverage includes generated still images, library round trips, original hashes, export, geometry, tone, organization and verified backup/restore.
- The existing release configuration targets macOS 14+ and explicitly builds Apple Silicon. Only this macOS native version exists. Intel, older macOS runtime, camera/tether hardware, real RAW fixtures, HDR/wide-gamut display accuracy and VoiceOver are untested at baseline.
- Repeatable checks are listed in [VALIDATION.md](../VALIDATION.md). A screenshot verifies startup rendering. Interactive checks are recorded separately when performed.

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

## Viewer Loupe

- All 78 XCTest cases and the signed arm64 build passed on Apple M5 Pro, macOS 27.3. Automated tests verified center, edge and tiny-image regions, top-left pixel coordinates and unpremultiplied color readings.
- Native QA opened the Loupe through View on a signed test copy, read RGB 240/240/240 in the expected synthetic stripe, selected the 800% control, and hid it with the grave accent key. The Loupe has its own display panel and settings. Export recipes and catalogue format are unaffected.
- The Loupe requests a full-resolution render while active, uses the proofed image for magnification when proofing is on, and reads 8-bit sRGB before proofing. Inspection is currently available in the single-photo Viewer.

## RGB and luminance curves

- All 82 XCTest cases passed on the native Apple Silicon macOS variant. Tests verified point ordering and interpolation, isolated channels, transparent and partially transparent samples, neutral luminance, recipe validation, reset, Stamp, and Undo/Redo after reopening.
- Full-resolution edited PNG pixels matched the preview byte for byte. Both the source and managed original retained their SHA-256 hashes. Formats 1–4 continue to load, and the first saved channel curve selects format 5.
- Native QA opened the Inspector graph, added a red point, changed output from 127 to 128 through the accessible stepper, undid and redid the change, then switched to an independent luminance curve. The format-5 catalogue saved the red point.
- On Apple M5 Pro, an optimized 4000 × 3000 synthetic JPEG render had median times of 639 ms with neutral settings, 650 ms with three RGB curves, and 712 ms with RGB plus luminance. Each measurement was the median of five runs after one warm-up. Luminance uses linear-light blending toward black or white, with an sRGB graph and bounded lookup tables. This benchmark covers one synthetic image and one machine.

## Inspector histogram channels

- All 83 XCTest cases and the signed arm64 build passed on the native Apple Silicon macOS app. Synthetic fixtures verified bin counts, alpha handling, and that a red curve moves the expected red bin while leaving green and blue unchanged.
- Native QA confirmed all five choices in the Inspector and switched between luminance, combined RGB and blue. Switching modes left edit history empty. All four distributions are counted from the same edited 384-pixel preview, so toggling the presentation does not decode the photo again.

## Independent RGB Levels

- All 85 XCTest cases passed on the native Apple Silicon macOS app. The arm64 release archive passed strict signature verification. Tests covered black and white clipping, gamma remapping, channel isolation, the order of Levels and curves, recipe reset, persistent Undo/Redo and neutral combined controls.
- A combined Levels and curves recipe survived catalogue reopening in format 6. Its full-size PNG export matched the shared preview pixel for pixel. The input and managed original retained their hashes. Formats 1–5 remain readable.
- Native QA opened Channel Levels, set Red black point to 0.20, switched to a neutral Blue channel, then set Blue gamma to 1.50. The catalogue saved both independently in format 6, and both test originals retained their hashes. Auto Levels, quarter-tones and adjustment-input histograms are tracked in the next checkpoint.

## Adjustment input histograms

- All 88 XCTest cases passed and the signed arm64 app built. Fixtures verified the inputs before combined Levels, master curve, channel Levels and channel curves, including the encoded luminance axis and transparent pixels. Existing export equality tests continued to pass.
- Native QA switched the Curves graph from Red to Luminance, opened the separate Channel Levels input histogram, and changed the selected photo with both panels open. The request tests cover selection and upstream recipe changes and cancellation before opening a file.
- Sampling uses a 384-pixel version of the full oriented image at the tone stages, before lens correction and crop. The Inspector discards obsolete task results.

## Quarter-tones and Auto Levels

- All 91 automated cases passed on Apple Silicon. Tests verified exact neutral output for existing recipes, quarter-tone anchors and interpolation, automatic percentile selection, flat-channel handling, stale selection, one-step automatic Undo/Redo, and format-7 persistence. The full-size PNG export of a combined Levels and curves recipe matched the shared preview.
- Native QA applied combined Auto Levels, adjusted the dark quarter, applied separate RGB Auto Levels, and opened the clipping tolerance settings. The disposable catalogue recorded combined endpoints near 0.204 and 0.796, the 0.35 dark quarter, and distinct RGB endpoints. The arm64 release built and passed signature verification.

## Real camera RAW workflows

- The optional optimized `make test-raw` suite ran against four CC0 samples. Their downloaded SHA-256 hashes matched the release manifest. On Apple M5 Pro with macOS 27.3, all four files imported with camera metadata, rendered with format-7 quarter-tone and luminance curves, produced input histograms, and exported. Full-size PNG pixels matched the uncompressed render. Original exports, managed originals and external sources retained their original file hashes. [Fixtures and manifest](https://github.com/tellodaniel/revelraw-sample-raw-files/releases/tag/v1)
- Single-run render measurements include ImageIO decoding and tonal processing. These are host-specific timings.

| Fixture | Full-size pixels | 384-pixel preview | Full-size render |
| --- | --- | --- | --- |
| Sony a7 III ARW | 6000 × 4000 | 347 ms | 2,280 ms |
| Canon EOS R CR3 | 6720 × 4480 | 218 ms | 2,140 ms |
| Nikon Z 6 NEF | 6048 × 4024 | 97 ms | 1,688 ms |
| Ricoh GR III DNG | 6000 × 4000 | 34 ms | 1,694 ms |

- The fixture files remain external. The regular suite skips this test when `ISONIQUE_RAW_FIXTURES` is unset. The sample results cover this version of macOS ImageIO. Other camera models, decoder versions, demosaicing fidelity and high-bit-depth output remain unqualified.

## Viewer render cache

- The final optimized suite passed all 96 XCTest cases with the four external camera RAW fixtures enabled. The extracted Apple Silicon release app passed strict signature verification. The fixture-free debug suite passed 95 cases and skipped the optional RAW test.
- Automated tests cover render and geometry reuse, different edit recipes and resolutions, original refresh, file replacement and removal, least-recently-used eviction, pre-crop backing-store accounting, and cancellation. Native QA opened the Nikon NEF in Fit, switched to 100%, read pixels in the Loupe, and compared the NEF side by side with a PNG.
- In the optimized cache probe, a cold full-size Nikon Z 6 render took 2,005 ms. After a Fit render, five repeat full-size requests returned the same image object with a median lookup of 0.041 ms. The lookup measures the frame cache and file metadata check before proofing, overlays and display.
- The 128 MiB and eight-entry limits cover retained unproofed frames. Active views, in-flight rendering, proofing and warning overlays use separate memory. File changes are detected by path, filesystem identity, size and timestamps on lookup, with explicit refresh as an additional key.

## Auto Curves and Loupe-sampled points

- The optimized feature-only snapshot passed all 99 XCTest cases with the four external RAW samples enabled on Apple Silicon macOS 27.3.
- Three new XCTest cases covered percentile endpoints, flat histograms, anchor rounding, duplicates and point limits, transparent pixels, sampling through crop and flip, matching the staged luminance axis, and stale requests.
- An end-to-end test applied Combined, Separate and a new sampled point as three edits, reopened the library, and undid and redid each operation with one command. The full-size 600 × 320 PNG export matched the Viewer frame byte for byte. The source and managed original hashes were unchanged. The existing format-5 curve recipe holds these edits, with no new catalogue format.
- Native Apple Silicon QA applied both Auto Curves modes and added a red point with the Loupe. Undo and Redo removed and restored it. On the rebuilt app, sampling the same input selected the existing 115 → 120 point without adding history. The signed arm64 build passed verification.
- In Inspector → Adjustments → Channel Curves, use Auto Curves Combined for luminance or Auto Curves Separate for the RGB channels. Both stretch the occupied input range after excluding up to 0.5% of samples at each tail. Select a channel and choose Sample with Loupe, then click the image or use Add Curve Point on the Loupe. Sampling uses the nearest oriented source pixel under the full-size target and measures the selected curve input before proofing. Lens and straighten interpolation can make the displayed RGB readout differ from the sampled input.

## Browser thumbnail reuse

- Four XCTest cases covered cache hits, resolution, edit and revision invalidation, replacement and deletion, least-recently-used eviction, cancellation, shared results, and the decode limit. A thumbnail whose source changed during decoding was rejected.
- A release-mode request replay used 1,200 disposable catalogue records with 2700 × 1800 JPEG fixtures and an exposure edit on every fourth photo. Direct decoding took 822 ms at up to 12 concurrent decodes. The bounded cache took 1,682 ms for the cold pass at three workers. Revisiting the most recent 80 grid thumbnails took 58.3 ms and 80 decodes directly, or 1.5 ms and zero decodes with the cache. This measures thumbnail requests, excluding UI frame timing.
- Native QA opened the disposable catalogue in the signed Apple Silicon build, scrolled the grid forward and back, switched to the list, and opened the Viewer filmstrip. The retained thumbnail budget is 64 MiB and 512 entries, with up to three decodes in flight. Visible and in-flight images use separate memory.

## Browser filter and sort reuse

- Two XCTest cases covered catalogue edits, scope, search, rating, sort direction and selection, including live file appearance and removal for the originals filter, Advanced Search and Smart Albums. The local working-tree suite executed 106 cases with one optional RAW fixture skip and zero failures.
- An optimized probe reused the disposable 1,200-photo catalogue. Over three runs of 200 unchanged name-sorted reads, the median dropped from 454.9 ms for direct filtering and sorting to 0.233 ms for reused results. This measures repeated catalogue reads. A changed query, sort or catalogue still recomputes the result.
- The signed arm64 release archive passed strict verification.

## Grid thumbnail sizes and optimized release

- The Grid preference test covered the standard default, unknown saved values, persistence across reopened workspaces and libraries, an unchanged List layout, and an unchanged catalogue after choosing a size.
- Native QA on the signed 1,200-photo test build chose Compact from the View menu and Large from Settings. The fixed window exposed 14 Standard, 16 Compact and 6 Large photo cards through accessibility. Browser search narrowed the catalogue to a single named photo, and Settings still showed Large after restart.
- The isolated staged release executed 106 XCTest cases without failures or skips, including the four opt-in camera RAW fixtures. The arm64 bundle and signed archive passed strict verification on Apple M5 Pro and macOS 27.3 with Xcode 27.2.

## Folder-based reconnect for referenced originals

- Four new XCTest cases covered nested matches, known names, matching and mismatching fingerprints, duplicate matches, symlink exclusion, shared versions including Trash, reopening, filter refresh, cancellation and a failed catalogue write. Originals and non-destructive edits were preserved.
- Native QA on the signed build reconnected two originals and their shared version through the File menu and folder chooser. The report showed one unmatched original with different bytes and one ambiguous original with two matching copies. The Browser updated its offline badges, the saved catalogue contained the new paths, and all five candidate-file hashes were unchanged.
- The isolated optimized release executed 110 XCTest cases with zero failures or skips, including four camera RAW fixtures. The arm64 app and release archive passed strict signature verification on Apple M5 Pro, macOS 27.3 and Xcode 27.2.
