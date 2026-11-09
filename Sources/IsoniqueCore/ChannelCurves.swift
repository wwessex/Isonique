import Foundation

public enum CurveChannel: String, CaseIterable, Identifiable {
    case red = "Red", green = "Green", blue = "Blue", luminance = "Luminance"
    public var id: Self { self }
}

public struct CurvePoint: Codable, Equatable {
    public let input: Int
    public let output: Int

    public init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }
}

/// A piecewise-linear transfer function with editable outputs at both endpoints.
public struct ChannelCurve: Codable, Equatable {
    public static let pointLimit = 16
    public static let identity = ChannelCurve(validated: [CurvePoint(input: 0, output: 0), CurvePoint(input: 255, output: 255)])
    public private(set) var points: [CurvePoint]

    private init(validated points: [CurvePoint]) { self.points = points }

    public init?(points: [CurvePoint]) {
        guard (2...Self.pointLimit).contains(points.count), points.first?.input == 0, points.last?.input == 255,
              points.allSatisfy({ (0...255).contains($0.output) }),
              zip(points, points.dropFirst()).allSatisfy({ $0.input < $1.input }) else { return nil }
        self.points = points
    }

    private enum CodingKeys: CodingKey { case points }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let curve = Self(points: try container.decode([CurvePoint].self, forKey: .points)) else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: container, debugDescription: "Invalid curve points")
        }
        self = curve
    }

    public func value(at fraction: Double) -> Double {
        let input = min(1, max(0, fraction)) * 255
        let upper = points.firstIndex { Double($0.input) >= input } ?? points.count - 1
        let right = points[upper]
        guard upper > 0 else { return Double(right.output) / 255 }
        let left = points[upper - 1]
        let mix = (input - Double(left.input)) / Double(right.input - left.input)
        return (Double(left.output) + Double(right.output - left.output) * mix) / 255
    }

    public mutating func movePoint(at index: Int, input: Int, output: Int) {
        guard points.indices.contains(index) else { return }
        let position = points[index].input
        let left = index == 0 ? position : points[index - 1].input + 1
        let right = index == points.count - 1 ? position : points[index + 1].input - 1
        let target = index == 0 || index == points.count - 1 ? position : min(right, max(left, input))
        points[index] = CurvePoint(input: target, output: min(255, max(0, output)))
    }

    @discardableResult
    public mutating func insertPoint(input: Int, output: Int) -> Int? {
        guard points.count < Self.pointLimit, (1..<255).contains(input),
              let index = points.firstIndex(where: { $0.input >= input }), points[index].input != input else { return nil }
        points.insert(CurvePoint(input: input, output: min(255, max(0, output))), at: index)
        return index
    }

    public mutating func removePoint(at index: Int) {
        guard index > 0, index < points.count - 1 else { return }
        points.remove(at: index)
    }
}

public struct ChannelCurves: Codable, Equatable {
    public private(set) var red: ChannelCurve?
    public private(set) var green: ChannelCurve?
    public private(set) var blue: ChannelCurve?
    public private(set) var luminance: ChannelCurve?

    public init() {}
    var isEmpty: Bool { red == nil && green == nil && blue == nil && luminance == nil }

    public subscript(channel: CurveChannel) -> ChannelCurve {
        get { self[keyPath: path(for: channel)] ?? .identity }
        set { self[keyPath: path(for: channel)] = newValue == .identity ? nil : newValue }
    }

    private func path(for channel: CurveChannel) -> WritableKeyPath<Self, ChannelCurve?> {
        switch channel {
        case .red: \.red
        case .green: \.green
        case .blue: \.blue
        case .luminance: \.luminance
        }
    }
}

public extension Adjustments {
    func curve(for channel: CurveChannel) -> ChannelCurve { channelCurves?[channel] ?? .identity }

    mutating func setCurve(_ curve: ChannelCurve, for channel: CurveChannel) {
        var curves = channelCurves ?? ChannelCurves()
        curves[channel] = curve
        channelCurves = curves.isEmpty ? nil : curves
    }
}
