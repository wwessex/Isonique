# Isonique validation

[Workflow test results](docs/APERTURE_TEST_RESULTS.md) records the native macOS checks for library management, review and rendering, including which RAW samples and system versions were exercised. The separate [development provenance notes](MECHANICS.md) describe historical research that informed some behaviours.

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
3. Select All, then uncheck at least one photo. Confirm the count changes and import the remaining selection. Check the library count and filenames, open the managed originals, and confirm the unchecked photo was excluded.
4. Start another import and click Cancel Import while a transfer is active. Record how many files completed before cancellation. Reopen the disposable library and confirm it contains only complete imports. Check that the camera still lists the source photos.
5. Reopen the camera browser, select a photo and disconnect the cable. Check that the grid and selection clear and Import Options becomes unavailable. Reconnect, choose the camera again, confirm thumbnails load with an empty selection, and import a photo that has not already been imported.

## Simulated tethered capture

Run the signed build against a disposable library.

```sh
make build
tether_dir=$(mktemp -d)
ditto -x -k build/Isonique.zip "$tether_dir"
open -na "$tether_dir/Isonique.app" --args --library "$tether_dir/Library" --simulate-tether
```

Open File → Simulated Tethered Capture. Capture a shot and check that one JPEG enters the library even though the simulator repeats the file notification. While a shot is active, Capture is disabled. Try Cancel Shot before transfer completes, then disconnect and reconnect. A new capture after reconnect should import one new photo. The XCTest simulator covers RAW/JPEG split arrivals and cancellation after a prior file commits.

## Physical tethered capture

Use a disposable library and record the camera model, firmware, USB mode, macOS version and capture format. Use the signed bundle from `make build`.

1. Open File → Tethered Capture, choose the camera and connect. If the camera is import-only, confirm the panel reports that remote shutter is unavailable and Capture stays disabled.
2. On a camera that supports the Mac-triggered shutter, set it to single-shot JPEG and click Capture. Verify the shutter fires once, then open the imported JPEG in the Viewer and confirm earlier files on the camera were excluded.
3. Switch to RAW + JPEG and shoot. Verify both files arrive, link as one RAW/JPEG pair in the library and remain on the camera. Record the time between arrivals if a companion falls outside the grouping window. Repeat with two successive shots.
4. Cancel while waiting for a shot or transferring its files. Check that complete imports remain readable and reconnect before issuing another shot. Repeat with a cable disconnect and verify that reconnect starts from the current camera catalogue.
