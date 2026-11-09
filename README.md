# Isonique

Isonique is an independent, native SwiftUI photo workspace for Apple Silicon Macs running macOS 14 or later. It brings Aperture-inspired library management and non-destructive editing to a local photo catalogue. Building requires Xcode or its command-line tools. The app has no third-party package dependencies.

## Project status

The current build supports managed and referenced originals, cancellable imports, multiple libraries, photo Trash, verified backups, compound Smart Albums, keyboard culling and non-destructive editing with local Dodge and Burn masks. Browsable versions share originals and can be compared side by side. Stacks support library-wide and album-specific picks, plus persistent collapse.

The 9 November 2026 validation run passed 85 XCTest cases and the signed arm64 release build on Apple M5 Pro with macOS 27.3. Native QA exercised the Viewer Loupe, channel curves, histogram controls and channel Levels on disposable libraries. Older macOS runtimes and physical camera workflows remain unverified. [Feature parity audit](docs/APERTURE_FEATURE_PARITY.md) · [Implementation plan](docs/APERTURE_IMPLEMENTATION_PLAN.md) · [Test results](docs/APERTURE_TEST_RESULTS.md)

## Build and run

Open `Package.swift` in Xcode, or run `make build` in this directory. The release build script creates and ad-hoc signs `build/Isonique.app`. Double-click that bundle or run `make run`. A clean signed archive is also created at `build/Isonique.zip`; use it when cloud-backed storage adds Finder metadata to the unpacked bundle.

`make test` runs the core and workspace test suites. Coverage includes import and cancellation, library persistence and recovery, photo review, and pixel-level preview/export checks with generated photos and disposable libraries. Git excludes generated builds and local screenshots.

For an automated window check, run `"build/Isonique.app/Contents/MacOS/Isonique" --screenshot shots/now.png` from this directory. The app opens normally, draws 120 frames, saves its entire window as a PNG (creating parent folders), then exits. Capture failures exit with an error within 20 seconds. On macOS 14.4 and newer, Apple's current-process window capture requires no Screen Recording permission. On macOS 14.0–14.3, screenshot mode requires existing Screen Recording permission; ordinary interactive launch still works without it.

For compatibility, Isonique retains the previous application’s managed library at `~/Library/Application Support/ApertureNative/Library`. It does not open an existing Apple Aperture catalogue as its own database. For development, launch the executable with `--library /absolute/path/to/a/new/empty/folder` to isolate data.

## Interface

Click a photo to focus the Browser or Viewer. Use 0–5 for ratings, 9 to reject, = and − to raise or lower, / to flag and the left/right arrows to move between photos. Command-1 through Command-7 assign colors and Command-0 clears the label. Change label names in Isonique → Settings. Filter colors from Sort & Filter or use them in a Smart Album.

Use the question-mark toolbar button or Help → Features & Limits to see what is still missing. The searchable guide separates unavailable tools, features with limits and working features; it initially shows missing or limited features only. It is an inventory, not a promise that unavailable features have been implemented.

The workspace follows the supplied Aperture references: library navigation, a dark photo canvas, a bottom filmstrip, a metadata list and an adjustment inspector. On macOS 26 and newer the filmstrip, inspector and floating viewer controls use native Liquid Glass. macOS 14–15 use native translucent materials. The toolbar can hide the inspector for a larger photograph and sort by import date, filename, rating or capture date in either direction. All star thresholds and exact Unrated only / Rejected only filters are available. Inspector has Info, Adjustments and Library tabs, numeric adjustment entry, individual resets, crop/rotation controls and selective Stamp options. Info shows import date and original storage, with Reveal Original in Finder and relink or consolidation controls where applicable. The editing strip adds rotate left/right, crop with guides and aspect presets, straighten with an alignment grid and 0.1° fine-angle controls, Lift/Stamp to copy adjustments, original comparison and Undo/Redo. The first launch opens the grid. Use Control-G for Grid Browser or Control-L for List Browser. Select a list row to inspect it, double-click to open it, and use Up/Down to navigate. Back or Escape returns to your selected layout. Isonique remembers the layout across launches. All Photos returns to the whole library and clears search and browser filters. The parity audit tracks historical references and remaining gaps.

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

Legacy recovery imports embedded originals and supported embedded metadata from Aperture libraries. Proprietary recipes, database relationships, externally referenced files, Faces, Places, stacks and versions remain outside that recovery workflow. [Legacy library compatibility](COMPATIBILITY.md)

Isonique reads catalogue formats 1–6. Referenced originals and compound or project-scoped Smart Albums require format 2 or later. Browsable versions and stack controls require format 3 or later. Local brushes, channel curves and channel Levels require formats 4, 5 and 6 respectively. A library upgrades when it saves the relevant recipe in a photo, adjustment snapshot or persistent history. Backups include managed originals and retain the paths to referenced files. Keep a separate backup of those files.

