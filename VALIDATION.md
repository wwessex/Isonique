## Fresh import/proofing trace validation — 9 November 2026

- Reopened original main program in Deep mode. Seven sequential pseudocode calls completed and were read individually; all fell back after Ghidra returned no result. Followed name/setting/message references, checked reset/transformer assembly and selector pointers, decoded original RAW+JPEG nib. Retained 21 evidence records in `evidence/import-proofing-main-trace.json`.
- Implemented recovered reset choice as new-options default, RAW/JPEG primary choices and strict format filters. Existing serialized pairing values still decode. Added regression coverage for unpaired files, other formats, uppercase extensions and saved choices. Same-folder matching and separate-photo edits remain independent limitations.
- `make test`: 25 tests passed, zero failures. `make build`: arm64 production compile and staging signature verification passed. Extracting `build/Isonique.zip` to `/private/tmp/isonique-deep-import-signed` also passed strict signature verification. Cloud-backed Documents reattached FinderInfo to the loose bundle and caused a later signature check to fail; use the ZIP for a clean signed copy.
- Direct GUI launch from the restricted shell aborted in macOS `_RegisterApplication` before application initialization. The Craft Anything `rebuild_check` then successfully rebuilt and launched the app, captured its 3472×1994 window and passed mechanics validation (15 existing sourced entries at that check). Three newly sourced import entries were subsequently added to mechanics.json (18 total); JSON parsing confirmed. Interactive import-option clicks and actual camera RAW decoding were not exercised.
- Inspected sole maintained native macOS SwiftUI implementation. No web/PWA, iOS, Android or Windows variants exist. Intel execution, older macOS, physical mobile devices and original x86_64 runtime remain untested. Original RAW/pixel formulas, catalogue relationships, matching RAW into existing masters, stamp merging, lens and proofing fidelity remain unresolved.

## Latest main-program trace and Rating menu validation — 9 November 2026

- Original main executable opened with `core_target_open` in confirmed Deep mode. Six sequential, individually awaited/read pseudocode calls completed. All used the fallback lifter because Ghidra returned no result. Checked rating/rejection assembly and method implementation pointers; retained `evidence/rating-menu-main-trace.json`.
- New Rating menu and inspector share `adjustRating(by:)` and `setRejected(_:)`, using the recovered delta, bounds and rejection rules through the existing save/undo operation. Menu placement and unit steps are independent UI choices.
- `make test`: all 20 tests passed, zero failures, including recovered rating transitions/bounds, filter truth table, straighten, crop ratio, persistence, import/recovery and exports.
- `rebuild_check`: release build passed, app launched and drew at 3472×1994, mechanics passed with 15 sourced entries and zero estimated. Screenshot inspected. Regenerated arm64 signed app/ZIP; signing verification runs in the build script. Interactive menu clicks were not automated.
- Native macOS SwiftUI is the only maintained version found. No web/PWA, iOS, Android or Windows sources exist. Intel, older macOS, mobile devices and the original x86_64 program's runtime were not tested. Original proprietary RAW/pixel fidelity, catalogue migration and Stamp merge semantics remain unresolved.

## Earlier crop-options trace validation

- Original main program opened with `core_target_open` in Deep mode. Seven sequential pseudocode calls completed and were read individually; Ghidra returned no result, so fallback output was used. Crop ratio was checked against complete assembly, selector pointers and exact mask bytes. Evidence: `evidence/crop-options-main-trace.json`.
- Added custom crop ratios and integrated `CropRules.aspectRatio` into pixel/lock updates. Existing positive aspect preferences retain their meaning. Source-coordinate rotation branches are unit tested; live UI uses already rotated display coordinates. New custom ratio interaction was not manually exercised.
- `make build`: arm64 release and signature verification passed; `build/Isonique.app` and `build/Isonique.zip` regenerated.
- `make test`: 20 tests passed, zero failures, including ratio magnitudes, 90/270 inversion, 0/180 orientation and invalid-input guards.
- `rebuild_check`: build, launch and 3472×1994 screenshot passed; mechanics passed with 15 sourced entries, zero estimated. Main-window screenshot inspected.
- Maintained versions inspected: native macOS SwiftUI only. No web/PWA, Windows, iOS or Android implementation exists. Intel and older macOS runtime behavior and original x86_64 execution remain untested. Full original RAW processing, catalogue compatibility, proprietary crop solving and Stamp merge behavior remain unresolved.

## Earlier main-program trace validation — 8 November 2026

