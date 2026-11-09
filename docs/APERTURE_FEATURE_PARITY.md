# Aperture 3 feature parity

Baseline audited against Isonique commit `0ebda9a` on 9 November 2026. Only the native Swift/SwiftUI/AppKit macOS app is maintained. The Swift package has a UI executable, an IsoniqueCore library, XCTest and no external package dependencies. ImageIO handles decoding and encoding, Core Graphics runs an 8-bit sRGB pipeline, and CryptoKit supplies SHA-256. Libraries store an atomic JSON catalogue and byte-verified originals on disk. UserDefaults holds several app-level options. There are no web/PWA, iOS, Android, Windows or other maintained app sources. See the [compatibility inventory](../COMPATIBILITY.md) for legacy catalogue evidence and [test results](APERTURE_TEST_RESULTS.md) for what was exercised.

## Historical sources and scope

- Apple introduced Faces, Places, non-destructive Brushes, adjustment presets, richer full-screen browsing and multimedia slideshows in Aperture 3. The Apple-authored launch and 3.5 manuals establish workflows and controls. The supplied 908-page PDF exceeded the browser extractor limit, and direct download returned HTTP 403. The 3.5 guide's complete text and the mirrored Apple Help supplied the detailed baseline. [Apple launch announcement](https://www.apple.com/uk/newsroom/2010/02/09Apple-Releases-Aperture-3/), [Apple Aperture 3 manual index](https://manuals.plus/m/3cdedfd315f296a727dc36c3d1097eb5923ff228252dc12b207021f3b8da88e0), [Apple Aperture 3.5 User Guide](https://manuals.plus/m/1c479d8d9aca8e7f49239d83e673f00ea3d728f55419ace76037fdca54ff2182), [Apple Help mirror](https://aperture.skydocu.com/en/)
- The 3.5 guide documents the unified iPhoto library, iCloud shared streams, SmugMug and Apple Maps workflows. Apple’s 3.4.5 update addressed camera/card deletion and ejection. The contemporaneous 3.6 release-note transcription identifies Yosemite compatibility and fixes for soft proofing performance, shared streams, writing IPTC to originals and Library First Aid. It separately reports RAW Decode 6. The original 3.6 support link did not load. [Apple 3.4.5 release notes](https://support.apple.com/en-me/106572), [3.6 release-note transcription](https://www.photojoseph.com/tips/2014/10/20/aperture-36-release-notes-and-raw-engine-v6)
- Historical command reference is the Apple shortcut card plus the 3.5 guide’s workspace and individual workflow sections. The table records representative commands and gaps. An exhaustive command-by-command transcription and direct execution of Aperture 3.6 are outstanding. [Apple shortcut card mirror](https://www.yumpu.com/en/document/view/55992561/apple-aperture-3-keyboard-shortcuts-aperture-3-keyboard-shortcuts), [Command Editor help](https://aperture.skydocu.com/en/customize-the-aperture-workspace/customize-keyboard-shortcuts/overview/)

Statuses refer to the feature scope named in each row. “Fully implemented and tested” requires verified operation and integration for that scope. Existing code without enough evidence for that label is marked as needing improvement or partial. Historical workflow and modern design choices are tracked separately.

## Library, selection and metadata

| Aperture workflow | Status | Isonique audit |
| --- | --- | --- |
| Create and switch independent Isonique libraries | Fully implemented and tested | File → New Isonique Library (⇧⌘N) creates a new folder. File → Open Isonique Library verifies and switches libraries. Both commands exercised in the native app. Normal launch remembers the selected path. |
| Library recents and relocation | Partially implemented | Existing verified libraries can be opened from a new location. No recents or Finder document handler. |
| Managed originals and byte-exact original export | Implemented but needs improvement | SHA-256-verified copies and original export have automated coverage. A missing managed original can be restored from matching bytes. |
| Referenced originals, offline badges, reconnect, relocate, consolidate | Partially implemented | Optional referenced import, offline browser filter, verified single-file relink and copy consolidation. No bulk reconnect, managed-to-referenced relocation or offline preview cache. |
| Projects, albums, sidebar navigation and project overview/skimming | Partially implemented | Flat projects and albums; membership, filters and sidebar navigation. No project covers or skimming. |
| Nested folders and albums under projects; drag/drop and manual ordering | Missing | Sidebar groups are display sections only. |
| Smart Albums and compound search | Partially implemented | Live rating, flag and text conjunction. No user-built All/Any rule set, date, lens, label, person, location, format or original status rules. |
| Manual and automatic stacks, picks, album picks, expand/collapse | Partially implemented | Explicit groups and capture-date time window; no persistent pick, album pick, collapse, promote or demote. |
| Original/adjusted display, create and duplicate independently editable versions | Partially implemented | Saved adjustment snapshots can be restored. Versions are not separate browser items and have no independent metadata or comparison. |
| Ratings, rejected state, flags and color labels | Partially implemented | Recovered rating bounds and filters, single/batch actions and flags. No color labels or keyboard culling equivalents. |
| Hierarchical keywords, keyword HUD, keyword buttons and presets | Partially implemented | Comma-separated keywords and import presets. No vocabulary tree, quick groups or vocabulary import/export. |
| IPTC/EXIF/XMP, metadata views, custom fields and autofill | Partially implemented | Import reads selected embedded fields; Info edits caption/keywords, XML/XMP supports selected fields, export can include EXIF/IPTC/GPS. No full field editor, views, autofill or custom fields. |
| Metadata presets, Lift and Stamp, batch metadata and date adjustment | Partially implemented | Presets at import and selective caption/keywords/rating Stamp. No dedicated batch metadata editor or capture-time correction. |
| Duplicate detection | Implemented but needs improvement | Exact SHA-256 on import. No library-wide visual similarity review or comparison tools. |
| Photo Trash and Put Back | Fully implemented and tested | Sidebar, photo context menu, File command (⌘Delete), batch actions and edit history. Restores project, albums, stack, edits and original identity. Tested with restart, backup, and native controls. |
| Version and container Trash, empty to Finder Trash | Missing | Trash is photo-only and retains original files on disk. |
| Library export/merge, original relocation and consolidation | Missing | Existing backup/restore can make a separate copy. No reconciliation or project-level export. |
| Vaults, backup, verification and restoration | Implemented but needs improvement | Independent verified snapshots and restore to a new folder. Copies managed originals and preserves external paths without copying their files, as with historical Aperture vaults. No incremental vault updates or scheduling. |
| Library First Aid, permissions and catalogue repair | Partially implemented | Read-only verification of catalogue and original hashes. No repair or rebuild. |
| Aperture/iPhoto interchange | Partially implemented | Read-only staged extraction of embedded originals plus some embedded metadata. No import of proprietary database relationships, referenced originals, historical adjustment recipes or vault format. |

## Image adjustment controls

| Aperture workflow | Status | Isonique audit |
| --- | --- | --- |
| Exposure, contrast, saturation, preset monochrome | Implemented but needs improvement | Shared renderer, numeric fields, resets and tested pixel results. 8-bit sRGB intermediate and adjustment clipping limit grading latitude. |
| Exposure brightness, recovery, black point and highlight/shadow detail | Partially implemented | Shadows, highlights and a Levels black point are real. Dedicated brightness, highlight recovery and extended-range RAW treatment are absent. |
| White balance and tint | Partially implemented | Warmth and tint channel gain. No picker, Kelvin/RAW neutral, skin tone or natural gray modes. |
| Enhance, vibrancy, definition, color correction and targeted color | Missing | No equivalent to vibrancy, local contrast, auto enhance, color targeting or tint wheels. |
| Curves and Levels | Partially implemented | Three fixed-position master controls and black/white/gamma. No editable points, separate RGB/luminance channels or quarter-tone Levels. |
| Sharpen/edge sharpen, noise reduction, chromatic aberration, vignette/devignette | Missing | Manual radial distortion is a separate control. No lens profile database. |
| Rotate and straighten | Implemented but needs improvement | Pixel geometry tested, including blank-corner trimming. Rotation/angle clears an existing crop. |
| Crop, presets, custom ratio and guides | Implemented but needs improvement | Draw/move/resize, aspect lock, orientation presets and pixel dimensions. Crop edges round to available pixels at render resolution. |
| Flip and orientation | Partially implemented | EXIF normalization and quarter turns. No horizontal or vertical flip command at baseline. |
| Red-eye, retouch, clone, heal and spot/patch | Missing | No controls or corresponding image operations. |
| Black-and-white channel mix, monochrome tint and sepia | Partially implemented | Desaturation and monochrome preset; no channel mixer, tint or sepia. |
| RAW fine-tuning and decoder reprocess | Missing | ImageIO decoding depends on the host. No RAW controls or camera fixture qualification. |
| Brushes, edges, size, softness, opacity, masks, multiple adjustment instances | Missing | No masks or brush engine. Historical Quick Brushes also included skin smoothing, polarize, contrast, tint, saturation, definition, sharpening, blur, noise reduction and halos. |
| Adjustment presets, custom recipes, Lift/Stamp, reset and history | Partially implemented | Four built-in presets, selective/batch Stamp, individual/reset-all, optional bounded persistent undo/redo. No custom adjustment presets or named global history UI. A slider can save many intermediate events and rerender at each one. |

## Browser, Viewer and geospatial workflows

| Aperture workflow | Status | Isonique audit |
| --- | --- | --- |
| Grid, filmstrip, list and two Browsers | Partially implemented | Grid and single viewer with filmstrip. No list, dual Browser, Quick Preview mode or manual ordering. |
| Single-image, multiple-image, Compare and Primary Only | Partially implemented | Single image and toggle to original. No synchronized side-by-side/multi-view or compare pick. |
| Full-screen Viewer/Browser/Projects, HUDs, secondary display | Partially implemented | Native window controls and slideshow. No dedicated full-screen photo layouts or secondary display targeting. |
| Zoom, Loupe and pixel-level inspection | Partially implemented | Binary fit/full-resolution render; no loupe, pan or precise magnification presets. |
| Histogram, Hot/Cold warnings, overlays and soft proofing | Partially implemented | Edited luminance histogram and RGB ICC simulation. No RGB histogram channels, clipping overlays, metadata badges or printer/paper simulation. |
| Light Table | Missing | No free layout, alignment or printing of layout. |
| Sorting, filtering, selection and context menus | Partially implemented | Four sort fields, rating/flag/text and explicit batch mode. Limited context menus, no range selection or drag and drop at baseline. |
| Faces detection, recognition, naming, confirmation and filtering | Missing | On-device detection and grouping are modern implementation choices; Aperture historically offered face naming and suggestions. |
| Places, location assignment, location filters and GPS tracks | Partially implemented | GPS can be copied into exports. No map, catalogue coordinates, edits, reverse geocoding, GPX matching or location search. |
| Viewer audio/video, audio attachments and trimming | Missing | Still-image workflow only. |

## Ingest, output and publishing

| Aperture workflow | Status | Isonique audit |
| --- | --- | --- |
| File/folder import, naming, metadata presets, duplicate rejection | Implemented but needs improvement | Background execution and presets. Metadata, naming and membership commit with the original in one catalogue write per file. Pair linking remains a separate final transaction. Duplicate hashing and catalogue writes still scale poorly for large batches. |
| Import preview, automatic projects, progress, cancellation and post-import actions | Partially implemented | Global busy spinner and outcome counts; no per-file progress, cancellation, import selection grid, time-zone correction, automatic split, backup-on-import, move source or eject. |
| RAW+JPEG pairing and preferred original | Partially implemented | By folder/stem, limited to newly imported partners. No switching one version’s underlying original. |
| Camera/cards/devices and tethered capture | Missing | Mounted folders import as files. No camera transport, shutter control or hardware validation. |
| Original/adjusted export, JPEG/TIFF/PNG/PSD and modern HEIF | Partially implemented | JPEG/TIFF/PNG and byte-copy original; no HEIF/PSD, 16-bit working output or export color-space choice. |
| Size, quality, export presets, batch and naming templates | Partially implemented | Long-edge downsize, JPEG quality, presets and unique batch filenames. No naming tokens, TIFF compression or comprehensive format options. |
| Metadata options, IPTC on originals and watermark | Partially implemented | EXIF/IPTC/GPS switches. No XMP sidecar output or watermark. Direct original writes are deferred in favor of preserving source bytes. |
| External editor round trip, plug-ins and automation | Missing | No derivative handoff, plug-in bridge or AppleScript scripting dictionary. |
| Print, contact sheets, proof layouts and books | Missing | No print layout/presets or local PDF book export. |
| Slideshow playback, themes, audio and movie output | Partially implemented | Local playback and interval controls. No authoring, soundtrack, transitions, persisted album or movie export. |
| HTML web galleries and journals | Missing | Original exported local sites; local HTML would be a practical equivalent. |
| Apple book ordering, My Photo Stream, iCloud/Facebook/Flickr/SmugMug publishing | Not applicable or replaced by modern functionality | Historical service-specific integrations are outside the local workflow baseline. Local export exists; no dedicated publishing or sync. |

## Menu, preferences and shortcuts

| Surface | Status | Audit |
| --- | --- | --- |
| File | Partially implemented | Import (⌘I), export (⇧⌘E), metadata import, open/verify/backup/restore, legacy recovery and import options. Original also included library switching/creation, relocate/consolidate/reconnect, versions, deletion and print. |
| Edit | Partially implemented | Undo/redo photo edit (⌘Z / ⇧⌘Z). Native text editing should retain text undo in focused inputs; application-wide override needs interaction review. |
| View / Window | Partially implemented | SwiftUI window menu, sidebar/inspector, grid/viewer controls and Escape to Browser. Dedicated Aperture layouts, HUDs, overlays and window controls are absent. |
| Images / Photos, Metadata, Adjustments | Partially implemented | Review and Rating menus, Inspector and edit strip expose some equivalents. No comprehensive photo, metadata or adjustment menu structure. |
| Help | Partially implemented | Searchable Features & Limits window. No workflow help or command reference inside the app. |
| Application preferences | Partially implemented | UserDefaults for import/export presets, history, crop ratio and library path. No Settings scene for general, appearance, import, export, labels, previews, accounts or advanced settings. |
| Command sets and gestures | Missing | Original supported searchable Command Editor, alternate and import/export command sets, ratings with digits, W for Inspector cycling, F for full screen, and configurable layouts and gestures. No equivalent command editor. |
| Native workspace polish | Partially implemented | Dark appearance, macOS 26 material with fallback, AppKit panels and named controls. Light appearance, systematic VoiceOver testing, trackpad interaction and toolbar customization outstanding. |

## Proposed modern work

16-bit or float processing, wide-gamut/EDR previews and exports, measured CPU/GPU selection, cancellable render scheduling, bounded thumbnail caching, catalogue scaling, undo coalescing and recovery after interruption are modernization work. Vision face detection is a candidate for local processing. GPS browsing can use embedded coordinates with optional map tiles. Neither task requires an account for the local library. Proprietary Apple artwork, historical pixel formulas and direct legacy catalogue writes are outside this implementation.

Baseline persistence bugs fixed include partial import records and in-memory photo edits that survived a failed catalogue save. Remaining risks include overlapping preview renders during slider drags, repeated catalogue scans and sorting in view updates, and missing large-library and physical camera tests.