RAW decoding uses the Mac's ImageIO codecs. Camera RAW samples, high-bit-depth output and calibrated wide-gamut display behavior remain unqualified. Edited exports use 8-bit sRGB. The native macOS app is the sole maintained version.

## Processing alternatives

See [PROCESSING_ALTERNATIVES.md](PROCESSING_ALTERNATIVES.md) for the implemented pixel equations and researched open-source RAW and processing options. LibRaw and libvips are candidates, not bundled engines.

### Export and precision options

Use **Export Photo…** to choose JPEG, PNG, TIFF or unchanged original, adjust JPEG quality and longest-edge pixel size, choose EXIF/IPTC/GPS inclusion and save named presets. Original output copies every original byte, including original location metadata. Edited output uses 8-bit sRGB; a longest edge of 0 means full size and smaller images are never enlarged.

In Crop, drag inside to move or use the corner handles to resize. Choose an aspect, lock it across sessions, switch portrait/landscape or enter exact pixel dimensions and click Set. Apply Crop saves it; Cancel leaves the saved crop unchanged. Inspector → Lift & Stamp Options also offers caption, keywords and rating checkboxes; checked fields replace the destination values, including blanks. All metadata boxes start unchecked.

### Import and editing options

- **RAW+JPEG:** Import Options defaults to Both (Use JPEG as Original), following the recovered original reset rule. It also offers Both (Use RAW as Original), Keep separate, JPEG files only, RAW files only, and the existing Prefer RAW / Prefer JPEG choices. Existing saved choices remain unchanged. Both modes select the chosen format after import. Strict only modes filter all input files. Files match by folder and base name. Links are created between successfully imported companions; Info switches between them, with separate edits. Existing duplicates remain untouched. Prefer modes choose based on filenames, so an unsupported RAW file is reported rather than replaced automatically with JPEG.
- **Import naming and metadata presets:** Set a filename prefix and optional caption, comma-separated keywords and rating, with named save/load/delete presets. Names change in the catalogue and export suggestions; source and managed filenames stay unchanged. Presets replace embedded metadata only when enabled.
- **XML and XMP:** Enable matching `.xmp` sidecars during import; sidecar fields override presets. File → Import XML / XMP Metadata applies XMP to the selected photo, or XML records to unique original/source filename matches. Supported fields are caption, keywords and rating. Supported XML is `<photos><photo filename="A.jpg"><caption>Text</caption><keywords>one, two</keywords><rating>4</rating></photo></photos>`, plus Apple AlbumData.xml Master Image List ImagePath/Comment/Rating metadata. It does not migrate a proprietary Aperture database, image paths, edits, collections or relationships. Missing/ambiguous matches stop metadata import before changing photos; malformed sidecars are reported before importing that file.
- **Color proofing and lens correction:** Inspector → Color Proofing & Lens loads an RGB ICC profile for a viewer-only relative-colorimetric round-trip simulation. No CMYK, paper/ink or gamut warning simulation. Manual barrel/pincushion correction uses the same radial resampling before geometry in preview and export, extending edges; automatic lens profiles, vignetting and chromatic aberration are unavailable. ICC selection lasts for the session.
- **Persistent history:** File → Import & History Options offers Keep Undo/Redo history after closing, off by default. When enabled, up to 100 photo snapshots and their redo state are saved with each edit in the library catalogue. Turning it off deletes saved history while keeping session Undo/Redo. New edits clear Redo. Older builds that can open the catalogue may ignore newer optional recipe or metadata fields when saving.

All application changes apply to the sole maintained variant: native Apple Silicon macOS. No web/PWA, mobile, Windows or independent native variants exist here.

### Batch workflows, smart albums, stacks and versions

Smart albums now use the recovered original rating filters: All ratings, star thresholds, five stars, Unrated only and Rejected only. Existing saved minimum-rating rules retain their behavior. Exact-only rules require this build; an older executable may discard the new optional filter index and revert to its saved threshold. Stacking checks that at least two selected photos actually exist in the catalogue. See `MECHANICS.md` for function addresses, evidence and unresolved original behavior.

Use **Select Photos** in the toolbar, then click photos or **Select All**. The selection bar applies ratings, flags, color labels, adjustment presets and selective Stamp to selected photos, assigns albums/projects, and exports the selection using the existing format/metadata options. Batch export creates a new folder and numbers filenames to avoid collisions. It stops on the first error, reports how many files completed and retains those files. The inspector continues to edit one photo; Undo restores one photo per step.

**Create → New Smart Album** combines All or Any rules for metadata, dates, labels, adjustments, file type and original status. Membership updates from current metadata. Right-click a Smart Album to edit its rules. **View → Advanced Search** (Shift-Command-F) uses the same rules in the current Browser and can save them as a Smart Album. **Organize → Stack Selected** groups selected photos. Stacks appear in the sidebar and **Remove Selected from Stacks** ungroups selected members. Use **Stacks → Set Stack Pick** (Command-Backslash) to set the cover, or **Set Album Pick** (Shift-Command-Backslash) for a regular album. Collapse from the Stacks or photo context menu. The sidebar stack view always shows every matching member.

