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

## Next implementation slice

1. Add a local-mask recipe to `Adjustments` with a neutral default. Store normalized stroke points and map them consistently through crop, rotate and flip.
2. Add a Viewer brush tool for dodge and burn. Expose size, softness and strength, plus erase and reset. Keep an Undo step per stroke.
3. Apply the mask through the shared renderer. Test coverage, edge falloff, crop and rotation mapping, preview/export parity, persistent recipes, Undo and original hashes.
4. Follow with clipping overlays, a Loupe, and independent RGB and luminance curves. Review performance with large images as these tools enter the Viewer.

Other open core work includes Finder Trash handoff, batch relinking, original relocation, library merging/repair, import at camera devices, and interrupted-write recovery across multiple app processes. Build and interaction evidence should stay in the test record.
