# Isonique — working stage 1

A separate Swift/SwiftUI macOS photo workspace. This is an independent implementation, not a rebuilt or patched Apple Aperture. Requires macOS 14 or newer on Apple Silicon; no third-party packages or network downloads are needed.

Source repository: [wwessex/Isonique](https://github.com/wwessex/Isonique). Clone the repository, then run `make build` from its root. Generated build folders, local screenshots and logs are excluded from source control.

## Build and run

Open `Package.swift` in Xcode, or run `make build` in this directory. The release build script creates and ad-hoc signs `build/Isonique.app`. Double-click that bundle or run `make run`. A clean signed archive is also created at `build/Isonique.zip`; use it when cloud-backed storage adds Finder metadata to the unpacked bundle.

`make test` runs import, persistence, rendered export, path-safety and legacy-copy recovery tests using generated photographs and a disposable synthetic library. Build output and development libraries are ignored by Git.

For an automated window check, run `"build/Isonique.app/Contents/MacOS/Isonique" --screenshot shots/now.png` from this directory. The app opens normally, draws 120 frames, saves its entire window as a PNG (creating parent folders), then exits. Capture failures exit with an error within 20 seconds. On macOS 14.4 and newer, Apple's current-process window capture requires no Screen Recording permission. On macOS 14.0–14.3, screenshot mode requires existing Screen Recording permission; ordinary interactive launch still works without it.

For compatibility, Isonique retains the previous application’s managed library at `~/Library/Application Support/ApertureNative/Library`. It does not open an existing Apple Aperture catalogue as its own database. For development, launch the executable with `--library /absolute/path/to/a/new/empty/folder` to isolate data.

## Interface

Use the question-mark toolbar button or Help → Features & Limits to see what is still missing. The searchable guide separates unavailable tools, features with limits and working features; it initially shows missing or limited features only. It is an inventory, not a promise that unavailable features have been implemented.

The workspace follows the supplied Aperture references: library navigation, a dark photo canvas, a bottom filmstrip, and an adjustment inspector. On macOS 26 and newer the filmstrip, inspector and floating viewer controls use native Liquid Glass. macOS 14–15 use native translucent materials. The toolbar can hide the inspector for a larger photograph and sort by import date, filename, rating or capture date in either direction. All star thresholds and exact Unrated only / Rejected only filters are available. Inspector has Info, Adjustments and Library tabs, numeric adjustment entry, individual resets, crop/rotation controls and selective Stamp options. Info includes the import date and Reveal Managed Original. The editing strip adds rotate left/right, crop with guides and aspect presets, straighten with an alignment grid and 0.1° fine-angle controls, Lift/Stamp to copy adjustments, original comparison and session Undo/Redo. The first photo opens automatically when an existing library loads. See `FEATURE_AUDIT.md` for the online references and remaining feature gaps.

## Working workflows

- A native three-pane workspace with Library, Projects, Albums, a grid, image viewer, filmstrip and inspector.
- Import individual photographs or folders; retain full-resolution managed copies, verify SHA-256 against the source and skip exact duplicates. Import into the selected project or album.
- Create projects and albums; assign an image to a project and multiple albums using the inspector.
- Browse metadata, edit caption/keywords, assign zero to five stars or reject photographs, flag photographs and search/filter the library.
- Adjust exposure, contrast, saturation, warmth, tint, shadows and highlights, rotate, straighten and crop non-destructively with a single source-defined CPU pipeline using 8-bit sRGB. Earlier Core Image previews may look different; saved adjustment values and originals remain compatible. All recipes are stored in the app's JSON catalogue, independently of immutable originals. Compare with the original, reset, undo/redo, lift adjustments from one photo and stamp them onto another, and view at fit or 100%. Geometry changes clear an earlier crop; reopen Crop to redraw it. Crop offers freeform selection and centered aspect presets. Lift copies the supported recipe; Stamp applies the groups checked in Inspector (exposure/color, white balance, tone and geometry), keeping unchecked groups and photo metadata. Natural, Vivid, Black & White and Warm presets replace tone/color settings while retaining geometry.
- Export full-resolution edited JPEGs. Export refuses existing destinations and any location inside a managed or legacy library. Select a new filename if an export already exists.
- Recover embedded originals from a legacy library using File → Recover Aperture Originals. The app hashes all regular files, makes a temporary complete copy inside its own library, verifies the copy and source, then imports from that copy's `Masters`/`Originals` directories. Embedded IPTC captions/keywords and IPTC/XMP ratings are retained when present; database-only metadata and sidecars are not migrated. Duplicates and unsupported files are reported separately, with unsupported filenames; storage/write failures stop recovery. The source is read only. Symlinks are rejected. Temporary recovery copies are removed afterward. Recovery can need substantial extra disk space.

Bulk import, rendering and recovery run off the UI thread. Edits are disabled during bulk operations to avoid concurrent catalogue updates. Import errors and unsupported files are reported rather than silently counted as successes.

## Limits

See `COMPATIBILITY.md`. This stage does not demonstrate full Aperture library compatibility. Preserve separate backups of all important libraries. There is no migration of proprietary adjustment recipes, project/album database relationships, referenced originals, faces/places, stacks, versions, plug-ins, videos or books. No cloud sync, mobile or web app is included. RAW availability and rendering depend on the host's macOS codecs, and have not been tested against actual camera RAW files here. Export currently produces JPEG only and does not copy EXIF/IPTC/GPS metadata. Captions and keywords are retained in the new catalogue.

## Recovered mechanics

The Deep-mode follow-ups in `MECHANICS.md` trace original rating and editing-tool functions. The app uses the recovered -1…5 rating range, rejection transitions, ±45° straighten bounds and missing-source Lift behavior, and recovered rating-filter indices/comparisons. Adjustment rendering remains independent; recovered legacy metadata does not establish pixel fidelity. Completed pseudocode records are retained in `evidence/decompilation.json` and `evidence/editing-decompilation.json`.

## Processing alternatives

See [PROCESSING_ALTERNATIVES.md](PROCESSING_ALTERNATIVES.md) for the implemented pixel equations and researched open-source RAW and processing options. LibRaw and libvips are candidates, not bundled engines.

### Export and precision options

Use **Export Photo…** to choose JPEG, PNG, TIFF or unchanged original, adjust JPEG quality and longest-edge pixel size, choose EXIF/IPTC/GPS inclusion and save named presets. Original output copies every original byte, including original location metadata. Edited output uses 8-bit sRGB; a longest edge of 0 means full size and smaller images are never enlarged.

In Crop, drag inside to move or use the corner handles to resize. Choose an aspect, lock it across sessions, switch portrait/landscape or enter exact pixel dimensions and click Set. Apply Crop saves it; Cancel leaves the saved crop unchanged. Inspector → Lift & Stamp Options also offers caption, keywords and rating checkboxes; checked fields replace the destination values, including blanks. All metadata boxes start unchecked.
