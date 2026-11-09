import SwiftUI
import IsoniqueCore

enum AutoLevelsMode { case combined, separate }

enum AutoLevelsPreferences {
    static let blackClipKey = "autoLevels.blackClipPercent"
    static let whiteClipKey = "autoLevels.whiteClipPercent"
    static let defaultClipPercent = 0.5
}

extension Workspace {
    func applyAutoLevels(_ mode: AutoLevelsMode, input: ToneHistogram, for photo: Photo,
                         blackClip: Double, whiteClip: Double) {
        guard !busy, !batchMode, !isViewingTrash, let selected,
              selected.id == photo.id, selected.adjustments == photo.adjustments else { return }
        func endpoints(_ bins: [Int]) -> ClosedRange<Double>? {
            AutoLevels.endpoints(bins, blackClipPercent: blackClip, whiteClipPercent: whiteClip)
        }
        var recipe = photo.adjustments
        switch mode {
        case .combined:
            guard let range = endpoints(input.luminance) else { status = "Auto Levels · insufficient tonal range"; return }
            recipe.blackPoint = range.lowerBound
            recipe.whitePoint = range.upperBound
        case .separate:
            let channels: [(LevelsChannel, [Int])] = [(.red, input.red), (.green, input.green), (.blue, input.blue)]
            var foundRange = false
            for (channel, bins) in channels {
                guard let range = endpoints(bins) else { continue }
                foundRange = true
                var levels = recipe.levels(for: channel)
                levels.blackPoint = range.lowerBound
                levels.whitePoint = range.upperBound
                recipe.setLevels(levels, for: channel)
            }
            guard foundRange else { status = "Auto Levels · insufficient tonal range"; return }
        }
        guard recipe != photo.adjustments else { status = "Auto Levels · endpoints already match"; return }
        compareOriginal = false
        edit { $0.adjustments = recipe }
    }
}

struct AutoLevelsButton: View {
    @EnvironmentObject private var model: Workspace
    @AppStorage(AutoLevelsPreferences.blackClipKey) private var blackClip = AutoLevelsPreferences.defaultClipPercent
    @AppStorage(AutoLevelsPreferences.whiteClipKey) private var whiteClip = AutoLevelsPreferences.defaultClipPercent
    let mode: AutoLevelsMode
    let input: ToneHistogram?
    let photo: Photo

    var body: some View {
        Button(mode == .combined ? "Auto Levels Combined" : "Auto Levels Separate") {
            guard let input else { return }
            model.applyAutoLevels(mode, input: input, for: photo, blackClip: blackClip, whiteClip: whiteClip)
        }.disabled(input == nil || model.busy || model.batchMode || model.isViewingTrash)
            .help(mode == .combined ? "Set combined black and white points from the luminance histogram"
                  : "Set independent black and white points from the red, green and blue histograms")
    }
}

struct AutoLevelsSettingsSection: View {
    @AppStorage(AutoLevelsPreferences.blackClipKey) private var blackClip = AutoLevelsPreferences.defaultClipPercent
    @AppStorage(AutoLevelsPreferences.whiteClipKey) private var whiteClip = AutoLevelsPreferences.defaultClipPercent

    var body: some View {
        Section("Auto Levels") {
            Stepper("Black clipping \(percentage(blackClip))", value: $blackClip, in: 0...5, step: 0.1)
            Stepper("White clipping \(percentage(whiteClip))", value: $whiteClip, in: 0...5, step: 0.1)
            Text("Sets how many samples Auto Levels may clip from each end of the input histogram.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func percentage(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}