- Opened original main executable in Deep mode; nine sequential pseudocode reads completed. All used fallback because the Ghidra bridge returned no result. Retained results in `evidence/current-main-program-trace.json`.
- Verified flagged query assembly and selector references; shared browser predicate now uses the recovered flag equality and existing rating rule constants. Visible filter behavior is preserved.
- `make build`: arm64 release passed; staged app signature verified; app and ZIP produced.
- `make test`: all 16 XCTest cases passed, zero failures. Covers rating truth table, bounds, persistence, original preservation, import/recovery, rendering and export. Interactive flag combinations were not automated.
- `rebuild_check`: build passed; app started and drew a 2880×1800 screenshot; mechanics passed with 14 sourced values and zero estimated values.
- Inspected maintained variants: native SwiftUI macOS only. No web/PWA, Windows, iOS or Android source variant exists. Intel, older macOS and original x86_64 Aperture execution were not validated in this pass. Full proprietary RAW/rendering/catalogue behavior remains unresolved.

# Verification — 8 November 2026

## Current pass: saved straighten bounds

Opened original main executable in Deep mode; searched names, settings and messages; followed CFString and Objective-C references; completed and read six sequential pseudocode results. Ghidra returned no result for each; fallback output was checked against full assembly and typed data for numeric claims. Records: `evidence/restored-angle-decompilation.json`; addresses and limitations: `MECHANICS.md`.

Restored recipes and catalogue saves now clamp straighten to the recovered -45…45 bounds. Added a catalogue regression covering raw older out-of-range recipes, exact persisted JSON values, valid angles, crop/identity preservation and unchanged original hash. `make test`: **16/16 passed**. `make build`: arm64 release and strict staged ad-hoc signature verification passed, producing `build/Isonique.app` and `build/Isonique.zip`. SwiftPM global-cache permission warnings were nonfatal.

`rebuild_check`: build, 2880×1800 startup screenshot and mechanics (13 sourced values, zero estimated) passed. Visually inspected the startup screenshot: workspace, image and inspector draw; no interactive angle-control verification is claimed. Only native macOS arm64 exists and was checked. Intel, older macOS, real camera RAW and proprietary catalogue/rendering fidelity remain untested or unresolved.

## Fresh original-function follow-up

Opened the original main executable in Deep mode, searched strings for names/settings/messages, followed references, and completed/read eight sequential pseudocode calls. Full records: `evidence/fresh-mechanics-decompilation.json`. Ghidra returned no result, so the built-in fallback was used; the incremental straighten formula was verified against full assembly and typed f64 constants. Existing rating/filter evidence remains documented separately.

Added fine-angle buttons using the recovered per-input `min(45,max(-45,current+delta))` rule; 0.1° step is an independent UI choice. Expanded the existing renderer-boundary regression with overshoot/reversal sequences and nonfinite-input safeguards. `make build` passed arm64 release compilation and strict staged ad-hoc signature verification. `make test` passed all 12 XCTest cases, zero failures. `rebuild_check` passed build, 2880×1800 startup screenshot, and mechanics (12 sourced values, zero estimated). Visually inspected that screenshot; Straighten was closed, so it does not establish interactive fine-angle button behavior. No interactive click test is claimed.

Only the native Apple Silicon macOS app exists and was built/tested. No web/PWA/mobile implementation was found. Intel and macOS 14/15 execution were not tested; original x86_64 Aperture was inspected statically. SwiftPM cache-permission/deprecation warnings did not prevent compilation. Original RAW/pixel formulas, crop solver, proprietary catalogue and full workflow compatibility remain unresolved.

## Inspector decompilation and recovered rating filters

Opened the original main executable in confirmed Deep mode, searched names/settings/messages, followed selector and CFString references, and completed/read 11 sequential individual pseudocode calls. Records are retained in `evidence/inspector-decompilation.json` and `evidence/inspector-reference-followup.json`. Ghidra returned no result; the fallback lifter was checked against assembly, all 16 typed filter-table entries, and RedRock comparator jump-table/CFString data. Original executable SHA-256 still matches `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`.

The shared rating filter now uses original indices and predicates, adding exact Unrated only and Rejected only choices while retaining all prior choices. No persisted catalogue fields changed. `make build` passed arm64 release compilation and staged strict ad-hoc signature verification, producing `build/Aperture Native.app` and `build/Aperture Native.zip`. `make test` passed **12 XCTest cases, zero failures**, including the complete recovered filter truth table over -1…5. SwiftPM global cache warnings did not prevent local builds.

`rebuild_check` passed **build, app-screenshot (2880×1800), mechanics (12 sourced values, zero estimated)**. Visually inspected `checks/round-0/screenshot.png` and retained it at `shots/now.png`: toolbar filter, image, filmstrip and inspector draw correctly. The screenshot shows the closed All ratings picker; it does not verify clicking each option. Predicate behavior is covered by the truth-table regression and inspected UI wiring.

