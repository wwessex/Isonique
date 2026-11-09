# Isonique

A separate Swift/SwiftUI macOS photo workspace. This is an independent implementation, not a rebuilt or patched Apple Aperture. Requires macOS 14 or newer on Apple Silicon; no third-party packages or network downloads are needed.

Clone the repository, then run `make build` from its root. Generated build folders, local screenshots and logs are excluded from source control. [Source repository](https://github.com/wwessex/Isonique)

The ongoing Aperture work is documented in the [feature parity audit](docs/APERTURE_FEATURE_PARITY.md), [implementation plan](docs/APERTURE_IMPLEMENTATION_PLAN.md) and [test results](docs/APERTURE_TEST_RESULTS.md).

## Build and run

Open `Package.swift` in Xcode, or run `make build` in this directory. The release build script creates and ad-hoc signs `build/Isonique.app`. Double-click that bundle or run `make run`. A clean signed archive is also created at `build/Isonique.zip`; use it when cloud-backed storage adds Finder metadata to the unpacked bundle.

`make test` runs import, persistence, rendered export, path-safety and legacy-copy recovery tests using generated photographs and a disposable synthetic library. Build output and development libraries are ignored by Git.

For an automated window check, run `"build/Isonique.app/Contents/MacOS/Isonique" --screenshot shots/now.png` from this directory. The app opens normally, draws 120 frames, saves its entire window as a PNG (creating parent folders), then exits. Capture failures exit with an error within 20 seconds. On macOS 14.4 and newer, Apple's current-process window capture requires no Screen Recording permission. On macOS 14.0–14.3, screenshot mode requires existing Screen Recording permission; ordinary interactive launch still works without it.

For compatibility, Isonique retains the previous application’s managed library at `~/Library/Application Support/ApertureNative/Library`. It does not open an existing Apple Aperture catalogue as its own database. For development, launch the executable with `--library /absolute/path/to/a/new/empty/folder` to isolate data.

## Interface

Click a photo to focus the Browser or Viewer. Use 0–5 for ratings, 9 to reject, = and − to raise or lower, / to flag and the left/right arrows to move between photos. Command-1 through Command-7 assign colors and Command-0 clears the label. Change label names in Isonique → Settings. Filter colors from Sort & Filter or use them in a Smart Album.

Use the question-mark toolbar button or Help → Features & Limits to see what is still missing. The searchable guide separates unavailable tools, features with limits and working features; it initially shows missing or limited features only. It is an inventory, not a promise that unavailable features have been implemented.

The workspace follows the supplied Aperture references: library navigation, a dark photo canvas, a bottom filmstrip, and an adjustment inspector. On macOS 26 and newer the filmstrip, inspector and floating viewer controls use native Liquid Glass. macOS 14–15 use native translucent materials. The toolbar can hide the inspector for a larger photograph and sort by import date, filename, rating or capture date in either direction. All star thresholds and exact Unrated only / Rejected only filters are available. Inspector has Info, Adjustments and Library tabs, numeric adjustment entry, individual resets, crop/rotation controls and selective Stamp options. Info includes the import date and Reveal Managed Original. The editing strip adds rotate left/right, crop with guides and aspect presets, straighten with an alignment grid and 0.1° fine-angle controls, Lift/Stamp to copy adjustments, original comparison and Undo/Redo. Existing libraries open in the photo grid. Click a photo to open it; Back or Escape returns to the grid. All Photos returns to the whole library and clears search/rating filters. See `FEATURE_AUDIT.md` for the online references and remaining feature gaps.

## Working workflows

- A native three-pane workspace with Library, Projects, Albums, a grid, image viewer, filmstrip and inspector.
- Import individual photographs or folders. Copy originals into the library or reference their current location. Skip exact duplicates and optionally create a project on import. Cancel Import stops between files and keeps completed imports.
- Create or switch libraries in the File menu. Move selected photos to the sidebar Trash with Command-Delete and use Put Back to restore their edits and membership. Sort & Filter can show unavailable originals, which can be reconnected to matching bytes from the Inspector or File menu.
- Create projects and albums; assign an image to a project and multiple albums using the inspector.
- Browse metadata, edit caption/keywords, assign zero to five stars or reject photographs, flag photographs and search/filter the library.
- Adjust exposure, brightness, contrast, saturation, vibrancy, sepia, warmth, tint, shadows and highlights, rotate, flip, straighten and crop non-destructively with a single source-defined CPU pipeline using 8-bit sRGB. Earlier Core Image previews may look different; saved adjustment values and originals remain compatible. All recipes are stored in the app's JSON catalogue, independently of immutable originals. Compare with the original, reset, undo/redo, lift adjustments from one photo and stamp them onto another, and view at fit or 100%. Rotation and straightening clear an earlier crop. Flipping keeps its subject. Crop offers freeform selection and centered aspect presets. Lift copies the supported recipe; Stamp applies the groups checked in Inspector (exposure/color, white balance, tone and geometry), keeping unchecked groups and photo metadata. Natural, Vivid, Black & White, Warm and Sepia presets replace tone/color settings while retaining geometry.
- Export edited JPEG, PNG or TIFF, or make byte-exact original copies. Export refuses existing destinations and locations inside the current Isonique library or an Apple photo library.
- Recover embedded originals from a legacy library using File → Recover Aperture Originals. The app hashes all regular files, makes a temporary complete copy inside its own library, verifies the copy and source, then imports from that copy's `Masters`/`Originals` directories. Embedded IPTC captions/keywords and IPTC/XMP ratings are retained when present; database-only metadata and sidecars are not migrated. Duplicates and unsupported files are reported separately, with unsupported filenames; storage/write failures stop recovery. The source is read only. Symlinks are rejected. Temporary recovery copies are removed afterward. Recovery can need substantial extra disk space.

Bulk import, rendering and recovery run off the UI thread. Edits are disabled during bulk operations to avoid concurrent catalogue updates. Import errors and unsupported files are reported rather than silently counted as successes.

## Limits

See `COMPATIBILITY.md`. This stage does not demonstrate full Aperture library compatibility. Preserve separate backups of all important libraries. There is no migration of proprietary adjustment recipes, project/album database relationships, referenced originals, faces/places, stacks, versions, plug-ins, videos or books. XML import supports metadata only, as described below. No cloud sync, mobile or web app is included. RAW availability and rendering depend on the host's macOS codecs, and have not been tested against actual camera RAW files here. Edited exports can include selected EXIF, IPTC and GPS metadata. Captions and keywords are retained in the new catalogue.

## Processing alternatives

See [PROCESSING_ALTERNATIVES.md](PROCESSING_ALTERNATIVES.md) for the implemented pixel equations and researched open-source RAW and processing options. LibRaw and libvips are candidates, not bundled engines.

### Export and precision options

Use **Export Photo…** to choose JPEG, PNG, TIFF or unchanged original, adjust JPEG quality and longest-edge pixel size, choose EXIF/IPTC/GPS inclusion and save named presets. Original output copies every original byte, including original location metadata. Edited output uses 8-bit sRGB; a longest edge of 0 means full size and smaller images are never enlarged.

In Crop, drag inside to move or use the corner handles to resize. Choose an aspect, lock it across sessions, switch portrait/landscape or enter exact pixel dimensions and click Set. Apply Crop saves it; Cancel leaves the saved crop unchanged. Inspector → Lift & Stamp Options also offers caption, keywords and rating checkboxes; checked fields replace the destination values, including blanks. All metadata boxes start unchecked.

### Next five options (6–10)

- **RAW+JPEG:** Import Options defaults to Both (Use JPEG as Original), following the recovered original reset rule. It also offers Both (Use RAW as Original), Keep separate, JPEG files only, RAW files only, and the existing Prefer RAW / Prefer JPEG choices. Existing saved choices remain unchanged. Both modes select the chosen format after import. Strict only modes filter all input files. Files match by folder and base name. Links are created between successfully imported companions; Info switches between them, with separate edits. Existing duplicates remain untouched. Prefer modes choose based on filenames, so an unsupported RAW file is reported rather than replaced automatically with JPEG.
- **Import naming and metadata presets:** Set a filename prefix and optional caption, comma-separated keywords and rating, with named save/load/delete presets. Names change in the catalogue and export suggestions; source and managed filenames stay unchanged. Presets replace embedded metadata only when enabled.
- **XML and XMP:** Enable matching `.xmp` sidecars during import; sidecar fields override presets. File → Import XML / XMP Metadata applies XMP to the selected photo, or XML records to unique original/source filename matches. Supported fields are caption, keywords and rating. Supported XML is `<photos><photo filename="A.jpg"><caption>Text</caption><keywords>one, two</keywords><rating>4</rating></photo></photos>`, plus Apple AlbumData.xml Master Image List ImagePath/Comment/Rating metadata. It does not migrate a proprietary Aperture database, image paths, edits, collections or relationships. Missing/ambiguous matches stop metadata import before changing photos; malformed sidecars are reported before importing that file.
- **Color proofing and lens correction:** Inspector → Color Proofing & Lens loads an RGB ICC profile for a viewer-only relative-colorimetric round-trip simulation. No CMYK, paper/ink or gamut warning simulation. Manual barrel/pincushion correction uses the same radial resampling before geometry in preview and export, extending edges; automatic lens profiles, vignetting and chromatic aberration are unavailable. ICC selection lasts for the session.
- **Persistent history:** File → Import & History Options offers Keep Undo/Redo history after closing, off by default. When enabled, up to 100 photo snapshots and their redo state are saved with each edit in the library catalogue. Turning it off deletes saved history while keeping session Undo/Redo. New edits clear Redo. Older app versions can read these libraries but ignore new lens, pairing and history fields and may discard them when saving.

All application changes apply to the sole maintained variant: native Apple Silicon macOS. No web/PWA, mobile, Windows or independent native variants exist here.

### Batch workflows, smart albums, stacks and versions

Smart albums now use the recovered original rating filters: All ratings, star thresholds, five stars, Unrated only and Rejected only. Existing saved minimum-rating rules retain their behavior. Exact-only rules require this build; an older executable may discard the new optional filter index and revert to its saved threshold. Stacking checks that at least two selected photos actually exist in the catalogue. See `MECHANICS.md` for function addresses, evidence and unresolved original behavior.

Use **Select Photos** in the toolbar, then click photos or **Select All**. The selection bar applies ratings, flags, color presets and selective Stamp to selected photos, assigns albums/projects, and exports the selection using the existing format/metadata options. Batch export creates a new folder and numbers filenames to avoid collisions. It stops on the first error, reports how many files completed and retains those files. The inspector continues to edit one photo; Undo restores one photo per step.

**Create → New Smart Album** combines All or Any rules for metadata, dates, labels, adjustments, file type and original status. Membership updates from current metadata. Right-click a Smart Album to edit its rules. **View → Advanced Search** (Shift-Command-F) uses the same rules in the current Browser and can save them as a Smart Album. **Organize → Stack Selected** groups selected photos. Stacks appear in the sidebar and **Remove Selected from Stacks** ungroups selected members.

Inspector → Adjustments → **Editing Versions** saves named adjustment recipes and offers Restore/Delete. Restoring participates in Undo, keeps current metadata, and shares the immutable original. These features do not migrate legacy Aperture relationships or recipes. New optional catalogue fields preserve reads of existing libraries; older executables may discard these fields on save. This supersedes earlier statements that batch Stamp/export and smart albums/stacks/versions are unavailable.

### Five review and tonal features — 9 November 2026

Inspector → Adjustments now shows a live **luminance histogram** of a 384-pixel edited preview, **Levels** (black/white input points and gamma), and a **Master Tone Curve** (three output controls at 25%, 50%, 75% input). Levels and the piecewise-linear curve run after the other tone controls and before lens/geometry in the shared preview/export renderer. Reset buttons, presets, Undo/Redo, persistent history, named versions and the tone Stamp group include the new fields. These are independent 8-bit sRGB tools, without RGB channel curves, masks or recovered Apple formulas. Existing catalogues default to a neutral transform; older executables can discard the new optional settings when saving.

**Review → Auto Stack by Capture Time** (also in the Review toolbar menu) previews groups for a 0–60 second maximum consecutive gap, using the current view or selected batch. Missing/invalid capture dates and already-stacked photos are excluded. Dates use embedded capture time as recorded, without camera time-zone reconciliation. A chain of short gaps can span more than the selected interval. Creating stacks participates in per-photo Undo.


Only native Apple Silicon macOS is maintained. No independent web/PWA/mobile implementation is present; Intel, older macOS runtimes and physical-device testing are unavailable on this host.

### Verified library backups and restore

File → **Back Up Library** copies the saved catalogue (including metadata, collections, versions, recipes and any saved history) and all catalogued managed originals into a new folder. Managed originals must match their imported SHA-256 and copied bytes are checked again. The catalogue retains external paths. Back up referenced files at their external locations. A manifest protects the catalogue bytes during restore. Store backups on a separate drive for protection against disk loss. Uncatalogued files and per-user preferences are not included; this is an independent Isonique format, not an Aperture vault.

**Restore Library Backup** checks the selected backup’s format, manifest and originals before asking for a destination. It checks them again, copies into a separate new folder, and opens that library. Backup and restore require an existing writable parent directory. Existing destinations and locations inside the current library or backup are refused; failures remove the temporary copy. The current library and backup remain intact. **Open Isonique Library** lets you return to the previous library, checking its originals first. The last opened/restored library is remembered across ordinary launches; `--library` still overrides it. An unavailable saved location shows an error rather than silently creating an empty library. File menus remain usable to open/restore another library.

**Check Library Integrity** reads the saved catalogue and hashes its referenced originals, reporting success or the first error. It never repairs or deletes files. These tools do not repair malformed catalogues, merge libraries, restore legacy vaults or verify undocumented Aperture databases. Backup and checking run off the UI thread while library edits are disabled.
