# Isonique implementation plan

Keep the existing native app, independent catalogue and shared renderer. Deliver individual workflows with persistence, UI, and test evidence before extending their scope.

| Priority | Order and acceptance checks |
| --- | --- |
| 1. Core | Make each imported record atomic with its final metadata and membership. Verify rollback and duplicate behavior. Add photo Trash and Put Back with original bytes preserved, then in-app creation and switching between independent libraries. Follow with referenced originals, offline/relink and consolidation. Fix write-failure handling and import progress/cancellation. |
| 2. Daily workflows | Expand Smart Album rules and browser search together. Add browsable versions, stack picks, folders, color labels and keyboard culling. Add global photo adjustments with shared render and export tests. Improve browser layouts and selection. |
| 3. Advanced | Add local masks and brush recipes, compare/Loupe/Light Table, richer metadata, Faces/Places, tethering where hardware allows, and output workflows for external editing, watermarking, print and local galleries. |
| 4. Modernization | Profile the native app with large catalogues and high-resolution files. Improve render cancellation, catalogue and cache performance, wide-gamut and high-bit-depth behavior, native accessibility and display validation. |

## Checkpoint

Baseline audited at `0ebda9a`. Per-file import transaction, photo Trash/Put Back, independent library creation and atomic workspace photo edits are complete. Referenced import, missing-file status, verified single-file relink and copy consolidation are implemented. Import runs as a cancellable job with per-file progress and optional new project creation. Compound Smart Albums and advanced browser search now use shared criteria. Horizontal/vertical flip and basic brightness, vibrancy and sepia are in the shared renderer. Keyboard culling, color labels and persistent label names are in the native workspace. Browsable versions and side-by-side comparison now use a stable shared-original identity. Stacks have persistent picks, album picks and collapsed Browser covers. The native List Browser uses the workspace filters, selection and review commands and remembers its layout. Historical evidence, baseline status and remaining gaps are indexed in [workflow comparison](WORKFLOW_COMPARISON.md). Runtime evidence belongs in [test results](TEST_RESULTS.md).

Dodge and Burn are integrated with the Viewer and shared renderer. Format 4 stores strokes with the edit recipe, snapshots and optional persistent Undo/Redo. Coverage, edge falloff, geometry mapping, persistence, Undo and preview/export consistency have automated tests.

The Viewer and comparison panes have highlight and shadow warnings with persistent thresholds and View menu controls. The separate display overlay uses rendered pixels before proofing. Automated tests cover threshold boundaries and export isolation, and native QA covered the menu switches, shortcut, threshold sliders and comparison panes.

The single-photo Viewer has a pointer-driven Loupe with full-resolution sampling, 200/400/800% magnification, a pixel grid and 8-bit sRGB readings. Tests cover coordinate mapping and alpha, and native QA verified the menu, readout and shortcut.

The shared renderer and Inspector support independent red, green, blue and luminance curves. Format 5 protects the new recipes. Native QA covered point controls and Undo/Redo, and automated tests cover channel isolation, persistence and export pixels. The test record includes a 12 MP render measurement.

The Inspector histogram supports luminance, combined RGB and individual channels from one edited preview. Selecting a histogram view is a persistent UI preference.

Channel Levels provides independent black point, white point and gamma for each RGB channel. Format 6 protects the new recipes. Channel Levels runs after the legacy combined controls and before the independent curves. Tests cover isolation, rendering order, persistence, Undo/Redo and export.

Levels and Curves have input histograms sampled at the corresponding renderer stages. The Inspector uses one cancellable sample for all open adjustment panels. The channel luminance histogram matches the curve axis.

Combined and per-channel Levels have dark and light quarter controls. Format 7 protects the new recipes. Auto Levels uses the corresponding input histogram and adjustable percentiles for combined and individual RGB endpoints.

Four real camera RAW samples passed full-size tonal render, edited PNG and original-copy checks on macOS 27.3. The opt-in test and sample links are recorded in the README and test results.

The single Viewer and comparison panes reuse recent unproofed frames within a per-workspace byte and entry budget. A Nikon Z 6 sample confirmed reuse after switching render resolution, and tests cover eviction, cancellation and changed or missing originals.

Auto Curves and Loupe-sampled curve points use the existing channel curve recipe. Each automatic correction or new sampled point is one Undo step. Tests cover persistence and full-size PNG export equality.

Grid, List and filmstrip share a 64 MiB thumbnail cache and a bounded, cancellable decode queue. Native browsing and a deterministic 1,200-photo request replay were exercised.

The Browser reuses its last metadata-only filter and sort result and a photo selection index. Queries that depend on original availability still check the files live.

Grid thumbnail size is now a persistent application preference in View and Settings. Three sizes use their own cache resolution and leave the List and filmstrip unchanged.

The File menu reconnects missing referenced originals from a folder using known names and verified fingerprints. It reports unmatched and ambiguous files and applies all verified paths in a single catalogue write. Single-file relink remains available for fully renamed files.

Missing managed originals can be recovered from a backup or folder. Verified copies are installed independently at their existing paths without a catalogue write. Recovery can resume after interruption and skips completed installs. A forced quit can leave a hidden staging file.

The folder picker can target selected Browser photos, the current project or the entire library for both original search commands. A scoped match still applies to every version of the original.

The File menu consolidates selected references into verified managed copies. Shared versions change storage together, and external originals stay in place. If the catalogue cannot be saved, the references stay in use and a retry can reuse the verified copies.

The File menu relocates selected managed originals outside the library. It checks copies, saves new references for all versions, and then sends old managed files to Finder Trash. A failed or cancelled save can leave verified destination copies that a retry can reuse.

Relocation also works for already-referenced originals. The chooser defaults to keeping old external files. If the user elects to move them, a source that another record still references remains in place. A reference that already matches its proposed path is skipped.

The chooser offers original, catalogue or numbered filenames, with no subfolders or folders by project or capture year and month. The read-only preview shows the exact paths per original, how many versions share each one, and whether a collision will use the storage name, reuse a verified copy or skip a blocked path. Apply uses the approved paths, refuses a stale catalogue, and skips paths that become occupied or unsafe. A fresh preview is needed to approve a different path.

New Preset in Relocate Originals saves a named filename and subfolder template to application preferences. Edit and Delete manage saved presets. Templates use literal text and tokens for original name, catalogue name, project, capture date and sequence; the original extension is added automatically. Blank subfolders keep the output flat. Validation rejects unsafe syntax and expansions before the preview can be approved. The signed macOS app also includes an original vector icon rendered into standard and Retina icon sizes at build time.

File → Open Recent Library remembers up to ten successfully opened libraries. It uses verified opening and shows parent folders for duplicate names. Clearing the list preserves the startup library.

File → Export Project as Library packages the active photos in one project as a verified, independent library. It copies each shared original once and includes referenced originals as managed copies. Relevant albums, stack picks and surviving pairs stay with the photos. Smart Albums whose results would change because originals become managed are saved as regular albums with their existing matches. Trash and undo history are outside the export scope.

File → Import Project Library adds a verified, self-contained export as a separate project. Copies are independent even when their bytes match originals in the destination. The importer remaps colliding identities, scopes Smart Albums to the imported project and saves the whole project together. Cancellation and save failures clean up the copies. Crash recovery for forcibly interrupted catalogue writes remains open.