Only the native Apple Silicon macOS implementation exists and was built/tested. No web/PWA/mobile implementation exists. Intel and older macOS execution remain untested. White-balance conversion routing was read, but original pixel formulas, shadows/highlights behavior, presets, proprietary RAW/selective stamping and full catalogue compatibility remain unresolved. Existing independent rendering is not claimed as original-equivalent.


## Latest Inspector expansion

`make build` passes with the arm64 release executable, bundle and ZIP; staged strict ad-hoc signing passes. `make test` passes all 11 XCTest cases, including new adjustment persistence/export, old catalogue neutral defaults, directional tonal changes, selective Stamp and preset geometry preservation. No original image writes are introduced.

`rebuild_check` passes build, app-screenshot (2880×1800) and mechanics (10 sourced values). Visually inspected the resulting screenshot: Info / Adjustments / Library tabs, preset menu, exposure/color controls, warmth/tint and highlights/shadows are visible and aligned; remaining controls are scrollable. This is a rendering check, not automated interaction coverage of every menu, text field or Finder reveal.

Only native Apple Silicon macOS is maintained here and was built/checked. No web/PWA/mobile variant exists. Intel and macOS 14/15 runtime behavior remain untested. Existing original-library/RAW/proprietary editing compatibility limits remain unchanged.


## Latest Deep-mode editing mechanics validation

Reopened the original main executable and completed nine sequential, awaited pseudocode reads for rotation, crop and Lift/Stamp. Records: `evidence/editing-decompilation.json`. Ghidra returned no result; recovered straighten bounds/formula were verified using complete assembly and typed original f64 data. MECHANICS.md records the full reference trail, function addresses, results and limitations.

Updated shared `StraightenRules` and the slider to use recovered ±45° bounds, and made Lift preserve its existing clipboard when no source photo is selected. Catalogue schema remains version 1. `make test` passed all **eight** tests, including rendering beyond the recovered bounds, nonfinite handling and opaque corners at ±45°. `make build` passed, produced the arm64 app and ZIP, and strictly verified its staged ad-hoc signature.

The final `rebuild_check` passed **build, app-screenshot (2880×1800), and mechanics (10 sourced values, 0 estimated)**. Visually inspected `checks/round-0/screenshot.png`: workspace, image, filmstrip and inspector draw correctly. This screenshot does not exercise the straighten slider or Lift actions. Only native Apple Silicon macOS exists here; no web/PWA/mobile variants were available. Intel execution, older macOS and interactive gesture testing remain untested. Original main executable hash remains unchanged. Pixel fidelity, proprietary crop solver and full original library compatibility remain unresolved.

## Editing toolbar follow-up

Added a dedicated edit strip with Select, rotate left/right, interactive Crop, Straighten, Lift/Stamp, original comparison and Undo/Redo. Crop includes excluded-area dimming, a thirds grid, freeform drag selection, aspect presets and explicit Apply/Cancel. Straighten includes an alignment grid, degree control and corner trimming. Preview and JPEG export use the same geometry path, including CPU fallback. Existing version-1 catalogue recipes decode new fields with neutral defaults. The app opens the first available photograph when loading a library; hidden picker labels prevent the header from wrapping.

`make test` passed all **seven XCTest cases** (zero failures). New tests verify old recipe decoding, saved geometry, CPU/preview/export dimensions, rotation direction with asymmetric pixels, top-left crop origin, opaque straighten corners and unchanged original hashes. `make build` passed and the staged arm64 release bundle passed strict signature verification. Final `rebuild_check` passed **build, app-screenshot (2880×1800) and mechanics**. Its final window image was visually inspected and copied to `shots/now.png`.

Only the native Apple Silicon macOS version is maintained here and was checked; no web/PWA or mobile variants exist. Intel, macOS 14/15 and physical mobile devices were not tested. GUI screenshot verification covers rendering; drag gestures, session undo and Lift/Stamp have not been driven by automated UI interaction. Online source comparisons, precise feature behavior and remaining gaps are recorded in `FEATURE_AUDIT.md`; brushes, red-eye and advanced tonal tools remain unsupported.

## Screenshot option follow-up

The rebuilt native macOS arm64 app supports `--screenshot <file.png>`. It draws 120 frames at a nominal 60 Hz, captures its own composited window through ScreenCaptureKit, writes PNG atomically and exits. Window/capture failures are bounded by 20 seconds. Without the option no capture timer or automatic exit is installed.

