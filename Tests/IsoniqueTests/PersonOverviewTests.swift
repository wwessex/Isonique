import ImageIO
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class PersonOverviewTests: XCTestCase {
    func testGalleryFiltersAndCountsOfflinePhotosAndUsesLibraryPortrait() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let first = try XCTUnwrap(model.library.photos[0].projectID)
        let second = try XCTUnwrap(model.library.photos[1].projectID)
        let request = try fixture.openOverview(model)
        let portrait = try XCTUnwrap(fixture.overview(model).faces.first { $0.photo.projectID == second })
        XCTAssertTrue(model.setRepresentativeFace(portrait, for: request))
        model.personOverview = nil
        var draft = model.library
        draft.photos[0].people?.faces[1].assignName("Sam Lee")
        draft.photos[3].people?.faces[0].assignName("In Trash")
        XCTAssertTrue(model.commit(draft))
        // The sidebar sets the scope before SwiftUI's change handler clears the selection.
        model.selection = fixture.photos[0].id
        XCTAssertNotNil(model.selected)
        model.scope = "people-gallery"
        XCTAssertNil(model.selected)
        model.search = "Previously entered photo search"
        model.showPeople()
        XCTAssertTrue(model.isPeopleGallery)
        XCTAssertNil(model.selected)
        XCTAssertFalse(model.canReviewSelection)

        let gallery = model.peopleGallery
        XCTAssertEqual(gallery.people.map(\.id), ["sam lee", "zoe rivera"])
        let matches = gallery.matching(name: "  zÓE   ri ", project: nil)
        XCTAssertEqual(matches.map(\.id), ["zoe rivera"])
        XCTAssertEqual(matches.first?.total, 3)
        XCTAssertEqual(matches.first?.count(in: first), 1)
        XCTAssertEqual(matches.first?.count(in: second), 1)
        XCTAssertEqual(gallery.matching(name: "", project: second).map(\.id), ["zoe rivera"])
        XCTAssertEqual(gallery.matching(name: "Sam", project: second).count, 0)
        XCTAssertEqual(gallery.matching(name: "Sam", project: first).first?.total, 1)
        XCTAssertTrue(gallery.matching(name: "", project: UUID()).isEmpty)
        let tile = try XCTUnwrap(gallery.matching(name: "zoe", project: first).first)
        XCTAssertEqual(tile.portrait.id, portrait.id, "The project filter preserves the library's portrait choice")
        XCTAssertThrowsError(try fixture.repository.verifiedFaceSource(for: tile.portrait.photo))
        model.browseGalleryPerson(tile, project: first)
        XCTAssertEqual(model.scope, "project:\(first)")
        XCTAssertEqual(model.photos.map(\.id), [fixture.photos[0].id])
        XCTAssertEqual(model.selected?.id, fixture.photos[0].id)
        model.showPeople()
        model.browseGalleryPerson(tile, project: nil)
        XCTAssertEqual(model.scope, "person:zoe rivera")
        XCTAssertEqual(Set(model.photos.map(\.id)), Set(fixture.photos.prefix(3).map(\.id)))
    }

    func testGalleryRefreshesCountsAndPortraitAfterReassignmentAndUndo() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let request = try fixture.openOverview(model)
        let choice = try XCTUnwrap(fixture.overview(model).faces.first { $0.photo.id == fixture.photos[1].id })
        XCTAssertTrue(model.setRepresentativeFace(choice, for: request))
        model.personOverview = nil
        model.showPeople()
        XCTAssertEqual(model.peopleGallery.matching(name: "zoe", project: nil).first?.portrait.id, choice.id)
        let photo = model.library.photos[1]
        let project = try XCTUnwrap(photo.projectID)
        var people = try XCTUnwrap(photo.people)
        people.faces[0].assignName("Sam Lee")
        XCTAssertTrue(model.applyPeopleReview(PeopleReview(photo: photo, root: fixture.repository.root), people: people))
        let updated = model.peopleGallery
        XCTAssertEqual(updated.matching(name: "zoe", project: nil).first?.portrait.photo.id, fixture.photos[0].id)
        XCTAssertEqual(updated.matching(name: "zoe", project: nil).first?.total, 2)
        XCTAssertEqual(updated.matching(name: "", project: project).map(\.id), ["sam lee"])
        XCTAssertNil(updated.matching(name: "sam", project: project).first?.portrait.face.representativeChosenAt)
        model.undoEdit()
        XCTAssertEqual(model.peopleGallery.matching(name: "", project: project).first?.portrait.id, choice.id)
        model.redoEdit()
        let reopened = fixture.open()
        XCTAssertEqual(reopened.peopleGallery.matching(name: "", project: project).map(\.id), ["sam lee"])
    }

    func testCountsAndRepresentativeChoicePersistAndStayBrowsableOffline() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let overview = fixture.overview(model)
        XCTAssertEqual(overview.photoCount, 3)
        XCTAssertEqual(overview.projectCounts.map(\.name), ["A Project", "B Project", "No Project"])
        XCTAssertEqual(overview.projectCounts.map(\.count), [1, 1, 1])
        XCTAssertEqual(overview.faces.count, 4)
        XCTAssertEqual(overview.portrait?.photo.id, fixture.photos[0].id)
        XCTAssertNil(overview.chosenFace)
        let request = try fixture.openOverview(model)
        let choice = try XCTUnwrap(overview.faces.first { $0.photo.id == fixture.photos[1].id })
        XCTAssertThrowsError(try fixture.repository.verifiedFaceSource(for: choice.photo))
        XCTAssertTrue(model.setRepresentativeFace(choice, for: request))
        XCTAssertEqual(model.library.version, 39)
        XCTAssertEqual(model.history.undo.count, 1)
        XCTAssertEqual(model.library.photos.map(\.adjustments), fixture.photos.map(\.adjustments))

        let reopened = fixture.open()
        XCTAssertEqual(fixture.overview(reopened).chosenFace?.id, choice.id)
        let secondRequest = try fixture.openOverview(reopened)
        reopened.browsePerson(secondRequest)
        XCTAssertEqual(reopened.scope, "person:zoe rivera")
        XCTAssertEqual(Set(reopened.photos.map(\.id)), Set(fixture.photos.prefix(3).map(\.id)))
        XCTAssertNil(reopened.personOverview)
        reopened.undoEdit()
        XCTAssertNil(fixture.overview(reopened).chosenFace)
        let redo = fixture.open()
        redo.redoEdit()
        XCTAssertEqual(fixture.overview(redo).chosenFace?.id, choice.id)
    }

    func testRemovalAndReassignmentFallBackAndUndoRestoresChoice() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let request = try fixture.openOverview(model)
        let choice = try XCTUnwrap(fixture.overview(model).faces.first { $0.photo.id == fixture.photos[1].id })
        XCTAssertTrue(model.setRepresentativeFace(choice, for: request))

        let photo = model.library.photos[1]
        var revised = try XCTUnwrap(photo.people)
        revised.faces[0].assignName("Someone Else")
        XCTAssertTrue(model.applyPeopleReview(PeopleReview(photo: photo, root: fixture.repository.root), people: revised))
        XCTAssertNil(fixture.overview(model).chosenFace)
        XCTAssertEqual(fixture.overview(model).portrait?.photo.id, fixture.photos[0].id)
        XCTAssertEqual(fixture.overview(model).photoCount, 2)
        XCTAssertNil(PersonOverview(key: "someone else", library: model.library).chosenFace)
        XCTAssertFalse(model.setRepresentativeFace(choice, for: request))

        model.undoEdit()
        XCTAssertEqual(fixture.overview(model).chosenFace?.id, choice.id)
        let restored = model.library.photos[1]
        var removed = try XCTUnwrap(restored.people)
        removed.removeFace(choice.face.id)
        XCTAssertTrue(model.applyPeopleReview(PeopleReview(photo: restored, root: fixture.repository.root), people: removed))
        XCTAssertNil(fixture.overview(model).chosenFace)
        let reopened = fixture.open()
        XCTAssertEqual(fixture.overview(reopened).portrait?.photo.id, fixture.photos[0].id)
        reopened.undoEdit()
        XCTAssertEqual(fixture.overview(reopened).chosenFace?.id, choice.id)
        reopened.redoEdit()
        XCTAssertNil(fixture.overview(reopened).chosenFace)
    }

    func testReplacingChoiceAndRenamingGroupPreserveVersionIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let request = try fixture.openOverview(model)
        let faces = fixture.overview(model).faces
        XCTAssertTrue(model.setRepresentativeFace(faces[1], for: request))
        XCTAssertTrue(model.setRepresentativeFace(faces[2], for: request))
        XCTAssertEqual(fixture.overview(model).faces.filter { $0.face.representativeChosenAt != nil }.map(\.id), [faces[2].id])
        XCTAssertTrue(model.setRepresentativeFace(try XCTUnwrap(fixture.overview(model).chosenFace), for: request))
        XCTAssertEqual(model.history.undo.count, 2)
        var draft = model.library
        let version = try XCTUnwrap(draft.createVersion(of: faces[2].photo.id, from: .current))
        XCTAssertTrue(version.people?.faces.allSatisfy { $0.representativeChosenAt == nil } == true)
        let review = try draft.reviewPersonName("zoe rivera", action: .rename("Zoë Morgan"))
        XCTAssertNotNil(draft.applyPersonNameReview(review))
        XCTAssertEqual(PersonOverview(key: "zoe morgan", library: draft).chosenFace?.id, faces[2].id)

        // A group merge can bring two saved representatives together.
        let other = try XCTUnwrap(draft.photos[2].people?.faces.first)
        draft.photos[2].people?.faces[0].assignName("Sam Lee")
        draft.photos[2].people?.faces[0].setRepresentative(chosenAt: Date(timeIntervalSince1970: 1))
        let merge = try draft.reviewPersonName("zoe morgan", action: .merge(intoKey: "sam lee"))
        XCTAssertNotNil(draft.applyPersonNameReview(merge))
        let merged = PersonOverview(key: "sam lee", library: draft)
        XCTAssertEqual(merged.chosenFace?.id, faces[2].id)
        XCTAssertTrue(merged.faces.contains { $0.face.id == other.id && $0.face.representativeChosenAt != nil })
    }

    func testPortraitCropUsesTopLeftCoordinatesAndClampsAtEdge() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 20, width: 80, height: 20))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 20))
        let image = try XCTUnwrap(context.makeImage())
        let top = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0, y: 0, width: 0.25, height: 0.25)))
        let bottom = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25)))
        let upper = try XCTUnwrap(FaceDetection.portrait(in: image, region: top))
        let lower = try XCTUnwrap(FaceDetection.portrait(in: image, region: bottom))
        let tile = try XCTUnwrap(FaceDetection.portrait(in: image, region: top, maximum: 8))
        XCTAssertEqual(upper.width, 24)
        XCTAssertEqual(upper.height, 12)
        XCTAssertEqual(lower.width, upper.width)
        XCTAssertEqual(lower.height, upper.height)
        XCTAssertEqual(tile.width, 8)
        XCTAssertEqual(tile.height, 4)
        func pixel(_ source: CGImage) throws -> [UInt8] {
            let sample = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            sample.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let data = try XCTUnwrap(sample.data)
            return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: 3))
        }
        XCTAssertEqual(try pixel(upper), [255, 0, 0])
        XCTAssertEqual(try pixel(lower), [0, 0, 255])
        XCTAssertEqual(try pixel(tile), [255, 0, 0])
    }

    private struct Fixture {
        let folder: URL
        let repository: LibraryRepository
        let preferences: UserDefaults
        let suite: String
        let photos: [Photo]

        init() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PersonOverview-\(UUID())")
            self.folder = folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
            suite = "PersonOverview.\(UUID())"
            preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            preferences.set(true, forKey: "history.persist")
            let first = IsoniqueCore.Collection(name: "A Project")
            let second = IsoniqueCore.Collection(name: "B Project")
            let projects = [first.id, second.id, nil, first.id]
            photos = try projects.enumerated().map { index, project in
                let filename = "Offline-\(index).jpg"
                var photo = Photo(filename: filename, originalName: filename, projectID: project,
                                  width: 80, height: 40, camera: "", captureDate: "", sha256: "fixture-\(index)")
                photo.referencedPath = folder.appendingPathComponent(filename).path
                photo.importedAt = Date(timeIntervalSince1970: Double(index))
                photo.adjustments.exposure = Double(index) / 10
                if index == 3 { photo.trashedAt = Date() }
                var people = PhotoPeople()
                for offset in 0..<(index == 0 ? 2 : 1) {
                    let region = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.1 + Double(offset) * 0.25, y: 0.1,
                                                                            width: 0.2, height: 0.2)))
                    var face = PhotoFace(region: region)
                    face.assignName(offset == 0 ? "Zoë Rivera" : "ZOE RIVERA")
                    people.faces.append(face)
                }
                photo.people = people
                return photo
            }
            var library = try repository.load()
            library.projects = [second, first]
            library.photos = photos
            _ = try repository.save(library)
        }

        @MainActor func open() -> Workspace { Workspace(libraryRoot: repository.root, preferences: preferences) }
        @MainActor func overview(_ model: Workspace) -> PersonOverview { PersonOverview(key: "zoe rivera", library: model.library) }

        @MainActor func openOverview(_ model: Workspace) throws -> PersonOverviewRequest {
            model.openPersonOverview(try XCTUnwrap(model.peopleGroups.first { $0.id == "zoe rivera" }))
            return try XCTUnwrap(model.personOverview)
        }

        func cleanUp() {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
