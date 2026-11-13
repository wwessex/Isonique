# Isonique

Isonique is an independent, open-source photo management and editing application inspired by the workflow and professional photography tools of Apple’s discontinued Aperture.

Isonique runs on Apple Silicon Macs. Import a shoot, sort and rate the photos, edit selected images and export finished files from one local library. You can let Isonique manage originals or reference files where they already live. Edits are saved as recipes in the Isonique catalogue, leaving the original files intact.

## Features

- **Import and organise.** Import files or folders, or select individual photos from a connected camera or mounted card in the thumbnail browser. Skip exact duplicates, work with multiple libraries, organise in projects and albums, and build Smart Albums with combined rules. Isonique can read matching XMP sidecars and link RAW+JPEG pairs. Reconnect missing references or recover missing managed originals from a folder using verified matches. The search can cover selected photos, a project or the entire library. Consolidate selected references into managed storage or preview relocation with built-in or reusable custom filename and subfolder presets before moving originals. Open Recent Library switches between previously opened libraries. Export Project as Library makes a portable copy with its edits and originals. Import Project Library adds that copy as a separate project. Merge Project Library previews changes to a matching project. Merge Libraries reviews additions across a whole Isonique library and keeps existing records.
- **Review a shoot.** Browse a grid with adjustable thumbnail sizes, a metadata list or a filmstrip. Press **P** for a bounded Quick Preview that keeps selection, filtering and review shortcuts available while pausing adjustment tools. The List Browser offers 14 configurable metadata columns; use **View → Customise List Columns** for visibility, then drag native table headers to reorder or resize them. Use **View → Second Browser** to open an independently scoped grid with its own search, rating filter, sort and selection; keyboard review follows the Browser you most recently focused. All Photos, projects and regular albums support persistent Manual order by drag and drop or Move to Beginning/End, with collapsed stacks moving as one block. Use keyboard ratings, rejection, flags and colour labels to narrow a selection. Group related photos in stacks, create separate editable versions of an original, and compare two or more selected versions or photos in responsive Primary/Select layouts. Promote or remove the active Select from the View menu or keyboard, navigate Selects with the arrow keys, and synchronize zoom and pan across every visible pane or navigate them independently. The Photography Workspace provides remembered Editing, Culling and Compare layouts, native full screen, independent Browser, filmstrip, Inspector and toolbar visibility, Control-W focus cycling and a colour-managed secondary-display Viewer when another display is connected. Use **View → Customise Toolbar** to choose and order the main controls. The **Keyboard Command Editor** preserves the existing shortcuts in its built-in set and provides named, importable and exportable custom sets whose commands are scoped to Browser, Viewer or Compare without stealing text-field input. Create persistent named Light Tables from the visible selection, then freely move, resize, rotate, align and stack photos on a Fit or 100% canvas. Duplicate reusable layouts or save and print their full-resolution adjusted output without changing photo recipes.
- **Find photos by person.** Open **People** in the sidebar for a gallery of named people and their saved portraits. Search by name or filter by project, then click a person to browse their matching photos. Counts and browsing work offline, with placeholders for unavailable portraits. Use **Person Overview** to see counts by project and choose a representative face. Open **Review Summary** from People or **Metadata → People Review Summary** to count unscanned photo versions, unnamed faces and distinct offline originals for a project or the whole library. With the summary open, press **⌥⌘S** to scan available unscanned versions on your Mac or **⌥⌘R** to open the **Unnamed Faces** queue for that scope. **Review Faces** lets you name, add, redraw or remove individual boxes. **Rename or Merge Person** previews changes to photo versions and exact-name Smart Album rules. Person rules also work in Advanced Search. Identity assignment is manual. Photo exports and XMP sidecars exclude People records. Library copies and backups include saved boxes, names and representative choices.
- **Organise by location.** Browse geotagged photos in Places and filter them with GPS Smart Albums. Assign coordinates from Apple Maps search, a map pin or manual entry. Use **Assign Location → Saved Places** to save and reuse named coordinates across libraries. In Places, **Assign Project Location** previews and fills missing locations across the current project in one Undo step. Use **GPX Tracks** to import, show, hide or remove a route. Click a waypoint pin to assign its coordinates to selected versions, or use **Metadata → Match GPX Track** for timestamp matching.
- **Edit non-destructively.** Adjust exposure, colour, white balance and tone. Set white balance with Kelvin and tint controls or sample an opaque neutral pixel through the full-resolution Viewer Loupe. Target reusable red, orange, yellow, green, cyan, blue, magenta or Loupe-sampled colour ranges with independent Hue, Saturation and Luminance controls. Mix red, green and blue contributions for black-and-white conversion and add an optional monochrome tint. Add bounded local contrast with Definition strength and radius controls. Use automatic and manual Curves and Levels, global or edge sharpening, luminance noise reduction, red/cyan and blue/yellow chromatic-aberration correction, vignette or devignette, crop, straighten, manual lens correction, multi-spot Repair or Clone retouching, and manual red-eye correction with multiple editable pupils. Local Dodge, Burn, Saturation, Definition, Sharpening, Luminance Noise Reduction, Contrast, Blur, Tint, Skin Smoothing, Polarize and Halo Reduction brushes support edge-aware painting, erase, Viewer-only mask overlays, mask inversion, post-stroke opacity and Fit or 100% pixel-zoom brushing. Pressure-sensitive tablet pens can map independent Off, Soft, Linear or Firm responses to brush size and strength, each with a saved minimum; mouse and trackpad strokes retain the fixed controls. Bounded source-space mask caching reuses unchanged masks between Viewer and export, while a newly appended stroke rasterises only its suffix. Create multiple named instances of any brush, then enable, reorder, duplicate or delete them independently. Tint provides hue and saturation controls; Skin Smoothing provides amount and detail-preservation controls; Polarize provides intensity; and Halo Reduction provides amount and radius controls per instance. Save reusable custom adjustment presets with selected groups and review their changes before applying them to one photo or a batch. The Viewer provides clipping warnings, a pixel Loupe and RGB ICC proofing. Pinch with a Mac trackpad or compatible magnification device for smooth fit-relative 1–800% Viewer zoom; tiny movements remain at Fit instead of jumping to 100%, and Fit and 100% remain available as buttons. Multi-photo Compare can synchronize normalized zoom and pan across different aspect ratios or navigate each pane independently. Undo edits and copy selected adjustments or metadata to other photos with Lift and Stamp. **Photos → Edit with External Editor** sends the rendered version as a TIFF and imports the verified return as a new managed derivative while preserving the source master.
- **Export.** Save edited JPEG, PNG, TIFF or HEIF files with size and metadata options, or export byte-for-byte copies of originals. Add an optional text watermark with live position, opacity and scale preview. JPEG and HEIF provide quality controls. TIFF export offers uncompressed, LZW, ZIP and PackBits output, and export presets remember these choices. In batch export, choose or type a filename template, review the exact image and sidecar names, and save the template in an export preset. Enable **GPS — current photo location** to include the assigned or embedded location in edited exports. Cleared locations export without GPS. Enable **Write matching XMP sidecar** to carry keyword paths, flat keywords, caption, rating, title, creator, copyright and credit alongside either export. Edited output uses 8-bit sRGB. RGB ICC proofing affects the Viewer.
- **Print contact sheets and proofs.** Press Command-P to paginate the current Browser view or selected photos. Choose contact-sheet grids or one-photo proofs, A4/A3/US Letter paper, orientation, margins, captions and sRGB, Display P3 or monochrome output. Save reusable print presets, export the exact layout as PDF or continue through the native macOS print panel.
- **Protect a library.** Check catalogue and original integrity, back up managed originals and the catalogue, and restore to a separate library folder. If another workspace saves first, use File → Reload Library before retrying your edit. Back up referenced originals at their external locations.

