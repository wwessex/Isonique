import SwiftUI

extension Workspace {
    var loupeActive: Bool { showLoupe && viewer && tool == .select && comparisonID == nil }

    var canShowLoupe: Bool {
        guard !batchMode, !isViewingTrash, let selected else { return false }
        return isOriginalAvailable(selected) == true
    }

    func toggleLoupe() {
        if loupeActive { showLoupe = false; return }
        guard canShowLoupe else { return }
        stopComparison()
        viewer = true
        tool = .select
        showLoupe = true
    }
}

struct LoupeSample {
    let x: Int
    let y: Int
    let region: CGRect

    init(point: CGPoint, width: Int, height: Int, span: Int) {
        x = min(width - 1, max(0, Int((point.x * Double(width)).rounded(.down))))
        y = min(height - 1, max(0, Int((point.y * Double(height)).rounded(.down))))
        let columns = min(span, width), rows = min(span, height)
        region = CGRect(x: min(width - columns, max(0, x - columns / 2)),
                        y: min(height - rows, max(0, y - rows / 2)), width: columns, height: rows)
    }

    func rgba(in image: CGImage) -> [Int]? {
        let rect = CGRect(x: x, y: y, width: 1, height: 1)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let pixel = image.cropping(to: rect), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: space, bitmapInfo: info),
              let data = context.data else { return nil }
        context.draw(pixel, in: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let alpha = Int(bytes[3])
        guard alpha != 0 else { return [0, 0, 0, 0] }
        return (0..<3).map { min(255, (Int(bytes[$0]) * 255 + alpha / 2) / alpha) } + [alpha]
    }
}

struct LoupeTarget: View {
    @Binding var point: CGPoint
    var sample: ((CGPoint) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Color.clear.contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase, size.width > 0, size.height > 0 else { return }
                    point = normalized(location, in: size)
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    guard let sample, size.width > 0, size.height > 0 else { return }
                    let location = normalized(tap.location, in: size)
                    point = location
                    sample(location)
                }, including: sample == nil ? .none : .all)
                .overlay(alignment: .topLeading) {
                    Circle().strokeBorder(.black, lineWidth: 3)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                        .frame(width: 16, height: 16)
                        .position(x: point.x * size.width, y: point.y * size.height)
                        .allowsHitTesting(false)
                }
        }.accessibilityHidden(true)
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, location.x / size.width)),
                y: min(1, max(0, location.y / size.height)))
    }
}

struct LoupePanel: View {
    let image: ViewerImage
    let point: CGPoint
    @AppStorage("loupe.magnification") private var magnification = 4
    @AppStorage("loupe.pixelGrid") private var grid = true

    var body: some View {
        let scale = [2, 4, 8].contains(magnification) ? magnification : 4
        let sample = LoupeSample(point: point, width: image.display.width, height: image.display.height, span: 144 / scale)
        let region = sample.region
        let cell = CGFloat(scale)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Loupe", systemImage: "magnifyingglass")
                Spacer(minLength: 8)
                Menu("\(scale * 100)%") {
                    Picker("Magnification", selection: $magnification) {
                        ForEach([2, 4, 8], id: \.self) { Text("\($0 * 100)%").tag($0) }
                    }
                    Toggle("Pixel Grid", isOn: $grid)
                }.fixedSize().accessibilityLabel("Loupe magnification")
            }
            if let patch = image.display.cropping(to: region) {
                Image(decorative: patch, scale: 1)
                    .resizable().interpolation(.none)
                    .frame(width: region.width * cell, height: region.height * cell)
                    .overlay {
                        if grid && scale >= 4 {
                            Path { path in
                                for x in 1..<patch.width {
                                    path.move(to: CGPoint(x: CGFloat(x) * cell, y: 0))
                                    path.addLine(to: CGPoint(x: CGFloat(x) * cell, y: region.height * cell))
                                }
                                for y in 1..<patch.height {
                                    path.move(to: CGPoint(x: 0, y: CGFloat(y) * cell))
                                    path.addLine(to: CGPoint(x: region.width * cell, y: CGFloat(y) * cell))
                                }
                            }.stroke(.white.opacity(0.28), lineWidth: 0.5)
                        }
                        Rectangle().strokeBorder(.white, lineWidth: 1)
                            .frame(width: cell, height: cell)
                            .position(x: (CGFloat(sample.x) - region.minX + 0.5) * cell,
                                      y: (CGFloat(sample.y) - region.minY + 0.5) * cell)
                    }
                    .frame(width: 144, height: 144)
                    .background(.black.opacity(0.65))
            }
            Text("x \(sample.x)   y \(sample.y)").monospacedDigit()
            if let rgba = sample.rgba(in: image.rendered) {
                Text("R \(rgba[0])  G \(rgba[1])  B \(rgba[2])").monospacedDigit()
                if rgba[3] != 255 { Text("Alpha \(rgba[3])").monospacedDigit() }
            }
        }.font(.caption)
            .frame(width: 156)
            .padding(10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pixel Loupe")
    }
}