The final `rebuild_check` successfully ran `make`, launched the executable with `--screenshot`, obtained a 2880×1800 PNG and reported **build, app-screenshot and mechanics passed**. Visually inspected `checks/round-0/screenshot.png`: toolbar, sidebar, photograph, inspector, text and native materials are present. An unchanged copy of that checker-produced image is retained at `shots/now.png`. Earlier AppKit bitmap/PDF capture attempts omitted composited layers and were replaced with ScreenCaptureKit.

The direct shell attempt with `--screenshot app/shots/now.png` aborted in macOS application registration before app startup (status 134); the runtime walkthrough tool was denied by the current approval policy. Successful GUI execution was verified through Craft Anything's checker. Only native macOS exists; no web/PWA, desktop alternative or mobile implementation is present. macOS 14.0–14.3 and Intel execution remain untested; screenshot mode on those older macOS versions requires existing Screen Recording permission. The checked host supports permission-free current-process capture (macOS 14.4+).

Corrected the mechanics schema and preserved historical, unimplemented startup/adjustment constants separately in `evidence/legacy-mechanics.json`; implemented recovered rating rules remain in the runtime checklist. Original library/pixel compatibility questions remain unresolved. The older launch/check results below describe prior attempts and are superseded by this successful screenshot check.

## Actual results

- `./scripts/build.sh`: **passed**, release arm64 executable produced with Swift 6.4.2 / Xcode's macOS 27.2 SDK on the macOS 27.3 arm64 host. Deployment target: macOS 14, not tested on macOS 14.
- `make test`: **passed**, five XCTest cases with zero failures after the Deep-mode rating changes. Covers copied import, duplicate detection, saved metadata/ratings/album membership/adjustments, rendered image changes, full-size JPEG export, overwrite refusal, source hash preservation, verified recovery of synthetic legacy originals, path traversal and symlink rejection, and invalid-image handling.
- Ad-hoc bundle signing and `codesign --verify --deep --strict`: **passed** in temporary build staging. The cloud-backed Documents workspace attaches Finder/File Provider metadata to `.app` folders, which can invalidate a subsequent strict verification of the loose copy. `build/Aperture Native.zip` contains the clean verified bundle; extract outside cloud-backed storage for distribution testing. No Developer ID signing or notarisation is claimed.
- `file` reports the new executable as **Mach-O 64-bit executable arm64**.
- The original Apple Aperture executable SHA-256 is still `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`, matching the prior investigation. No original app/library writes were performed.

## Not verified

- **Visible launch:** the local GUI launch attempt exited with status 134 before producing the optional launch report. Computer Use returned `Computer Use was not approved to use Aperture Native`. No window observation or screenshot was obtained, and no successful GUI launch is claimed. The app's launch probe is available as `--launch-report /path/to/report.txt`, with `--library /path/to/new/empty/folder` for a disposable catalogue, when GUI access is available.
- **Craft Anything check:** the requested `rebuild_check` was invoked against the project. It returned `not_found`: “No answer: no build is running for this project, or the check took too long.” This is no automated checker result, not a passing check. Its remediation says to use it while Craft Anything is building, or finish the build and let the after-turn check run.
- No real Aperture library, representative camera RAW file, Intel execution, device import, older macOS, web/PWA or mobile variant was validated. Only the newly implemented arm64 macOS version was compiled/tested. Recovery testing used a generated fixture, and proprietary catalogue compatibility remains unsupported.

## Toolchain limits

SwiftPM's default Swift Build engine failed during dSYM generation with `Operation not permitted`; the project build script uses the still-supported native SwiftPM build engine. The host emits deprecation and inaccessible global-cache warnings. Package manifest sandboxing is disabled for the local build because nested `sandbox-exec` is unavailable inside the execution sandbox; host permissions are not changed. The app has no remote package dependencies.

## Reference interface update — 8 November 2026

Viewed all four supplied attachments. Preserved the library/viewer/filmstrip/inspector arrangement while adding system Liquid Glass (macOS 26+) to the filmstrip, inspector, viewer controls and brand mark, native sidebar/status vibrancy, rounded accent selections, and a toolbar inspector toggle. macOS 14–15 have a native material fallback.

After this change, the release arm64 build and staged strict signature verification passed; all four existing tests passed. Fixed compiler selection in the build script and test command: SwiftPM had selected a user-installed Swift 6.3.1 compiler incompatible with the current Apple SDK; both now select Apple's compiler with xcrun. No new dependencies were added.

rebuild_check was invoked after the final build and returned not_found: no active build or check timed out. No passing visual checker result is claimed. GUI appearance and the fallback on older macOS remain unverified. Only the supplied native macOS variant exists; no web/PWA or mobile implementation was found.

## Deep-mode mechanics follow-up — 8 November 2026

