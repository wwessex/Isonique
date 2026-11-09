# Compatibility and scope

The current user instruction authorises a separate native reconstruction in working stages, superseding the earlier investigation's full-parity-only restriction. Historical investigation evidence remains in `MECHANICS.md` and `mechanics.json`.

## Isolation

Apple's original Aperture.app and existing libraries are never patched or used as writable databases. The new app has a different bundle identifier (`local.craftanything.isonique`), a separate name, and a separate catalogue. Its own library cannot be created inside an application or legacy photo library. Imported originals are managed copies verified with SHA-256. Non-destructive edits live in `catalog.json`.

## Legacy recovery

Legacy compatibility recovers embedded originals from `Masters` and `Originals`, including IPTC captions and keywords and embedded IPTC/XMP ratings when ImageIO exposes them. Ratings use the supported -1…5 range; XMP takes precedence over IPTC. Missing or invalid ratings default to unrated. Existing duplicate photos retain their current metadata. Recovery first makes and verifies a full disposable copy, compares file hashes before and after reading the source, and reads photographs from the copy. Symbolic links are refused. Duplicates and unsupported photographs are counted separately; unsupported relative filenames are shown (first 20 in the recovery dialog). Storage, catalogue-write and integrity errors stop recovery instead of being counted as unsupported images. A hash change stops recovery and is reported; already imported verified photos may remain in the new library. No recovery action writes a legacy database.

Tests use a **synthetic** `.aplibrary` directory with a generated PNG and opaque mock database. There is no supplied real user library to validate. Successful fixture recovery is not evidence of full Aperture compatibility. Referenced files outside a library, database projects/albums, database-only ratings and metadata, editing recipes and previews are not migrated. Embedded tags may be older than the latest changes in Aperture; read-only recovery cannot retrieve those database-only changes. Sidecar files are not imported. No claim is made that the original application's rendering can be reproduced.

## Supported implementation

macOS desktop only: SwiftUI with AppKit panels and windows, ImageIO metadata/thumbnails, source-defined CPU pixel rendering, managed import, projects/albums, rating/flag, caption/keywords, search/filter, exposure/contrast/saturation, comparison, fit/100% viewer and edited JPEG export. System RAW decoding is used where available; exact camera support and original Aperture RAW rendering are unverified. Export metadata preservation is not implemented.

## Unsupported

Legacy library editing, automatic catalogue conversion, adjustment/plug-in parity, multiple editing versions, stacks, faces/places, tethering, lens correction, retouching, soft proofing, books, slideshows, video, network/cloud sync and external referenced-original relocation are not implemented. Some proprietary legacy processing and abandoned services may be impossible to reproduce exactly; no full compatibility promise is made.

## Platforms

Only the newly created arm64 macOS application is built and tested. The supplied legacy Intel macOS bundle is preserved. No separate web/PWA, iOS, or other native sources were supplied, created or validated. Physical-device camera import, representative real RAW files, older supported macOS releases, signed/notarised distribution and real Aperture libraries require further validation.

## Isonique rebrand and rendering

The previous `~/Library/Application Support/ApertureNative/Library` path is deliberately retained to keep existing catalogues visible. The bundle, executable, Swift modules and interface are named Isonique. Historical evidence and Apple Aperture recovery labels keep their original names. See `PROCESSING_ALTERNATIVES.md`: Apple ImageIO remains the decoder; LibRaw and libvips are researched alternatives only. All previews and exports now use the same independent CPU formulas, so earlier Core Image results may change without changing saved recipes or originals.

## Remaining library features and options

Available in Help → Features & Limits, searchable by feature name:

- Direct opening or editing of `.aplibrary` catalogues; automatic database migration and round-trip interchange.
- Project/folder hierarchy, album membership, smart album rules, stacks, versions, version names and color labels.
- Database-only captions, keywords, ratings and flags; faces, places and other metadata relationships. Embedded metadata import does not reconstruct these relationships.
- Referenced-original discovery, relinking, relocation and consolidation; offline volume handling and missing-original resolution.
- Aperture XML catalogue and XMP sidecar import, preview recovery and original adjustment recipes.
- Library merging, vault backup/restore and catalogue repair/rebuild.
- Camera/tethered import, RAW+JPEG pairing, import renaming and metadata presets.
- Batch selection/edit/export; TIFF/PNG/original export, output dimensions/quality presets and embedded metadata export.
- Local brushes, retouching, red-eye, curves, levels, histogram, lens correction, soft proofing, printing, books, slideshows, plug-ins and video workflows.

The sole maintained implementation is native Apple Silicon macOS. No real Aperture catalogue has been supplied for end-to-end validation; fixture success is limited evidence, not a full compatibility claim.

Embedded metadata uses Apple's [IPTC caption property](https://developer.apple.com/documentation/imageio/kcgimagepropertyiptccaptionabstract) and [ImageIO metadata reader](https://developer.apple.com/documentation/imageio/cgimagemetadatacopystringvaluewithpath(_:_:_:)). No proprietary database schema was guessed or modified.

## Options 6–10 compatibility update

The only maintained variant is native Apple Silicon macOS. RAW/JPEG linking retains independent originals and recipes, and requires matching companions successfully imported together. Import presets rename catalogue display/export names only. XML/XMP support is metadata-only (README lists the accepted schemas), not full Aperture catalogue compatibility. Lens correction is independent radial resampling, not recovered Apple or automatic camera-profile processing. Proofing accepts RGB ICC only and affects the viewer, not output. Optional history is bounded to 100 edits in the catalogue; switching it off removes persisted snapshots. Older executables ignore new optional fields and can discard them when saving.

## Isonique backup support — 9 November 2026

Verified backup/restore, integrity checking and existing-library opening now work for this app's catalogue and managed originals. New destinations are mandatory. Backups retain the exact saved catalogue and every referenced original, with SHA-256 validation and a catalogue manifest. Restore switches the active library only after a successful verified copy. UserDefaults preferences and unreferenced files are excluded. Legacy Aperture vaults, library merging and automatic repair remain unsupported. No catalogue schema change; backup-manifest.json is an auxiliary file.
