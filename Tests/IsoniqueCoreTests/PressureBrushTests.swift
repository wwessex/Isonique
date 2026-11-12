import XCTest
@testable import IsoniqueCore

final class PressureBrushTests: XCTestCase {
    func testPressureCurvesClampAndMapSizeAndStrengthIndependently() {
        let mapping = BrushPressureMapping(sizeCurve: .soft, strengthCurve: .firm,
                                           minimumSize: 0.2, minimumStrength: 0.1)
        XCTAssertEqual(mapping.sample(pressure: -1, isTablet: true),
                       BrushPressureSample(radiusScale: 0.2, strengthScale: 0.1))
        XCTAssertEqual(mapping.sample(pressure: 2, isTablet: true),
                       BrushPressureSample(radiusScale: 1, strengthScale: 1))
        let middle = mapping.sample(pressure: 0.25, isTablet: true)
        XCTAssertEqual(middle.radiusScale, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(middle.strengthScale, 0.15625, accuracy: 0.000_001)
        XCTAssertEqual(mapping.sample(pressure: 0.1, isTablet: false),
                       BrushPressureSample(radiusScale: 1, strengthScale: 1),
                       "Mouse and trackpad input must retain the configured fixed brush")
        XCTAssertEqual(mapping.sample(pressure: .nan, isTablet: true),
                       BrushPressureSample(radiusScale: 1, strengthScale: 1))

        let sizeOnly = BrushPressureMapping(sizeCurve: .linear, strengthCurve: .off,
                                            minimumSize: 0, minimumStrength: 0)
            .sample(pressure: 0.4, isTablet: true)
        XCTAssertEqual(sizeOnly.radiusScale, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(sizeOnly.strengthScale, 1)
    }

    func testMidStrokeSamplesVaryRadiusAndStrength() throws {
        let sizeStroke = LocalBrushStroke(adjustment: .dodge, radius: 0.2, softness: 0,
            strength: 1, points: [
                BrushPoint(x: 0.2, y: 0.5, radiusScale: 0.25, strengthScale: 1),
                BrushPoint(x: 0.5, y: 0.5, radiusScale: 0.5, strengthScale: 1),
                BrushPoint(x: 0.8, y: 0.5, radiusScale: 1, strengthScale: 1),
            ])
        let sizeMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [sizeStroke],
            sourceWidth: 100, sourceHeight: 100))
        XCTAssertEqual(sizeMask.coverage(for: .dodge, x: 20, y: 58,
            imageWidth: 100, imageHeight: 100), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(sizeMask.coverage(for: .dodge, x: 80, y: 58,
            imageWidth: 100, imageHeight: 100), 0.99)

        let strengthStroke = LocalBrushStroke(adjustment: .dodge, radius: 0.08, softness: 0,
            strength: 0.8, points: [
                BrushPoint(x: 0.2, y: 0.5, radiusScale: 1, strengthScale: 0.2),
                BrushPoint(x: 0.5, y: 0.5, radiusScale: 1, strengthScale: 0.5),
                BrushPoint(x: 0.8, y: 0.5, radiusScale: 1, strengthScale: 1),
            ])
        let strengthMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [strengthStroke],
            sourceWidth: 100, sourceHeight: 100))
        XCTAssertEqual(strengthMask.coverage(for: .dodge, x: 20, y: 50,
            imageWidth: 100, imageHeight: 100), 0.16, accuracy: 0.01)
        XCTAssertEqual(strengthMask.coverage(for: .dodge, x: 50, y: 50,
            imageWidth: 100, imageHeight: 100), 0.4, accuracy: 0.01)
        XCTAssertEqual(strengthMask.coverage(for: .dodge, x: 80, y: 50,
            imageWidth: 100, imageHeight: 100), 0.8, accuracy: 0.01)
    }

    func testFormat34RoundTripAndFormat33Compatibility() throws {
        let legacyPoint = try JSONDecoder().decode(BrushPoint.self,
            from: Data(#"{"x":0.25,"y":0.75}"#.utf8))
        XCTAssertEqual(legacyPoint, BrushPoint(x: 0.25, y: 0.75))
        let encodedLegacy = try XCTUnwrap(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(legacyPoint)) as? [String: Any])
        XCTAssertNil(encodedLegacy["radiusScale"])
        XCTAssertNil(encodedLegacy["strengthScale"])

        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 100, height: 100, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushInstances = [LocalBrushInstance(name: "Fixed", adjustment: .dodge,
            strokes: [LocalBrushStroke(adjustment: .dodge, radius: 0.1, softness: 0.5,
                strength: 0.8, points: [legacyPoint])])]
        var format33 = Library()
        format33.version = 33
        format33.photos = [photo]
        XCTAssertNoThrow(try format33.validateSchema())
        format33.upgradeForPressureBrushes()
        XCTAssertEqual(format33.version, 33, "Fixed mouse recipes must not force a format upgrade")

        photo.adjustments.localBrushInstances[0].strokes = [LocalBrushStroke(
            adjustment: .dodge, radius: 0.1, softness: 0.5, strength: 0.8,
            points: [BrushPoint(x: 0.25, y: 0.75, radiusScale: 0.4, strengthScale: 0.65)])]
        var pressureLibrary = Library()
        pressureLibrary.version = 33
        pressureLibrary.photos = [photo]
        XCTAssertThrowsError(try pressureLibrary.validateSchema())
        pressureLibrary.upgradeForPressureBrushes()
        XCTAssertEqual(pressureLibrary.version, 34)
        XCTAssertNoThrow(try pressureLibrary.validateSchema())
        let reopened = try JSONDecoder().decode(Library.self,
            from: JSONEncoder().encode(pressureLibrary))
        XCTAssertEqual(reopened.photos[0].adjustments, photo.adjustments)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush])
            .localBrushInstances, photo.adjustments.localBrushInstances)
    }
}
