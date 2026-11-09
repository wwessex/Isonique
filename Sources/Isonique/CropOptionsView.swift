import SwiftUI
import AppKit
import IsoniqueCore

struct CropOptionsView: View {
    @Binding var crop: PhotoCrop
    @Binding var aspect: Double
    @Binding var locked: Bool
    let size: CGSize
    let cancel: () -> Void
    let apply: () -> Void
    @State private var width = 1
    @State private var height = 1
    @State private var ratioWidth = 3.0
    @State private var ratioHeight = 2.0
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Menu("Aspect") {
                    Button("Freeform") { locked = false; aspect = 0 }
                    Button("Full image") { locked = false; aspect = 0; crop = PhotoCrop(x: 0, y: 0, width: 1, height: 1) }
                    Button("Square") { preset(1) }
                    Button("4:3") { preset(4.0 / 3) }
                    Button("3:2") { preset(3.0 / 2) }
                    Button("16:9") { preset(16.0 / 9) }
                }.fixedSize()
                Toggle("Lock aspect", isOn: $locked).onChange(of: locked) { _, value in
                    if value && aspect <= 0 { aspect = CropRules.aspectRatio(width: crop.width * size.width, height: crop.height * size.height) ?? 1 }
                }
                Button("Portrait / Landscape") { preset(1 / max(0.0001, aspect > 0 ? aspect : crop.width * size.width / (crop.height * size.height))) }
            }
            HStack(spacing: 6) {
                Text("Custom ratio")
                TextField("Width", value: $ratioWidth, format: .number).frame(width: 65).accessibilityLabel("Aspect ratio width")
                Text(":")
                TextField("Height", value: $ratioHeight, format: .number).frame(width: 65).accessibilityLabel("Aspect ratio height")
                Button("Set ratio") {
                    if let value = CropRules.aspectRatio(width: ratioWidth, height: ratioHeight) { preset(value) }
                }.disabled(CropRules.aspectRatio(width: ratioWidth, height: ratioHeight) == nil)
            }.textFieldStyle(.roundedBorder)
            ViewThatFits(in: .horizontal) {
                HStack { pixelFields; actionButtons }
                VStack { pixelFields; actionButtons }
            }
            Text("Drag inside to move; drag a corner to resize; drag outside to redraw. Aspect lock is remembered.").font(.caption2).foregroundStyle(.secondary)
        }.onAppear(perform: sync).onChange(of: crop) { _, _ in sync() }.onChange(of: size) { _, _ in sync() }
    }
    var pixelFields: some View {
        HStack(spacing: 6) {
            Text("Pixels")
            TextField("Width", value: $width, format: .number).frame(width: 65).accessibilityLabel("Crop width in pixels")
            Text("×")
            TextField("Height", value: $height, format: .number).frame(width: 65).accessibilityLabel("Crop height in pixels")
            Button("Set") {
                crop = CropRules.pixels(width: width, height: height, image: size, current: crop)
                aspect = CropRules.aspectRatio(width: Double(width), height: Double(height)) ?? 1
            }.disabled(width < 1 || height < 1 || Double(width) > size.width || Double(height) > size.height)
        }.textFieldStyle(.roundedBorder)
    }
    var actionButtons: some View {
        HStack { Spacer(minLength: 8); Button("Cancel", action: cancel); Button("Apply Crop", action: apply).buttonStyle(.borderedProminent) }
    }
    func sync() { width = max(1, Int((crop.width * size.width).rounded())); height = max(1, Int((crop.height * size.height).rounded())) }
    func preset(_ value: Double) {
        aspect = value; locked = true
        let normalized = value * size.height / size.width
        let w = min(1, normalized), h = min(1, 1 / normalized)
        crop = PhotoCrop(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }
}
struct CropCanvas: View {
    let image: ViewerImage
    @Binding var crop: PhotoCrop
    let pixelSize: CGSize
    let aspect: Double?
    @State private var startingCrop: PhotoCrop?
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: crop.x * size.width, y: crop.y * size.height, width: crop.width * size.width, height: crop.height * size.height)
            ZStack(alignment: .topLeading) {
                ClippingPreview(image: image).frame(width: size.width, height: size.height)
                Path { path in path.addRect(CGRect(origin: .zero, size: size)); path.addRect(rect) }.fill(.black.opacity(0.5), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Path { path in
                    path.addRect(rect)
                    for n in 1...2 {
                        let x = rect.minX + rect.width * CGFloat(n) / 3, y = rect.minY + rect.height * CGFloat(n) / 3
                        path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                        path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }.stroke(.white.opacity(0.9), lineWidth: 1).allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle()).frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                    .gesture(DragGesture().onChanged { drag in
                        if startingCrop == nil { startingCrop = crop }
                        guard let start = startingCrop else { return }
                        crop = CropRules.fitted(x: start.x + drag.translation.width / size.width, y: start.y + drag.translation.height / size.height, width: start.width, height: start.height, image: pixelSize)
                    }.onEnded { _ in startingCrop = nil })
                ForEach(0..<4) { corner in
                    let right = corner % 2 == 1, bottom = corner >= 2
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 12, height: 12)
                        .contentShape(Rectangle()).position(x: right ? rect.maxX : rect.minX, y: bottom ? rect.maxY : rect.minY)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            if startingCrop == nil { startingCrop = crop }
                            guard let start = startingCrop else { return }
                            let anchorX = right ? start.x : start.x + start.width
                            let anchorY = bottom ? start.y : start.y + start.height
                            let endX = min(1, max(0, (right ? start.x + start.width : start.x) + drag.translation.width / size.width))
                            let endY = min(1, max(0, (bottom ? start.y + start.height : start.y) + drag.translation.height / size.height))
                            var result = CropRules.fitted(x: 0, y: 0, width: abs(endX - anchorX), height: abs(endY - anchorY), image: pixelSize, aspect: aspect)
                            // Constrain to the space around the opposite, fixed corner.
                            let availableW = endX >= anchorX ? 1 - anchorX : anchorX
                            let availableH = endY >= anchorY ? 1 - anchorY : anchorY
                            let factor = min(1, min(availableW / result.width, availableH / result.height))
                            result.width *= factor; result.height *= factor
                            if result.width * pixelSize.width < 1 || result.height * pixelSize.height < 1 { return }
                            result.x = endX >= anchorX ? anchorX : anchorX - result.width
                            result.y = endY >= anchorY ? anchorY : anchorY - result.height
                            crop = result
                        }.onEnded { _ in startingCrop = nil })
                        .accessibilityLabel("Crop corner \(corner + 1)")
                }
            }.frame(width: size.width, height: size.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    let x1 = min(1, max(0, drag.startLocation.x / size.width)), y1 = min(1, max(0, drag.startLocation.y / size.height))
                    let x2 = min(1, max(0, drag.location.x / size.width)), y2 = min(1, max(0, drag.location.y / size.height))
                    if abs(x2 - x1) > 0.005, abs(y2 - y1) > 0.005 {
                        crop = CropRules.fitted(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1), image: pixelSize, aspect: aspect)
                    }
                }).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.accessibilityLabel("Crop area. Drag inside to move or drag corner handles to resize. Exact pixel fields are below.")
    }
}
