import SwiftUI

// Keep this inventory aligned with FEATURE_AUDIT.md and COMPATIBILITY.md.
struct FeatureGuide: View {
    @State private var query = ""
    @State private var missingOnly = true

    private struct Feature: Identifiable {
        let title: String
        let detail: String
        var id: String { title }

        init(title: String, detail: String) {
            self.title = Bundle.main.localizedString(forKey: title, value: nil, table: nil)
            self.detail = Bundle.main.localizedString(forKey: detail, value: nil, table: nil)
        }
    }
    private struct Group: Identifiable {
        let title: String
        let symbol: String
        let features: [Feature]
        var id: String { title }
    }
    private let groups: [Group] = [
        Group(title: "Remaining missing features", symbol: "circle.dashed", features: [
            Feature(title: "1. Full Aperture library migration", detail: "Original recovery exists, but old edits, database-only metadata, project hierarchy and album relationships are not migrated."),
            Feature(title: "3. Retouching and advanced brushes", detail: "Clone, heal, red-eye removal, edge-aware brushes and general adjustment masks are pending."),
            Feature(title: "8. Physical tethered capture", detail: "File → Tethered Capture can request one shot at a time from a camera that reports remote shutter support. Physical camera testing is pending. Use File → Import from Camera or Card to check only the photos you want to import."),
            Feature(title: "9. Publishing and extensions", detail: "Books, printing tools, plug-ins, slideshow export and video workflows are missing. Review → Start Slideshow plays edited photos on this Mac."),
            Feature(title: "10. Cloud sync and other devices", detail: "Cloud sync and web, Windows, iPhone, iPad and Android apps are not included.")
        ]),
        Group(title: "New options (6–10)", symbol: "slider.horizontal.3", features: [
            Feature(title: "6. RAW+JPEG pairing", detail: "Link a pair with JPEG or RAW as the primary file, keep originals separate, or filter to JPEG or RAW files during import. The Prefer options are also available. Linked photos have a companion button in Info and each keeps its own edits. macOS decoding limits still apply."),
            Feature(title: "7. Import naming and metadata presets", detail: "Add a catalogue filename prefix and save named caption, keywords and rating presets in Import Options. Source files are never renamed."),
            Feature(title: "8. XML and XMP exchange", detail: "Read matching XMP sidecars during import, or use File → Import XML / XMP Metadata. In Export, enable Write matching XMP sidecar to save keyword paths, flat keywords, caption and rating alongside the image. Import also supports Isonique photo XML and AlbumData.xml comments and ratings."),
            Feature(title: "9. Color proofing and lens correction", detail: "Choose an RGB ICC profile for a viewer-only color simulation; CMYK and paper/ink simulation are unsupported. Manual radial lens correction applies to preview and export; automatic camera/lens profiles are unavailable."),
            Feature(title: "10. Persistent edit history", detail: "Enable Keep Undo/Redo history in Import & History Options to retain the latest 100 edits per library across launches. Turning it off removes saved history.")
        ]),
        Group(title: "Available with limits", symbol: "exclamationmark.circle", features: [
            Feature(title: "GPX tracks and matching", detail: "Select a project and open Places → GPX Tracks to import, show, hide or remove a route. Click a waypoint pin to review its coordinates and choose which photo versions to assign it to. Metadata → Match GPX Track matches selected photos by timestamp. Both assignment workflows use one Undo step. Reimport older GPX files to add their waypoints."),
            Feature(title: "6. Referenced-original management", detail: "Leave originals where they are from Import Options. Filter referenced and unavailable files using Sort & Filter. Use File → Reconnect Referenced Originals to search a folder for missing references with known filenames and verify their fingerprints. Info can relink or consolidate one file. Use Select Photos and File → Consolidate Selected Originals to copy a batch into managed storage. File → Relocate Originals previews filename and subfolder presets and shows collisions before copying. New Preset saves a reusable pair of custom templates. Isonique verifies the copies before updating the catalogue. Old referenced files are kept by default. Isonique backups retain links; back up external originals separately."),
            Feature(title: "Photo Trash", detail: "Move a photo to Trash from its context menu or press Command-Delete. Select Trash in the sidebar and use Put Back to restore its edits and memberships. Empty Trash reviews eligible records and managed originals before removal. It keeps referenced files and originals used by active versions. Use the same command to retry any pending Finder Trash moves."),
            Feature(title: "7. Library backup and repair", detail: "File → Back Up Library, Restore Library Backup and Check Library Integrity verify catalogue copies and original hashes. Library First Aid lists missing managed originals, offline references and untracked managed files. Recover Missing Managed Originals copies verified matches from a backup or folder into the current library. Full restores open a separate new library. File → Open Recent Library switches between previously opened libraries. If another workspace saves first, use File → Reload Library before retrying your edit. Select a project and use File → Export Project as Library to create a portable copy with its edits and originals. File → Import Project Library copies an exported project into the current library as a separate project. Merge Project Library reconciles an edited export with its matching project. Merge Libraries reviews and adds projects, albums, photos and versions from another Isonique library while keeping existing records. Legacy vaults and automatic catalogue repair remain missing."),
            Feature(title: "4. Histogram, Levels and curves", detail: "The Inspector shows live output and adjustment-input histograms. Levels and Channel Levels have manual endpoints, gamma, dark and light quarter-tones, and automatic endpoints. Channel Curves edits red, green, blue and luminance independently. These tools use the shared 8-bit sRGB preview and export pipeline."),
            Feature(title: "Viewer Loupe", detail: "Use View → Show Loupe, the Viewer magnifier, or the grave accent key. Move the pointer over the photo to magnify it and read coordinates and 8-bit sRGB values. The Loupe menu offers three magnifications and an optional pixel grid."),
            Feature(title: "Viewer clipping warnings", detail: "Use View → Highlight Hot & Cold Areas or press Option-Shift-H. Separate highlight and shadow switches are also in View. Red marks highlights, blue marks shadows, and magenta marks pixels that meet both thresholds. Settings controls sensitivity. Warnings measure the sRGB preview before proofing and appear only in the Viewer."),
            Feature(title: "Local Dodge and Burn", detail: "Open a brush from Photos, the Brush menu or the Adjustments inspector. Set size, softness and strength, then click or drag on the fit-to-window photo. The preview updates on release. Erase and Reset Mask affect the selected mask. Each stroke and reset can be undone. Masks are saved with the edit recipe and included in edited exports."),
            Feature(title: "Slideshow playback", detail: "Review → Start Slideshow plays the current filtered/sorted view or batch selection. Pause/play, previous/next, 3/5/10-second timing and Escape to finish. Uses saved edits, loops and leaves the library selection unchanged. No soundtrack or movie export."),
            Feature(title: "2. Batch photo workflows", detail: "Select Photos enables multiple selection, Select All, rating, flags, presets, selective Stamp, album/project assignment and export to a new folder. Inspector edits one photo; use the selection bar for batch actions. Batch Change can edit captions and keywords in one Undo step. Export stops on the first failure and reports completed files."),
            Feature(title: "Keyword vocabulary", detail: "Use Metadata → Keyword Vocabulary to build a tree of reusable keywords, apply a term to selected photos, or import and export a tab-indented UTF-8 text list."),
            Feature(title: "Keyword groups and quick assignment", detail: "Create or edit groups in Metadata → Manage Keyword Groups. View → Show Keyword Controls displays buttons for the active group. Click a keyword or Apply Group to append to the visible selection. Shift-click to remove a keyword. With the Browser or Viewer focused, Option–1 through Option–8 add keywords by group order, and adding Shift removes them. Each edit is one Undo step. Groups are available across your Isonique libraries."),
            Feature(title: "Batch change captions and keywords", detail: "Use Metadata → Batch Change, Shift-Command-B, or Batch Change in the selection bar. Choose which fields to edit. Append keeps existing keywords and skips duplicates. The preview lists the current and resulting values for each affected photo. Apply saves the batch as one Undo step."),
            Feature(title: "Adjust photo date and time", detail: "Choose Metadata → Adjust Date and Time or use the Info inspector. Select several photos and keep their capture intervals, or assign a date to all selected versions. A correction is one Undo step. Adjusted exports can include the corrected EXIF time, and original bytes are preserved."),
            Feature(title: "5. Smart albums, stacks and versions", detail: "Create Smart Albums with All/Any rules for dates, metadata, rating and original status. Advanced Search uses the same rules. Right-click an album to edit it. Group photos into stacks, set global or regular-album picks, and collapse to the pick. The sidebar shows all stack members. Create separately editable versions from an original or the current recipe, and compare them side by side. Adjustment Snapshots still save and restore recipes on a single version. Review → Auto Stack groups consecutive capture times using a 0–60 second gap, leaving existing stacks and missing dates alone. Legacy Aperture relationships remain unavailable."),
            Feature(title: "Aperture library recovery", detail: "Recovers embedded originals and embedded IPTC captions/keywords and ratings from a verified temporary copy. Reports duplicates and unsupported files separately. Does not migrate database-only metadata, old edits, projects, albums or referenced originals. Keep a separate backup of your old library."),
            Feature(title: "Export options", detail: "JPEG, PNG, TIFF and unchanged original export, individually or as a selected batch. JPEG quality, longest-edge resizing, saved presets and separate EXIF/IPTC/GPS choices are available. Original copies retain all embedded metadata. Edited output uses 8-bit sRGB."),
            Feature(title: "Crop", detail: "Move the crop by dragging inside; resize with corner handles or redraw outside. Aspect lock is remembered, presets switch between portrait and landscape, and pixel dimensions can be entered."),
            Feature(title: "Lift and Stamp", detail: "Copies checked adjustment groups and optional caption, keywords and rating to one photo or the selected batch. Selected metadata replaces target values, including empty values; the clipboard lasts only for this session."),
            Feature(title: "RAW and color processing", detail: "Isonique uses its own documented pixel formulas for preview and export. RAW decoding depends on macOS camera codecs. Four camera RAW samples passed on macOS 27.3; other cameras and system versions can behave differently. Edited exports use 8-bit sRGB."),
            Feature(title: "Undo and Redo", detail: "Session Undo/Redo is always available. Optional persistent history retains the latest 100 photo edits in the catalogue.")
        ]),
        Group(title: "Available now", symbol: "checkmark.circle", features: [
            Feature(title: "Project location assignment", detail: "Select a project in Places and choose Assign Project Location to review and fill missing locations in one Undo step. The review preserves existing locations, including embedded GPS in older originals, and skips explicitly cleared locations and originals it cannot verify."),
            Feature(title: "Export format, quality, size and metadata", detail: "Choose JPEG, PNG, TIFF or unchanged original; set JPEG quality and longest-edge size; save reusable presets; choose EXIF, IPTC and GPS for edited exports."),
            Feature(title: "Precise crop and selective metadata Stamp", detail: "Move and resize crops, lock aspect, switch portrait/landscape, enter exact pixels, and Stamp selected captions, keywords and ratings."),
            Feature(title: "Multiple Isonique libraries", detail: "Create a separate folder using File → New Isonique Library and switch using File → Open Isonique Library."),
            Feature(title: "Import and organize", detail: "Import files or folders, verify managed copies, skip exact duplicates, and optionally create a project. File → Import from Camera or Card discovers connected cameras and mounted media with a DCIM folder. It uses the same import presets, always copies originals into the library, and leaves the source unchanged. Cancel Import keeps completed photos."),
            Feature(title: "Review and metadata", detail: "Click a photo to use 0–5 for ratings, 9 to reject, / to flag and the arrows to navigate. The Metadata menu assigns seven color labels. Rename them in Settings and filter them from Sort & Filter."),
            Feature(title: "Non-destructive editing", detail: "Exposure, brightness, contrast, saturation, vibrancy, sepia, warmth, tint, shadows, highlights, presets, rotation, flip, straighten, crop, original comparison and selective Stamp preserve originals.")
        ])
    ]

