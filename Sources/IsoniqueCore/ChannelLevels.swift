import Foundation

public enum LevelsChannel: String, CaseIterable, Identifiable {
    case red = "Red", green = "Green", blue = "Blue"
    public var id: Self { self }
}

public struct LevelQuarterTones: Codable, Equatable {
    public var darkOutput = 0.25
    public var lightOutput = 0.75

    public init() {}

    var normalized: Self {
        var result = Self()
        if darkOutput.isFinite { result.darkOutput = min(0.5, max(0, darkOutput)) }
        if lightOutput.isFinite { result.lightOutput = min(1, max(0.5, lightOutput)) }
        return result
    }

    func map(_ input: Double) -> Double {
        let darkWeight = max(0, 1 - abs(input - 0.25) * 4)
        let lightWeight = max(0, 1 - abs(input - 0.75) * 4)
        return input + (darkOutput - 0.25) * darkWeight + (lightOutput - 0.75) * lightWeight
    }
}

public struct LevelValues: Codable, Equatable {
    public var blackPoint = 0.0
    public var whitePoint = 1.0
    public var gamma = 1.0
    public internal(set) var quarterTones: LevelQuarterTones?

    public init() {}

    var normalized: Self {
        func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        var values = Self()
        values.blackPoint = clamp(blackPoint, to: 0...0.99, fallback: 0)
        values.whitePoint = clamp(whitePoint, to: min(1, values.blackPoint + 0.01)...1, fallback: 1)
        values.gamma = clamp(gamma, to: 0.1...4, fallback: 1)
        if let quarters = quarterTones?.normalized, quarters != LevelQuarterTones() {
            values.quarterTones = quarters
        }
        return values
    }

    func map(_ input: Double) -> Double {
        let x = pow(min(1, max(0, (input - blackPoint) / (whitePoint - blackPoint))), 1 / gamma)
        return quarterTones?.map(x) ?? x
    }

    public var darkQuarter: Double {
        get { quarterTones?.darkOutput ?? 0.25 }
        set { setQuarterTones(dark: newValue, light: lightQuarter) }
    }

    public var lightQuarter: Double {
        get { quarterTones?.lightOutput ?? 0.75 }
        set { setQuarterTones(dark: darkQuarter, light: newValue) }
    }

    private mutating func setQuarterTones(dark: Double, light: Double) {
        quarterTones = normalizedQuarters(dark: dark, light: light)
    }
}

public struct ChannelLevels: Codable, Equatable {
    public private(set) var red: LevelValues?
    public private(set) var green: LevelValues?
    public private(set) var blue: LevelValues?

    public init() {}
    var isEmpty: Bool { red == nil && green == nil && blue == nil }
    var hasQuarterTones: Bool {
        [red, green, blue].contains { $0?.normalized.quarterTones != nil }
    }

    public subscript(channel: LevelsChannel) -> LevelValues {
        get { self[keyPath: path(for: channel)]?.normalized ?? LevelValues() }
        set {
            let values = newValue.normalized
            self[keyPath: path(for: channel)] = values == LevelValues() ? nil : values
        }
    }

    private func path(for channel: LevelsChannel) -> WritableKeyPath<Self, LevelValues?> {
        switch channel {
        case .red: \.red
        case .green: \.green
        case .blue: \.blue
        }
    }
}

public extension Adjustments {
    var darkLevelQuarter: Double {
        get { levelQuarterTones?.normalized.darkOutput ?? 0.25 }
        set { levelQuarterTones = normalizedQuarters(dark: newValue, light: lightLevelQuarter) }
    }

    var lightLevelQuarter: Double {
        get { levelQuarterTones?.normalized.lightOutput ?? 0.75 }
        set { levelQuarterTones = normalizedQuarters(dark: darkLevelQuarter, light: newValue) }
    }

    var hasLevelQuarterTones: Bool {
        (levelQuarterTones?.normalized ?? LevelQuarterTones()) != LevelQuarterTones() ||
            channelLevels?.hasQuarterTones == true
    }

    func levels(for channel: LevelsChannel) -> LevelValues { channelLevels?[channel] ?? LevelValues() }

    mutating func setLevels(_ levels: LevelValues, for channel: LevelsChannel) {
        var channels = channelLevels ?? ChannelLevels()
        channels[channel] = levels
        channelLevels = channels.isEmpty ? nil : channels
    }
}

private func normalizedQuarters(dark: Double, light: Double) -> LevelQuarterTones? {
    var values = LevelQuarterTones()
    values.darkOutput = dark
    values.lightOutput = light
    let normalized = values.normalized
    return normalized == LevelQuarterTones() ? nil : normalized
}

public enum AutoLevels {
    /// Clip the requested percentage of samples from each tail. Very narrow ranges are left alone.
    public static func endpoints(_ bins: [Int], blackClipPercent: Double, whiteClipPercent: Double) -> ClosedRange<Double>? {
        guard bins.count == 256, bins.allSatisfy({ $0 >= 0 }) else { return nil }
        let total = bins.reduce(0, +)
        guard total > 0 else { return nil }
        func count(_ percent: Double) -> Int {
            guard percent.isFinite else { return 0 }
            return Int((Double(total) * min(5, max(0, percent)) / 100).rounded(.down))
        }
        func rank(_ rank: Int) -> Int {
            var cumulative = 0
            for (code, samples) in bins.enumerated() {
                cumulative += samples
                if cumulative > rank { return code }
            }
            return 255
        }
        let lower = rank(count(blackClipPercent)), upper = rank(total - count(whiteClipPercent) - 1)
        guard upper - lower >= 3 else { return nil }
        return Double(lower) / 255...Double(upper) / 255
    }
}
