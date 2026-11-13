import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class PersonNameEditorTests: XCTestCase {
    func testRenamePreviewCollisionCancellationAndOfflinePersistentUndoRedo() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let source = PhotoFace.personKey("Zoë Rivera")
        let group = try XCTUnwrap(model.peopleGroups.first { $0.id == source })
        model.scope = group.scope
        model.secondaryBrowser.visible = true
        model.secondaryBrowser.scope = group.scope
        model.openPersonNameEditor(group)
        let request = try XCTUnwrap(model.personNameEditor)
        let before = try Data(contentsOf: fixture.catalogue)
        XCTAssertEqual(model.library.version, 37)
        XCTAssertThrowsError(try model.library.reviewPersonName(source, action: .rename("  SÁM   LEE "))) {
            XCTAssertEqual($0 as? PersonNameError, .existingName)
        }
        XCTAssertThrowsError(try model.library.reviewPersonName(source, action: .rename("Hidden"))) {
            XCTAssertEqual($0 as? PersonNameError, .existingName)
        }
        XCTAssertThrowsError(try model.library.reviewPersonName(source, action: .rename(" \t"))) {
            XCTAssertEqual($0 as? PersonNameError, .emptyName)
        }
        let correction = try model.library.reviewPersonName(source, action: .rename("Zoë Rivera"))
        XCTAssertEqual(correction.photos.map(\.id), fixture.photos.prefix(2).map(\.id))
        XCTAssertEqual(correction.photos.map(\.faceCount), [1, 1])
        let review = try model.library.reviewPersonName(source, action: .rename("  Zoë   Morgan  "))
        XCTAssertEqual(review.destinationName, "Zoë Morgan")
        XCTAssertEqual(review.photos.map(\.id), fixture.photos.prefix(3).map(\.id))
        XCTAssertEqual(review.photos.map(\.faceCount), [2, 1, 1])
        XCTAssertEqual(review.photos.map(\.inTrash), [false, false, true])
        XCTAssertEqual(review.rules.map(\.comparison), [.equals, .differs, .equals])
        XCTAssertEqual(review.rules.map(\.before), [" ZOE RIVERA ", "Zoë Rivera", "Zoë Rivera"])
        XCTAssertEqual(review.rules.map(\.after), ["Zoë Morgan", "Zoë Morgan", "Zoë Morgan"])
        XCTAssertEqual(try Data(contentsOf: fixture.catalogue), before)

        model.cancelPersonNameEditor()
        XCTAssertFalse(model.applyPersonNameReview(review, request: request))
        XCTAssertEqual(try Data(contentsOf: fixture.catalogue), before)
        XCTAssertTrue(model.history.undo.isEmpty)
        model.openPersonNameEditor(group)
        let confirmed = try XCTUnwrap(model.personNameEditor)
        XCTAssertTrue(fixture.photos.allSatisfy { (try? fixture.repository.availableOriginalURL($0)) == nil })
        XCTAssertTrue(model.applyPersonNameReview(review, request: confirmed))
        XCTAssertEqual(model.library.version, 38)
        XCTAssertEqual(model.history.undo.count, 1)
        XCTAssertEqual(model.scope, "person:zoe morgan")
        XCTAssertEqual(model.secondaryBrowser.scope, "person:zoe morgan")
        XCTAssertEqual(model.library.photos[0].personNames, ["Zoë Morgan", "Zoë Morgan", "Sam Lee"])
        XCTAssertEqual(model.library.photos[2].personNames, ["Zoë Morgan", "Hidden"])
        XCTAssertEqual(model.library.photos[0].people?.faces.map(\.region), fixture.photos[0].people?.faces.map(\.region))
        XCTAssertEqual(model.library.photos[0].people?.faces.map(\.id), fixture.photos[0].people?.faces.map(\.id))
        XCTAssertEqual(model.library.photos.map(\.adjustments), fixture.photos.map(\.adjustments))
        let expectedRules = try XCTUnwrap(model.library.albums[0].rule?.query?.criteria)
        XCTAssertEqual(expectedRules.map(\.value), ["Zoë Morgan", "Zoë Morgan", "Rivera", "Zoë", "Zoë Rivera", "Sam Lee"])
        let albumScope = "album:\(fixture.albums[1].id)"
        model.scope = albumScope
        XCTAssertEqual(Set(model.photos.map(\.id)), Set(fixture.photos.prefix(2).map(\.id)))

        let reopened = fixture.open()
        reopened.scope = "person:zoe morgan"
        reopened.undoEdit()
        XCTAssertEqual(reopened.scope, group.scope)
        XCTAssertEqual(reopened.library.photos, fixture.photos)
        XCTAssertEqual(reopened.library.albums, fixture.albums)
        XCTAssertFalse(reopened.canUndo)
        let redo = fixture.open()
        XCTAssertTrue(redo.canRedo)
        redo.scope = group.scope
        redo.redoEdit()
        XCTAssertEqual(redo.scope, "person:zoe morgan")
        XCTAssertEqual(redo.library.photos, model.library.photos)
        XCTAssertEqual(redo.library.albums, model.library.albums)
        XCTAssertFalse(redo.canRedo)
    }

    func testMergeKeepsBothFacesAndPreservesLaterRuleEditsAndTrashHistory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let source = "zoe rivera"
        let group = try XCTUnwrap(model.peopleGroups.first { $0.id == source })
        XCTAssertThrowsError(try model.library.reviewPersonName(source, action: .merge(intoKey: source))) {
            XCTAssertEqual($0 as? PersonNameError, .samePerson)
        }
        XCTAssertThrowsError(try model.library.reviewPersonName(source, action: .merge(intoKey: "unknown"))) {
            XCTAssertEqual($0 as? PersonNameError, .missingDestination)
        }
        let review = try model.library.reviewPersonName(source, action: .merge(intoKey: "sam lee"))
        XCTAssertEqual(review.destinationName, "Sam Lee")
        XCTAssertEqual(review.rules.count, 3, "A rule already targeting the destination is not rewritten")
        model.openPersonNameEditor(group)
        XCTAssertTrue(model.applyPersonNameReview(review, request: try XCTUnwrap(model.personNameEditor)))
        XCTAssertEqual(model.peopleGroups.map(\.id), ["sam lee"])
        XCTAssertEqual(model.peopleGroups.first?.photoCount, 3)
        XCTAssertEqual(model.library.photos[0].personNames, ["Sam Lee", "Sam Lee", "Sam Lee"])
        XCTAssertEqual(model.library.photos[3], fixture.photos[3])

        // Another operation can save a rule without creating a photo-history step.
        var draft = model.library
        draft.albums[0].rule?.query?.criteria[1].value = "Later edit"
        draft.albums[0].rule?.query?.criteria[2].value = "Later substring"
        draft.photos.removeAll { $0.id == fixture.photos[2].id }
        var history = model.history
        history.discardEmptiedTrash(photoIDs: [fixture.photos[2].id], originalIDs: [fixture.photos[2].originalID])
        XCTAssertTrue(model.commit(draft, history: history))
        let reopened = fixture.open()
        reopened.undoEdit()
        XCTAssertEqual(reopened.library.photos[0], fixture.photos[0])
        XCTAssertEqual(reopened.library.albums[0].rule?.query?.criteria.prefix(3).map(\.value),
                       [" ZOE RIVERA ", "Later edit", "Later substring"])
        let redo = fixture.open()
        redo.redoEdit()
        XCTAssertEqual(redo.library.photos[0].personNames, ["Sam Lee", "Sam Lee", "Sam Lee"])
        XCTAssertEqual(redo.library.albums[0].rule?.query?.criteria.prefix(3).map(\.value),
                       ["Sam Lee", "Later edit", "Later substring"])
    }

    func testAReviewCannotOverwriteNewerCatalogueEdits() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.open()
        let group = try XCTUnwrap(model.peopleGroups.first { $0.id == "zoe rivera" })
        model.openPersonNameEditor(group)
        let request = try XCTUnwrap(model.personNameEditor)
        let review = try model.library.reviewPersonName(group.id, action: .rename("New Name"))
        var newer = try fixture.repository.load()
        newer.photos[0].caption = "Saved in a different window"
        _ = try fixture.repository.save(newer)
        XCTAssertFalse(model.applyPersonNameReview(review, request: request))
        XCTAssertTrue(model.history.undo.isEmpty)
        XCTAssertEqual(try fixture.repository.load().photos[0].caption, "Saved in a different window")
        XCTAssertEqual(try fixture.repository.load().photos[0].personNames, fixture.photos[0].personNames)
    }

    private struct Fixture {
        let folder: URL
        let repository: LibraryRepository
        let preferences: UserDefaults
        let suite: String
        let photos: [Photo]
        let albums: [IsoniqueCore.Collection]
        var catalogue: URL { repository.root.appendingPathComponent("catalog.json") }

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("PersonName-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
            suite = "PersonName.\(UUID())"
            preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            preferences.set(true, forKey: "history.persist")
            let people = [["Zoë Rivera", "Zoe Rivera", "Sam Lee"], ["zoe rivera"], ["Zoë Rivera", "Hidden"], ["Sam Lee"]]
            let folder = folder
            photos = try people.enumerated().map { index, names in
                let filename = "Offline-\(index).jpg"
                var photo = Photo(filename: filename, originalName: filename, projectID: nil, width: 80, height: 60,
                                  camera: "", captureDate: "", sha256: "fixture-\(index)")
                photo.referencedPath = folder.appendingPathComponent(filename).path
                photo.adjustments.exposure = Double(index) / 5
                if index == 2 { photo.trashedAt = Date(timeIntervalSince1970: 100) }
                var assignments = PhotoPeople()
                for (offset, name) in names.enumerated() {
                    let box = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.1 + Double(offset) * 0.2, y: 0.1,
                                                                        width: 0.15, height: 0.15)))
                    var face = PhotoFace(region: box)
                    face.assignName(name)
                    assignments.faces.append(face)
                }
                photo.people = assignments
                return photo
            }
            var smart = SmartAlbumRule()
            var query = PhotoQuery()
            query.match = .any
            query.criteria = [
                .init(field: .person, comparison: .equals, value: " ZOE RIVERA "),
                .init(field: .person, comparison: .differs, value: "Zoë Rivera"),
                .init(field: .person, comparison: .contains, value: "Rivera"),
                .init(field: .person, comparison: .excludes, value: "Zoë"),
                .init(field: .keyword, comparison: .equals, value: "Zoë Rivera"),
                .init(field: .person, comparison: .equals, value: "Sam Lee")
            ]
            smart.query = query
            var album = IsoniqueCore.Collection(name: "People Rules")
            album.rule = smart
            query.match = .all
            query.criteria = [.init(field: .person, comparison: .equals, value: "Zoë Rivera")]
            smart.query = query
            var exact = IsoniqueCore.Collection(name: "Zoë Photos")
            exact.rule = smart
            albums = [album, exact]
            var draft = try repository.load()
            draft.photos = photos
            draft.albums = albums
            _ = try repository.save(draft)
        }

        @MainActor func open() -> Workspace { Workspace(libraryRoot: repository.root, preferences: preferences) }

        func cleanUp() {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