Use **Help → Features & Limits** for available commands and their limits.

## Design and compatibility

The workspace pairs library navigation with a photo Viewer and an adjustment inspector. Isonique stores recipes and organisation in its own catalogue and uses the same source-defined editing pipeline for preview and export. RAW decoding and metadata support depend on the system ImageIO codecs. Four camera RAW samples were validated on macOS 27.3. [Processing notes](PROCESSING_ALTERNATIVES.md) · [Test results](docs/TEST_RESULTS.md)

**File → Recover Aperture Originals** can recover files stored inside a legacy library, plus supported metadata embedded in those files, from a verified temporary copy. Allow space for that copy. Legacy catalogue relationships, stored edits, referenced originals and vaults are outside the recovery workflow. [Library compatibility](COMPATIBILITY.md)

## System requirements

- An Apple Silicon Mac running macOS 15 or later. Native macOS is the maintained platform.
- To build from source, install Xcode 26 or later or the matching Command Line Tools, with SwiftPM and the macOS 26 SDK or later. The app uses the newer appearance APIs when available.
- Storage for your library, managed originals and any backups or temporary recovery copies.

## Build and install

```sh
git clone https://github.com/wwessex/Isonique.git
cd Isonique
make build
```

Open `build/Isonique.app` or move it to Applications. `make run` builds and opens the app from the checkout. The build also creates `build/Isonique.zip` containing the arm64 app and its licence. If a cloud-backed checkout attaches metadata that interferes with signature validation, extract the ZIP into a local folder and open that copy. The local build uses an ad-hoc signature and packages the app icon from [its vector source](Resources/IsoniqueIcon.svg).

