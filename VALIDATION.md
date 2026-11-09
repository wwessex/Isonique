# Verification — 8 November 2026

## Latest Inspector expansion

`make build` passes with the arm64 release executable, bundle and ZIP; staged strict ad-hoc signing passes. `make test` passes all 11 XCTest cases, including new adjustment persistence/export, old catalogue neutral defaults, directional tonal changes, selective Stamp and preset geometry preservation. No original image writes are introduced.


Only native Apple Silicon macOS is maintained here and was built/checked. No web/PWA/mobile variant exists. Intel and macOS 14/15 runtime behavior remain untested. Existing original-library/RAW/proprietary editing compatibility limits remain unchanged.


## Editing toolbar follow-up

Added a dedicated edit strip with Select, rotate left/right, interactive Crop, Straighten, Lift/Stamp, original comparison and Undo/Redo. Crop includes excluded-area dimming, a thirds grid, freeform drag selection, aspect presets and explicit Apply/Cancel. Straighten includes an alignment grid, degree control and corner trimming. Preview and JPEG export use the same geometry path, including CPU fallback. Existing version-1 catalogue recipes decode new fields with neutral defaults. The app opens the first available photograph when loading a library; hidden picker labels prevent the header from wrapping.


Only the native Apple Silicon macOS version is maintained here and was checked; no web/PWA or mobile variants exist. Intel, macOS 14/15 and physical mobile devices were not tested. GUI screenshot verification covers rendering; drag gestures, session undo and Lift/Stamp have not been driven by automated UI interaction. Online source comparisons, precise feature behavior and remaining gaps are recorded in `FEATURE_AUDIT.md`; brushes, red-eye and advanced tonal tools remain unsupported.

## Not verified

- **Visible launch:** the local GUI launch attempt exited with status 134 before producing the optional launch report. Computer Use returned `Computer Use was not approved to use Aperture Native`. No window observation or screenshot was obtained, and no successful GUI launch is claimed. The app's launch probe is available as `--launch-report /path/to/report.txt`, with `--library /path/to/new/empty/folder` for a disposable catalogue, when GUI access is available.
- No real Aperture library, representative camera RAW file, Intel execution, device import, older macOS, web/PWA or mobile variant was validated. Only the newly implemented arm64 macOS version was compiled/tested. Recovery testing used a generated fixture, and proprietary catalogue compatibility remains unsupported.

## Toolchain limits

SwiftPM's default Swift Build engine failed during dSYM generation with `Operation not permitted`; the project build script uses the still-supported native SwiftPM build engine. The host emits deprecation and inaccessible global-cache warnings. Package manifest sandboxing is disabled for the local build because nested `sandbox-exec` is unavailable inside the execution sandbox; host permissions are not changed. The app has no remote package dependencies.

## Reference interface update — 8 November 2026

Viewed all four supplied attachments. Preserved the library/viewer/filmstrip/inspector arrangement while adding system Liquid Glass (macOS 26+) to the filmstrip, inspector, viewer controls and brand mark, native sidebar/status vibrancy, rounded accent selections, and a toolbar inspector toggle. macOS 14–15 have a native material fallback.

After this change, the release arm64 build and staged strict signature verification passed; all four existing tests passed. Fixed compiler selection in the build script and test command: SwiftPM had selected a user-installed Swift 6.3.1 compiler incompatible with the current Apple SDK; both now select Apple's compiler with xcrun. No new dependencies were added.


# Features & Limits guide — 8 November 2026

Added the native Features & Limits window, Help menu command and question-mark toolbar entry. The guide offers text search, an initial missing/limited-only filter and grouped capability descriptions based on the current source and audit.


Only the native Apple Silicon macOS app is maintained here; no web/PWA, Windows or mobile implementation exists. Intel and macOS 14/15 runtime behavior remain untested. Original Aperture catalogue compatibility, proprietary rendering and retired services remain unresolved.


## Isonique rebrand and processing alternatives — 8 November 2026

Renamed the Swift package/modules, executable, bundle/identifier, window/sidebar/alerts and build outputs to Isonique. Retained `ApertureNative/Library` storage and catalogue schema for existing data. Original evidence and legacy Aperture format/recovery labels remain accurate. Removed superseded generated Aperture Native app/zip from build/ after the new build passed.

`make build` passed the arm64 release build and staged strict ad-hoc signature verification. `make test` passed all 13 tests, including a new public-renderer check against known neutral/±1 EV sRGB middle-gray output. Existing tests cover persisted recipes, source hashes, recovery, export, tone, geometry and rating rules. Pixel adjustments now consistently use the documented independent CPU path. RAW decoding remains ImageIO; LibRaw/libvips/OpenImageIO were researched against upstream documentation and recorded in PROCESSING_ALTERNATIVES.md, not integrated or benchmarked.


## Embedded metadata and library gap inventory — 8 November 2026

- `make test`: 15 XCTest cases passed. New synthetic TIFF/IPTC and XMP fixtures cover retained Unicode captions, keywords, star ratings, rejection (-1), out-of-range and malformed XMP ratings, duplicate preservation, separate unsupported-file reporting, catalogue reload and unchanged original hashes. An initial relative-path failure caused by macOS /var → /private/var canonicalization was fixed; the final suite passes.
- `make build`: arm64 release, staged bundle signing verification and signed archive creation passed. Deliverables: `build/Isonique.app` and `build/Isonique.zip`. SwiftPM emitted user cache access and deprecated native-build-system warnings; neither blocked compilation.
- Sole maintained version inspected/edited/validated: native Apple Silicon macOS app. No web/PWA, desktop alternative or mobile source exists here. Intel, older macOS runtime behavior, physical devices and representative real camera RAW files remain unvalidated.
- No real Aperture catalogue was supplied. Embedded metadata support does not migrate database-only edits/metadata, catalogue relationships, referenced originals or sidecars. Remaining features/options are listed in Help → Features & Limits and COMPATIBILITY.md.

