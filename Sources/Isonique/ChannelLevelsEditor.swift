import SwiftUI
import IsoniqueCore

extension Workspace {
    func setChannelLevels(_ levels: LevelValues, for channel: LevelsChannel, photoID: UUID) {
        guard !busy, !batchMode, !isViewingTrash, let photo = selected, photo.id == photoID else { return }
        var adjusted = photo.adjustments
        adjusted.setLevels(levels, for: channel)
        guard adjusted != photo.adjustments else { return }
        compareOriginal = false
        edit { $0.adjustments = adjusted }
    }
}

struct ChannelLevelsEditor: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo
    let input: ToneHistogram?
    @State private var channel: LevelsChannel = .red
    @State private var draft: LevelValues?

    private var saved: LevelValues { photo.adjustments.levels(for: channel) }
    private var levels: LevelValues { draft ?? saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Levels channel", selection: $channel) {
                ForEach(LevelsChannel.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            AdjustmentHistogramView(series: input.map { [series(from: $0)] } ?? [])
                .frame(height: 48).background(.black.opacity(0.25))
                .accessibilityHidden(false).accessibilityLabel("\(channel.rawValue) Levels input histogram")
            slider("Channel black point", \.blackPoint, in: 0...max(0, levels.whitePoint - 0.01))
            slider("Channel white point", \.whitePoint, in: min(1, levels.blackPoint + 0.01)...1)
            slider("Channel gamma", \.gamma, in: 0.1...4)
            slider("Channel dark quarter", \.darkQuarter, in: 0...0.5)
            slider("Channel light quarter", \.lightQuarter, in: 0.5...1)
            HStack {
                AutoLevelsButton(mode: .separate, input: input, photo: photo)
                Button("Reset Channel Levels") { commit(LevelValues()) }
                    .disabled(saved == LevelValues())
            }
        }.onChange(of: channel) { _, _ in draft = nil }
    }

    private func series(from input: ToneHistogram) -> ([Int], Color) {
        switch channel {
        case .red: (input.red, .red)
        case .green: (input.green, .green)
        case .blue: (input.blue, .blue)
        }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<LevelValues, Double>,
                        in range: ClosedRange<Double>) -> some View {
        let canMove = range.lowerBound < range.upperBound
        let value = Binding {
            levels[keyPath: path]
        } set: { updated in
            var values = levels
            values[keyPath: path] = updated
            if draft != nil { draft = values } else { commit(values) }
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }.font(.caption).accessibilityHidden(true)
            Slider(value: value, in: canMove ? range : 0...1, step: 0.01) { Text(title) } onEditingChanged: { editing in
                if editing {
                    draft = saved
                } else if let draft {
                    self.draft = nil
                    commit(draft)
                }
            }.disabled(!canMove).labelsHidden()
                .accessibilityValue(Text(value.wrappedValue, format: .number.precision(.fractionLength(2))))
        }
    }

    private func commit(_ values: LevelValues) { model.setChannelLevels(values, for: channel, photoID: photo.id) }
}
