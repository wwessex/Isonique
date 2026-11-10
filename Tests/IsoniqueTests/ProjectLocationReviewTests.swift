import ImageIO
import IsoniqueCore
import UniformTypeIdentifiers
import XCTest
@testable import Isonique

final class ProjectLocationReviewTests: XCTestCase {
    @MainActor
    func testProjectPreviewProtectsKnownLocationsAndUndoesAllAssignmentsTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueProjectLocation-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let model = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let repository = try XCTUnwrap(model.repository)
        let project = Collection(name: "Walk")
        let otherProject = Collection(name: "Other walk")
        let originalPoint = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        let assignedPoint = try XCTUnwrap(GPSCoordinates(latitude: 51.512, longitude: -0.107))
        let destination = try XCTUnwrap(GPSCoordinates(latitude: 51.525, longitude: -0.14))
        var library = model.library
        library.projects = [project, otherProject]
        var options = ImportOptions()
        options.storage = .referenced
        let names = ["Indexed GPS", "Legacy GPS", "Assigned", "Cleared", "Indexed Missing",
                     "Legacy Missing", "Offline", "Changed", "Trash", "Other"]
        for (index, name) in names.enumerated() {
            let url = root.appendingPathComponent(name + ".jpg")
            let hasGPS = ["Indexed GPS", "Legacy GPS", "Cleared"].contains(name)
            try writeJPEG(to: url, colour: CGFloat(index) / CGFloat(names.count), withGPS: hasGPS)
            let projectID = name == "Other" ? otherProject.id : project.id
            XCTAssertTrue(try repository.importPhoto(url, projectID: projectID, into: &library, options: options))
            if name.hasPrefix("Legacy") || name == "Offline" || name == "Changed" {
                library.photos[library.photos.count - 1].gpsIndex = nil
            }
            switch name {
            case "Assigned": library.photos[library.photos.count - 1].locationOverride = .assigned(assignedPoint)
            case "Cleared": library.photos[library.photos.count - 1].locationOverride = .cleared
            case "Trash": library.photos[library.photos.count - 1].trashedAt = .now
            default: break
            }
        }
        let byName = Dictionary(uniqueKeysWithValues: zip(names, library.photos))
        let legacyMissing = try XCTUnwrap(byName["Legacy Missing"])
        let duplicate = try XCTUnwrap(library.createVersion(of: legacyMissing.id, from: .current))
        XCTAssertTrue(model.commit(library), model.error ?? "Could not save fixture")
        for name in ["Indexed Missing", "Offline"] {
            let original = root.appendingPathComponent(name + ".jpg")
            try FileManager.default.moveItem(at: original, to: original.appendingPathExtension("offline"))
        }
        try writeJPEG(to: root.appendingPathComponent("Changed.jpg"), colour: 0.95, withGPS: true)
        let legacyOriginal = try repository.availableOriginalURL(legacyMissing)
        let originalBytes = try Data(contentsOf: legacyOriginal)
        let baselinePhotos = model.library.photos
        let catalogue = libraryRoot.appendingPathComponent("catalog.json")
        let baselineCatalogue = try Data(contentsOf: catalogue)

        model.scope = "all"
        model.choosePresentation(.places)
        model.openProjectLocationEditor()
        XCTAssertNil(model.locationEditor)
        model.scope = "project:\(project.id)"
        model.search = "Indexed GPS"
        XCTAssertEqual(model.photos.map(\.originalName), ["Indexed GPS.jpg"])
        model.openProjectLocationEditor()
        let edit = try XCTUnwrap(model.locationEditor)
        let review = try ProjectLocationReview(edit: edit, repository: repository)
        let eligible: Set<UUID> = [try XCTUnwrap(byName["Indexed Missing"]).id, legacyMissing.id, duplicate.id]
        XCTAssertEqual(review.eligibleIDs, eligible)
        XCTAssertEqual(review.locatedCount, 3)
        XCTAssertEqual(review.clearedCount, 1)
        XCTAssertEqual(review.unverifiedCount, 2)
        XCTAssertEqual(Set(edit.changes(to: destination, restrictedTo: review.eligibleIDs).map(\.photoID)), eligible)
        XCTAssertEqual(try Data(contentsOf: catalogue), baselineCatalogue)

        model.locationEditor = nil
        XCTAssertFalse(model.applyLocationEdit(edit, coordinates: destination, projectReview: review))
        XCTAssertTrue(model.history.undo.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), baselineCatalogue)

        model.openProjectLocationEditor()
        let nextEdit = try XCTUnwrap(model.locationEditor)
        let nextReview = try ProjectLocationReview(edit: nextEdit, repository: repository)
        XCTAssertTrue(model.applyLocationEdit(nextEdit, coordinates: destination, projectReview: nextReview))
        XCTAssertEqual(model.history.undo.count, 1)
        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertNil(reopened.error)
        reopened.scope = "project:\(project.id)"
        reopened.choosePresentation(.places)
        let changed = reopened.library.photos.filter { $0.cataloguedLocation == destination }
        XCTAssertEqual(Set(changed.map(\.id)), eligible)
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).map(\.id)), [originalPoint, assignedPoint, destination])
        XCTAssertEqual(reopened.library.photos.filter { !eligible.contains($0.id) },
                       baselinePhotos.filter { !eligible.contains($0.id) })

        reopened.undoEdit()
        XCTAssertEqual(reopened.library.photos, baselinePhotos)
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).map(\.id)), [originalPoint, assignedPoint])
        reopened.redoEdit()
        XCTAssertEqual(Set(reopened.library.photos.filter { $0.cataloguedLocation == destination }.map(\.id)), eligible)
        XCTAssertEqual(try Data(contentsOf: legacyOriginal), originalBytes)
    }

    @MainActor
    func testProjectReviewRejectsAChangedLocationBeforeApplying() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueProjectReview-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let model = Workspace(libraryRoot: root.appendingPathComponent("Library"), preferences: preferences)
        let repository = try XCTUnwrap(model.repository)
        let project = Collection(name: "Walk")
        let url = root.appendingPathComponent("Photo.jpg")
        try writeJPEG(to: url, colour: 0.25, withGPS: false)
        var draft = model.library
        draft.projects = [project]
        XCTAssertTrue(try repository.importPhoto(url, projectID: project.id, into: &draft))
        XCTAssertTrue(model.commit(draft))
        model.scope = "project:\(project.id)"
        model.choosePresentation(.places)
        model.openProjectLocationEditor()
        let edit = try XCTUnwrap(model.locationEditor)
        let review = try ProjectLocationReview(edit: edit, repository: repository)
        let newer = try XCTUnwrap(GPSCoordinates(latitude: 51, longitude: -1))
        let proposed = try XCTUnwrap(GPSCoordinates(latitude: 52, longitude: -2))
        draft = model.library
        draft.photos[0].locationOverride = .assigned(newer)
        XCTAssertTrue(model.commit(draft))
        XCTAssertFalse(model.applyLocationEdit(edit, coordinates: proposed, projectReview: review))
        XCTAssertEqual(try repository.load().photos.first?.cataloguedLocation, newer)
        XCTAssertTrue(model.history.undo.isEmpty)
    }

    private func writeJPEG(to url: URL, colour: CGFloat, withGPS: Bool) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: colour, green: 0.2, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [String: Any] = [:]
        if withGPS {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: 51.5,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 0.125,
                kCGImagePropertyGPSLongitudeRef as String: "W"
            ] as [String: Any]
        }
        CGImageDestinationAddImage(writer, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }
}