## Top 10 missing features and options


## Top five missing options — 8 November 2026

Implemented the five options ranked in FeatureGuide: format; quality/size/presets; metadata; crop precision; and Stamp metadata selection. Changes are in Sources/IsoniqueCore/Options.swift, Library.swift and the native SwiftUI interface. Features & Limits and FEATURE_AUDIT.md now show these as available.

- `make build`: passed, Apple arm64 release bundle and signed ZIP rebuilt; strict signature verification passed. SwiftPM reports inaccessible optional user caches and a deprecated build-system flag, without build errors.
- `make test`: 19 tests passed, zero failures. New checks cover JPEG/PNG/TIFF format and exact resized dimensions; current IPTC caption/keywords/rating and original EXIF/GPS round trips; metadata omission; no overwrites; no enlargement; quality affecting encoded output; original-copy hash identity; preset serialization; pixel crop size after rotation/straighten; portrait aspect bounds; selective metadata-only and mixed Stamp preserving unchecked fields and photo identity. Existing catalogue, recovery, rating and rendering tests remain passing.
- Maintained versions inspected: native macOS SwiftUI/AppKit app only. No web/PWA, desktop Windows, iOS or Android implementation exists here. Apple Silicon host checked; Intel, macOS 14/15 runtime and physical mobile devices were not tested.
- Edited export remains 8-bit sRGB. Original export includes all source metadata regardless of metadata checkboxes, as explained in the export sheet. Full Aperture catalogue migration, proprietary RAW parity, plug-ins and retired services remain outside this option change and unresolved.


## GitHub upload validation (2026-11-08)

Prepared source for https://github.com/wwessex/Isonique on main, preserving the repository's existing license and files. Excluded Swift build caches, generated app/ZIP output, screenshots and logs. Native Apple Silicon macOS is the only maintained application; no separate web/PWA, mobile or Windows variants exist.


## Next five options — 9 November 2026

Implemented native options 6–10: RAW/JPEG import modes and companion links, naming/metadata presets, XML/XMP metadata import, RGB ICC proof simulation/manual lens distortion, and optional persistent photo history. `make test`: 24 tests passed, zero failures, including pairing preference and prefix behavior, XMP/XML/AlbumData parsing, old-catalogue defaults and bounded saved history, lens recipe persistence/selective Stamp and RGB proof acceptance/rejection. `make build`: arm64 release and ad-hoc bundle/archive signature verification passed. Compiler errors from the initial XML import and inspector references were fixed.


## Batch workflows, organization and photo navigation — 9 November 2026

Interpreted the ambiguous “two 5 features” request as missing-feature ranks 2 and 5 after an unanswered clarification: batch workflows, smart albums/stacks/versions. Added explicit Back to current grid, Escape, All Photos clearing search/rating filters, grid startup, and click-to-open photo navigation. Added stable-ID batch updates and numbered batch exports, smart album predicates/editor, manual stack grouping/sidebar and named adjustment versions. Feature guide and README disclose supported behavior and limits.

## Five review/tonal additions — 9 November 2026

- `make test`: 35 tests passed, zero failures. New coverage checks legacy neutral decoding, new-field persistence and selective Stamp, levels clipping/gamma/curve interpolation, histogram bins and processed pixels, and auto-stack gap boundaries, invalid dates and existing-stack exclusion.
- `make build`: arm64 release succeeded; staged app signature and clean archive verified. New actor-isolation warnings were fixed; remaining warnings concern unavailable user caches and SwiftPM's existing native-build-system deprecation.
- Direct interactive UI checking was unavailable: computer-use access to Isonique was not approved. Slideshow controls/timing and auto-stack sheet have build coverage and core logic coverage, but were not interactively exercised. No original screenshot exists in capture/reference for a new likeness comparison.
- Sole maintained variant: native Apple Silicon macOS. No separate web/PWA/mobile/Windows code exists. Intel, older macOS runtimes, actual RAW cameras and devices remain untested. Full legacy migration and Apple rendering fidelity remain unresolved.
## Verified library protection — 9 November 2026

- Added independent Isonique backup, manifest-verified restore into a new folder, read-only integrity checking and verified existing-library opening. Saved location persists; missing saved libraries produce an actionable error. No original Aperture format or pixel reconstruction changes.
- `make test`: 40 tests passed, zero failures. Five new backup tests cover exact catalogue/original round trips (metadata, collections, versions and history), corrupt/missing originals, tampered catalogue, existing/nested/legacy/symlink paths and empty libraries. Verified-open behavior is included. Tests use disposable synthetic libraries and never restore into user data.
- `make build`: arm64 release, staged strict ad-hoc signature verification and refreshed app/ZIP passed. SwiftPM user-cache access warnings remain nonfatal environment limits.
- Sole maintained variant checked: native Apple Silicon macOS. No web/PWA, Windows or separate mobile implementations exist. Intel, older macOS runtimes, physical devices and real Aperture catalogue migration remain untested/unavailable. Legacy vaults, automatic repair/merging, retouching and other inventory gaps remain.


