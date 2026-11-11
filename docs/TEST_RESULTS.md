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

## Folder-based recovery for managed originals

- Repository and workspace tests covered camera filenames and backup storage filenames, shared versions and Trash, wrong bytes, multiple matches, an occupied directory, existing regular files, cancellation, competing installs and retry after a simulated interrupted stage. Reopening preserved edits and recovered files. The operation left catalogue and source bytes intact.
- On the signed arm64 app, File → Recover Missing Managed Originals restored two files and made their shared version available. The result reported a duplicate match and an occupied destination. All five source hashes and the recovered hashes were checked on disk.

## Scoped folder searches

- Workspace tests covered selection with a shared version, an offscreen batch selection, project membership, and saved paths for originals outside the scope. Managed recovery tests confirmed that only requested files were installed.
- The signed app exposed Entire Library, Selected Photos and Current Project in the native folder chooser. Current Project reconnected two originals, including a shared version in another project. The other project's unrelated original remained offline. The saved catalogue confirmed the same paths.
- The managed recovery suite executed 115 tests with the four camera RAW fixtures and zero failures or skips. The scoped release passed strict signature verification.

## Batch consolidation of referenced originals

- Repository tests covered scoped selection, shared versions including Trash, unavailable originals, occupied managed destinations, changed source fingerprints and cancellation. An immutable catalogue forced a filesystem write failure. Retrying reused the verified managed copy and preserved the source file.
- The signed app consolidated two referenced originals and their shared version from a Browser batch selection. A third original was reported as unavailable. The saved catalogue and managed hashes confirmed the results, and all three source hashes remained intact.
- The optimized suite executed 119 tests with zero failures or skips, including the four camera RAW fixtures. The signed arm64 app and archive passed strict verification on Apple M5 Pro with macOS 27.3 and Xcode 27.2.

## Managed original relocation

- Repository tests covered shared and trashed versions, filename conflicts, occupied destinations, cancellation, a rejected destination inside the library, a blocked catalogue write and retry without replacing the verified copy. A simulated cleanup failure retained the managed file.
- In the signed app, File → Relocate Originals converted two managed originals and a shared version to references. It reported a fallback filename for a collision. The saved paths and destination hashes matched the catalogue, the occupied file stayed intact, and the old managed paths were released.

## Referenced original relocation

- Repository tests covered keeping previous external files by default, opting to move them, preserving an aliased file still used by a trashed record, and skipping originals already in the destination.
- The signed app showed the keep-copies option enabled by default. With it disabled, two references and a shared version changed paths. An unselected aliased reference still opened its old source, and the unshared old file was released. Destination and retained-source hashes matched.

## Recent library switching

- Workspace tests covered verified switching, same-name library labels, bounded and deduplicated preferences, failed opening of a missing library, and persistence of the list and startup library. Clearing recents preserved the startup library.
- In the signed app, opening an alternate library populated File → Open Recent Library. The submenu switched back to the original library and cleared the saved list. The active library preference still pointed to the original library.
- The optimized suite executed 126 tests with zero failures or skips, including four camera RAW fixtures. The signed arm64 app and release archive passed strict verification on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Export a project as an independent library

- Repository tests reopened the export after disconnecting the old external original. They checked shared originals, a version whose imported record belonged to another project, named recipes, pixel-for-pixel rendering, regular and Smart Album membership, stack picks, RAW+JPEG pair links and exclusion of unrelated or trashed records.
- The tests also covered cancellation, simultaneous export to the same destination, occupied and dangling-link destinations, missing originals and failed fingerprint checks. The source catalogue and originals were verified unchanged.
- Native QA selected a project, exported it through the File menu, and reopened the destination through Open Isonique Library. The new library showed the project, album, shared version and saved exposure. Its three photo records referenced two local files whose hashes matched.
- The signed Apple Silicon build passed strict verification on macOS 27.3. The optimized test suite executed 129 tests with zero failures or skips, including four camera RAW fixtures.

## Import a project library as a separate project

- Repository tests exported a project and imported it back into the original library twice. They verified remapping for colliding project, photo, original, album, stack, pair and named-recipe IDs, preservation of noncolliding IDs and undo-reserved identities, retained edits and shared originals, scoped Smart Albums and verified reopen.
- Cancellation after the first verified copy left no staged files or catalogue changes. An immutable catalogue forced a save failure after copies had been published, and rollback removed those copies. A retry succeeded. The tests also covered a destination catalogue change during import and corrupt source bytes.
- Native QA imported a library with matching IDs using File → Import Project Library. The separate project and album appeared with distinct names. The saved catalogue had six photo records and four verified originals, with the imported edits and shared-original links intact. Source hashes matched before and after.
- The signed Apple Silicon build passed strict verification on macOS 27.3. The optimized suite executed 135 tests with zero failures or skips, including four camera RAW fixtures.

## Merge an edited project library

- Repository tests covered both matching-photo policies, metadata and edit conflicts, album and stack membership, shared originals, explicit Trash, and absent and moved photos. Wrong project IDs and conflicting fingerprints were rejected. Cancellation and a forced catalogue write failure left the destination catalogue and original files intact.
- In the signed app, File → Merge Project Library added one version, updated one photo and moved one photo into Library Trash. The saved catalogue and original hashes confirmed the changes. The incoming catalogue and files matched their pre-merge hashes.

## Merge review and export membership

- Tests recorded membership in an actual export, removed a previously exported photo, and verified that only matching originals were eligible for inferred Trash. Destination-only additions and photos moved to another project were retained. A declined preview left the catalogue, originals and staging area unchanged.
- Native QA cancelled the merge from its review, then accepted the same plan. The previously exported photo went to Library Trash, the destination-only version stayed visible, and the new version shared the verified original. The saved catalogue matched the reviewed plan and the incoming file hashes were unchanged.
- The signed native Apple Silicon build passed strict verification on macOS 27.3. The optimized test suite passed all 141 tests, including four camera RAW fixtures.

## Three-way project photo merge

- Tests exercised both conflict preferences, matching changes made on both sides, destination-only and imported-only metadata, saved recipes, album changes, shared originals and fallback for a membership-only export. Cancellation and forced catalogue write failure were also exercised with a full edit baseline.
- Native QA reviewed an exposure conflict with Prefer current values selected. The saved library retained the current exposure and keywords and applied the imported rating and flag. Incoming file hashes were unchanged.

## Merge independent adjustments

- Tests reopened a merged project under both conflict preferences. Current Exposure and imported Contrast survived together. Conflicting crop and rotation values came from the same library, as did Levels endpoints. The review named the affected groups.
- The signed app reviewed a crop and rotation conflict and merged with Prefer current values. The Inspector showed Exposure 0.60 and Contrast 1.35. The catalogue retained the crop and orientation, and original file hashes matched in both libraries.
- The optimized suite passed all 144 tests, including four camera RAW fixtures, on Apple M5 Pro, macOS 27.3 and Xcode 27.2. The branding check and signed arm64 build passed.

## Merge stack presentation