Opened original main executable, searched names/settings/messages, followed string and Objective-C references, awaited each function pseudocode result, and resolved imported RedRock rating constants. Ghidra returned no result; fallback output was cross-checked against assembly for rating clamping and reject checkbox conditional moves. Fourteen follow-up pseudocode records are retained in evidence/decompilation.json; one additional setRatingTo call is cited in MECHANICS.md. Geode GNG adjustment metadata was read, but pixel formulas remain unresolved.

The app now uses the recovered rating range (-1 through 5), reject-on=-1/off=0 behavior and direct star assignment. Rejected-star rendering is safe; All ratings includes rejects. Catalogue version 1 remains readable. The new regression test exercises range boundaries, rejection transitions, star display, old catalogue loading, save normalization and unchanged original hashes. All five tests passed. Final make build passed, produced the arm64 release app and ZIP, and verified the staged signature strictly. No GUI or older-OS execution was verified in this follow-up. Only native macOS exists; original Intel binaries were inspected statically, not run; no web/PWA/mobile variant was available.
# Features & Limits guide — 8 November 2026

Added the native Features & Limits window, Help menu command and question-mark toolbar entry. The guide offers text search, an initial missing/limited-only filter and grouped capability descriptions based on the current source and audit.

Validation: `make build` passed, including arm64 release compilation and strict staged bundle signing. `make test` passed all 12 existing tests. `rebuild_check` passed build, 2880×1800 app screenshot and all 12 sourced mechanics entries. The returned screenshot was visually inspected and shows the new question-mark entry without disturbing the workspace. Interactive guide-window/search/filter testing was unavailable because Computer Use returned “Computer Use was not approved to use Aperture Native”; no interactive result is claimed. SwiftPM emitted user-cache permission warnings but completed successfully.

Only the native Apple Silicon macOS app is maintained here; no web/PWA, Windows or mobile implementation exists. Intel and macOS 14/15 runtime behavior remain untested. Original Aperture catalogue compatibility, proprietary rendering and retired services remain unresolved.


## Isonique rebrand and processing alternatives — 8 November 2026

Renamed the Swift package/modules, executable, bundle/identifier, window/sidebar/alerts and build outputs to Isonique. Retained `ApertureNative/Library` storage and catalogue schema for existing data. Original evidence and legacy Aperture format/recovery labels remain accurate. Removed superseded generated Aperture Native app/zip from build/ after the new build passed.

`make build` passed the arm64 release build and staged strict ad-hoc signature verification. `make test` passed all 13 tests, including a new public-renderer check against known neutral/±1 EV sRGB middle-gray output. Existing tests cover persisted recipes, source hashes, recovery, export, tone, geometry and rating rules. Pixel adjustments now consistently use the documented independent CPU path. RAW decoding remains ImageIO; LibRaw/libvips/OpenImageIO were researched against upstream documentation and recorded in PROCESSING_ALTERNATIVES.md, not integrated or benchmarked.

`rebuild_check` passed build, startup screenshot (2880×1800), and mechanics (12 sourced values). Visually inspected checks/round-0/screenshot.png: Isonique is visible in title/sidebar; an existing photo/catalogue renders with the inspector and filmstrip. This is a startup/render check, not an interactive test of every control. Only the native Apple Silicon macOS version exists. No web/PWA or separate mobile sources are present; Intel, older macOS, real camera RAW and LibRaw integration remain untested. Earlier full-original compatibility and Rust investigation unknowns are historical and not resolved by this task.

## Fresh main-program rating-delta pass — 8 November 2026

- Reopened original main executable in confirmed Deep mode. Completed and read six separate awaited pseudocode calls, plus full delta/setter assembly and selector data. Ghidra bridge returned no result; fallback limitations retained in evidence/rating-delta-decompilation.json and MECHANICS.md.
- Implemented recovered delta addition combined with separately verified user bounds, through Lower/ Raise Rating controls and the existing persistence/Undo path. Unit button steps and overflow protection are independent choices.
- `make -C app build`: passed arm64 release, strict staging signature verification, regenerated Isonique.app and Isonique.zip.
- `make -C app test`: 13 tests passed, zero failures; expanded rating test covers all seven states, both delta directions and overflow guards.
- Craft Anything `rebuild_check`: build passed; startup screenshot passed at 2880×1800; mechanics passed with 13 sourced values. Viewed checks/round-0/screenshot.png: photo workspace renders. Screenshot opens Adjustments; it does not constitute an interaction check of the new Info buttons.
- Only native macOS Swift implementation exists. No web/PWA/mobile variant found. Apple Silicon build tested on this host; Intel, macOS 14/15 execution, real camera RAW, proprietary catalogue and original rendering fidelity remain unvalidated. No original runtime execution was attempted in this pass.
- SwiftPM user-cache access warnings occur under sandbox restrictions; local build/test outputs succeed. Original reference screenshots are absent (capture contains README only).

