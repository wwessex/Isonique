# Isonique validation

[Workflow test results](docs/TEST_RESULTS.md) records the native macOS checks for library management, review and rendering, including which RAW samples and system versions were exercised. The separate [development provenance notes](MECHANICS.md) describe historical research that informed some behaviours.

## Reproduce the checks

- Run `make check-branding` to check the bundle identity and catch common misleading product claims in the checkout.
- Run `make test` for the core and workspace XCTest suites. Set `ISONIQUE_RAW_FIXTURES` to enable the optional camera sample test, or use `make test-raw` for the optimised RAW test alone.
- Run `make build` to compile and ad-hoc sign the arm64 bundle. Extract `build/Isonique.zip` to a local folder and run `codesign --verify --deep --strict /absolute/path/to/Isonique.app` to verify the packaged copy.
- Follow the [README smoke test](README.md#development) to launch with a disposable catalogue and capture the window.

The supported deployment target is macOS 14. Native validation has been performed on Apple Silicon with macOS 27.3. Running on older macOS versions, using physical camera devices and recovering a real legacy Aperture library remain separate validation tasks.

## Physical PTP camera import

Use a disposable library and a physical USB camera in PTP or Photo Transfer mode. Put at least three distinct test photos on the camera. A larger group of photos gives you time to cancel an active transfer. Record the Isonique commit, macOS version, camera model, firmware and USB mode with the results. [README smoke test](README.md#development)

1. Confirm the camera appears in macOS Image Capture, then close Image Capture before opening Isonique’s File → Import from Camera or Card. If Image Capture sees the camera and Isonique does not, record the app’s signing configuration and check Apple’s ImageCaptureCore import requirements. [Image Capture user guide](https://support.apple.com/guide/image-capture/imgcp1003/mac) · [ImageCaptureCore configuration](https://developer.apple.com/documentation/imagecapturecore/)
2. Choose the camera and confirm the grid shows recognizable thumbnails for the test photos. The selection should start empty.
3. Choose one photo and import it. Check the library count and filename, open the managed original, and confirm the other test photo was excluded.
4. Start another import and click Cancel Import while a transfer is active. Record how many files completed before cancellation. Reopen the disposable library and confirm it contains only complete imports. Check that the camera still lists the source photos.
5. Reopen the camera browser, select a photo and disconnect the cable. Check that the grid and selection clear and Import Options becomes unavailable. Reconnect, choose the camera again, confirm thumbnails load with an empty selection, and import a photo that has not already been imported.