- Tests exported and reopened the baseline, then exercised both conflict preferences. A source-only collapse change and album-pick removal survived both preferences. The selected global pick followed the preference, and the destination-only album pick and cross-project stack stayed in place. A separate fixture exercised the previous policy for older exports.
- In the signed app, the review listed one stack update and a conflicting Stack Pick. Prefer current values kept the existing cover and applied the imported collapse. The Browser displayed the collapsed cover, and the catalogue confirmed the album pick was cleared. Source catalogue and original hashes were unchanged.
- The optimized suite passed all 145 tests without skips, including four camera RAW fixtures, on Apple M5 Pro, macOS 27.3 and Xcode 27.2. The branding check and signed arm64 build passed.

## Three-way album definitions

- Repository tests exported and reopened the album baseline, then merged with both conflict preferences. The review identified a regular album name conflict and a Smart Album rule conflict. A destination-only name and an imported compound rule survived together and returned the expected photos after reopening. An older export without the album baseline kept matching definitions and added a new album.
- Tests protected albums shared at export or at merge, including an outside-project member in Library Trash. They also protected library-wide and broadened Smart Album definitions and verified that storage rules exported as fixed memberships stay outside the baseline.
- Native QA caught and corrected stale presentation state in the shared collection sheet. The signed build opened the correct Rename Album and New Album sheets. Using Rename Album and File → Merge Project Library, the review showed a name conflict and a rule update. Prefer current values kept the local name, and the imported rule reduced the Smart Album to the one flagged photo. The saved catalogue retained the regular memberships and both libraries' original hashes matched.
- The optimized suite passed all 149 tests without skips, including four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Whole-library preflight

- Tests compared multiple projects, an empty project, unassigned photos, shared versions and source Trash. Preflight completed with a missing source Originals directory and left both catalogues byte-for-byte intact. Separate cases reported incompatible fingerprints and album types and rejected a symlink to the current library.
- The debug suite ran 152 tests with zero failures and one optional RAW fixture skip. The signed arm64 build passed on macOS 27.3.

## Additive whole-library merge

- Tests reopened a merged catalogue with multiple projects, a scoped Smart Album, a cross-project version sharing a new managed original, a version reusing an existing original, a complete stack and pair, and a referenced source original copied into managed storage. Existing records and source hashes were preserved. Retrying found zero additions and left the destination catalogue byte-for-byte intact.
- Declining the review, cancelling during staging, forcing a catalogue save failure, and modifying the source catalogue during staging left the destination catalogue and originals unchanged. Corrupt referenced originals and stack or edit-history identity conflicts blocked publication.
- The signed app previewed additions across two source projects, then kept the destination unchanged when the review was cancelled. Approval added one project, one album, one photo and one version. The existing photo retained its caption, the new version reused its original, and original hashes matched both catalogues. A separate review named an incompatible original fingerprint and offered only Done.
- The optimized suite passed all 156 tests without skips, including four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Whole-library matching-photo edits and metadata

- Repository tests verified the add-only default, both review preferences, an edit-only merge, cancellation before publication, and preservation of photo identities, album and project membership, and source and destination Trash state. A reopened catalogue contained the selected exposure, crop, saved recipe, rating, flag, color label, caption, keywords and capture date.
- A corrupt source original blocked a combined merge of additions and edits. A corrupt destination original also blocked an edit-only merge. Both tests checked that the catalogue and original-file inventory stayed as they were before the operation.
- The signed app listed Exposure, Rating, Caption and Keywords for one matching photo. Keep Current retained exposure 0.40. Use Imported changed it to 1.15 and saved the listed metadata with zero copies. Both original-file hashes and the source catalogue hash matched.
- The optimized suite passed all 158 tests without skips, including four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Whole-library Trash reconciliation

- Tests covered the unchecked default, exact identity matching, cancellation, repeat merges, and a shared original with an active version. Destination-only photos, photos already in destination Trash, and source-only Trash were retained in their respective libraries. Put Back restored the entire destination photo record after reopening.
- Conflicting original IDs or fingerprints blocked publication. An immutable destination catalogue forced a save failure after staging new originals and verified that both additions and Trash moves rolled back.
- In the signed app, the default kept both photos active. The enabled review listed the exact photo to move. The local-only version remained active and Put Back restored the moved photo with its edits and memberships. The source catalogue and original-file hashes matched their starting values.
- The optimized suite passed all 161 tests without skips, including four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Read-only Empty Library Trash review

- Repository tests covered an empty Trash, an original kept for an active version, one managed candidate shared by two trashed versions, and a referenced original kept in place. Missing files, symlinks and ambiguous names were excluded from the candidate list. Catalogue bytes, managed hashes and referenced contents matched before and after review.
- In the signed app, both the File command and the Trash browser opened the same read-only report. It listed three photo records, one managed candidate, one original kept for the active version, and one referenced original kept in place. All three Trash records and every original file remained in place after closing the review.
- The optimized suite passed all 164 tests without skips, including four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Empty Library Trash and Finder handoff

- Tests reopened the library after a successful move followed by a failed move. Retry moved only the pending original. Another test forced the progress write to fail after a successful move and verified that retry cleared the absent file. A replaced file and a path claimed by a new catalogue record were protected.
- Tests checked that stale reviews and failed catalogue publication never reached Finder. Changed or unavailable originals kept their Trash records. Referenced originals and originals used by active versions retained their hashes after publication, and surviving edit history remained usable.
- In the signed app, the review listed one Finder candidate, one original kept for an active version, and one referenced original. Cancel preserved the three Trash records. An opt-in native test used the system Trash API on a disposable original, checked its hash in Finder Trash, and restored it to the test fixture.
- The optimized suite passed all 169 tests without skips, including the native Finder handoff and four camera RAW fixtures. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Read-only Library First Aid report

- Repository tests distinguished missing managed originals, offline references and untracked files. Shared versions counted once. Trash records and pending Finder moves kept their managed paths out of the untracked list. Tests also covered case aliases, unsafe paths and an absent Originals directory. Catalogue bytes and file contents matched before and after the report.
- In the signed app, File → Library First Aid listed one finding in each requested category. The catalogue records and managed file hashes matched after dismissal.
- The optimized suite passed all 173 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Library First Aid recovery

- Tests recovered a verified managed original and reconnected a verified offline reference in Library Trash. Same-name files with different fingerprints stayed unmatched. An original that went missing after the report and an untracked managed file stayed outside the recovery scope.
- Both entry points rejected a stale report. The publication guard also rejected a stale snapshot after searching for matching originals. Catalogue bytes matched the newer save and no managed copy was published.
- In the signed app, First Aid restored one managed original and reconnected one offline reference. The restored file matched its saved fingerprint, the new reference persisted, and the pre-existing file hashes matched.
- The optimized suite passed all 175 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Untracked file fingerprint inspection