## Embedded metadata and library gap inventory — 8 November 2026

- `make test`: 15 XCTest cases passed. New synthetic TIFF/IPTC and XMP fixtures cover retained Unicode captions, keywords, star ratings, rejection (-1), out-of-range and malformed XMP ratings, duplicate preservation, separate unsupported-file reporting, catalogue reload and unchanged original hashes. An initial relative-path failure caused by macOS /var → /private/var canonicalization was fixed; the final suite passes.
- `make build`: arm64 release, staged bundle signing verification and signed archive creation passed. Deliverables: `build/Isonique.app` and `build/Isonique.zip`. SwiftPM emitted user cache access and deprecated native-build-system warnings; neither blocked compilation.
- Craft Anything `rebuild_check`: passed build, application startup/drawing at 2880×1800, and mechanics (13 sourced values). Inspected `../checks/round-0/screenshot.png`: main photo workspace renders. No original reference screenshot was available in capture/reference for pixel comparison. Help/recovery dialog interactions were not automated.
- Sole maintained version inspected/edited/validated: native Apple Silicon macOS app. No web/PWA, desktop alternative or mobile source exists here. Intel, older macOS runtime behavior, physical devices and representative real camera RAW files remain unvalidated.
- No real Aperture catalogue was supplied. Embedded metadata support does not migrate database-only edits/metadata, catalogue relationships, referenced originals or sidecars. Remaining features/options are listed in Help → Features & Limits and COMPATIBILITY.md.

## Top 10 missing features and options

Updated the native macOS Help → Features & Limits window with two ranked lists of exactly ten entries each. Retained search, filtering and available/limited summaries; removed duplicate reference links. Verified both lists contain numbers 1–10. `make build` passed with arm64 compilation, signing and archive verification. `rebuild_check` passed build, startup screenshot (2880×1800) and all 13 mechanics source entries. This content-only change does not alter photo processing or catalogue data. The guide's interactive search/filter and scrolling were not UI-automated. Only the native Apple Silicon Mac implementation exists; no web/PWA/mobile variant was present. Intel and older macOS execution remain untested.

## Top five missing options — 8 November 2026

Implemented the five options ranked in FeatureGuide: format; quality/size/presets; metadata; crop precision; and Stamp metadata selection. Changes are in Sources/IsoniqueCore/Options.swift, Library.swift and the native SwiftUI interface. Features & Limits and FEATURE_AUDIT.md now show these as available.

- `make build`: passed, Apple arm64 release bundle and signed ZIP rebuilt; strict signature verification passed. SwiftPM reports inaccessible optional user caches and a deprecated build-system flag, without build errors.
- `make test`: 19 tests passed, zero failures. New checks cover JPEG/PNG/TIFF format and exact resized dimensions; current IPTC caption/keywords/rating and original EXIF/GPS round trips; metadata omission; no overwrites; no enlargement; quality affecting encoded output; original-copy hash identity; preset serialization; pixel crop size after rotation/straighten; portrait aspect bounds; selective metadata-only and mixed Stamp preserving unchecked fields and photo identity. Existing catalogue, recovery, rating and rendering tests remain passing.
- `rebuild_check` after final release build: passed build (`make`), app startup/window capture at 3472×1994, and all 14 sourced mechanics entries. Screenshot `checks/round-0/screenshot.png` inspected: viewer and inspector draw correctly. New export-sheet and crop gestures were not manually automated; their shared data/rendering rules are covered by tests.
- Maintained versions inspected: native macOS SwiftUI/AppKit app only. No web/PWA, desktop Windows, iOS or Android implementation exists here. Apple Silicon host checked; Intel, macOS 14/15 runtime and physical mobile devices were not tested.
- Edited export remains 8-bit sRGB. Original export includes all source metadata regardless of metadata checkboxes, as explained in the export sheet. Full Aperture catalogue migration, proprietary RAW parity, plug-ins and retired services remain outside this option change and unresolved.


## GitHub upload validation (2026-11-08)

Prepared source for https://github.com/wwessex/Isonique on main, preserving the repository's existing license and files. Excluded Swift build caches, generated app/ZIP output, screenshots and logs. Native Apple Silicon macOS is the only maintained application; no separate web/PWA, mobile or Windows variants exist.

`make build` passed and verified the ad-hoc signature; `make test` passed all 20 tests. Craft Anything `rebuild_check` passed build, startup/window capture (3472×1994) and all 15 sourced mechanics entries. User-level SwiftPM cache warnings reflect sandbox write limits and did not prevent compilation. Intel and older macOS runtime validation were not performed. Existing Aperture catalogue/RAW compatibility limitations remain documented.

