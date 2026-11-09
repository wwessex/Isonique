# Aperture implementation plan

Keep the existing native app, independent catalogue and shared renderer. Deliver individual workflows with persistence, UI, and test evidence before extending their scope.

| Priority | Order and acceptance checks |
| --- | --- |
| 1. Core | Make each imported record atomic with its final metadata and membership. Verify rollback and duplicate behavior. Add photo Trash and Put Back with original bytes preserved, then in-app creation and switching between independent libraries. Follow with referenced originals, offline/relink and consolidation. Fix write-failure handling and import progress/cancellation. |
| 2. Daily parity | Expand Smart Album rules and browser search together. Add browsable versions, stack picks, folders, color labels and keyboard culling. Add global photo adjustments with shared render and export tests. Improve browser layouts and selection. |
| 3. Advanced | Add local masks and brush recipes, compare/Loupe/Light Table, richer metadata, Faces/Places, tethering where hardware allows, and output workflows for external editing, watermarking, print and local galleries. |
| 4. Modernization | Profile the native app with large catalogues and high-resolution files. Improve render cancellation, catalogue and cache performance, wide-gamut and high-bit-depth behavior, native accessibility and display validation. |

## Checkpoint

Baseline audited at `0ebda9a`. Per-file import transaction, photo Trash/Put Back, independent library creation and atomic workspace photo edits are complete. Referenced import, missing-file status, verified single-file relink and copy consolidation are implemented. Import runs as a cancellable job with per-file progress and optional new project creation. Compound Smart Albums and advanced browser search now use shared criteria. Horizontal/vertical flip and basic brightness, vibrancy and sepia are in the shared renderer. Keyboard culling, color labels and persistent label names are in the native workspace. Browsable versions and side-by-side comparison now use a stable shared-original identity. Stacks have persistent picks, album picks and collapsed Browser covers. The native List Browser uses the workspace filters, selection and review commands and remembers its layout. Historical evidence, baseline status and remaining gaps are indexed in [feature parity](APERTURE_FEATURE_PARITY.md). Runtime evidence belongs in [test results](APERTURE_TEST_RESULTS.md).

Dodge and Burn are integrated with the Viewer and shared renderer. Format 4 stores strokes with the edit recipe, snapshots and optional persistent Undo/Redo. Coverage, edge falloff, geometry mapping, persistence, Undo and preview/export consistency have automated tests.

The Viewer and comparison panes have highlight and shadow warnings with persistent thresholds and View menu controls. The separate display overlay uses rendered pixels before proofing. Automated tests cover threshold boundaries and export isolation, and native QA covered the menu switches, shortcut, threshold sliders and comparison panes.

The single-photo Viewer has a pointer-driven Loupe with full-resolution sampling, 200/400/800% magnification, a pixel grid and 8-bit sRGB readings. Tests cover coordinate mapping and alpha, and native QA verified the menu, readout and shortcut.

The shared renderer and Inspector support independent red, green, blue and luminance curves. Format 5 protects the new recipes. Native QA covered point controls and Undo/Redo, and automated tests cover channel isolation, persistence and export pixels. The test record includes a 12 MP render measurement.

The Inspector histogram supports luminance, combined RGB and individual channels from one edited preview. Selecting a histogram view is a persistent UI preference.

## Next implementation slice

1. Extend Levels with per-channel controls and preserve existing recipes and export rendering.
2. Use the channel histograms in the adjustment graphs and qualify higher-resolution tone workflows.

Other open core work includes Finder Trash handoff, batch relinking, original relocation, library merging/repair, import at camera devices, and interrupted-write recovery across multiple app processes. Build and interaction evidence should stay in the test record.