New default libraries are stored at `~/Library/Application Support/Isonique/Library`. If you used an earlier build and have no catalogue at the new default location, Isonique opens the earlier default library in place. A library chosen through File → Open Isonique Library is remembered across launches. [Library paths and catalogue compatibility](COMPATIBILITY.md)

## Development

Open `Package.swift` in Xcode to work on the SwiftUI/AppKit app, the `IsoniqueCore` library and the XCTest targets. The Swift package declares no external dependencies.

```sh
make check-branding
make test
```

The optional camera RAW test uses four external samples. Download `Canon-EOS-R.CR3`, `Nikon-Z6.NEF`, `Ricoh-GR-III.DNG` and `Sony-a7III.ARW`, verify them against the published hashes, then run `ISONIQUE_RAW_FIXTURES=/absolute/path/to/fixtures make test-raw`. [Sample release and hashes](https://github.com/tellodaniel/revelraw-sample-raw-files/releases/tag/v1)

To smoke-test a build with a disposable library, run:

```sh
smoke_dir=$(mktemp -d)
mkdir "$smoke_dir/Library"
build/Isonique.app/Contents/MacOS/Isonique --library "$smoke_dir/Library" --screenshot "$smoke_dir/window.png"
```

Screenshot mode captures the app window and exits. On the supported macOS 15 and newer releases, ordinary app launch and current-process capture work without Screen Recording permission.

## Contributing

Open an issue to report a bug or propose a change. Include the macOS version, steps to reproduce and the expected result. For a pull request, include the tests you ran and use disposable libraries or fixtures cleared for redistribution. Keep user catalogues, proprietary material and raw research records outside the repository. [Implementation plan](docs/IMPLEMENTATION_PLAN.md)

## Licence and trademarks

The project uses the [Apache License 2.0](LICENSE). macOS frameworks and system symbols are provided by the platform under their own terms. The development provenance notes describe the scope and limits of the source review. [Development provenance](docs/DEVELOPMENT_PROVENANCE.md)

Aperture, Mac and macOS are trademarks of Apple Inc. The Aperture name identifies the historical product and the source library format for original-file recovery. [Apple trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