## Next five options — 9 November 2026

Implemented native options 6–10: RAW/JPEG import modes and companion links, naming/metadata presets, XML/XMP metadata import, RGB ICC proof simulation/manual lens distortion, and optional persistent photo history. `make test`: 24 tests passed, zero failures, including pairing preference and prefix behavior, XMP/XML/AlbumData parsing, old-catalogue defaults and bounded saved history, lens recipe persistence/selective Stamp and RGB proof acceptance/rejection. `make build`: arm64 release and ad-hoc bundle/archive signature verification passed. Compiler errors from the initial XML import and inspector references were fixed.

Craft Anything `rebuild_check` passed build, app screenshot (3472×1994) and all 15 existing sourced mechanics. Inspected `checks/round-0/screenshot.png`: viewer, photo, filmstrip, inspector and new Color Proofing & Lens disclosure render correctly. New options are independent behavior, not recovered Aperture mechanics; existing sourced mechanics remain unchanged. Menu interaction, real camera RAW pairs, printer profiles and real legacy XML catalogues were not exercised; XML tests use synthetic standard records. Only the native Apple Silicon macOS variant exists and was built/checked on this host. Intel, older macOS and mobile/device execution remain untested; there are no separate web/PWA, Windows or mobile implementations to synchronize.

## Batch workflows, organization and photo navigation — 9 November 2026

Interpreted the ambiguous “two 5 features” request as missing-feature ranks 2 and 5 after an unanswered clarification: batch workflows, smart albums/stacks/versions. Added explicit Back to current grid, Escape, All Photos clearing search/rating filters, grid startup, and click-to-open photo navigation. Added stable-ID batch updates and numbered batch exports, smart album predicates/editor, manual stack grouping/sidebar and named adjustment versions. Feature guide and README disclose supported behavior and limits.

`make test`: 29 tests passed, zero failures, including four new organization tests covering live all-rule matching, stable batch targeting/original identity, new-field persistence/legacy decoding, and batch destination protection. Release arm64 build passed; staged ad-hoc signature verification passed and build/Isonique.zip regenerated. `git diff --check` passed. Craft Anything `rebuild_check` passed make, launch/screenshot at 3472×1994, and all 18 sourced mechanics entries. Captured grid layout inspected at checks/round-0/screenshot.png. The check establishes launch/rendering; individual clicks, dialogs, older macOS and Intel execution were not automated. No camera/device validation. Only native Apple Silicon macOS exists; no web/PWA, separate mobile or Windows variants are present. No proprietary Aperture compatibility claim or changes to recovered mechanics.
# 9 November 2026: organization mechanics follow-up

Opened the original main executable in Deep mode, searched names/settings/messages, followed references and awaited twelve pseudocode calls individually. All completed through the fallback lifter after Ghidra returned no result. Original rating tables and manual-stack count comparison were checked against data/assembly; complete records are in `evidence/organization-main-trace.json` and `MECHANICS.md`.

`make test`: **31 tests passed, zero failures**, including persisted exact smart-album filters combined with flag/text predicates, legacy threshold decoding, and stale-selection stack eligibility. `make build`: arm64 release compiled and linked; staged ad-hoc signature verified and `build/Isonique.app` / `build/Isonique.zip` regenerated. SwiftPM global-cache warnings reflect inaccessible cache folders; local build completed.

Craft Anything `rebuild_check`: build passed; application launched and drew a **3472×1994** window; mechanics check passed (18 sourced values at that check; the newly recovered stack prerequisite was subsequently added as value 19). The screenshot was visually inspected. No interactive smart-album sheet automation was performed; its SwiftUI code compiled and underlying persisted rules were tested. Only the native Apple Silicon macOS implementation exists and was checked. Intel, older macOS, mobile devices and original x86_64 Aperture execution were not validated. Original stack joining, version database, RAW/pixel and catalogue fidelity remain unresolved.

## Five review/tonal additions — 9 November 2026

