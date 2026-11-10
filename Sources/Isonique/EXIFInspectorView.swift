import IsoniqueCore
import SwiftUI

struct EXIFInspectorView: View {
    let photo: Photo
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("EXIF", isExpanded: $expanded) {
            if expanded {
                OriginalMetadataReader(photo: photo) { readout in
                    VStack(alignment: .leading, spacing: 8) {
                        switch readout {
                        case .metadata(let metadata) where metadata.exif.isEmpty:
                            Text("No capture settings found in the original.").foregroundStyle(.secondary)
                        case .metadata:
                            ForEach(MetadataViewField.allCases.filter(\.isEXIF)) { field in
                                LabeledContent(field.label, value: readout.value(for: field))
                            }
                        case .offline:
                            Text("EXIF is unavailable while the original is offline.").foregroundStyle(.secondary)
                        case .unreadable:
                            Text("Could not read EXIF from the original.").foregroundStyle(.secondary)
                        case .loading:
                            ProgressView("Reading EXIF…").controlSize(.small)
                        }
                    }.textSelection(.enabled).padding(.top, 8)
                }
            }
        }
    }
}
