import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class AdjustmentPresetTests: XCTestCase {
    @MainActor
    func testLegacyLoadCreateUpdateRenameDeleteAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueAdjustmentPresetStore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        let suite = "IsoniqueAdjustmentPresetStore-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(Data("older-setting".utf8), forKey: "export.presets")
        preferences.set(Data(#"[{"name":"Legacy","recipe":{"exposure":1.25}}]"#.utf8),
                        forKey: AdjustmentPresetPreferences.key)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        let legacy = try XCTUnwrap(workspace.adjustmentPresets.first)
        XCTAssertEqual(legacy.name, "Legacy")
        XCTAssertEqual(legacy.adjustments.exposure, 1.25)
        XCTAssertEqual(legacy.groups, AdjustmentGroup.nonSpatialGroups)
        var recipe = Adjustments()
        recipe.exposure = 0.75
        XCTAssertTrue(workspace.createAdjustmentPreset(named: " Studio ", adjustments: recipe, groups: [.basic]))
        XCTAssertFalse(workspace.createAdjustmentPreset(named: "studio", adjustments: recipe, groups: [.basic]))
        let studio = try XCTUnwrap(workspace.adjustmentPresets.first { $0.name == "Studio" })
        recipe.exposure = 1.5
        XCTAssertTrue(workspace.updateAdjustmentPreset(studio.id, adjustments: recipe, groups: [.basic, .detail]))
        XCTAssertTrue(workspace.renameAdjustmentPreset(studio.id, to: "Studio Bright"))
        XCTAssertFalse(workspace.renameAdjustmentPreset(studio.id, to: "legacy"))

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        let saved = try XCTUnwrap(reopened.adjustmentPresets.first { $0.id == studio.id })
        XCTAssertEqual(saved.name, "Studio Bright")
        XCTAssertEqual(saved.adjustments.exposure, 1.5)
        XCTAssertEqual(saved.groups, [.basic, .detail])
        XCTAssertEqual(preferences.data(forKey: "export.presets"), Data("older-setting".utf8))
        reopened.deleteAdjustmentPreset(legacy.id)
        reopened.deleteAdjustmentPreset(studio.id)
        XCTAssertTrue(AdjustmentPresetPreferences.load(from: preferences).isEmpty)
    }

    @MainActor
    func testReviewSingleAndBatchApplyUndoRedoAndSpatialProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueAdjustmentPresetApply-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        var first = photo("First.jpg", exposure: -1, cropX: 0.1)
        var second = photo("Second.jpg", exposure: -0.5, cropX: 0.2)
        let firstSpatial = first.adjustments
        let secondSpatial = second.adjustments
        library.photos = [first, second]
        library = try repository.save(library)
        first = library.photos[0]
        second = library.photos[1]
        let suite = "IsoniqueAdjustmentPresetApply-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = first.id
        var recipe = Adjustments()
        recipe.exposure = 1.75
        recipe.crop = PhotoCrop(x: 0.35, y: 0.2, width: 0.4, height: 0.5)
        let safe = CustomAdjustmentPreset(name: "Bright", adjustments: recipe, groups: [.basic])

        workspace.previewAdjustmentPreset(safe)
        let singleReview = try XCTUnwrap(workspace.adjustmentPresetReview)
        XCTAssertEqual(singleReview.photoIDs, [first.id])
        XCTAssertEqual(safe.changedGroups(in: first.adjustments), [.basic])
        workspace.applyAdjustmentPreset(singleReview)
        XCTAssertEqual(workspace.selected?.adjustments.exposure, 1.75)
        assertSpatial(workspace.selected?.adjustments, equals: firstSpatial)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.exposure, -1)
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.exposure, 1.75)
        workspace.undoEdit()

        workspace.batchMode = true
        workspace.batchSelection = [first.id, second.id]
        workspace.previewAdjustmentPreset(safe)
        let batchReview = try XCTUnwrap(workspace.adjustmentPresetReview)
        XCTAssertEqual(Set(batchReview.photoIDs), [first.id, second.id])
        workspace.applyAdjustmentPreset(batchReview)
        XCTAssertEqual(workspace.history.undo.count, 2)
        XCTAssertEqual(workspace.library.photos.first { $0.id == first.id }?.adjustments.exposure, 1.75)
        XCTAssertEqual(workspace.library.photos.first { $0.id == second.id }?.adjustments.exposure, 1.75)
        assertSpatial(workspace.library.photos.first { $0.id == first.id }?.adjustments, equals: firstSpatial)
        assertSpatial(workspace.library.photos.first { $0.id == second.id }?.adjustments, equals: secondSpatial)
        workspace.undoEdit()
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos.first { $0.id == first.id }?.adjustments.exposure, -1)
        XCTAssertEqual(workspace.library.photos.first { $0.id == second.id }?.adjustments.exposure, -0.5)
        workspace.redoEdit()
        workspace.redoEdit()
        XCTAssertEqual(workspace.library.photos.first { $0.id == first.id }?.adjustments.exposure, 1.75)
        XCTAssertEqual(workspace.library.photos.first { $0.id == second.id }?.adjustments.exposure, 1.75)
    }

    private func photo(_ name: String, exposure: Double, cropX: Double) -> Photo {
        var photo = Photo(filename: name, originalName: name, projectID: nil,
                          width: 100, height: 80, camera: "", captureDate: "", sha256: UUID().uuidString)
        photo.adjustments.exposure = exposure
        photo.adjustments.crop = PhotoCrop(x: cropX, y: 0.1, width: 0.65, height: 0.7)
        photo.adjustments.localBrushes = [LocalBrushStroke(adjustment: .dodge, radius: 0.04,
            softness: 0.6, strength: 0.5, points: [BrushPoint(x: 0.3, y: 0.4)])]
        photo.adjustments.spotRemovals = [SpotRemoval(mode: .repair, source: BrushPoint(x: 0.2, y: 0.2),
            destination: BrushPoint(x: 0.5, y: 0.5), radius: 0.05)]
        photo.adjustments.redEyeCorrections = [RedEyeCorrection(center: BrushPoint(x: 0.6, y: 0.4),
            radius: 0.04, darkness: 0.5)]
        return photo
    }

    private func assertSpatial(_ actual: Adjustments?, equals expected: Adjustments,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual?.crop, expected.crop, file: file, line: line)
        XCTAssertEqual(actual?.localBrushes, expected.localBrushes, file: file, line: line)
        XCTAssertEqual(actual?.spotRemovals, expected.spotRemovals, file: file, line: line)
        XCTAssertEqual(actual?.redEyeCorrections, expected.redEyeCorrections, file: file, line: line)
    }
}