- `make test`: 35 tests passed, zero failures. New coverage checks legacy neutral decoding, new-field persistence and selective Stamp, levels clipping/gamma/curve interpolation, histogram bins and processed pixels, and auto-stack gap boundaries, invalid dates and existing-stack exclusion.
- `make build`: arm64 release succeeded; staged app signature and clean archive verified. New actor-isolation warnings were fixed; remaining warnings concern unavailable user caches and SwiftPM's existing native-build-system deprecation.
- `rebuild_check`: build passed, app started and drew at 3472×1994, mechanics passed (19 sourced values). Screenshot `checks/round-0/screenshot.png` inspected: histogram populated, Levels/Master Tone Curve disclosure rows and Review toolbar present; inspector remains scrollable. No proprietary mechanics are claimed for these independent features.
- Direct interactive UI checking was unavailable: computer-use access to Isonique was not approved. Slideshow controls/timing and auto-stack sheet have build coverage and core logic coverage, but were not interactively exercised. No original screenshot exists in capture/reference for a new likeness comparison.
- Sole maintained variant: native Apple Silicon macOS. No separate web/PWA/mobile/Windows code exists. Intel, older macOS runtimes, actual RAW cameras and devices remain untested. Full legacy migration and Apple rendering fidelity remain unresolved.
## Fresh review/tonal decompilation validation — 9 November 2026

- Reopened the original Aperture main executable in confirmed Deep mode. Completed and read 12 individually awaited pseudocode calls covering Auto Stack, histogram, Levels, Curves and slideshow functions. Ghidra returned no result for all 12; fallback output, full slideshow assembly, selector pointers and typed constants are retained in `evidence/review-tonal-main-trace.json`. MECHANICS.md records addresses, actual values, reference trails and unresolved algorithms.
- Applied original preset display default 3.0 seconds and the verified import-in-progress slideshow guard. Native menu and toolbar share the guarded startup method. Other busy-operation exclusion is an independent concurrency policy. No catalogue fields or saved adjustments changed.
- `make test`: 35 tests passed, zero failures. `make build`: arm64 release and staged strict signature verification passed; refreshed `build/Isonique.app` and `build/Isonique.zip`. SwiftPM global-cache warnings were nonfatal sandbox limits.
- `rebuild_check`: build passed, startup screenshot 3472×1994 passed, mechanics passed with 21 sourced entries and zero estimated entries. Inspected screenshot: selected photo, populated histogram, Levels/Curve disclosure rows and workspace render. Screenshot does not exercise slideshow timing or import-block interactions; these were not interactively tested. No original screenshot is available for likeness comparison.
- Checked sole maintained native macOS app. No web/PWA, Windows, iOS or Android sources exist. Intel/older macOS/devices and original legacy runtime were not tested. Original tonal pixel algorithms, Auto Stack grouping semantics, RAW rendering, catalogue migration, plug-ins and retired services remain unresolved.

## Verified library protection — 9 November 2026

- Added independent Isonique backup, manifest-verified restore into a new folder, read-only integrity checking and verified existing-library opening. Saved location persists; missing saved libraries produce an actionable error. No original Aperture format or pixel reconstruction changes.
- `make test`: 40 tests passed, zero failures. Five new backup tests cover exact catalogue/original round trips (metadata, collections, versions and history), corrupt/missing originals, tampered catalogue, existing/nested/legacy/symlink paths and empty libraries. Verified-open behavior is included. Tests use disposable synthetic libraries and never restore into user data.
- `make build`: arm64 release, staged strict ad-hoc signature verification and refreshed app/ZIP passed. SwiftPM user-cache access warnings remain nonfatal environment limits.
- Craft Anything `rebuild_check`: build passed; startup screenshot passed at 3472×1994; all 21 sourced mechanics passed. Screenshot visually inspected: grid photo, sidebar, inspector and histogram render. Native File-panel interactions and cross-drive backups were not automated; repository copy/verify/restore paths were exercised in tests.
- Sole maintained variant checked: native Apple Silicon macOS. No web/PWA, Windows or separate mobile implementations exist. Intel, older macOS runtimes, physical devices and real Aperture catalogue migration remain untested/unavailable. Legacy vaults, automatic repair/merging, retouching and other inventory gaps remain.


## 9 November 2026: original backup/restore trace follow-up

- Opened the original main executable in Deep mode; string/reference tracing and nine sequential awaited pseudocode reads retained in `evidence/backup-restore-main-trace.json`. Ghidra failed for every read; fallback analysis was corroborated with assembly for applied rules.
- Native Restore now validates source schema/integrity before destination selection; shared copy checks parent directory type/writability. SHA-256 and Isonique format version remain independent choices.
- `make test`: 41 tests passed, including manifest versions 0/2 and catalogue version 2 refusal before output creation, plus existing backup preservation/corruption tests.
- Only native SwiftUI macOS is maintained. No web/PWA/mobile/Windows implementations found. Original legacy runtime, Intel, older macOS, file-panel interaction and cross-drive behavior have not been exercised in this pass.

- `make build`: arm64 release compiled; ad-hoc signature verified; app and signed ZIP rebuilt. Craft Anything `rebuild_check` passed build, launch/draw screenshot (3472×1994), and mechanics (22 sourced entries). Screenshot inspected.