File → Merge Project Library reconciles a self-contained export with its matching project by stable IDs. The user chooses which matching photo values to keep. New versions reuse a verified original, while new originals are staged and published with one catalogue update. An explicit option applies source Trash changes. Photos moved to a different destination project stay in place.

New exports record the project photo IDs and original fingerprints at export time. Merge can use that record to identify previously exported photos that were removed. Destination-only additions stay in place, and older exports apply only explicit Trash changes. The review shows proposed additions, updates, copies and Trash moves before staging.

New exports record the starting editable values for each photo. Merge combines changes made on only one side and uses the conflict preference when both sides changed a field differently. The review identifies conflicting fields and matching photos without an edit baseline. Membership-only exports retain the previous merge behavior.

Independent controls such as Exposure and Contrast merge separately. Geometry, Levels, Curves, channel adjustments and brush masks each stay grouped, and the review names the control or group that needs a decision.

Project exports also record the starting collapsed state, global stack picks and album picks. Merge applies one-sided changes and pick removals, and previews conflicting picks separately from photo conflicts. It limits presentation changes to stacks fully within the merge scope. Older exports keep the previous stack merge behavior.

Project exports record eligible album definitions. Merge compares names independently from complete Smart Album rules, and the review identifies conflicting fields. Right-click a regular album to rename it. Regular albums shared across projects at export or merge are protected, including memberships in Library Trash. Smart Albums must stay scoped to the matching project on both sides. Rules exported as fixed memberships, album type or scope changes, and matching definitions in older exports keep their destination values. Album deletion reconciliation remains open.

File → Merge Libraries compares two full catalogues without opening the source or reading original files during review. It shows additions per project, versions that can reuse originals and identity conflicts. On approval it verifies reused destination originals, copies new managed and referenced originals into managed storage, and publishes the additions with one catalogue write. It retains existing records by default and preserves complete new stacks and pairs.

The default is Add new items only. The two review options list differing adjustment and metadata fields on active photos with matching photo IDs, original IDs and fingerprints. Whole-library review compares the two current catalogues without an export baseline. It can keep current values or apply imported values to the listed fields in the same transaction as additions. It verifies the affected destination originals and preserves photo identities, storage and memberships.

The Apply source Library Trash to matching photos checkbox starts off. When enabled, the review names active destination photos with explicit source Trash records and matching photo IDs, original IDs and recorded fingerprints. Conflicting Trash identities block publication. The approved move records the source Trash date and keeps the destination edits and memberships for Put Back. Destination-only records and existing Trash stay in place.

File → Empty Library Trash and the Trash browser review all trashed catalogue records before removal. The inventory lists managed Finder Trash candidates, originals kept for active versions, referenced files kept in place, and managed files that require a check. It conservatively protects case-equivalent paths.

On approval, Empty Library Trash checks the reviewed catalogue snapshot and candidate fingerprints. The first catalogue write removes eligible records and records pending Finder moves together. The handoff runs after that write, so a failed move leaves a retry entry and an unreferenced managed file. Use the same command to retry after reopening. Retry verifies the fingerprint, protects a path claimed by another record, and clears an already absent file from the queue. Unavailable or changed candidates retain their Library Trash records.

File → Library First Aid reports missing managed originals, offline references, and untracked regular files directly inside Originals. It counts shared originals once, includes Library Trash records in the catalogue inventory, and lists pending Finder Trash moves separately. The report reads file metadata. Check Library Integrity verifies original hashes.

First Aid can recover reviewed missing managed originals or reconnect reviewed offline references from a selected folder. The search matches known names and verifies the saved fingerprints. Before copying or changing references, Isonique checks the report's catalogue snapshot under the catalogue write lock. Reconnected originals update every version, including Library Trash records.

Inspect Untracked Files hashes the files in the reviewed report. It compares them with saved catalogue fingerprints, including offline originals, and can inspect selected Isonique backups. It checks each backup's catalogue and manifest and reads the matching managed files to verify their bytes. The inspection is read-only.

After inspection, Review Quarantine lists the files before moving them to First Aid Quarantine inside the library. Restore Quarantined Files reviews the return to Originals under the same names. Both actions check the live catalogue under its write lock and verify the reviewed fingerprints before moving. Claimed paths, pending Finder Trash files and occupied destinations are skipped. Each move is atomic, and quarantined files remain available after reopening.

Catalogue writes from independently opened workspaces compare the revision they loaded with the catalogue on disk under the write lock. Successful saves advance the workspace's revision. File → Reload Library reads the latest catalogue without rewriting it and retains valid browser navigation. It replaces stale Undo/Redo history with saved history when enabled, and keeps session history when the catalogue is unchanged.