- Tests found renamed files by fingerprint in catalogue records and selected backups. They covered an offline catalogue reference, shared versions, a backup-only match, a same-name mismatch and a file that disappeared after review. An unrelated backup file was outside the inspection scope.
- A corrupt matching backup file failed verification, and a changed catalogue invalidated the reviewed report. Catalogue and file contents matched before and after inspection.
- In the signed app, First Aid displayed one catalogue match and one verified backup file for the same untracked file. The library catalogue, backup catalogue, backup manifest and tested file hashes matched after dismissal.
- The optimized suite passed all 177 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## First Aid quarantine and restore

- Tests quarantined two inspected files and reopened the library. Restore kept an occupied destination intact and returned the other file. Retrying after clearing the destination restored the remaining file under its original name. Catalogue bytes and file fingerprints matched the starting fixture.
- A fresh catalogue check protected a newly claimed original and a pending Finder Trash file. A changed fingerprint blocked a move, and a later catalogue claim blocked restore into the claimed path.
- In the signed app, the quarantine and restore dialogs each listed the reviewed file before confirmation. The restored file returned to Originals with the same hash, and the catalogue contents matched.
- The optimized suite passed all 179 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff. The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2.

## Stale catalogue write protection

- Two independent workspaces opened the same library without changing its existing catalogue bytes. One saved a caption and flag; the other's stale rating edit and Undo were rejected. Both the newer bytes and the rejected workspace's local edit history stayed intact.
- Reload preserved valid project scope and photo selection, read the newer values and saved Undo/Redo history, and let the second workspace save a rating. Reopening showed the rating alongside the first workspace's caption and flag. Reloading an unchanged catalogue kept session history; reloading a missing catalogue kept the current session and did not recreate the file.
- A stale managed import rolled back its copy and kept the source and newer catalogue unchanged. A subsequent import based on the current catalogue succeeded, and its returned revision supported another edit.
- The optimized suite passed all 182 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff.
- In two independently launched copies of the signed macOS app, the second copy rejected a stale three-star edit and displayed the reload instructions. File → Reload Library showed the first copy's five-star rating. A fresh flag edit then saved alongside that rating. Both values persisted, and the original SHA-256 matched.
- The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2. Isonique has one maintained native macOS application in this repository.

## Relocate Originals filename and subfolder preview

- The preview left the catalogue, source bytes and destination folders unchanged. Tests checked catalogue filenames, safe project folder names, numbered filenames with their extensions, capture year/month folders and the fallback for invalid or missing capture dates.
- Two versions of a shared original produced one preview path and one copy. The saved catalogue pointed both versions to that path before source cleanup, and the version in Library Trash kept its edits.
- Tests covered case-equivalent names in the same batch, occupied filenames, storage-name fallback, verified file reuse without replacement, a collision and a symlink introduced after review, and a stale catalogue. Apply never chose an alternate path that the user had not reviewed.
- The optimized suite passed all 186 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff.
- In the signed macOS app, choosing Numbered sequence and Capture year / month previewed one shared original at `2025/03/Original-0001.png` and listed both versions. The catalogue and destination were unchanged at review. After approval, both references used the previewed path, the previous referenced file stayed in place, and both file fingerprints matched.
- The branding check and signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2. This repository maintains one native macOS app.

## Reusable relocation presets and application icon

- Tests saved, reopened, edited and deleted named presets through separate preference instances. They also rejected a duplicate name and ignored an invalid saved template.
- Template validation covered absolute paths, traversal, empty components, package folders, malformed tokens, control characters and excessive expanded lengths. Invalid previews left both the catalogue and destination unchanged.
- Tests checked project and capture tokens, sequence order, stable original names, file extensions and missing metadata. A custom path with an occupied filename previewed a storage-name fallback; apply wrote exactly that path, reused one original for both versions and preserved their edits.
- In a fresh signed app process, the saved preset reappeared after restart. The editor rejected `../escape`. Applying the valid preview copied one file to `Export Session/2025/03/Delivery-Shared-0001.png` and saved that path for both versions. The old referenced file stayed in place and the fingerprints matched.
- The optimized suite passed all 191 tests without skips, including four camera RAW fixtures and the native Finder Trash handoff. Branding and the signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2. The only maintained version is the native macOS app. The signed archive included a readable `.icns` with ten standard and Retina representations from 16 to 1024 pixels.

## Read-only camera and card import

- Mounted media tests read supported photos from DCIM only and skipped symlinks and files outside DCIM. They covered duplicate detection, sidecar metadata, progress, forced managed copies even with a referenced preset, and a card removed before import. Source bytes and directory entries stayed intact.
- Simulated camera transfers covered size verification, matching XMP, RAW/JPEG pairing within the same camera folder, distinct files with the same name in another folder, per-file progress, staging cleanup, and cancellation after an earlier photo committed. Unsafe camera catalogue paths were rejected.
- In the signed native app, Isonique discovered a disposable read-only disk image as mounted media. The existing Load Preset action restored the prefix and import settings. Import produced one managed original in the new project, preserved the card file and image hashes, and read the sidecar caption and rating.
- All 195 release tests passed without skips, including four camera RAW fixtures and the native Finder Trash handoff. Branding and the signed arm64 build passed on Apple M5 Pro, macOS 27.3 and Xcode 27.2. This repository maintains one native macOS app. No physical USB camera was attached; native PTP session and download behavior on hardware remains unverified.

## Camera and card thumbnail selection

- Core tests verified that a selected card import reports progress for the selected files, keeps completed photos after cancellation, detects an unavailable card, and can retry after a fresh scan. The retry skipped the completed duplicate and imported the other selected file. A thumbnail test verified the requested size bound.
- Simulated camera tests verified that selecting a JPEG excludes its unselected RAW companion and an identically named photo in another folder. The importer requested the selected JPEG and its matching sidecar. A separate test verified that disconnect stops the transfer, keeps the completed photo, and lets a fresh catalogue import a newly selected file.
- In the signed app, a read-only mounted disk image displayed two thumbnails. Select All, Deselect All and individual checkboxes updated the count. Cancelling the browser left the catalogue empty. Ejecting the volume cleared an active selection, and remounting allowed a fresh selection. Import copied only the selected PNG, applied its XMP caption and preserved the disk image and source file hashes.
- All 198 optimized tests passed without skips, including four camera RAW fixtures and the Finder Trash handoff. Branding and the signed arm64 build passed on macOS 27.3 with Xcode 27.2. The native macOS app is the sole maintained version. Physical PTP camera thumbnail and reconnect behavior remain unverified.

## Physical PTP checkpoint preflight

