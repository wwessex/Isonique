# Isonique implementation plan

Keep the existing native app, independent catalogue and shared renderer. Deliver individual workflows with persistence, UI, and test evidence before extending their scope.

| Priority | Order and acceptance checks |
| --- | --- |
| 1. Core | Make each imported record atomic with its final metadata and membership. Verify rollback and duplicate behavior. Add photo Trash and Put Back with original bytes preserved, then in-app creation and switching between independent libraries. Follow with referenced originals, offline/relink and consolidation. Fix write-failure handling and import progress/cancellation. |
| 2. Daily workflows | Expand Smart Album rules and browser search together. Add browsable versions, stack picks, folders, color labels and keyboard culling. Add global photo adjustments with shared render and export tests. Improve browser layouts and selection. |
| 3. Advanced | Add local masks and brush recipes, compare/Loupe/Light Table, richer metadata, Faces/Places, tethering where hardware allows, and output workflows for external editing, watermarking, print and local galleries. |
| 4. Modernization | Profile the native app with large catalogues and high-resolution files. Improve render cancellation, catalogue and cache performance, wide-gamut and high-bit-depth behavior, native accessibility and display validation. |

## Checkpoint

Baseline audited at `0ebda9a`. Per-file import transaction, photo Trash/Put Back, independent library creation and atomic workspace photo edits are complete. Referenced import, missing-file status, verified single-file relink and copy consolidation are implemented. Import runs as a cancellable job with per-file progress and optional new project creation. Compound Smart Albums and advanced browser search now use shared criteria. Horizontal/vertical flip and basic brightness, vibrancy and sepia are in the shared renderer. Keyboard culling, color labels and persistent label names are in the native workspace. Browsable versions and side-by-side comparison now use a stable shared-original identity. Stacks have persistent picks, album picks and collapsed Browser covers. The native List Browser uses the workspace filters, selection and review commands and remembers its layout. Historical evidence, baseline status and remaining gaps are indexed in [workflow comparison](APERTURE_FEATURE_PARITY.md). Runtime evidence belongs in [test results](APERTURE_TEST_RESULTS.md).

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

Quick Search finds catalogue IPTC title, creator, copyright and credit. Advanced Search and Smart Albums offer field-specific substring and exact comparisons with their negations. Each creator is compared separately. An IPTC Smart Album rule requires catalogue format 12. Search reads the catalogue so results work with offline originals. Values inherited only from an older library’s originals remain available in Info and export.

## Reusable metadata presets

Metadata → Batch Change → Reusable Metadata Presets saves checked caption and IPTC fields, plus the chosen flat keyword mode. Loading a preset fills the editor, where users can review, revise and apply the results as one Undo step. Presets live in app preferences and are shared across libraries. Case-insensitive duplicate names are refused.

Import Options offers the same presets independently of storage, pairing and filename choices. A chosen preset applies after the import caption, keyword and rating defaults. Matching XMP fields take precedence. Saved import options and full import presets keep their chosen metadata values as a snapshot. Removing a reusable preset leaves saved import snapshots and previously edited photos intact.

## Next checkpoint

Add IPTC metadata fields to selective Lift and Stamp. Reuse existing per-field merge rules and grouped history so a Stamp applies only checked fields and preserves the rest. Verify single and visible batch selection, explicit clears, ordered creators, Undo/Redo after reopening and legacy catalogues. After that, add a reviewed way to catalogue inherited IPTC fields on older originals so they become searchable without reimport.

## Pending physical camera checks

1. Run the [physical PTP camera import checklist](../VALIDATION.md#physical-ptp-camera-import) when a camera is available. Record thumbnail, deselection, active transfer cancellation and reconnect results.
2. Run the [physical tethered capture checklist](../VALIDATION.md#physical-tethered-capture) with a camera that advertises the remote shutter capability. Measure the interval between RAW and JPEG arrivals and check the behavior after cancellation and rapid successive shots. The quiet period is provisional because the native callback reports file additions without identifying the originating shutter request.

Other open core work includes library merging and repair. Build and interaction evidence belongs in the test record.