File → Import from Camera or Card discovers local cameras through [Image Capture Core](https://developer.apple.com/documentation/imagecapturecore/) and local removable or ejectable volumes with a DCIM folder. The source picker updates when mounted media changes. The thumbnail grid starts with an empty selection and supports individual choices and bulk selection. Card previews use the bounded thumbnail cache and cameras provide thumbnails through Image Capture Core. Disconnect clears the grid and selection. Reconnect lets the user browse a fresh catalogue and select photos again. Import applies presets and RAW/JPEG pairing within the selection and reuses XMP sidecars, duplicate detection and progress. Cameras download one photo at a time to private temporary storage. The import verifies the expected length when the camera reports it, clears temporary copies and retains successfully saved photos after cancellation. It sends no deletion, rename or eject commands.

## Tethered capture evaluation

ImageCaptureCore reports separate capabilities for a Mac-triggered shutter and a shutter pressed on the camera. For a camera that reports `cameraDeviceCanTakePicture`, the macOS API exposes `requestTakePicture()`. The SDK deprecates the old tether enable and disable calls on macOS 14 because supported cameras enable the standard shutter command by default. The capability checks, shutter call and new-item delegate signature type-checked for Isonique’s macOS 14 deployment target. [Camera capabilities](https://developer.apple.com/documentation/imagecapturecore/icdevicecapability) · [Tether setup deprecation](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestenabletethering())

The initial simulated arrivals went straight to the importer. Replays could download the same file twice, and separate import batches left RAW and JPEG unpaired. The prototype and native adapter now collect new-file notifications before handing them to the importer.

## Simulated tethered capture prototype

The opt-in simulator runs through File → Simulated Tethered Capture when Isonique starts with `--simulate-tether`. The panel generates JPEGs and repeats their file notifications. The session allows one shot at a time and passes each completed shot to the existing camera importer. It waits for the simulator’s end-of-shot signal, so RAW and JPEG companions can arrive in separate notifications and still use the importer’s same-batch pairing. The session excludes the connection’s initial catalogue and suppresses replayed files before download. [Simulator walkthrough](../VALIDATION.md#simulated-tethered-capture)

Cancellation stops the active shot and preserves any complete imports. Disconnect cancels the shot, and reconnect begins with a fresh catalogue once the previous shot finishes unwinding. The prototype uses a simulator-provided shot boundary.

## Native ImageCaptureCore tethered capture

File → Tethered Capture opens the chosen camera’s session and waits for its initial catalogue. Isonique checks the Mac-triggered shutter capability after the catalogue is ready and before each shutter request. A shot uses the first new photo’s folder and filename stem, and collects matching arrivals until two seconds pass without a new matching file. It excludes known files and late companions for known photos. The collection times out after 30 seconds. The existing managed importer writes the shot to the current library and links RAW and JPEG companions that arrive within the window. Native cancellation stops waiting or transferring and closes the session. Reconnect starts with a fresh catalogue.

The signed bundle enables the Hardened Runtime and includes Apple’s required Photos Library entitlement for ImageCaptureCore. Isonique continues to use its own catalogue and file storage. [ImageCaptureCore configuration](https://developer.apple.com/documentation/imagecapturecore?changes=l_11)

## Capture date and time correction

Metadata → Adjust Date and Time and the Info inspector preview a correction for the selected photo versions. For a batch, the default shifts all valid dates by the reference photo's change. It skips photos without a valid date and reports them before applying. Turning off Keep intervals between photos assigns one capture time to the whole selection and can fill missing dates. The entered date is interpreted as a camera wall-clock value at second precision. Date sorting, capture-date filters, automatic stacking and relocation templates use the saved catalogue value.

One catalogue save records the correction. Undo and Redo restore the group in a single step, and format 8 stores that group when persistent history is enabled. The original files and their fingerprints are preserved. Adjusted JPEG, PNG and TIFF exports include the corrected EXIF capture time when EXIF is enabled. [Historical Aperture workflow](https://aperture.skydocu.com/en/work-with-metadata/adjust-the-photo-date-and-time/)

## Batch caption and keyword editing

Metadata → Batch Change, Shift-Command-B, and the selection bar open a review for the current visible selection. The preview lists each affected photo with the current and resulting values. Caption replacement is optional. Keywords can be left unchanged, appended or replaced. Append skips case-insensitive duplicates and preserves existing order and spelling. Replace uses the new list, and an empty replacement clears the chosen field.

Apply writes the reviewed values in one catalogue save. If the selected records or their metadata changed after review, the app asks for a fresh preview. The change updates search and Smart Albums, and Undo and Redo restore the affected fields together. Persistent batch metadata history uses catalogue format 9. Captions and keywords continue to use the existing catalogue fields. [Historical Aperture workflow](https://aperture.skydocu.com/en/work-with-metadata/batch-change-metadata/)

## Reusable keyword groups

Metadata → Manage Keyword Groups creates, renames and edits named groups, and confirms before deleting them. Group definitions, the active group and visibility of the controls live in application preferences and are available across libraries. Keyword order determines button order. Duplicate entries are removed using the same matching as Batch Change.

View → Show Keyword Controls displays a group picker, individual keyword buttons and Apply Group. The Metadata menu also offers the active group's keywords. Assignment appends to the visible selection, skips existing keywords and uses the same grouped history as Batch Change. Editing or deleting a group leaves already assigned photo keywords intact. [Historical Aperture workflow](https://aperture.skydocu.com/en/organize-and-sort-photos/add-keywords-to-photos/apply-keywords-using-keyword-controls-and-presets/)

## Quick keyword removal and shortcuts

The keyword controls support Shift-click removal and Metadata → Remove Keyword. With Keyword Controls visible and the Grid Browser, List Browser or Viewer focused, Option–1 through Option–8 add keywords by active group order. Add Shift to remove the corresponding keyword. Search and Inspector text fields keep their normal key input. The same catalogue history handles assignment and removal, so Undo restores the entire selection in one step. [Aperture shortcut reference](https://www.manualshelf.com/manual/apple/aperture-3-upgrade/operation-manual-english/page-298.html)

## Reusable keyword vocabulary and regional English

Metadata → Keyword Vocabulary lets you add, rename and remove branches, apply a term to selected photos, and exchange tab-indented UTF-8 text lists. The tree persists in app preferences and is shared across libraries. Import merges case-insensitive matches within each branch, keeping existing spelling and order. Invalid files are rejected before saving. Photo assignments retain their full vocabulary path alongside the existing flat keyword field. [Aperture keyword list reference](https://aperture.skydocu.com/en/organize-and-sort-photos/add-keywords-to-photos/export-and-import-keyword-lists/)

The app bundle uses the macOS language preference to select British English resources and uses base English as the fallback. The translated labels cover regional spellings in the interface and app menus. [Apple bundle language reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledevelopmentregion)

## Hierarchy-aware keyword assignment and search

Apply Keyword in the vocabulary stores the selected term with its ancestors. The Info inspector lists and removes assigned paths independently. A vocabulary rename or deletion leaves the saved path available for search. Existing flat tags keep their meaning and can be edited separately. Ordinary keyword search and IPTC export use the term name.

Find Photos in the vocabulary searches for an exact path. Advanced Search and Smart Albums also support an entire branch, including its descendants. Catalogues with path assignments or saved path rules use format 10. Earlier catalogues open with their existing flat tags.

The signed build displayed Centre and Minimise in the native Window menu using the Mac’s British English preference. The same bundle displayed Center and Minimize under a US English override. AppKit supplies these commands.

## XMP keyword hierarchy exchange

Export → Write matching XMP sidecar saves current metadata alongside a rendered image or a byte-for-byte original. The sidecar stores full keyword paths in Lightroom’s `lr:hierarchicalSubject` and flat tags in `dc:subject`. IPTC export continues to include flat tags and each assigned path’s leaf name. XMP uses `|` between levels. Export reports an error if a keyword name contains that character. [Adobe hierarchy format](https://github.com/adobe-dmeservices/custom-metadata#hierarchical-keywords-support) · [IPTC Keywords specification](https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata-2025.1.html#keywords)

Import reads hierarchy paths from embedded XMP. Enable Read matching .xmp sidecars to apply adjacent sidecars during photo import. File → Import XML / XMP Metadata applies a sidecar to the selected photo. Fields present in a sidecar replace the corresponding fields, and omitted fields keep their current values. Flat tags and assigned paths remain separate in the catalogue.

## IPTC title, creator, copyright and credit

Info → IPTC Metadata edits the selected version. Enter one creator per line to retain the byline order. Save IPTC Metadata commits the edited fields together. Metadata → Batch Change previews per-field replacements for the visible selection. Check a field and leave its input blank to clear it. “From original” in the preview means the catalogue has no saved value for that field. Each Apply is one Undo step, and catalogue format 11 supports these fields and their persistent history.

Import reads the four fields from embedded IPTC and XMP, with matching sidecar fields taking precedence when present. Older catalogues can read inherited fields from available originals in Info and during export. Edited image export can embed the current IPTC values. XMP sidecars work with both edited images and byte-for-byte originals. Title and copyright use the default XMP language value, or the first supplied translation when no default is present. Creator uses an ordered list. [IPTC Photo Metadata Standard](https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata-2025.1.html#metadata-properties)

## IPTC search and saved rules

Quick Search finds catalogue IPTC title, creator, copyright and credit. Advanced Search and Smart Albums offer field-specific substring and exact comparisons with their negations. Each creator is compared separately. An IPTC Smart Album rule requires catalogue format 12. Search reads the catalogue so results work with offline originals. Values inherited only from an older library’s originals can be brought into search with Catalogue IPTC from Originals.

## Reusable metadata presets

Metadata → Batch Change → Reusable Metadata Presets saves checked caption and IPTC fields, plus the chosen flat keyword mode. Loading a preset fills the editor, where users can review, revise and apply the results as one Undo step. Presets live in app preferences and are shared across libraries. Case-insensitive duplicate names are refused.

Import Options offers the same presets independently of storage, pairing and filename choices. A chosen preset applies after the import caption, keyword and rating defaults. Matching XMP fields take precedence. Saved import options and full import presets keep their chosen metadata values as a snapshot. Removing a reusable preset leaves saved import snapshots and previously edited photos intact.

## Selective IPTC Lift and Stamp

Use the edit strip, Adjustments → Lift & Stamp Options, or the Photos menu and Shift-Command-C / Shift-Command-V. Lift reads missing IPTC fields from an available original in the background. The inspector shows the lifted source and its IPTC values. Stamp copies the checked fields and adjustment groups to the selected photo or visible batch selection. An explicit IPTC clear replaces the destination value. Missing fields are skipped. Mixed stamps are one Undo step and affect only changed fields and adjustment groups. Catalogue format 13 stores persistent stamp history. [Aperture 3.5 Help](https://aperture.skydocu.com/en/make-image-adjustments/ways-to-perform-adjustments/apply-standard-adjustments/)

## Catalogue inherited IPTC from originals

Metadata → Catalogue IPTC from Originals reviews the current selection. It verifies each original’s SHA-256 and reads one original per shared identity. Offline, changed or unreadable originals appear in the review. Cancel IPTC Review stops the scan after the current original. Add to Catalogue fills only unset title, creator, copyright or credit fields and makes them searchable. A catalogue edit made during review requires a fresh review. Additions use one Undo step and preserve the original bytes.

## Read-only EXIF in Info

Expand Info → EXIF to inspect shutter speed, aperture, ISO, focal length and lens from the selected photo’s original. ImageIO reads the metadata in the background when the section is open. Changing photos or refreshing original availability updates the readout. The section distinguishes an absent field from an offline or unreadable original. It uses the actual focal length and displays subsecond exposures as fractions when they closely match a reciprocal. [ImageIO EXIF keys](https://developer.apple.com/documentation/imageio/exif-dictionary-keys)

## Configurable metadata views in Info

The Metadata View picker includes General, EXIF Info, IPTC Core and Caption & Keywords. General uses the existing Info layout. Manage Metadata Views creates a view from selected fields or duplicates the current view as a starting point. Use the move buttons to set the display order. Custom views can be renamed, edited and deleted. The active view and custom definitions are stored in app preferences and shared across libraries. Deleting the active custom view returns Info to General. Editable fields use the existing photo edit controls. [Aperture 3.5 Help](https://aperture.skydocu.com/en/work-with-metadata/work-with-metadata-views/create-modify-and-manage-metadata-views/)

## Catalogue-backed EXIF search

Advanced Search and Smart Albums compare saved shutter speed, aperture, ISO, focal length and lens. Shutter speed accepts seconds or a fraction and compares exposure duration. Aperture and focal length accept decimal values, ISO accepts positive whole numbers, and lens uses text comparisons. Present and missing rules test whether the catalogue has a value. A missing value, including one from an unindexed photo, matches only an explicit missing rule.

Imports read EXIF during the normal catalogue save. For older photos, Metadata → Catalogue EXIF from Originals verifies selected original fingerprints and records their capture values in one save. It skips unavailable or changed originals and supports cancellation. The catalogue preserves indexed values while originals are offline. Saved capture values and EXIF Smart Album rules use format 14. [Aperture 3.5 Help](https://aperture.skydocu.com/en/organize-and-sort-photos/search-for-photos/search-using-a-combination-of-criteria/)

## GPS readout in Info

Choose GPS in the Info inspector’s Metadata View menu to see signed latitude and longitude in decimal degrees. The readout uses the effective catalogue location when available. For unindexed photos it reads the primary image’s embedded GPS metadata and distinguishes missing or invalid coordinates, an offline original and an unreadable image. Latitude and Longitude can also be added to custom metadata views. The view reads locally and leaves original bytes and the catalogue unchanged. Aperture’s Info inspector also had a Map pane for viewing and assigning locations. [Aperture 3.5 Help](https://aperture.skydocu.com/en/organize-and-sort-photos/organize-photos-using-places/work-with-locations-in-the-info-inspector/)

## Catalogue-backed GPS search

New imports index the primary image’s embedded GPS. In an older library, select photos and choose Metadata → Catalogue GPS from Originals. It verifies each original’s fingerprint once, indexes its versions together and skips offline, unreadable or changed originals. Advanced Search and Smart Albums can compare signed latitude or longitude, or match a radius in kilometres around a coordinate pair. Coordinate comparisons accept the six-decimal values shown in Info. GPS Location presence rules distinguish photos with coordinates, photos checked without valid coordinates and photos yet to be checked.

Search uses the saved catalogue values, including while an indexed original is offline. Coordinates and saved GPS rules require catalogue format 15. An index entry that only records a completed check without coordinates does not require an upgrade.

## Places map browsing

Choose View → Places, the map button beside Grid and List, or Control–M. Places follows the sidebar scope and active filters. It plots geotagged versions even if they share a collapsed stack. Photos at identical coordinates share a pin. Click a pin to select a photo in the filmstrip and Inspector, or choose a thumbnail to centre its location. Open Selected Photo switches to the Viewer. Back returns to Places.

Map pins and selection use the catalogue, so offline originals still appear with an unavailable thumbnail. The Apple Maps basemap may require an internet connection. The app plots the catalogue’s coordinates without requesting the Mac’s location. [Aperture 3.5 Help](https://aperture.skydocu.com/en/organize-and-sort-photos/organize-photos-using-places/view-photo-locations/) [Apple MapKit](https://developer.apple.com/documentation/mapkit/mkmapview)

## Assign, clear and restore photo locations

Select a photo or use Select Photos for a batch. Choose Assign Location, Clear Location or Use Original Location in Metadata or in the Location menu under Info → GPS. Assign uses signed decimal degrees. Clear hides the location for those versions, and Use Original Location removes the override. The embedded GPS index remains available for unedited versions and can still be populated by Catalogue GPS from Originals. A batch records one Undo step. With persistent history enabled, Undo and Redo also work after reopening.

Places, GPS search and Smart Albums use the effective location. The catalogue saves edits and their history in format 16. Edited exports can include the effective location. Original-file export copies the source bytes.

## Map-based location assignment

Open Assign Location for a selected photo version or batch, then expand Pick on Map. Click a point to move the preview pin and fill the signed coordinate fields. Pan or zoom to refine the pick, or edit either coordinate directly. The picker opens around the current coordinates or the selected photos’ known locations when available. Assign Location saves the point through the existing location editor. Cancel discards the draft. The confirmed location updates Places and GPS Smart Albums in the same Undo step. [Apple MapKit coordinate conversion](https://developer.apple.com/documentation/mapkit/mkmapview/convert(_:tocoordinatefrom:))

## Address and place-name lookup

In Assign Location, enter an address or place name and choose Search Apple Maps or press Return in the search field. Choose a result to fill the coordinate fields and centre the preview map if it is open. Assign Location saves the resulting point to the selected versions. Stop Search cancels a request, and Cancel discards the location draft. Latitude and longitude remain editable when Apple Maps returns no matches or is unavailable. The catalogue stores the coordinates through the existing location edit. [Apple MapKit local search](https://developer.apple.com/documentation/mapkit/mklocalsearch)

## Saved named places

Open Assign Location, enter coordinates or choose them with Apple Maps search or Pick on Map, then use Saved Places → Save Current Coordinates. Saved places live in app preferences and are available offline across Isonique libraries. Choose a saved name to fill the draft coordinates and centre an open map. Use Assign Location to apply the coordinates. The Saved Places menu also lets you rename or remove an entry. Photos retain their assigned coordinates when the saved entry is renamed or removed.

## GPX track matching

Select one or more versions and choose Match GPX Track from Metadata or Info → GPS → Location. Choose a GPX 1.0 or 1.1 file, confirm the camera time zone and review the proposed coordinates alongside any existing catalogue location. The time zone defaults to the Mac’s current setting. When a camera timestamp falls in a repeated daylight-saving hour, enter a fixed offset such as UTC+01:00 to disambiguate it.

Matching uses exact fixes or interpolates between the surrounding points in one continuous segment. The maximum gap defaults to two minutes. Missing or invalid timestamps, conflicting fixes, discontinuities and times outside the track can leave a photo unmatched. Uncheck individual matches or cancel to discard the review. Applying saves the checked location changes as one Undo step using the existing catalogue format. Places and GPS Smart Albums update from the assigned coordinates, including for offline originals. GPX reading and matching run locally in the background.

Aperture imported GPX tracks into projects, drew tracks in Places and supported both timestamp matching and manual waypoint assignment. Isonique’s file picker opens a temporary review and saves the confirmed photo coordinates. [Aperture 3.5 Help](https://aperture.skydocu.com/en/organize-and-sort-photos/organize-photos-using-places/import-and-work-with-gps-track-file-data/)

## Project GPX tracks in Places

Select a project, open Places and choose GPX Tracks → Import GPX Track. A file can contain multiple track segments. Places draws each continuous segment separately, including tracks with untimed points, and splits the line at the antimeridian. Fit Map frames visible routes and photo pins. Project routes are available in an empty project and remain visible when a photo filter hides the pins. All Photos and album views continue to show photo pins from their own scope.

Use the track’s submenu to show, hide or remove it. The library saves route geometry and visibility in catalogue format 17, so the project can reopen the route after the GPX source moves. A project library export includes its saved routes, and importing that library copies them into the imported project. Merging edits into an existing project keeps its current track list. Removing a route preserves photo assignments and photo edit history. Match GPX Track continues to use a GPX file for timestamp matching. [GPX 1.1 schema](https://www.topografix.com/GPX/1/1/) · [MapKit polyline rendering](https://developer.apple.com/documentation/mapkit/mkpolylinerenderer)

## Manual GPX waypoint assignment

Open a project in Places and import a GPX file containing waypoints. Files containing only waypoints also work. Click a waypoint pin or use GPX Tracks → [track name] → Assign Waypoint. The preview shows the destination coordinates and the current locations of eligible photo versions. Check the versions to update, including those that have no pin yet. The preview respects the current project filters and excludes trashed versions.

Assign Location saves the checked changes as one Undo step. Cancel closes the preview without saving. The catalogue stores waypoints in format 18 and includes them in project library exports. Reimport files saved with the earlier GPX overlay feature to add their waypoints. [GPX 1.1 schema](https://www.topografix.com/GPX/1/1/)

## Project location assignment

Select a project in Places and choose Assign Project Location. The preview covers every active version in that project, including versions hidden by the current browser filters. It lists versions eligible for assignment and counts versions with existing locations, explicitly cleared locations, or GPS that could not be verified. For versions with no GPS index, the preview reads verified originals to distinguish embedded GPS from missing GPS.

Choose a destination by searching Apple Maps, using a saved place, picking on the map or entering coordinates. Assign Location fills the reviewed missing locations in one Undo step using the existing catalogue format. Cancel discards the preview. Aperture also offered project location assignment through its Project Info HUD. [Aperture 3.5 Help](https://aperture.skydocu.com/en/organize-and-sort-photos/organize-photos-using-places/assign-location-information-to-projects/)

## GPS in edited exports

Enable GPS — current photo location when exporting edited JPEG, PNG or TIFF files. Assigned coordinates are written with the appropriate hemisphere references. The export keeps additional GPS fields such as altitude when the embedded coordinates match the catalogue and the location comes from the original. A newly assigned location writes its coordinates without carrying measurement data from the original location. Unindexed photos fall back to the GPS embedded in the primary image.

Cleared locations and exports with GPS disabled omit GPS. Original-file export remains a byte-for-byte copy with its embedded metadata. [Apple Image I/O GPS dictionary](https://developer.apple.com/documentation/imageio/gps-dictionary-keys)

## Batch export naming templates

Select photos and open Export. Choose a template or enter literal text and tokens in Filename template. Available tokens are `{original}`, `{catalogue}`, `{version}`, `{project}`, `{year}`, `{month}`, `{day}` and `{sequence}`. Sequence tokens use four digits. Isonique appends the extension for the selected output format or the source extension for original export. A blank template and older presets use the existing numbered version names.

Review the final image and optional XMP sidecar names before choosing a destination. Case and Unicode equivalents share the same collision rules. A numeric suffix keeps colliding names distinct and follows the image into its sidecar. Export writes the previewed names to a new folder. Save Preset stores the template with the other export options. [Aperture 3.5 Help](https://aperture.skydocu.com/en/export-photos/rename-photos-at-export/)

## TIFF compression

Select TIFF as the export format, then choose None, LZW, ZIP or PackBits compression. All four modes are lossless and saved as part of the export preset. Presets created before this setting was introduced continue to use uncompressed TIFF output.

## HEIF export

Select HEIF to export an edited `.heic` file with the system Image I/O encoder. HEIF uses the same full-size renderer, longest-edge sizing, quality control, batch filename templates, metadata switches and optional XMP sidecars as the other edited formats. Export presets retain HEIF and its quality setting. The output remains 8-bit sRGB.

## Text watermarks

Enter text in the export sheet to enable a watermark on edited output. Choose a corner or the centre, then set opacity and relative scale while reviewing the first selected photo. The shared Core Graphics and Core Text renderer applies the same watermark after resizing and before JPEG, PNG, TIFF or HEIF encoding. Export presets retain the text and controls, batch export applies them to every selected version, and original-file export ignores watermark settings to preserve the source bytes.

## External editor round trip

Choose Photos → Edit with External Editor or use a photo's context menu. The first use asks for a macOS application; Settings can change or clear that persistent choice. Isonique renders the selected version at full size as a ZIP-compressed TIFF containing enabled EXIF, IPTC and GPS metadata, then opens that isolated file in the editor. Save over the TIFF and choose Import Edited Version in Isonique.

The verified return becomes a new managed derivative with a neutral Isonique recipe and the source photo's project, albums and catalogue metadata. It owns its TIFF master because ordinary Isonique versions must share exactly the same original bytes. The source master and recipe are not modified. Missing, unchanged, non-TIFF and duplicate returns are refused. Cancellation and launch failure remove the temporary handoff. A stale or failed catalogue save removes the installed copy before reporting the error.

## Contact sheets and printable proofs

Use File → Print Contact Sheet or Command-P for the current filtered Browser photos. In Select Photos mode, only the explicit batch selection is included. Contact Sheet arranges 1–10 rows and columns per page; Single-Photo Proof uses one adjusted photo per page. Choose A4, A3 or US Letter paper, orientation, margins and captions from the version name, source filename, catalogue caption or name and caption together. The preview pages use cached thumbnails while Save PDF and Print render the saved full-resolution recipes.

Output Colour supports sRGB, Display P3 and Black and White. RGB modes convert each rendered image with relative-colorimetric intent into the selected image colour space; Black and White converts only the print copy. Reusable presets retain every layout and colour choice. Save PDF writes a self-contained document. Print sends those same PDF pages to the native macOS print panel without modifying the catalogue or originals.

## Non-destructive spot removal

Choose Repair Spot or Clone Spot from Photos, the Viewer editing strip or the Adjustments inspector. New spots are created by clicking a clean source and then the destination blemish. Every stored spot retains an editable source, destination, mode and size; the Viewer draws their source-to-destination relationship and renders the editing canvas at full source resolution.

Clone copies the sampled patch directly. Repair transfers its texture with a local colour offset so it blends into the destination. Ordered spots render after global tone, Levels and Curves and before lens and geometric transforms, using the same source-space recipe for the Viewer and export. Circular feathering and clamped source sampling keep patches safe at image edges. Format 19 protects spot recipes, versions and persistent Undo/Redo history. Lift and Stamp expose Spot Removal as a separate opt-in group.

## Sharpening and luminance noise reduction

Open Detail in the Adjustments inspector for independent Sharpening, Edge sharpening and Luminance noise reduction amounts. Reduction uses a small edge-preserving luminance neighbourhood and keeps the image's channel differences. Global sharpening applies a luminance unsharp mask, while Edge sharpening gates its additional gain by local high-frequency contrast. Flat fields remain neutral.

The shared renderer applies luminance reduction after Levels and Curves, Repair and Clone after reduction, and sharpening before lens and geometric transforms. A 100% Viewer frame and edited export therefore use the same full-resolution pixels. Format 20 protects the three recipe values, versions and optional persistent history. The separate Detail Lift and Stamp group copies all three controls. Older recipes decode neutral values and remain on their existing catalogue version until a Detail adjustment is used.

## Chromatic aberration, vignette and devignette

Open Color Proofing & Lens for signed Red/Cyan and Blue/Yellow aberration correction, Vignette and Devignette. Each aberration slider moves only its named channel radially relative to green, supports inward or outward correction and clamps edge samples. Devignette brightens lens falloff in the source frame before noise reduction, retouching, sharpening and geometry. Vignette darkens the final cropped and rotated composition.

Format 21 protects all four values, versions and optional persistent history. Lens & vignette is a separate Lift and Stamp group, while project merge compares the four controls independently. Older recipes decode neutral values without upgrading. The implementation is manual and profile-free; vignette radius and softness are currently fixed.

## Kelvin white balance and neutral sampling

The Adjustments inspector exposes a 2000 K–12000 K Temperature control and the existing green/magenta Tint control. Sample Neutral opens the full-resolution Viewer Loupe and applies both values in one history entry after sampling an opaque, unclipped neutral grey or white source pixel. Sampling follows the saved crop, rotation, flip, straighten and lens mapping, but reads before the white-balance stage so an existing correction cannot compound itself.

Format 22 protects non-neutral Kelvin values in photos, versions, Lift and Stamp data and optional persistent history. Project merge compares Kelvin independently. Older recipes decode to neutral 6500 K and retain the existing normalized Warmth rendering; changing Kelvin or using the eyedropper clears that legacy offset. The Viewer cache and edited export share the same full-resolution sRGB renderer. RAW camera-neutral metadata, adjustable sample areas, automatic skin-tone or natural-grey modes and extended-range processing remain open.

## Targeted Hue, Saturation and Luminance

Targeted Color in the Adjustments inspector stores multiple named colour ranges. Add built-in red, orange, yellow, green, cyan, blue or magenta ranges, duplicate an existing range, or sample a custom source hue through the full-resolution Viewer Loupe. Each record has a circular hue centre, fully affected core width, smooth falloff and independent Hue, Saturation and Luminance values. Achromatic or transparent Loupe targets are rejected.

The shared renderer evaluates every range from the pixel's original hue, combines overlapping weights, then applies one bounded HSL conversion before Levels and Curves. Neutral or empty records bypass conversion exactly. Adjustment-input histograms and sampled curve points therefore see the targeted-colour result. Format 23 protects range records in photos, versions, targeted-colour Lift and Stamp data and optional persistent history; project merge compares the group independently. Older recipes decode an empty list and remain unchanged.

## Black-and-white channel mixer and tint

Black & White in Adjustments converts the targeted-colour result before Levels and Curves. Red, green and blue contributions range from zero to double strength; Rec. 709 values are the neutral defaults. The renderer clamps each contribution and the mixed output, so channel isolation, all-zero black and over-range white remain bounded. Tint Hue and Tint Strength optionally colourise the monochrome result while preserving HSL lightness. Strength zero produces equal RGB channels.

Format 24 protects the enable state, channel contributions and tint in photos, versions, the separate Black & white Lift and Stamp group and optional persistent history. Project merge compares all six controls independently. Older recipes decode disabled neutral values. The Black & White preset now enables the mixer instead of discarding channel information with global desaturation; existing saved saturation-zero recipes keep their historical rendering.

## Manual red-eye correction

Choose Manual Red-Eye from Photos, the Viewer Retouch menu or the Adjustments inspector. Clicking a pupil creates a source-space correction; choose any saved eye to reposition it or change its pupil size and darkness. Multiple regions are ordered and independently editable. Their dashed Viewer outlines are editing aids and never enter exported pixels.

The shared full-resolution renderer runs red-eye correction after basic tone and white balance and before Targeted Color, Black & White, Levels and Curves. A feathered circular mask affects only pixels whose red channel is measurably dominant over both other channels. Darkness can further lower the corrected pupil while neutral, green, blue and non-dominant skin pixels remain byte-identical. Regions clamp to image bounds, including pupils centred on an edge.

Format 25 protects eye records in photos, versions, the separate Red-eye Lift and Stamp group and optional persistent history. Project merge compares the complete region list. Older recipes decode an empty list and keep their previous rendering and catalogue version. Automatic face or eye detection is intentionally still pending.

## Definition local contrast

Open Detail in the Adjustments inspector for Definition strength and Definition radius. Strength runs from neutral to full; radius is stored as 0.25%–8% of the image's shorter side so the spatial scale remains consistent between preview sizes and full-resolution output. Reset Detail restores neutral strength and the 2% default radius.

The shared CPU renderer builds a separable local luminance mean, adds a bounded high-pass delta and leaves channel differences intact. Constant fields bypass without pixel changes. A full-strength correction can alter luminance by no more than 0.12, preventing hard transitions from creating unbounded bright or dark halos. Definition runs after luminance noise reduction and before Repair, Clone and sharpening.

Format 26 protects strength and radius in photos, versions, the Detail Lift and Stamp group and optional persistent history. Project merge compares both fields independently. Older recipes decode neutral strength and the default radius without upgrading.

## Reusable custom adjustment presets

Manage Custom Presets is available from the Inspector's Apply Preset menu and the Photos menu. A preset stores the current photo's recipe plus an explicit set of adjustment groups. Create starts with every non-spatial group selected; Update replaces the saved recipe and group selection from the current photo, while Rename and Delete do not touch photographs. Presets live in application preferences and are available across Isonique libraries.

Geometry, Local Brush, Spot Removal and Red-eye are classified as spatial. They are excluded by default so applying a preset preserves crop, rotation, photo-specific masks, Repair/Clone points and pupil regions. Users can deliberately select those groups, with a warning in both the manager and application review. Before Apply, the review lists target versions, selected groups, each version's groups that actually differ and the number that will change.

Single-photo and batch application use normal catalogue history and stale-write protection. Batch history follows the established photo-edit model: each changed version is one Undo/Redo step. Older preset payloads using `recipe` instead of `adjustments`, or omitting identifiers and groups, decode with the safe non-spatial group set. Existing built-in, import, export, print, metadata and relocation presets remain independent.

## Edge-aware local brush masks

Dodge and Burn now offer Edge Aware painting in both Fit and 100% Viewer modes. Each stroke stores whether edge protection was enabled. The source-space raster samples straight sRGB luminance at the first stroke point, keeps close tones fully affected and applies a smooth falloff before rejecting a high-contrast boundary. Normal and erase strokes share the same edge rule, size, softness and strength model.

Show Mask asks the shared source and geometry pipeline for a yellow Dodge or blue Burn overlay. The overlay applies crop, rotation, flip, straighten and lens geometry but remains a separate Viewer layer, so edited exports contain only the adjustment. Invert Mask and Mask Opacity are persistent settings for each Dodge or Burn mask. Opacity commits after a slider gesture as one history entry. An adjustment with no positive stroke remains inactive even if malformed saved settings request inversion.

Format 27 protects the per-stroke edge flag and per-mask opacity and inversion in photos, versions, Lift and Stamp, custom presets, project merge and optional persistent history. Existing strokes decode with edge protection off and default mask settings preserve their exact earlier rendering.

## Local Saturation and Definition brushes

Saturation and Definition join Dodge and Burn in the Photos menu, editing strip, Inspector and four-way Viewer control. Each has its own ordered strokes, erasures, edge-aware coverage, overlay colour, inversion and post-stroke opacity. Masks remain independent when they overlap: Saturation scales source chroma without changing the Definition mask, while Definition applies the existing bounded 2%-radius luminance local-contrast kernel through its own coverage after basic tone processing.

Zero mask opacity is pixel-neutral. Edge detection continues to sample original straight-sRGB luminance, so an effect does not leak across a protected boundary even when another mode overlaps it. Both effects run in the shared CPU preview/export pipeline. Format 28 distinguishes the new adjustment identifiers from format-27 Dodge/Burn recipes, allowing the preceding build to reject the newer catalogue cleanly instead of failing while decoding an enum value it does not understand.

## Local Sharpening and Luminance Noise Reduction brushes

Sharpening and Luminance Noise Reduction now join the four existing local modes in Photos, the editing strip, the Inspector and the six-way Viewer control. Each reuses the established source-coordinate mask, edge-awareness, erasing, inversion and post-stroke opacity. Sharpening applies the same bounded luminance high-pass kernel as the global Detail control after retouching and global sharpening. Luminance Noise Reduction applies the same edge-preserving luminance neighbourhood after global reduction and before Definition and retouching. Brush strength scales kernel output per pixel rather than selecting a separate preview approximation.

The two masks remain independent and compose in a stable order where they overlap: local reduction runs before local sharpening. Constant fields remain unchanged, edge-aware strokes do not cross a sampled high-contrast boundary and zero mask opacity bypasses each operation. Viewer previews and edited exports use this one CPU path; originals and Original-format exports remain byte-identical. Format 29 distinguishes the two new adjustment identifiers so format-28 builds reject those catalogues cleanly.

## Local Contrast and Blur brushes

Contrast and Blur complete two more Aperture-style local operations using the same source-coordinate strokes, edge-aware mask sampling, erasing, inversion, post-stroke opacity and Viewer-only overlays as the existing brushes. With eight modes, the Viewer uses a compact labelled picker instead of compressing every name into one segmented row. The Photos menu, editing strip and Inspector expose both operations directly.

Contrast expands luminance around the exact 8-bit sRGB midpoint after Curves and Levels, preserving a uniform 128-grey field while separating shadows and highlights at maximum strength. Blur blends toward the shared separable luminance neighbourhood after local and global sharpening, retaining the source's colour differences. Zero opacity bypasses both effects. Edge-aware masks protect the opposite side of a high-contrast boundary, and overlaps compose deterministically with Contrast before Blur. Format 30 distinguishes the two identifiers so format-29 builds reject incompatible recipes cleanly.

## Local Tint and Skin Smoothing brushes

Tint and Skin Smoothing complete two more Aperture-style local operations on the shared source-coordinate, edge-aware mask infrastructure. Tint stores a wrapped hue and bounded saturation and blends towards that colour while preserving source lightness. Skin Smoothing stores amount and detail preservation, selects warm skin-like pixels inside its mask and attenuates the smoothing kernel around retained fine detail. Both modes support erase, inversion, post-stroke opacity, overlays, Fit and 100% brushing, normal history and Lift and Stamp.

Skin Smoothing evaluates photographic colour before Tint so a strong cool tint cannot disable the skin classifier where the two masks overlap. Both use the full-resolution CPU preview/export renderer and keep originals untouched. Format 31 distinguishes their identifiers and settings, while older recipes decode with neutral/default settings and keep their previous appearance.

## Multiple local-adjustment instances

Every local effect can now own multiple named instances. Each instance persists its enabled state, ordered source-coordinate strokes, mask opacity and inversion plus Tint or Skin Smoothing parameters where applicable. The Viewer control creates, selects, renames, enables, reorders, duplicates and deletes instances. Every mutation uses normal photo history, so it participates in persistent Undo/Redo and stale-write protection.

Same-type instances composite in their displayed order; different effect types retain the established renderer stage order. Lift and Stamp and explicitly selected spatial custom presets copy the complete instance list, while safe preset defaults continue to preserve spatial recipes. A format-31 recipe remains unchanged when merely opened and renders through a stable one-instance compatibility view. Its legacy masks are converted to format 32 only when the user first uses an instance-aware editing action, and a pixel comparison verifies that conversion does not alter the rendered result.

## Local Polarize and Halo Reduction brushes

Polarize and Halo Reduction complete the outstanding Aperture-style local effect set on the shared instance-aware mask system. Polarize stores a bounded intensity for each instance and selectively darkens and increases saturation in cool chromatic sky-like pixels; neutral intensity, achromatic pixels and warm colours bypass the operation. Halo Reduction stores bounded amount and radius controls per instance and moves luminance overshoot towards a separable local mean after global and local sharpening. Neutral amount and flat fields remain unchanged, and its radius scales with the shorter rendered image side.

Both modes are available from Photos, the editing strip, the Inspector and the Viewer brush picker. They inherit independent names, enabled state, ordering, duplicate/delete actions, source-coordinate strokes, edge awareness, erase, inversion, opacity and Viewer-only overlays. Same-type instances composite in their displayed order in the one full-resolution preview/export renderer. Format 33 protects the new identifiers and parameters; format-32 instances decode compatible defaults, while a format-32 catalogue containing either new mode is rejected until upgraded. Lift and Stamp and explicitly spatial custom presets copy the complete records.

## Pressure-sensitive tablet brushes

The Viewer brush canvas now uses a native AppKit input surface so pen and eraser tablet events provide pressure alongside source coordinates. Size and strength have independent Off, Soft, Linear and Firm response mappings plus persisted minimum values. Mapping is resolved while the stroke is captured, and bounded radius and strength scales are stored on every sampled point. Existing mouse and trackpad input deliberately supplies no tablet pressure and therefore retains the configured fixed size and strength.

The source-space mask raster interpolates both scales along each segment while retaining edge protection, softness, erase, inversion and instance ordering. This makes the full-resolution Viewer and export output independent of later preference changes. Format 34 is required only when a point contains a non-default pressure scale; fixed format-33 recipes decode scale 1, omit default fields when re-encoded and do not upgrade merely because they are opened or saved.

## Source-space brush caching and Viewer magnification

Viewer, mask overlays and export now share a thread-safe source-space mask LRU bounded to 128 MiB and 12 entries. An unchanged instance is an exact hit. When a painting session appends strokes, the cache reuses the longest matching recipe prefix and rasterises only the suffix. Editing an earlier stroke, changing source dimensions or changing the decoded source fingerprint used by an edge-aware stroke causes a full rebuild. A cancelled request neither returns a cached result nor publishes partial work. Mask rasters remain capped at 2048 pixels on the longest source edge.

The performance contract is measurable without machine-sensitive wall-clock assertions: a 24-stroke append session performs 24 stroke rasters rather than 300, the clean and incremental masks agree, and a 12,000 × 8,000 source stays within a 16 MiB fixture budget. The format-34 pressure workflow confirms Undo/Redo, restart persistence, original preservation and byte-identical full-resolution Viewer and PNG export while the export records an exact shared-cache hit.

The Viewer also accepts the native macOS magnification gesture in Select and Brush modes. Pinching outward leaves Fit for continuous pixel zoom, pinching inward to the fitted scale returns to Fit, and the range is bounded to 1–800%. The fitted image scale, not an assumed 100%, is captured as the gesture baseline. A 0.5% hysteresis keeps tiny changes at Fit while still allowing fine increments immediately above it. The established Fit/100% control remains available. This works with Mac trackpads and compatible devices that emit AppKit magnification gestures; macOS does not expose arbitrary touch-display contacts as iOS-style touches without driver translation.

## Synchronized Compare navigation

The two-photo Compare workspace uses native AppKit scroll viewports with the same fit-relative 1–800% pixel-scale policy as the main Viewer. Both panes begin in Fit. Pinching, pressing 100% or scrolling updates a normalized centre coordinate; synchronized mode applies that coordinate and scale to both panes, so a wide Primary and tall Select image stay aligned without equating raw pixel offsets. Each pane retains its own Fit/100% control. Turning off Synchronize Navigation copies the shared state and then permits separate zoom and pan; turning it back on makes the Primary pane authoritative.

Fit requests retain the established 1800-pixel preview. Entering pixel zoom changes request identity and loads full resolution through the shared Viewer cache; changing magnification inside pixel mode only transforms the viewport. Returning to Fit cancels obsolete full-resolution work and requests the bounded preview. Replacing a comparison photo also changes task identity. Navigation lives only in SwiftUI/AppKit state and never writes catalogue recipes or enters exports.

## Multi-photo Compare and Primary/Select workflow

Compare now starts from two or more visible photos selected in the Browser. The current selection becomes Primary, the remaining photos are numbered Selects and responsive layouts use one, two or three columns with additional rows as space requires. Clicking a pane chooses its Select. Arrow keys move between Selects, Option-P promotes the active Select and Option-Delete removes it while protecting the final Primary/Select pair. Selecting another visible Browser photo during Compare adds it without silently changing the Primary.

Synchronized navigation stores one normalized scale and centre for every visible pane. Independent mode materializes a separate state for each photo; re-enabling synchronization makes the current Primary authoritative, and removing photos discards their stale navigation state. Full-resolution loads retain photo-specific task identities, so cancellation and comparison changes cannot publish an obsolete frame. The workflow is transient UI state: it does not save catalogue recipes, alter originals or change edited export pixels.

## Persistent Light Table workspace

Format 35 adds library-level named Light Table layouts without adding fields to a photo or its adjustment recipe. Each item stores a stable photo identifier, centre, size, rotation and stacking order on a 1600 × 1000 canvas. A layout starts with only the selected photos visible in the current filtered Browser. Adding photos later preserves every existing position. Layouts appear in their own sidebar section and can be renamed, duplicated or deleted.

The native canvas supports direct dragging, corner resizing, multi-selection, six alignments, five-degree rotation, bring-to-front/send-to-back ordering and removal. Fit scales the full canvas into the available workspace; 100% shows one canvas point per display point and requests the selected photo at full resolution through the shared Viewer cache. Every committed operation records one Light Table history snapshot, including persistent Undo/Redo when enabled.

PDF and native print output use one page at the saved canvas dimensions. Items render in stacking order through the same full-resolution adjustment renderer used by edited export, then apply only Light Table placement and rotation. Layout operations therefore cannot change catalogue photo recipes, original bytes or ordinary export output. The macOS print panel scales the canvas to the selected paper.

## Next checkpoint

Add a dedicated full-screen photography workspace with independently hideable Browser, filmstrip, Inspector and toolbar panels plus remembered layouts for editing, culling and Compare. Support native full-screen entry/exit, keyboard panel cycling and a secondary-display Viewer where available. Test state restoration, focus and shortcuts, mixed-display scale and colour profiles, cancellation during full-resolution transitions and preservation of recipes and exports.

## Pending physical camera checks

1. Run the [physical PTP camera import checklist](../VALIDATION.md#physical-ptp-camera-import) when a camera is available. Record thumbnail, deselection, active transfer cancellation and reconnect results.
2. Run the [physical tethered capture checklist](../VALIDATION.md#physical-tethered-capture) with a camera that advertises the remote shutter capability. Measure the interval between RAW and JPEG arrivals and check the behavior after cancellation and rapid successive shots. The quiet period is provisional because the native callback reports file additions without identifying the originating shutter request.

Other open core work includes library merging and repair. Build and interaction evidence belongs in the test record.
