import XCTest
@testable import IsoniqueCore

final class CustomAdjustmentPresetTests: XCTestCase {
    func testDefaultGroupsApplyNonSpatialSettingsAndProtectSpatialRecipes() throws {
        var target = Adjustments()
        target.exposure = -1
        target.crop = PhotoCrop(x: 0.1, y: 0.12, width: 0.7, height: 0.68)
        target.localBrushes = [LocalBrushStroke(adjustment: .dodge, radius: 0.05, softness: 0.7,
                                                 strength: 0.4, points: [BrushPoint(x: 0.3, y: 0.4)])]
        target.spotRemovals = [SpotRemoval(mode: .repair, source: BrushPoint(x: 0.2, y: 0.2),
                                           destination: BrushPoint(x: 0.4, y: 0.4), radius: 0.06)]
        target.redEyeCorrections = [RedEyeCorrection(center: BrushPoint(x: 0.6, y: 0.4),
                                                      radius: 0.04, darkness: 0.5)]
        var recipe = Adjustments()
        recipe.exposure = 1.5
        recipe.definition = 0.7
        recipe.crop = PhotoCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        recipe.localBrushes = [LocalBrushStroke(adjustment: .burn, radius: 0.08, softness: 0.5,
                                                 strength: 0.8, points: [BrushPoint(x: 0.7, y: 0.7)])]
        recipe.spotRemovals = []
        recipe.redEyeCorrections = []

        let preset = CustomAdjustmentPreset(name: "Safe", adjustments: recipe)
        XCTAssertEqual(preset.groups, AdjustmentGroup.nonSpatialGroups)
        XCTAssertFalse(preset.includesSpatialAdjustments)
        let result = preset.applying(to: target)
        XCTAssertEqual(result.exposure, 1.5)
        XCTAssertEqual(result.definition, 0.7)
        XCTAssertEqual(result.crop, target.crop)
        XCTAssertEqual(result.localBrushes, target.localBrushes)
        XCTAssertEqual(result.spotRemovals, target.spotRemovals)
        XCTAssertEqual(result.redEyeCorrections, target.redEyeCorrections)
        XCTAssertTrue(preset.changedGroups(in: target).contains(.basic))
        XCTAssertFalse(preset.changedGroups(in: target).contains(.geometry))
    }

    func testSpatialGroupsReplaceOnlyWhenExplicitlySelected() {
        var target = Adjustments()
        target.exposure = -1
        target.crop = PhotoCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        target.localBrushes = [LocalBrushStroke(adjustment: .dodge, radius: 0.04, softness: 0.5,
                                                 strength: 0.5, points: [BrushPoint(x: 0.2, y: 0.2)])]
        target.spotRemovals = [SpotRemoval(mode: .clone, source: BrushPoint(x: 0.2, y: 0.2),
                                           destination: BrushPoint(x: 0.7, y: 0.7), radius: 0.05)]
        target.redEyeCorrections = [RedEyeCorrection(center: BrushPoint(x: 0.5, y: 0.5),
                                                      radius: 0.05, darkness: 0.4)]
        var recipe = Adjustments()
        recipe.exposure = 2
        recipe.crop = PhotoCrop(x: 0.25, y: 0.2, width: 0.5, height: 0.55)
        recipe.localBrushes = []
        recipe.spotRemovals = []
        recipe.redEyeCorrections = []
        let groups: Set<AdjustmentGroup> = [.geometry, .localBrush, .retouch, .redEye]
        let preset = CustomAdjustmentPreset(name: "Spatial", adjustments: recipe, groups: groups)
        let result = preset.applying(to: target)
        XCTAssertTrue(preset.includesSpatialAdjustments)
        XCTAssertEqual(result.exposure, target.exposure)
        XCTAssertEqual(result.crop, recipe.crop)
        XCTAssertEqual(result.localBrushes, recipe.localBrushes)
        XCTAssertEqual(result.spotRemovals, recipe.spotRemovals)
        XCTAssertEqual(result.redEyeCorrections, recipe.redEyeCorrections)
    }

    func testRoundTripAndOlderPayloadsDefaultToSafeGroups() throws {
        var adjustments = Adjustments()
        adjustments.exposure = 0.8
        let preset = CustomAdjustmentPreset(name: "Editorial", adjustments: adjustments,
            groups: [.basic, .whiteBalance, .detail])
        XCTAssertEqual(try JSONDecoder().decode(CustomAdjustmentPreset.self,
            from: JSONEncoder().encode(preset)), preset)

        let legacyAdjustments = try JSONEncoder().encode(adjustments)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyAdjustments) as? [String: Any])
        let legacy = try JSONSerialization.data(withJSONObject: ["name": "Legacy", "recipe": object])
        let decoded = try JSONDecoder().decode(CustomAdjustmentPreset.self, from: legacy)
        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertEqual(decoded.adjustments.exposure, 0.8)
        XCTAssertEqual(decoded.groups, AdjustmentGroup.nonSpatialGroups)
        XCTAssertFalse(decoded.includesSpatialAdjustments)
    }
}
