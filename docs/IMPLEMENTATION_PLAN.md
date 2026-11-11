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

## Next checkpoint

Add TIFF compression choices to export presets. Verify lossless pixel round trips and compatibility with existing presets.

## Pending physical camera checks

1. Run the [physical PTP camera import checklist](../VALIDATION.md#physical-ptp-camera-import) when a camera is available. Record thumbnail, deselection, active transfer cancellation and reconnect results.
2. Run the [physical tethered capture checklist](../VALIDATION.md#physical-tethered-capture) with a camera that advertises the remote shutter capability. Measure the interval between RAW and JPEG arrivals and check the behavior after cancellation and rapid successive shots. The quiet period is provisional because the native callback reports file additions without identifying the originating shutter request.

Other open core work includes library merging and repair. Build and interaction evidence belongs in the test record.
