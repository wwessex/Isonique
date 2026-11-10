import IsoniqueCore
import MapKit
import XCTest
@testable import Isonique

final class PhotoLocationLookupTests: XCTestCase {
    @MainActor
    func testChoosingAResultPreviewsCoordinatesUntilAssignment() async throws {
        let coordinates = try XCTUnwrap(GPSCoordinates(latitude: 51.5079, longitude: -0.0994))
        let museum = PhotoLocationLookupResult(title: "Tate Modern", address: "Bankside, London", coordinates: coordinates)
        let other = PhotoLocationLookupResult(title: "Tate Britain", address: "Millbank, London", coordinates: coordinates)
        let lookup = PhotoLocationLookup { query in
            XCTAssertEqual(query, "Tate")
            return [other, museum]
        }
        XCTAssertNil(lookup.submit("   "))
        let search = try XCTUnwrap(lookup.submit(" Tate "))
        await search.value
        XCTAssertEqual(lookup.state, .results([other, museum]))
        XCTAssertNil(lookup.choose(UUID()))
        let result = try XCTUnwrap(lookup.choose(museum.id))
        XCTAssertEqual(result, museum)
        XCTAssertEqual(lookup.state, .idle)
        XCTAssertNil(lookup.choose(museum.id))

        let photo = Photo(filename: "Photo.jpg", originalName: "Photo.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        let edit = PhotoLocationEdit(action: .assign, libraryRoot: FileManager.default.temporaryDirectory, photos: [photo])
        let draft = PhotoLocationDraft(result.coordinates)
        XCTAssertEqual(edit.changes(to: draft.coordinates),
                       [PhotoLocationChange(photoID: photo.id, location: .assigned(coordinates))])
        XCTAssertNil(photo.cataloguedLocation)
    }

    @MainActor
    func testCancellationDiscardsLateResultsFromAnOlderSearch() async throws {
        let coordinates = try XCTUnwrap(GPSCoordinates(latitude: 51.5079, longitude: -0.0994))
        let oldResult = PhotoLocationLookupResult(title: "Tate Modern", address: nil, coordinates: coordinates)
        let newResult = PhotoLocationLookupResult(title: "Bankside", address: "London", coordinates: coordinates)
        let pending = AsyncStream<CheckedContinuation<[PhotoLocationLookupResult], Never>>.makeStream()
        let lookup = PhotoLocationLookup { query in
            if query == "Old query" {
                return await withCheckedContinuation { pending.continuation.yield($0) }
            }
            return [newResult]
        }

        let old = try XCTUnwrap(lookup.submit("Old query"))
        var requests = pending.stream.makeAsyncIterator()
        let completion = await requests.next()
        let lateCompletion = try XCTUnwrap(completion)
        lookup.cancel()
        XCTAssertTrue(old.isCancelled)
        XCTAssertEqual(lookup.state, .idle)

        let current = try XCTUnwrap(lookup.submit("New query"))
        await current.value
        lateCompletion.resume(returning: [oldResult])
        await old.value
        pending.continuation.finish()
        XCTAssertEqual(lookup.state, .results([newResult]))
        XCTAssertNil(lookup.choose(oldResult.id))
        XCTAssertEqual(lookup.choose(newResult.id), newResult)
    }

    @MainActor
    func testManualCoordinatesCanBeSavedWhenLookupIsUnavailable() async throws {
        let lookup = PhotoLocationLookup { query in
            if query == "Unknown place" { throw MKError(.placemarkNotFound) }
            throw URLError(.notConnectedToInternet)
        }
        let empty = try XCTUnwrap(lookup.submit("Unknown place"))
        await empty.value
        XCTAssertEqual(lookup.state, .noResults)
        let unavailable = try XCTUnwrap(lookup.submit("London"))
        await unavailable.value
        XCTAssertEqual(lookup.state, .unavailable)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLocationLookup-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let photo = Photo(filename: "Photo.jpg", originalName: "Photo.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        var library = workspace.library
        library.photos = [photo]
        XCTAssertTrue(workspace.commit(library))
        workspace.selection = photo.id
        workspace.openLocationEditor(.assign)
        var draft = PhotoLocationDraft()
        draft.latitude = "51,5"
        draft.longitude = "-0.125"
        let point = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        XCTAssertTrue(workspace.applyLocationEdit(try XCTUnwrap(workspace.locationEditor), coordinates: draft.coordinates))
        XCTAssertEqual(try workspace.repository?.load().photos.first?.cataloguedLocation, point)
        XCTAssertEqual(lookup.state, .unavailable)
    }
}