Use **Photos → New Version from Original** (Option-G) for neutral adjustments or **Duplicate Version** (Option-V) to retain the current edits. Each version starts with a copy of the selected photo’s catalogue metadata and has its own name, edits, ratings and album membership. The versions share the same original. **View → Compare Photos** (Option-O) opens a pinned reference beside the current selection. Command-Return closes comparison. **Adjustment Snapshots** in the Inspector still save and restore recipes on a single version.

### Review and tonal tools

Inspector → Adjustments shows a live **histogram** of a 384-pixel edited preview with Luminance, combined RGB, or separate Red, Green and Blue views. The Inspector remembers the selected view. **Levels** provides combined black and white input points and gamma, and the **Master Tone Curve** provides three output controls at 25%, 50% and 75% input. **Channel Levels** adds independent black point, white point and gamma for red, green and blue. Open **Channel Curves** to edit red, green, blue or luminance independently. Click to add a point, drag to move it, or use the point picker and numeric controls. A completed drag is one Undo step. In preview and export, combined Levels and the master curve run before channel Levels, then channel curves, then lens and geometry. Reset, presets, persistent history, versions and the tone Stamp group include these settings.

Choose **View → Highlight Hot & Cold Areas** or press **Option-Shift-H** to toggle both Viewer warnings. The View menu also has independent highlight and shadow switches. Red marks pixels where any rendered sRGB channel reaches the highlight threshold, blue marks pixels at or below the shadow threshold, and magenta marks pixels that meet both conditions. **Settings → Clipping Warnings** changes the default 100% highlight and 0% shadow thresholds. The warnings use the current preview before RGB proofing. They appear in the Viewer and side-by-side comparison and are excluded from exports.

Choose **View → Show Loupe**, click the Viewer’s magnifier, or press the grave accent key to inspect the full-resolution rendered photo. Move the pointer over the image at Fit or 100% to sample its pixels. The Loupe offers 200%, 400% and 800% magnification, a grid at 400% and above, and zero-based coordinates with 8-bit sRGB readings before proofing.

Choose **Dodge Brush** or **Burn Brush** from Photos, the editing strip’s Brush menu, or Inspector → Adjustments → Local Brush Masks. Click or drag on the fit-to-window photo to lighten or darken it. The stroke guide follows the pointer and the adjusted preview updates on release. Size, Softness and Strength are remembered across launches. **Erase** and **Reset Mask** affect the selected mask, and each stroke or reset has its own Undo step. Masks follow the original photo through crop, rotation, flip, straightening and lens correction. Built-in presets preserve them. To copy masks with Lift & Stamp, enable **Local brush masks** in the Inspector before stamping.

**Review → Auto Stack by Capture Time** (also in the Review toolbar menu) previews groups for a 0–60 second maximum consecutive gap, using the current view or selected batch. Missing/invalid capture dates and already-stacked photos are excluded. Dates use embedded capture time as recorded, without camera time-zone reconciliation. A chain of short gaps can span more than the selected interval. Creating stacks participates in per-photo Undo.


Only native Apple Silicon macOS is maintained. No independent web/PWA/mobile implementation is present; Intel, older macOS runtimes and physical-device testing are unavailable on this host.

### Verified library backups and restore

File → **Back Up Library** copies the saved catalogue (including metadata, collections, versions, recipes and any saved history) and all catalogued managed originals into a new folder. Managed originals must match their imported SHA-256 and copied bytes are checked again. The catalogue retains external paths. Back up referenced files at their external locations. A manifest protects the catalogue bytes during restore. Store backups on a separate drive for protection against disk loss. Uncatalogued files and per-user preferences are not included; this is an independent Isonique format, not an Aperture vault.

**Restore Library Backup** checks the selected backup’s format, manifest and originals before asking for a destination. It checks them again, copies into a separate new folder, and opens that library. Backup and restore require an existing writable parent directory. Existing destinations and locations inside the current library or backup are refused; failures remove the temporary copy. The current library and backup remain intact. **Open Isonique Library** verifies present managed originals and opens the library so missing originals can be relinked. The last opened/restored library is remembered across ordinary launches; `--library` still overrides it. An unavailable saved location shows an error rather than silently creating an empty library. File menus remain usable to open/restore another library.

**Check Library Integrity** reads the saved catalogue and hashes managed and referenced originals, reporting success or the first error. It never repairs or deletes files. These tools do not repair malformed catalogues, merge libraries, restore legacy vaults or verify undocumented Aperture databases. Backup and checking run off the UI thread while library edits are disabled.
