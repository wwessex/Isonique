# Isonique

Isonique is an independent, open-source photo management and editing application inspired by the workflow and professional photography tools of Apple’s discontinued Aperture. Isonique is developed independently and is not affiliated with, endorsed by, or maintained by Apple Inc.

Isonique runs on Apple Silicon Macs. Import a shoot, sort and rate the photos, edit selected images and export finished files from one local library. You can let Isonique manage originals or reference files where they already live. Edits are saved as recipes in the Isonique catalogue, leaving the original files intact.

## Features

- **Import and organise.** Import files or folders, or select individual photos from a connected camera or mounted card in the thumbnail browser. Skip exact duplicates, work with multiple libraries, organise in projects and albums, and build Smart Albums with combined rules. Isonique can read matching XMP sidecars and link RAW+JPEG pairs. Reconnect missing references or recover missing managed originals from a folder using verified matches. The search can cover selected photos, a project or the entire library. Consolidate selected references into managed storage or preview relocation with built-in or reusable custom filename and subfolder presets before moving originals. Open Recent Library switches between previously opened libraries. Export Project as Library makes a portable copy with its edits and originals. Import Project Library adds that copy as a separate project. Merge Project Library previews changes to a matching project. Merge Libraries reviews additions across a whole Isonique library and keeps existing records.
- **Review a shoot.** Browse a grid with adjustable thumbnail sizes, a metadata list or a filmstrip. Use keyboard ratings, rejection, flags and colour labels to narrow a selection. Group related photos in stacks, create separate editable versions of an original, and compare two versions or photos side by side.
- **Organise by location.** Browse geotagged photos in Places and filter them with GPS Smart Albums. Assign coordinates from Apple Maps search, a map pin or manual entry. Use **Assign Location → Saved Places** to save and reuse named coordinates across libraries.
- **Edit non-destructively.** Adjust exposure, colour, white balance and tone. Use automatic and manual Curves and Levels, crop, straighten, manual lens correction and local Dodge and Burn. The Viewer provides clipping warnings, a pixel Loupe and RGB ICC proofing. Undo edits and copy selected adjustments or metadata to other photos with Lift and Stamp.
- **Export.** Save edited JPEG, PNG or TIFF files with size and metadata options, or export byte-for-byte copies of originals. Enable **Write matching XMP sidecar** to carry keyword paths, flat keywords, caption, rating, title, creator, copyright and credit alongside either export. Edited output uses 8-bit sRGB. RGB ICC proofing affects the Viewer.
- **Protect a library.** Check catalogue and original integrity, back up managed originals and the catalogue, and restore to a separate library folder. If another workspace saves first, use File → Reload Library before retrying your edit. Back up referenced originals at their external locations.

Use **Help → Features & Limits** for available commands and their limits.

## Design and compatibility

The workspace pairs library navigation with a photo Viewer and an adjustment inspector. Isonique stores recipes and organisation in its own catalogue and uses the same source-defined editing pipeline for preview and export. RAW decoding and metadata support depend on the system ImageIO codecs. Four camera RAW samples were validated on macOS 27.3. [Processing notes](PROCESSING_ALTERNATIVES.md) · [Test results](docs/TEST_RESULTS.md)

**File → Recover Aperture Originals** can recover files stored inside a legacy library, plus supported metadata embedded in those files, from a verified temporary copy. Allow space for that copy. Legacy catalogue relationships, stored edits, referenced originals and vaults are outside the recovery workflow. [Library compatibility](COMPATIBILITY.md)

## System requirements

- An Apple Silicon Mac running macOS 14 or later. Native macOS is the maintained platform.
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

Screenshot mode captures the app window and exits. It requires Screen Recording permission on macOS 14.0–14.3. Ordinary app launch and current-process capture on macOS 14.4 or later work without that permission.

## Contributing

Open an issue to report a bug or propose a change. Include the macOS version, steps to reproduce and the expected result. For a pull request, include the tests you ran and use disposable libraries or fixtures cleared for redistribution. Keep user catalogues, proprietary material and raw research records outside the repository. [Implementation plan](docs/IMPLEMENTATION_PLAN.md)

## Licence and trademarks

The project uses the [Apache License 2.0](LICENSE). macOS frameworks and system symbols are provided by the platform under their own terms. The development provenance notes describe the scope and limits of the source review. [Development provenance](docs/DEVELOPMENT_PROVENANCE.md)

Aperture, Mac and macOS are trademarks of Apple Inc. The Aperture name identifies the historical product and the source library format for original-file recovery. [Apple trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
