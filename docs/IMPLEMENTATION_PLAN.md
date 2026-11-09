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

Relocation also works for already-referenced originals. The chooser defaults to keeping old external files. If the user elects to move them, a source that another record still references remains in place. Selecting the current folder reports the file without moving it.

File → Open Recent Library remembers up to ten successfully opened libraries. It uses verified opening and shows parent folders for duplicate names. Clearing the list preserves the startup library.

File → Export Project as Library packages the active photos in one project as a verified, independent library. It copies each shared original once and includes referenced originals as managed copies. Relevant albums, stack picks and surviving pairs stay with the photos. Smart Albums whose results would change because originals become managed are saved as regular albums with their existing matches. Trash and undo history are outside the export scope.

File → Import Project Library adds a verified, self-contained export as a separate project. Copies are independent even when their bytes match originals in the destination. The importer remaps colliding identities, scopes Smart Albums to the imported project and saves the whole project together. Cancellation and save failures clean up the copies. Crash recovery for forcibly interrupted catalogue writes remains open.

File → Merge Project Library reconciles a self-contained export with its matching project by stable IDs. The user chooses which matching photo values to keep. New versions reuse a verified original, while new originals are staged and published with one catalogue update. An explicit option applies source Trash changes. Photos moved to a different destination project stay in place.

New exports record the project photo IDs and original fingerprints at export time. Merge can use that record to identify previously exported photos that were removed. Destination-only additions stay in place, and older exports apply only explicit Trash changes. The review shows proposed additions, updates, copies and Trash moves before staging.

New exports record the starting editable values for each photo. Merge combines changes made on only one side and uses the conflict preference when both sides changed a field differently. The review identifies conflicting fields and matching photos without an edit baseline. Membership-only exports retain the previous merge behavior.

Independent controls such as Exposure and Contrast merge separately. Geometry, Levels, Curves, channel adjustments and brush masks each stay grouped, and the review names the control or group that needs a decision.

Project exports also record the starting collapsed state, global stack picks and album picks. Merge applies one-sided changes and pick removals, and previews conflicting picks separately from photo conflicts. It limits presentation changes to stacks fully within the merge scope. Older exports keep the previous stack merge behavior.

Project exports record eligible album definitions. Merge compares names independently from complete Smart Album rules, and the review identifies conflicting fields. Right-click a regular album to rename it. Regular albums shared across projects at export or merge are protected, including memberships in Library Trash. Smart Albums must stay scoped to the matching project on both sides. Rules exported as fixed memberships, album type or scope changes, and matching definitions in older exports keep their destination values. Album deletion reconciliation remains open.

## Next implementation slice

1. Add a read-only whole-library merge preflight. Match projects and originals by stable IDs, report incompatible fingerprints and shared originals, and preview additions across multiple projects before enabling catalogue writes.

Other open core work includes Finder Trash handoff for Library Trash, relocation naming and subfolders, library merging/repair, import at camera devices, and interrupted-write recovery across multiple app processes. Build and interaction evidence should stay in the test record.
