# Aperture test results

## Baseline, 9 November 2026

- `make test` passed 41 XCTest cases on arm64 macOS 27.3 (26C5035r), Xcode 27.2, Swift 6.4.2. Coverage includes generated still images, library round trips, original hashes, export, geometry, tone, organization and verified backup/restore.
- The existing release configuration targets macOS 14+ and explicitly builds Apple Silicon. Only this macOS native version exists. Intel, older macOS runtime, camera/tether hardware, real RAW fixtures, HDR/wide-gamut display accuracy and VoiceOver are untested at baseline.
- Existing build history is in [VALIDATION.md](../VALIDATION.md). A screenshot verifies startup rendering; interactive tests are recorded separately when performed.