    private var visibleGroups: [Group] {
        groups.filter { !missingOnly || $0.title != "Available now" }.compactMap { group in
            let features = group.features.filter {
                query.isEmpty || "\(group.title) \($0.title) \($0.detail)".localizedCaseInsensitiveContains(query)
            }
            return features.isEmpty ? nil : Group(title: group.title, symbol: group.symbol, features: features)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features & Limits").font(.largeTitle.bold())
            Text("Remaining missing features & available options").font(.title3)
            Text("Ranked by impact on everyday photo work. Features are whole workflows; options are choices within a workflow. All ten ranked options now have controls. See each entry for supported formats and remaining limits.")
                .foregroundStyle(.secondary)
            TextField("Search features or options, such as RAW or export", text: $query).textFieldStyle(.roundedBorder)
            Toggle("Show only missing or limited features", isOn: $missingOnly)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if visibleGroups.isEmpty { Text("No matching features. Try another search or turn off the filter.").foregroundStyle(.secondary) }
                    ForEach(visibleGroups) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            Label(group.title, systemImage: group.symbol).font(.headline)
                            ForEach(group.features) { feature in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title).font(.headline)
                                    Text(feature.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
            }
            HStack {
                Link("RAW alternative: LibRaw", destination: URL(string: "https://www.libraw.org/docs")!)
                Link("Pixel alternative: libvips", destination: URL(string: "https://www.libvips.org/")!)
            }.font(.caption)
            Divider()
            Text("Requires an Apple Silicon Mac with macOS 14 or later. Tested on macOS 27.3.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 560, minHeight: 480)
    }
}
