import Foundation

public enum LevelsChannel: String, CaseIterable, Identifiable {
    case red = "Red", green = "Green", blue = "Blue"
    public var id: Self { self }
}

public struct LevelValues: Codable, Equatable {
    public var blackPoint = 0.0
    public var whitePoint = 1.0
    public var gamma = 1.0

    public init() {}

    var normalized: Self {
        func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        var values = Self()
        values.blackPoint = clamp(blackPoint, to: 0...0.99, fallback: 0)
        values.whitePoint = clamp(whitePoint, to: min(1, values.blackPoint + 0.01)...1, fallback: 1)
        values.gamma = clamp(gamma, to: 0.1...4, fallback: 1)
        return values
    }

    func map(_ input: Double) -> Double {
        pow(min(1, max(0, (input - blackPoint) / (whitePoint - blackPoint))), 1 / gamma)
    }
}

public struct ChannelLevels: Codable, Equatable {
    public private(set) var red: LevelValues?
    public private(set) var green: LevelValues?
    public private(set) var blue: LevelValues?

    public init() {}
    var isEmpty: Bool { red == nil && green == nil && blue == nil }

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
    func levels(for channel: LevelsChannel) -> LevelValues { channelLevels?[channel] ?? LevelValues() }

    mutating func setLevels(_ levels: LevelValues, for channel: LevelsChannel) {
        var channels = channelLevels ?? ChannelLevels()
        channels[channel] = levels
        channelLevels = channels.isEmpty ? nil : channels
    }
}