- The Mac’s USB device inventory listed controllers only, and no physical camera was available. Hardware checks for thumbnails, selected import, active transfer cancellation and reconnect remain pending. [Physical PTP camera checklist](../VALIDATION.md#physical-ptp-camera-import)
- On macOS 27.3, the signed arm64 app showed the empty device browser and disabled Import Options. Refresh preserved the empty state, and Cancel returned to the disposable library with zero photos in its catalogue.
- All seven focused camera and card release tests passed. Those tests cover simulated transfers and file-based media.

## Tethered capture evaluation

- The ImageCaptureCore probe type-checked the remote and on-camera shutter capability checks, the remote shutter call, and the new-item callback against the macOS 14 arm64 target using Xcode 27.2. This checked API availability. Physical shutter execution and native callback delivery remain pending. [Tethered capture evaluation](IMPLEMENTATION_PLAN.md#tethered-capture-evaluation)
- Simulated arrivals passed selected new files through the production camera importer. The initial catalogue photo was excluded, the new photo and XMP caption were saved, and replaying the event downloaded the files again but created no duplicate catalogue record. Both runs removed their staging directories.
- Two simulated arrival batches for a JPEG and its RAW companion saved both files as independent originals. A separate existing test confirmed pairing when both arrive in a single batch. The simulation used synthetic image bytes and logical camera filenames to exercise pairing.
- All 200 optimized XCTest cases passed without skips on native macOS arm64, including the four external RAW fixtures and Finder Trash handoff.

## Simulated tethered capture prototype

- The controlled transport verified that a second shutter request is rejected while a shot is active. Duplicate notifications within a shot and replays after completion caused no extra downloads. Separate RAW and JPEG notifications paired after the simulator ended the shot, and the RAW primary preference was respected.
- Cancelling during a transfer preserved the earlier complete import and cleared both staging folders. Disconnecting during an open shot cancelled it. Reconnect excluded the fresh catalogue baseline and ignored late events from the old connection.
- In the signed macOS app, the simulator imported one JPEG per completed shot. Cancel Shot produced no import, Disconnect disabled Capture, and double-clicking Capture after reconnect imported one fresh file. The disposable library contained the two expected originals with matching catalogue hashes.
- All 203 optimized XCTest cases passed without skips on native macOS arm64, including the four external RAW fixtures and Finder Trash handoff. Branding and signed release packaging passed. The simulator supplies the shot-complete signal. Native PTP events and physical shutter behavior remain pending.

## Native ImageCaptureCore tethered capture and device selection

- Capability tests accepted the Mac-triggered shutter flag and rejected empty and camera-button-only capability lists. Simulated file additions used the production grouping policy and camera importer. A RAW and JPEG from separate callbacks linked in the saved catalogue, a leading XMP supplied metadata when sidecar reading was enabled, and replays, a late companion for a previous shot and a different folder's file were excluded. A stream with only replays and sidecars timed out. Cancellation discarded pending files and late callbacks. Reconnect used a fresh catalogue.
- In the signed macOS app without a physical camera attached, File → Tethered Capture showed the unavailable state and disabled Connect and Capture. The same app discovered a read-only test card. Its selection started empty, Deselect All disabled Import Options, and unchecking one photo after Select All left one photo for import. The catalogue and managed directory held only the checked PNG. The managed original matched the source and the card image and source file hashes matched their baselines. Simulated camera import tests verified that an unchecked RAW companion and an unchecked JPEG in a different folder were excluded.
- All 207 optimized XCTest cases passed on the sole maintained app, native macOS arm64 on Apple M5 Pro with macOS 27.3 and Xcode 27.2. The suite included four external RAW fixtures and the Finder Trash handoff. Branding passed, and the release archive passed strict signature verification with the Hardened Runtime and the Photos Library entitlement.
- The Mac's USB inventory listed controllers only. Camera thumbnails, permission and session behavior, shutter execution and actual RAW/JPEG arrival timing still need a physical PTP camera. [Physical tethered capture checklist](../VALIDATION.md#physical-tethered-capture)

## Capture date and time correction

- Tests covered relative shifts across midnight and a daylight-saving transition in camera wall-clock time. They verified missing and malformed values, leap day, out-of-range results, no-op previews and exact assignment to undated photos.
- Workspace tests verified visible selection scope, selection of a dated reference, preservation of a shared version's independent date, date sort and Smart Album updates, stale dialog rejection and one-step Undo/Redo after reopening. Empty Trash history pruning retained surviving dates in a grouped change. Backup and restore preserved a pending Redo.
- Export tests verified corrected EXIF capture times in adjusted JPEG, PNG and TIFF, EXIF exclusion when disabled, byte-exact original export, and unchanged managed and referenced original fingerprints.
- In the signed native app, Metadata → Adjust Date and Time rejected February 30 and previewed a two-photo change. Applying the correction preserved a 20-second interval and left the third photo's date alone. The Edit menu undid and redid the batch. The Info action showed the corrected value, and cancelling its review left the catalogue dates unchanged. The imported and managed originals matched their source hashes.
- All 211 optimized XCTest cases passed without skips, including four RAW fixtures and the Finder Trash handoff. Branding and strict signature verification passed for the sole maintained app, native arm64 on Apple M5 Pro with macOS 27.3 and Xcode 27.2.
- Physical camera checks remain pending. This checkpoint used generated JPEGs and a disposable library.

## Batch caption and keyword editing

- Preview tests covered independent caption and keyword edits, multiline captions, empty replacements, comma and whitespace handling, case-insensitive and Unicode-equivalent duplicates, and no-op appends. Existing keyword order and spelling were retained.
- Workspace tests covered visible batch selection, deselected photos, another project, Library Trash and a sibling version sharing an original. The preview left the catalogue untouched. Applying used the reviewed IDs even after the selection changed. A stale review was rejected without changing the catalogue or history.
- Reopening preserved the updated fields and Smart Album results. One Undo restored both photos and one Redo reapplied both edits. Disabling persistent history kept the existing catalogue format. Empty Trash removed the purged photo's history values while preserving Undo and Redo for the surviving photo.
- In the signed app, Shift-Command-B opened the editor for two selected photos. The preview showed the different appended lists and the shared caption. The Edit menu undid and redid the batch. The selection bar reopened the editor, and cancelling a replacement preview kept the appended values. The third photo's catalogue metadata and all three managed original hashes were unchanged.
- All 215 optimized XCTest cases passed without skips, including four RAW fixtures and the Finder Trash handoff. Branding and strict signature verification passed for the sole maintained app, native arm64 on Apple M5 Pro with macOS 27.3 and Xcode 27.2. Physical PTP checks remain pending.

## Reusable keyword groups and quick assignment

- Tests verified group creation, trimming, case-insensitive duplicate names, Unicode-equivalent keyword deduplication, renaming, deletion and active-group fallback. A fresh workspace opened another library with the same groups and visibility preference.
- Single-keyword and whole-group tests checked visible selection, preservation of captions, an unselected sibling version, another project and Library Trash. Reapplying a group with no new keywords left the catalogue and history unchanged. Reopening preserved the assigned keywords, and one Undo/Redo affected the whole group assignment even after its definition was deleted.
- In a signed app copy with isolated preferences, the Metadata command created a group from three entries and the toolbar showed two distinct buttons. With no batch selection, assignment was disabled. A single keyword button and Apply Group updated the selected photos, and the Info inspector reflected one-step Undo/Redo. The group and controls reappeared after relaunch. The unselected photo's keywords and all three managed file hashes matched their baselines.
- All 218 optimized XCTest cases passed without skips, including four RAW fixtures and the Finder Trash handoff. Branding and strict signature verification passed for the sole maintained app, native arm64 on Apple M5 Pro with macOS 27.3 and Xcode 27.2. Physical PTP checks remain pending.

## Quick keyword removal and shortcuts

- Tests verified case-insensitive removal across the visible selection, including equivalent Unicode spellings, without changing other keywords or captions. A repeated removal created no extra history. One Undo and Redo covered the entire selection.
- Shortcut tests checked active group order, missing slots, hidden controls, empty selections and unrelated modifiers.
- In a signed app copy with isolated preferences, Option–1 and Option–Shift–1 worked in the Grid Browser, List Browser and Viewer. The Grid batch used one Undo and Redo for both selected photos. Caption and Search received their normal Option-key characters, and clicking the Viewer image restored shortcut focus. Shift-click removed the keyword. The final catalogue values and all three original file hashes matched their baselines.
- All 220 release tests passed, including the RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Reusable keyword vocabulary and regional English

- Tests verified persistence across libraries, sibling deduplication by case and equivalent Unicode spelling, duplicate names in separate branches, merge order, editing and invalid file handling. Export and import into fresh preferences preserved the hierarchy and term spelling.
- In the signed app with isolated preferences, a text list with duplicate branches imported as one branch. The exported list matched the expected tab-indented text, and importing it again added zero keywords. A child term applied to the selected photo. The vocabulary survived relaunch, and child creation and renaming worked in the editor.
- With macOS set to British English, the signed app displayed “Colour” and “Grey” in the Metadata menu and “Colour Proofing & Lens” in the Inspector. A US English override for the test app displayed the corresponding US spellings. The system language setting was left at British English.
- All 223 release tests passed, including the RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Hierarchy-aware keyword assignment and search

- Tests covered duplicate prevention, same-name terms in separate branches, precise removal, persistent Undo/Redo, exact and branch rules, and flat keyword compatibility. Removing a vocabulary branch kept its assigned paths and ancestors available for search. A path rule saved without any assigned photos upgraded the catalogue to format 10 and reopened with its path intact.
- In the signed app, applying Places › London to one photo and People › London to another produced separate results in Find Photos. Advanced Search matched the Places branch. A plain London search also found the third photo, which had an existing flat London tag. The catalogue stored both paths separately and retained the flat tag.
- The native Window menu showed Centre and Minimise under the Mac’s British English preference, and Center and Minimize with a US English override on the disposable test copy.
- All 226 release tests passed, including RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## XMP keyword hierarchy exchange

- Exported a rendered JPEG and a byte-for-byte original with XMP sidecars, imported both into separate libraries and reopened the catalogues. The two London paths, independently assigned flat keywords, caption and rating survived. ImageIO confirmed that the JPEG still carried flat IPTC keywords, including one London entry for both paths. An older preset decoded and exported IPTC without a sidecar.
- Tests covered embedded TIFF XMP, bare RDF with alternate namespace prefixes, duplicate path handling, absent and explicitly empty fields, invalid hierarchy data, literal pipes in names and existing sidecar collisions. An image write failure removed its newly created sidecar.
- In the signed macOS app, exported a JPEG with IPTC and an XMP sidecar. File → Import XML / XMP Metadata applied the sidecar to a second photo. Info and the saved catalogue showed Places › London and People › London alongside the original flat tags from the sidecar.
- All 229 release tests passed, including RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## IPTC title, creator, copyright and credit

- The batch test verified field-by-field preview and clearing, rejection of a stale preview, selection scoping, and one-step Undo and Redo after separate catalogue reopens. Project merge tests verified independent field changes and the preservation of current values when an older source has no IPTC fields.
- Embedded IPTC import, legacy export inheritance and edited JPEG IPTC were verified against ImageIO. Rendered JPEG and byte-for-byte original exports round-tripped the four fields through XMP sidecars. Tests covered ordered creators, Unicode, omitted fields and explicit clears, including empty XMP credit in both element and attribute form.
- In the signed macOS app, saved an individual title edit from Info, then previewed and applied a title replacement and credit clear to two of three selected-library fixtures. Undo restored the prior title and credit, and Redo reapplied both changes. The saved catalogue retained both creators and copyright on all three photos. The unselected photo and original file hashes were unchanged.
- All 233 release tests passed, including four checksum-verified RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## IPTC search and reusable metadata presets

- Quick Search matched each of the four stored IPTC fields. Advanced Search tested field-specific comparisons, diacritic-insensitive matching and matching each creator separately. A saved IPTC rule upgraded an empty library to format 12. Smart Album membership followed edits, persistent Undo and Redo after reopening.
- Presets survived reopening in another library. Tests covered empty and duplicate preset names, preview and application to the chosen photo, preservation of unchecked fields, duplicate-free keyword append, Undo/Redo and preset deletion. Import tests verified older settings decode, a saved import setup retains the preset snapshot and matching XMP overrides only fields it supplies.
- In the signed macOS app, Quick Search found a photo by IPTC title. Advanced Search offered all four IPTC fields and saved a title rule as a Smart Album with one matching photo. A credit-only preset saved and reloaded in Batch Change, then applied to that photo and to a separate photo through Import Options. The saved catalogue confirmed the expected credit, the untouched fields and the import original's matching fingerprint.
- All 238 release tests passed, including four checksum-verified RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2. All local Markdown document links resolved after the parity records were renamed.

## Selective IPTC Lift and Stamp and inherited IPTC review

- The mixed Stamp test applied a recipe group, a title, ordered creators and an explicit credit clear to the visible batch selection. It excluded hidden and trashed photos, skipped no-op repeats and restored all changes together after reopening. Undo kept later changes to unselected fields. Tests also covered inherited lift values, unavailable fields and pruning a purged photo from grouped history.
- The inherited IPTC scan read each shared original once. Tests covered offline and fingerprint-mismatched originals, cancellation, stale metadata, retained overrides and explicit clears, catalogue persistence, search, and Undo/Redo. Original bytes matched before and after the review and apply.
- In the signed app, the Photos shortcuts lifted a source and stamped a title and credit clear onto two selected photos. One Undo and Redo restored and reapplied the batch. The Metadata review added Bravo’s missing title and copyright. Quick Search found the saved title, and the catalogue retained the credit clear. All managed original hashes matched.
- All 242 release tests passed, including the four verified RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Read-only EXIF in Info

- The JPEG test covered all five fields on a rotated original, a partial EXIF record, a photo with no capture settings, and offline, unreadable and restored references. It checked the catalogue bytes and original fingerprint before and after reading. A separate test covered valid APEX fallbacks, auxiliary lens metadata and invalid numeric values.
- The RAW workflow checked capture settings on Sony ARW, Canon CR3, Nikon NEF and Ricoh DNG files alongside the existing preview and export checks.
- In the signed app, Info → EXIF stayed open across selection changes. It showed the rotated JPEG and Sony RAW values, displayed unavailable fields for a partial JPEG and showed a distinct message for an offline reference. The catalogue bytes and original fingerprints matched after inspection.
- All 244 release tests passed, including four RAW fixtures and Finder Trash handoff. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Configurable metadata views in Info

- Preference tests verified custom fields and order, renaming, active view restoration across libraries, duplicate-name validation, access to every built-in view, and fallback to General after deleting the active view. Customising the views left the catalogue bytes unchanged.
- In the signed app, created Shoot Notes and reordered its fields to ISO, Caption and Lens. After quitting and reopening, Info restored the custom view and the same order. A caption edited from that view persisted. General, EXIF Info, IPTC Core and Caption & Keywords were all available. Collapsing and reopening General’s IPTC section retained an unsaved draft.
- All 246 release tests passed, including the four RAW fixtures and Finder Trash handoff. An older IPTC batch assertion now identifies its preview rows by photo ID to handle tied import times. The arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Catalogue-backed EXIF search

- Query tests covered numeric equality and inclusive bounds, fractional shutter speeds, optional units, invalid values, case- and diacritic-insensitive lens matching, and presence rules. Partial and unindexed records were excluded from ordinary comparisons, including negative comparisons. Saving an EXIF rule upgraded an otherwise empty catalogue to format 14.
- A rotated JPEG was indexed on import. Backfill tests covered selected versions of a shared original, partial and empty EXIF, and an offline reference. After reopening, a saved rule still matched the indexed photo with its original offline. Undoing an older photo edit preserved the indexed values. Original bytes matched before and after backfill.
- In the signed macOS app, Metadata → Catalogue EXIF from Originals indexed one selected photo. Advanced Search offered all five EXIF fields, accepted a 1/125-second rule and saved it as a one-photo Smart Album. After moving the disposable original out of the library and reloading, the same photo still matched and the Browser identified its original as unavailable.
- All 250 release tests passed, including Finder Trash handoff and catalogue indexing of four checksum-verified RAW fixtures (Sony ARW, Canon CR3, Nikon NEF and Ricoh DNG). The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Read-only GPS in Info

- Parser tests covered fractional degrees, all four hemisphere references, signed inputs consistent with the reference, geographic bounds and zero. They rejected missing or contradictory references, partial pairs, out-of-range and non-finite numbers, and non-numeric values.
- Integration tests read a referenced JPEG and a managed TIFF, checked a JPEG without GPS, and distinguished missing originals from an unreadable file. Coordinates returned after restoring each original. Catalogue bytes and original fingerprints matched before and after inspection. Info preference tests verified that a custom mix of GPS, EXIF and editable fields kept its order across workspaces and that the GPS preset remained available.
- In the signed macOS app, the GPS picker showed separately labelled latitude and longitude for northern/western and southern/eastern fixtures. It displayed distinct messages for untagged, unreadable and offline originals. Restoring the offline reference and reloading the library restored the readout. The fixture catalogue and file hashes matched after the run.
- All 253 release tests passed, including the four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Catalogue-backed GPS indexing and search

- Tests verified automatic indexing on JPEG import, selective backfill of a format 14 catalogue, shared versions, an untagged original and rejection of a replaced original. A saved GPS rule upgraded an empty catalogue to format 15. Undoing an edit made before backfill preserved the GPS index.
- Query tests covered signed comparisons, bounds, coordinate entry with a decimal comma and degree symbol, distinct missing and unindexed states, and a radius crossing the date line. After the indexed original was moved offline and the catalogue reopened, the saved rule matched both versions without checking original availability.
- In the signed macOS app, Metadata → Catalogue GPS from Originals indexed one selected reference. Advanced Search saved a ten-kilometre Smart Album. After removing the reference and reloading, the Smart Album retained its match. A separate longitude search still returned the offline photo. All disposable originals matched their initial hashes after the run.
- All 256 release tests passed, including the four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Places map browsing

- Workspace tests verified library and project membership, shared-coordinate pins, preservation of the selected version, rejection of an out-of-scope pin, and filtering in Places versus Grid. After removing a referenced original and reloading, both versions retained their map location and the selected version could still open in the Viewer. The catalogue bytes matched after browsing.
- Framing tests covered widely separated points and a wrapped bounding rectangle across the date line.
- In the signed macOS test app, Control–M opened Places with the London and Sydney pins visible together. Selecting the Sydney pin updated the Inspector. After moving the London original offline and reloading, selecting its pin updated the Inspector and the thumbnail showed that the original was unavailable. Each project displayed its own pin, Back returned from the Viewer to Places, and All Photos restored both pins. The catalogue and original hashes matched after inspection.
- All 258 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Non-destructive location assignment and clearing

- Workspace tests verified batch assignment to the visible selection in one history step, per-version overrides, stale and unchanged edits, and invalid coordinates. Reopening preserved the assignment, the explicit clear and their Undo/Redo history. Places and radius and missing-location Smart Albums followed the effective location while the original was offline.
- Backfill tests verified that an explicit clear survives GPS indexing and that a sibling version can still use the embedded location. Merge tests verified that explicit clears and resets survive the relevant conflict policy and that older exports preserve the current location edit.
- In the signed macOS test app, the Metadata command assigned new coordinates to an offline photo and moved it out of the London radius album. Undo and Redo changed membership, and Places grouped it at the new location. Clearing from Info removed the photo from Places and added it to the missing-location album. A second app instance reopened the catalogue, undid and redid the clear, and used the original location to restore the London pin. The coordinate fields exposed separate accessibility labels and all original file hashes matched.
- All 262 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Map-based location assignment

- The integration test projected a known map point to the native view and converted it back to coordinates. It verified that a cancelled draft did not change the catalogue bytes or history, then confirmed that only the selected version joined Places and a radius Smart Album. Undo and Redo removed and restored the match.
- In the signed macOS test app, clicking the map moved the preview pin and populated both fields. Using the zoom control and dragging the map kept the selected coordinates. Cancel left the catalogue and originals byte-for-byte unchanged. Confirming the pick for a version sharing an original removed only that version from its previous radius album and added a separate pin in Places. Undo and Redo combined and separated the pins again. The saved catalogue contained the picked coordinates only on the selected version, and original hashes matched.
- All 263 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Address and place-name lookup

- Automated tests covered result selection, rejection of an outdated result, cancellation followed by a late response, no matches and a simulated unavailable connection. After the simulated connection failure, a manual coordinate edit saved and reloaded from the catalogue.
- In the signed macOS test app, Apple Maps returned a named place and a street address. Selecting the named place filled both coordinates and updated the open preview map. Cancelling the sheet preserved the catalogue bytes and originals. Pressing Return in the search field with valid manual coordinates already entered submitted the address lookup. The address result saved on confirmation. After a separate no-results search, manually entered coordinates saved on the selected photo. All original hashes matched.
- All 269 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Saved named places

- Automated tests covered name validation and duplicates, persistence across preference instances, reuse across libraries, renaming with stable identity and coordinates, and removal. Creating a saved place kept the source catalogue byte-for-byte intact. The destination catalogue saved the assignment only on confirmation and retained it after the saved place was renamed and removed.
- In the signed macOS test app, saved a place from one photo, cancelled the assignment sheet and verified the catalogue hash. After relaunch, selected the saved place and assigned it to a second photo. Renamed and removed the entry from the menu. The catalogue retained the second photo’s assigned coordinates and all original file hashes matched.
- All 271 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## GPX track matching

- Parser tests covered GPX 1.0 and 1.1, explicit timestamp offsets, fractional seconds, exact and interpolated fixes, maximum gaps, antimeridian crossings, conflicting fixes, malformed files and cancellation. Segment boundaries, invalid fixes and clock resets interrupted interpolation. Photos outside a track remained unmatched.
- Workspace tests covered camera time zones and daylight-saving transitions, preview and cancellation with identical catalogue bytes, per-photo exclusion, stale selection and capture times, and a single persisted Undo/Redo step. Places and GPS Smart Albums updated after reopening, including for a photo with an offline original.
- In the native macOS test app, the Metadata command opened a GPX file and previewed exact, interpolated and missing-time rows. A 15-second gap limit suppressed the interpolated result. Cancel preserved the catalogue and original file hashes. Reopening the preview, unchecking a match and applying changed one photo. Undo and Redo worked and Places displayed the updated pin. Original file hashes still matched.
- All 279 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Project GPX track overlays in Places

- Parser and MapKit tests covered untimed coordinates, broken segments, the antimeridian and overlay rendering. The workspace test verified project isolation, visibility under photo filtering, and overlays in a project with no photos. It reopened a hidden route after deleting the test GPX file, then verified that showing and removing the route left the photo location and its persisted Undo/Redo history intact.
- Catalogue tests reopened a format 16 library, added a track in format 17 and verified that a project library export and import retained the route and its visibility. Removing the imported copy preserved the source project's route.
- In the native macOS test app, imported a route and used Fit Map to display the line alongside the assigned photo pin. A second project showed only its own pin. Hid the route, renamed the source file and relaunched. Show Track restored the route from the catalogue. Cancelling removal kept the route visible. Confirming removal cleared the route and preserved the photo pin, catalogue location fields and original file hashes.
- All 283 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Manual GPX waypoint assignment in Places

- Parser and catalogue tests covered named and unnamed waypoints, waypoint-only files, invalid coordinates, GPX 1.0 and 1.1, and format 17 track compatibility. Waypoints survived reopening and project export and import in format 18.
- Workspace and MapKit tests verified project scope, photo filters, waypoint marker selection, selection of an untagged version and exclusion of sibling, trashed and out-of-project versions. Cancellation preserved catalogue bytes. Assignment created one persisted Undo step and left original file bytes intact.
- In the native macOS app, opened the preview from a waypoint pin and cancelled it after selecting two photos. The catalogue location fields matched the baseline. The other project displayed its own pin. Reopened the preview from the track submenu, chose a different waypoint, assigned two checked versions and verified one-step Undo and Redo in Places. The other project's photo location and the original file hashes matched the baseline.
- All 284 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Project location assignment in Places

- Workspace tests covered project scope, versions hidden by browser filters, shared originals, and a read-only preview with unchanged catalogue bytes. The fixture verified that existing assignments, embedded GPS on both indexed and legacy originals, manual clears, and versions with unverified GPS were preserved. A version with an indexed missing location could be assigned while its original was offline. A newer location saved after preview prevented the assignment.
- In the native macOS app, the project preview listed both eligible versions and counted an existing location and a manual clear separately. Cancel left the catalogue byte-for-byte intact. The map showed the proposed pin before applying. One Undo removed both new assignments, and Redo restored them. The existing pin, other catalogue photo records and original file hashes matched the baseline.
- All 286 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## GPS in edited exports

- Reopened JPEG, PNG and TIFF exports to check assigned coordinates, embedded GPS, catalogue-only coordinates, and embedded GPS on older unindexed photos. A new assignment discarded the original altitude. Matching embedded GPS kept it. Clearing the location or turning GPS off omitted the GPS dictionary with EXIF and IPTC still enabled. Original exports of assigned and cleared versions matched the source bytes.
- In the native macOS app, exported assigned, cleared and embedded versions of one JPEG as a batch. Read the output GPS with Image I/O. The enabled batch contained the two expected locations, and the disabled batch contained no GPS. All three original copies matched the source bytes. The source and catalogue hashes also matched their baselines.
- All 287 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Batch export naming templates and preview

- Tested case and Unicode collisions, pre-existing numeric suffixes, mixed original extensions and matching XMP sidecars. The batch wrote exactly the previewed names and each original copy matched the source bytes. Reusing the same output folder was refused.
- Loaded a preset saved before filename templates and verified its numbered version names and TIFF size setting. Saved and decoded a new preset with all eight tokens, then reopened the TIFFs from both plans to verify their format, dimensions and previewed paths. Tested unsafe patterns, unknown tokens and multibyte filename limits.
- The native macOS app built and launched with a disposable test library. macOS ScreenCaptureKit could not capture its window, so manual checks of the sheet, preset controls and destination picker remain pending.
- All 290 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## TIFF compression choices

- Exported the same rendered image with None, LZW, ZIP and PackBits compression. Image I/O reported the requested compression tag for every file, and decoded RGBA pixels matched the render byte for byte.
- Decoded a preset created before the compression field existed and verified that it exported an uncompressed TIFF. New presets preserved their selected compression through JSON encoding and decoding. Exporting every compression mode left the managed original byte for byte unchanged.
- All 291 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## HEIF export

- Confirmed that the installed Image I/O encoder advertises `public.heic`. Single and batch exports produced `.heic` files that reopened as HEIC images, and changing the HEIF quality changed the encoded output.
- HEIF passed the existing metadata controls with EXIF, IPTC and GPS enabled and disabled. Corrected capture dates, catalogue GPS, explicit location clears and clipping-warning isolation use the same behavior as JPEG, PNG and TIFF.
- A full-quality HEIF export kept the full-size renderer dimensions. Its decoded 8-bit RGBA pixels stayed within an average difference of four levels and a maximum difference of 48 levels from the full-size preview. The export preset and batch filename survived encoding and decoding, and the managed original remained byte for byte unchanged.
- All 292 release tests passed, including four RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## Text watermarks

- Verified top-left, top-right, centre, bottom-left and bottom-right placement from changed-pixel bounds. Lower opacity produced a smaller pixel delta, and larger relative scale covered more pixels.
- Saved and reopened watermark text, position, opacity and scale in an export preset. A preset created before the watermark field still decoded with watermarking disabled.
- JPEG, PNG, TIFF and HEIF exports contained the watermark. PNG output matched the shared preview renderer pixel for pixel. A two-version batch produced the same previewed pixels for both files, while edited and original exports left the managed original byte for byte unchanged.
- All 294 release tests passed, including four verified RAW fixtures and Finder Trash handoff. The branding check passed and the arm64 archive passed strict signature verification on macOS 27.3 with Xcode 27.2.

## External editor round trip

- Five repository tests rendered the current recipe into the staged TIFF, replaced it with a simulated editor return and reopened the saved library. The imported derivative retained project, album, caption and keyword context, while its own managed TIFF and neutral recipe kept full-size PNG export pixels identical to the preview renderer. The source original stayed byte for byte unchanged.
- Cancellation removed only the isolated handoff. Missing, unchanged and non-TIFF returns left the catalogue unchanged. A competing catalogue save rejected the stale import and removed its installed copy. A simulated editor-launch failure removed the handoff, persisted no photo and reported the failure. The external-editor application choice survived a fresh workspace.
- All 300 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured in this run. The branding check passed. The native Apple Silicon release app built and its archive passed strict signature verification. No third-party editor was driven interactively, so the real application's save-in-place behaviour remains a manual compatibility check.

## Contact sheets and printable proofs

- Core tests covered a 13-photo landscape A4 contact sheet across three pages, exact margin bounds, a two-page single-photo proof, all caption sources and print-preset JSON round trips. A Letter PDF reopened with the expected page count and media box.
- Rendered PDF tests exercised sRGB, Display P3 and monochrome output. Colour pages retained differentiated RGB channels, monochrome pages rendered equal RGB channels, and an adjusted photo flowed through the shared full-resolution renderer. Save PDF refused an occupied destination. Catalogue records and every managed original remained byte for byte unchanged.
- Workspace tests verified current-project scope and explicit batch selection, persistent reusable print presets, landscape paper configuration and creation of a PDFKit-backed native `NSPrintOperation` without opening a printer dialog.
- All 305 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured in this run. The branding check passed and the native Apple Silicon release archive passed strict signature verification. A disposable-library launch reported one visible arm64 Isonique window. The native print operation was constructed but no physical printer or driver-specific colour path was available.

## Non-destructive spot removal

- Core rendering tests exercised separate Repair and Clone results, multiple ordered spots and a destination clipped by the top-left image edge. Source-to-Viewer coordinate round trips covered crop, quarter rotation, both flips, straighten and lens correction.
- Format 19 round trips retained spot IDs, modes, source and destination points, and sizes. Older recipes decode with no spots. Presets preserve spots, while Lift and Stamp copies them only through the separate Spot Removal group.
- Workspace tests created Repair and Clone spots, moved a source, changed size and mode, deleted a spot, and exercised one-step Undo and Redo before and after reopening persistent history. A source click without a destination remains a transient draft and does not write history.
- A full-size PNG export matched the shared Viewer render byte for byte. Edited and original exports left both the imported source and managed original hashes unchanged; original export remained a byte-for-byte copy.
- All 309 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured. The branding check passed, and the arm64 release app and signed archive built successfully. A disposable-library launch reported one visible Isonique window from the arm64 process. The native Apple Silicon macOS app is the sole maintained version; no web, mobile or separate desktop implementation exists. Testing used the Apple M5 Pro and 24 GB unified memory. Interactive source/destination pointer placement remains a manual QA check.

## Sharpening and luminance noise reduction

- Synthetic flat fields remained byte-for-byte unchanged with maximum global sharpening, edge sharpening and luminance reduction. Global and edge sharpening increased contrast on both sides of a controlled boundary while leaving distant flat pixels unchanged.
- Alternating luminance noise was reduced to less than 15% of its original variance while red-green and green-blue differences stayed within one 8-bit level. A high-contrast boundary remained unchanged by reduction.
- Format 20 retained all three values. Empty and older recipes decode neutral values without upgrading; a version-19 catalogue carrying Detail values is rejected. Presets preserve Detail, and Lift and Stamp changes it only through the separate Detail group.
- Workspace tests applied each control as an independent history entry, reopened persistent history, then undid and redid all three. A full-resolution Viewer cache frame matched edited PNG export byte for byte. Source, managed-original and original-export fingerprints remained unchanged.
- All 313 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured. The branding check passed, the arm64 release app and signed archive built successfully, and a disposable-library launch reported one visible arm64 Isonique window. The native Apple Silicon macOS app is the sole maintained version; no web, mobile or separate desktop implementation exists. Fixed-radius kernels were tested on generated 8-bit sRGB fixtures; large-file performance, colour-noise reduction and adjustable radius or threshold controls remain open.

## Chromatic aberration, vignette and devignette

- Synthetic red and blue boundaries verified independent Red/Cyan and Blue/Yellow correction in both radial directions. Green stayed unchanged, output dimensions were stable and maximum correction safely clamped samples at the image edge.
- Uniform fixtures verified that Vignette and Devignette leave the centre unchanged while darkening or brightening corners respectively. Neutral values bypassed each operation without changing pixels.
- A combined crop, quarter rotation, horizontal flip, straighten and radial-distortion recipe retained its geometry. Because Vignette runs after geometry, the final output corner darkened relative to the same rendered frame without Vignette.
- Format 21 retained all four controls. Empty and older recipes decode neutral values without upgrading; a version-20 catalogue carrying Lens & vignette values is rejected. Presets preserve the group, and Lift and Stamp changes it only when Lens & vignette is selected.
- Workspace tests applied four independent history entries, reopened persistent history, then undid and redid each value. A full-resolution 192 × 112 Viewer frame matched PNG export byte for byte. Source, managed-original and original-export fingerprints remained unchanged.
- All 318 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured. The branding check passed, the arm64 release app and signed archive built successfully, and a disposable-library launch reported one visible arm64 Isonique window. The native Apple Silicon macOS app is the sole maintained version; no web, mobile or separate desktop implementation exists. Automatic profiles, optical calibration, adjustable vignette shape and large-file performance remain open.

## Kelvin white balance and neutral sampling

- Neutral 6500 K recipes bypassed processing byte for byte. Directional fixtures verified that higher Kelvin warms red relative to blue and positive Tint raises red and blue relative to green. Older JSON without a Kelvin field decoded neutral, while existing normalized Warmth recipes retained their prior rendering and displayed an equivalent Kelvin value.
- The full-resolution Viewer Loupe sampler derived Kelvin and Tint from a mild colour cast and produced an output neutral to within two 8-bit code values. It followed horizontal-flip geometry, rejected a clipped target and rejected a transparent target. A neutral sample returned exactly 6500 K and zero Tint.
- Format 22 persisted Kelvin and Tint and rejected a non-neutral Kelvin recipe mislabeled as format 21. White Balance Lift and Stamp includes Kelvin, legacy Warmth and Tint together, while project merge compares Kelvin independently.
- The workspace test applied one sampled correction as one history entry, reopened the library, then undid and redid the edit. A full-resolution 192 × 112 Viewer cache frame matched edited PNG export byte for byte. Source and managed-original fingerprints remained unchanged.
- All 322 debug tests passed with two environment-dependent skips: verified camera RAW fixtures and the native Finder Trash handoff were not configured. The branding check passed, the optimized arm64 app and strictly verified signed archive built successfully, and a disposable-library launch produced a 3472 × 1994 Isonique window capture. The native Apple Silicon macOS app is the sole maintained version; no web, mobile or separate desktop implementation exists. RAW camera-neutral metadata, adjustable sample areas, automatic skin-tone or natural-grey modes, calibrated wide-gamut output and large-file performance remain open.
