# Aperture test results

## Baseline, 9 November 2026

- `make test` passed 41 XCTest cases on arm64 macOS 27.3 (26C5035r), Xcode 27.2, Swift 6.4.2. Coverage includes generated still images, library round trips, original hashes, export, geometry, tone, organization and verified backup/restore.
- The existing release configuration targets macOS 14+ and explicitly builds Apple Silicon. Only this macOS native version exists. Intel, older macOS runtime, camera/tether hardware, real RAW fixtures, HDR/wide-gamut display accuracy and VoiceOver are untested at baseline.
- Existing build history is in [VALIDATION.md](../VALIDATION.md). A screenshot verifies startup rendering; interactive tests are recorded separately when performed.

## Core persistence, Trash and multiple libraries

- `make test` passed 47 XCTest cases. Added import metadata and album round trip, symlink copy, malformed sidecar and save rollback/retry, safe library creation, Trash backup/restart, workspace selection, undo/redo and failed workspace write tests.
- `make build` passed arm64 release compilation, staged strict ad-hoc signature verification and archive generation. The native launch probe reported one visible arm64 Isonique window.
- Exercised the native import picker and sheet with a synthetic PNG. Command-Delete hid it from All Photos, the Trash sidebar showed it, and Put Back cleared Trash. Shift-Command-N created a separate empty library, then File → Open Isonique Library switched back and showed the restored photo. Verified source and stored copy SHA-256 matched and the two catalogues contained one and zero photos respectively.
- A sync conflict produced 16 untracked duplicate files during the pass. Verified each against Git and preserved them outside the repository in `checks/isonique-sync-duplicates`. SwiftPM initially compiled the duplicate Swift sources. Normal builds resumed after relocation.
- Photo Trash retains original files and is included in backup. Finder Trash handoff and folder, album, and version Trash remain pending. Catalogue format 1 remains readable by older builds, which ignore the photo Trash field.
