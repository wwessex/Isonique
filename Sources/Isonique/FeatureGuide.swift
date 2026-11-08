import SwiftUI

// Keep this inventory aligned with FEATURE_AUDIT.md and COMPATIBILITY.md.
struct FeatureGuide: View {
    @State private var query = ""
    @State private var missingOnly = true

    private struct Feature: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }
    private struct Group: Identifiable {
        let title: String
        let symbol: String
        let features: [Feature]
        var id: String { title }
    }
    private let groups: [Group] = [
        Group(title: "Top 10 missing features", symbol: "circle.dashed", features: [
            Feature(title: "1. Full Aperture library migration", detail: "Original recovery exists, but old edits, database-only metadata, project hierarchy and album relationships are not migrated."),
            Feature(title: "2. Batch photo workflows", detail: "Multi-photo selection, editing, Stamp and export are missing. Stamp and export work on one photo at a time."),
            Feature(title: "3. Retouching and local edits", detail: "Clone, heal, red-eye removal and adjustment brushes are missing."),
            Feature(title: "4. Advanced tonal tools", detail: "Histogram, curves and levels are missing; basic tone sliders are available."),
            Feature(title: "5. Smart albums, stacks and versions", detail: "Automatic album rules, stacks and multiple editing versions are missing. Basic projects and albums are available."),
            Feature(title: "6. Referenced-original management", detail: "Discovery, relinking, relocation and consolidation of external originals are missing; imported originals are managed copies."),
            Feature(title: "7. Library backup and repair", detail: "Vault backup/restore, library merging and catalogue repair tools are missing."),
            Feature(title: "8. Camera capture and import", detail: "Tethered capture and camera/device import controls are missing; file and folder import are available."),
            Feature(title: "9. Publishing and extensions", detail: "Books, slideshows, printing tools, plug-ins and video workflows are missing."),
            Feature(title: "10. Cloud sync and other devices", detail: "Cloud sync and web, Windows, iPhone, iPad and Android apps are not included.")
        ]),
        Group(title: "Remaining missing options", symbol: "slider.horizontal.3", features: [
            Feature(title: "6. RAW+JPEG pairing", detail: "Choosing how matching RAW and JPEG files are paired during import is not available."),
            Feature(title: "7. Import naming and metadata presets", detail: "Automatic import renaming and reusable metadata presets are missing."),
            Feature(title: "8. XML and XMP import", detail: "Aperture XML catalogue and XMP sidecar import choices are missing; embedded metadata import is available."),
            Feature(title: "9. Color proofing and lens correction", detail: "Soft-proof profiles and lens-correction controls are missing."),
            Feature(title: "10. Persistent edit history", detail: "An option to retain Undo/Redo history after closing the app is missing; saved adjustments remain in the catalogue.")
        ]),
        Group(title: "Available with limits", symbol: "exclamationmark.circle", features: [
            Feature(title: "Aperture library recovery", detail: "Recovers embedded originals and embedded IPTC captions/keywords and ratings from a verified temporary copy. Reports duplicates and unsupported files separately. Does not migrate database-only metadata, old edits, projects, albums or referenced originals. Keep a separate backup of your old library."),
            Feature(title: "Export options", detail: "JPEG, PNG, TIFF and unchanged original export, one photo at a time. JPEG quality, longest-edge resizing, saved presets and separate EXIF/IPTC/GPS choices are available. Original copies retain all embedded metadata. Edited output uses 8-bit sRGB."),
            Feature(title: "Crop", detail: "Move the crop by dragging inside; resize with corner handles or redraw outside. Aspect lock is remembered, presets switch between portrait and landscape, and pixel dimensions can be entered."),
            Feature(title: "Lift and Stamp", detail: "Copies checked adjustment groups and optional caption, keywords and rating to one photo. Selected metadata replaces target values, including empty values. Multi-photo stamping is missing; the clipboard lasts only for this session."),
            Feature(title: "RAW and color processing", detail: "Isonique uses its own documented pixel formulas for preview and export. RAW decoding still depends on macOS camera codecs and has not been validated with camera RAW files. LibRaw is a researched replacement, not yet integrated. Old Aperture recipes and matching pixel output are not supported."),
            Feature(title: "Undo and Redo", detail: "Photo edit history is available during the current session; it does not survive closing the app.")
        ]),
        Group(title: "Available now", symbol: "checkmark.circle", features: [
            Feature(title: "Export format, quality, size and metadata", detail: "Choose JPEG, PNG, TIFF or unchanged original; set JPEG quality and longest-edge size; save reusable presets; choose EXIF, IPTC and GPS for edited exports."),
            Feature(title: "Precise crop and selective metadata Stamp", detail: "Move and resize crops, lock aspect, switch portrait/landscape, enter exact pixels, and Stamp selected captions, keywords and ratings."),
            Feature(title: "Import and organize", detail: "Import files or folders, verify managed copies, skip exact duplicates, create projects and albums, and search names, keywords and cameras."),
            Feature(title: "Review and metadata", detail: "Ratings, rejection, flags, rating filters, sorting, captions, keywords, photo information and Reveal Managed Original are available."),
            Feature(title: "Non-destructive editing", detail: "Exposure, contrast, saturation, warmth, tint, shadows, highlights, presets, rotation, straighten, crop, original comparison and selective Stamp preserve managed originals.")
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
            Text("Top 10 missing features & remaining options").font(.title3)
            Text("Ranked by impact on everyday photo work. Features are whole workflows; options are choices within a workflow. The first five ranked options are now available: export format, quality and size, metadata, crop precision and Stamp metadata.")
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
            Text("Platform: Apple Silicon Mac, macOS 14 or newer. Checked on this Mac; Intel and older macOS runtime behavior are unverified.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 560, minHeight: 480)
    }
}
