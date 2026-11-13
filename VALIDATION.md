# Isonique validation

[Workflow test results](docs/TEST_RESULTS.md) records the native macOS checks for library management, review and rendering, including which RAW samples and system versions were exercised. The separate [development provenance notes](docs/DEVELOPMENT_PROVENANCE.md) describe historical research that informed some behaviours.

## Reproduce the checks

- Run `make check-branding` to check the bundle identity and catch common misleading product claims in the checkout.
- Run `make test` for the core and workspace XCTest suites. Set `ISONIQUE_RAW_FIXTURES` to enable the optional camera sample test, or use `make test-raw` for the optimised RAW test alone.
- Run `make build` to compile and ad-hoc sign the arm64 bundle. Extract `build/Isonique.zip` to a local folder and run `codesign --verify --deep --strict /absolute/path/to/Isonique.app` to verify the packaged copy.
- Follow the [README smoke test](README.md#development) to launch with a disposable catalogue and capture the window.

The supported deployment target is macOS 15. Native validation has been performed on Apple Silicon with macOS 27.3. Running on macOS 15 or 26, using physical camera devices and recovering a real legacy Aperture library remain separate validation tasks.

## Physical pressure-sensitive tablet

Use the signed build, a disposable library and a pen tablet that macOS recognises. Record the tablet model, driver, macOS version and Isonique commit.

1. Open a photo, select a local brush and leave Tablet Size and Tablet Strength on Linear. Draw one stroke from light to firm pressure. Show Mask should reveal increasing width and opacity without gaps.
2. Set Tablet Size to Off and Tablet Strength to Firm. Draw another light-to-firm stroke. Its width should stay fixed while opacity changes. Reverse the settings and confirm only width changes.
3. Change both minimum controls and compare Soft, Linear and Firm at mid pressure. Mouse and trackpad strokes must still use the fixed Size and Strength values.
4. Undo and Redo each stroke, reopen the library and export the edited photo. Confirm the masks persist and the Viewer matches export. Disconnect the tablet and confirm ordinary pointer painting still works.

## Physical Viewer magnification gesture

Use the signed build and a Mac trackpad or display/input driver that advertises standard AppKit magnification gestures. Record the hardware, driver and macOS version. A MacBook Pro trackpad is supported; current MacBook Pro displays do not provide direct touch contacts.

1. Open a large photo in the Viewer and pinch outward from Fit. Confirm the app enters continuous pixel zoom, reports the current percentage and remains responsive while the full-resolution frame loads.
2. Confirm a tiny outward pinch remains at Fit, then continue in small increments without jumping to 100%. Verify the gesture stops at 800%, then pinch inward to the fitted image scale and confirm it returns to Fit. The Fit/100% button must continue to switch modes.
3. At an intermediate zoom below and above 100%, scroll around the photograph, pinch again and confirm the gesture starts from the displayed percentage without a jump. Repeat with the Loupe enabled.
4. Enter a local brush, pinch without painting an accidental stroke, then paint and use Undo/Redo. Reopen the library and confirm the recipe did not change merely from zooming.
5. If testing a touch display, confirm its driver translates contacts into a native magnification gesture. Record unsupported direct-touch hardware separately rather than treating it as an Isonique zoom failure.

## Physical Compare navigation

Use at least four photos with visibly different aspect ratios and the signed build. Record the input device and macOS version.

1. Select at least three visible Browser photos and start Compare. Confirm the current photo is Primary, every other pane is numbered Select, and narrowing the Browser filter excludes hidden selections at startup.
2. Use the arrow keys to navigate Selects, Option-P to promote one to Primary and Option-Delete to remove one. Confirm the final Primary/Select pair cannot be reduced and Done cancels Compare without saving its UI state.
3. Resize the window through one-, two- and three-column layouts. Leave Synchronize Navigation enabled, click 100% in any pane, pan to an identifiable subject and confirm every percentage readout and normalized subject position moves together across mixed aspect ratios.
4. Pinch from Fit in small increments without a jump to 100%, continue to 800%, then pinch inward until every pane returns to Fit. Confirm the 1800-pixel preview is replaced by full resolution only while pixel zoom is active.
5. Disable Synchronize Navigation. Give each pane a different zoom and pan position, then enable synchronization and confirm every Select adopts the Primary pane’s navigation.
6. While full-resolution loading is visible, return to Fit, remove a Select or add a different Browser photo. Confirm an obsolete result never replaces a current pane.
7. Export every compared photo before and after navigation. Confirm output is identical and reopening the library retains its prior recipes without storing comparison membership or navigation.

## Physical Light Table workspace

Use a disposable library with at least four wide, tall and square photos, including one adjusted version.

1. Filter the Browser, select several visible photos and also leave one now-hidden photo selected. Create a Light Table and confirm only the visible selection is included.
2. Drag and resize a card at Fit and 100%, rotate it, multi-select two cards for each alignment, and move cards to front and back. Confirm the canvas remains responsive and does not accidentally edit a photo.
3. Undo and Redo each operation, rename and duplicate the layout, reopen the library and confirm every reusable layout retains geometry and stacking order.
4. Save PDF and use Print. Confirm the PDF matches the canvas arrangement, the print panel scales it to the selected paper and the adjusted photo matches an ordinary edited export.
5. Export the compared photos before and after Light Table work and verify identical output. Verify the managed originals remain byte-identical.

## Physical full-screen and secondary-display workspace

Use the signed build with at least two edited photos. For secondary-display checks, connect a second display with a different backing scale or ICC profile and record both display models, scale settings and selected colour profiles.

1. Choose each View → Photography Workspace layout, customise Browser, filmstrip, Inspector and toolbar visibility, quit and reopen Isonique, then confirm every layout restores independently.
2. Enter and leave native full screen with Control-Command-F and Escape. Confirm the library sidebar leaves in full screen and returns afterwards, the selected photo remains selected and Browser/Viewer rating shortcuts keep their expected focus.
3. Press Control-W repeatedly and confirm focus visits only visible panels. Exercise Option-Command-B/F/I/T, including restoring the toolbar from its menu shortcut after hiding it. Confirm typing in search or metadata fields is not interpreted as a review shortcut.
4. With a second display connected, choose Show Secondary Display Viewer. Confirm the window opens on the non-primary display at its native scale, follows Viewer and Compare selection changes and looks consistent when the displays use different ICC profiles. Optional RGB proofing must still be visibly explicit rather than silently baked into the screen transform.
5. Change photos, switch Fit/100% and close the secondary Viewer while a full-resolution frame is loading. Confirm no obsolete image replaces the current selection and reopening starts with the current photo.
6. Export the tested photos before and after full-screen, focus and secondary-display changes. Confirm byte-identical edited exports, unchanged recipes after reopening and unchanged original fingerprints.

## Physical toolbar and keyboard command customisation

Use the signed build with British English selected in macOS and at least three photos. Keep one photo selected in Grid, Viewer and Compare during the checks.

1. Choose View → Customise Toolbar, hide and reorder several controls, close the sheet and confirm the live toolbar matches. Quit and reopen Isonique, confirm the order returns, then use Reset to Defaults.
2. Open Keyboard Command Editor, create and rename a set, change one command in each Browser, Viewer and Compare scope and confirm each shortcut runs only in its declared scope. Restart and confirm the active named set and bindings return.
3. Try to assign one shortcut to overlapping commands, a macOS editing or file command, a colour label and a quick-keyword slot. Confirm each collision is explained and no existing binding changes. Confirm reuse between disjoint Browser/Viewer and Compare scopes is accepted.
4. Focus Search and editable Inspector metadata, type the unmodified rating keys and customised shortcuts, and confirm the exact text appears without changing the photo. Open a sheet and confirm workflow shortcuts remain inactive until it closes.
5. Export the named set, reset or remove its bindings, import the JSON and confirm the restored set receives a distinct name when necessary. Cancel both file panels and confirm the current set remains unchanged.
6. Export an edited photo before and after customisation. Confirm identical pixels and metadata, an unchanged catalogue and unchanged source and managed-original fingerprints.

## Quick Preview and List Browser customisation

Use the signed build with British English selected in macOS and a disposable library containing at least six photos with long captions, keyword paths and catalogued EXIF values.

1. In Grid, select a photo, apply a filter and sort order, press **P**, then navigate and assign a rating, flag and colour label. Confirm the selection, visible order and filter remain stable. Enter Viewer and confirm the bounded preview has a yellow Quick Preview indicator and adjustment controls are paused.
2. Focus Search and type `p`. Confirm the literal character appears and Quick Preview does not toggle. Clear Search, restore Browser focus and press **P** to toggle it. Open Compare and confirm the unmodified key is not routed there.
3. Enter List Browser and choose View → Customise List Columns. Confirm British English spelling and all 14 fields. Show Caption, Keywords, Lens and ISO; hide Camera. Confirm long values truncate visually without changing their stored metadata.
4. Drag the Caption header before Rating, resize it, quit and relaunch Isonique, then confirm visibility, order and width return. Use Reset List Columns and confirm the six defaults return.
5. Export an edited photo before and after these preference changes. Confirm identical pixels and metadata, an unchanged catalogue and unchanged source and managed-original fingerprints.

## Second Browser and manual Browser order

Use the signed build and a disposable library containing two projects, a regular album, a Smart Album, one collapsed stack and at least one version.

1. Choose **View → Second Browser**. Give each Browser a different container, search, rating filter and sort. Select a different photo in each pane and confirm changing one selection does not change the other.
2. Click each pane in turn and use rating, flag and arrow-key commands. Confirm commands affect only the focused pane's selection. Focus either Search field and confirm typed shortcut characters remain text.
3. In All Photos, a project and a regular album, drag photos to a new Manual order and use Move to Beginning/End. Confirm a collapsed stack moves as one contiguous block and a version can move independently. Confirm Smart Albums, Flagged, Trash, Places and a stack-only view do not offer Manual order.
4. Undo and redo an order change, quit and relaunch, then confirm both Browser configurations and every catalogue order return. Import one new photo and confirm it appends without disturbing the saved sequence.
5. Export and reimport an ordered project twice. Confirm regular-album memberships and relative order survive both imports with distinct remapped identifiers. Merge an older project export and confirm current order is protected by the selected conflict preference.
6. Export an edited photo before and after Browser ordering. Confirm identical pixels and metadata, unchanged recipes and unchanged source and managed-original fingerprints.

## People and face detection

Use a disposable library with an upright group photo and JPEG variants with rotated or mirrored EXIF orientation.

1. Select the photos and choose **Metadata → Detect Faces in Selection**. Open **Review Faces** and check that each box fits the orientation of the preview. Cancel a larger batch and confirm that its pending changes were discarded.
2. Give a face a multiword name, draw a missed face, redraw an existing box and remove a false positive. Rescan and confirm that the dismissed face does not reappear. Save, then Undo, Redo and reopen the library with persistent history enabled.
3. Check the People sidebar and add a **Person** rule in Advanced Search and a Smart Album. Disconnect the referenced original and repeat the queries. Confirm that saved names can still be corrected, while detection and box placement require the original.
4. Compare before-and-after edited and original exports with XMP enabled. Check that People names and boxes are absent and the original fingerprints match.
5. Select a named group and choose **Metadata → Rename or Merge Person**. Try renaming it to a case or accent variant of another group's name. Confirm Rename reports the collision, then choose Merge and preview affected photo versions and exact-name Smart Album rules. Cancel one review and apply another. Reopen the library and verify one Undo or Redo changes the assignments and rules together. Repeat with the referenced originals offline.
6. Run **Metadata → Review Unnamed Faces** from a project containing at least two versions with unnamed faces. Confirm the project scope, then switch to Entire Library. Check the highlighted box, assign an existing or new name and dismiss a face. Confirm each saved decision advances. Skip a face and bring it back with Review Skipped Faces. Repeat with the original offline, then reopen the library with persistent history enabled and verify Undo and Redo restore the expected queue.
7. Select a named group and open **Person Overview**. Check the project counts against its active versions, choose a different face and reopen the library. Make that original unavailable and verify the saved choice, counts and Browse Photos action. Remove or reassign the chosen face in Review Faces and verify the fallback portrait. Undo to restore the choice.
8. Open **People** with enough named groups to scroll. Search for a name using different case or accents, select a project and check the counts and opened photos. Confirm that a saved portrait can come from another project, an offline portrait shows a placeholder, and reassigning its face refreshes the tile. Scroll away while a portrait is loading and return to verify the current tile loads.
9. Open **Review Summary** with an unscanned available version and two versions sharing an offline original. Compare the project and library counts. Reconnect the original and choose **Refresh**. Run **Scan Available Photos** and check that only unscanned available versions in scope are marked scanned. Open **Review Unnamed Faces** from the summary and verify it carries over the scope and includes saved offline faces.
10. Expand **Show Offline Originals** with offline managed and referenced originals, including versions sharing an original across projects. Confirm each file appears once per scope under its storage type and that opening the list leaves the catalogue untouched. Open **Library First Aid** from the managed group and **Reconnect Referenced Originals** from the referenced group. Reconnect a project’s reference and reopen the summary. Confirm the row is gone and that unrelated offline references remain listed in library scope.
11. Start a People scan in Review Summary and repeat with **Metadata → Detect Faces in Selection**. Verify that checked, skipped and remaining counts update and add up to the batch total. Disconnect a referenced original before the scan reaches it and confirm it stays unscanned. Cancel after at least one check and verify that all pending changes are discarded. Run a complete scan and verify that one Undo restores all affected versions.

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
