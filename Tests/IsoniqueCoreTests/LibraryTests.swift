import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import IsoniqueCore

final class LibraryTests: XCTestCase {
    func testRecoveredCropAspectRatio() throws {
        XCTAssertEqual(try XCTUnwrap(CropRules.aspectRatio(width: -3, height: -2)), 1.5)
        for rotation in [90, 270] {
            XCTAssertEqual(try XCTUnwrap(CropRules.aspectRatio(width: 3, height: 2, rotation: rotation)), 2.0 / 3, accuracy: 1e-12)
        }
        for rotation in [0, 180] {
            XCTAssertEqual(CropRules.aspectRatio(width: 3, height: 2, rotation: rotation), 1.5)
        }
        XCTAssertNil(CropRules.aspectRatio(width: 0, height: 2))
        XCTAssertNil(CropRules.aspectRatio(width: 2, height: .infinity))
        XCTAssertNil(CropRules.aspectRatio(width: .nan, height: 2))
    }
    func testImportJobCancellationKeepsCommittedFilesAndProject() async throws {
        let directory = temporary!
        let first = try fixture("01.png", red: 0.1)
        let second = try fixture("02.png", red: 0.2)
        let third = try fixture("03.png", red: 0.3)
        let repo = try LibraryRepository.createEmpty(at: directory.appendingPathComponent("Library"))
        let (draft, report, updates) = await Task.detached {
            var draft = Library()
            var updates: [ImportProgress] = []
            let report = await ImportJob.run(urls: [third, first, second], options: ImportOptions(), repository: repo,
                                             projectID: nil, albumID: nil, newProjectName: "Studio", into: &draft) { update in
                updates.append(update)
                if update.processed == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            return (draft, report, updates)
        }.value
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(draft.photos.map(\.originalName), ["01.png"])
        XCTAssertEqual(updates.map(\.processed), [0, 1, 1])
        XCTAssertTrue(updates.allSatisfy { $0.total == 3 })
        let persisted = try repo.load()
        XCTAssertEqual(persisted.projects.map(\.name), ["Studio"])
        XCTAssertEqual(persisted.photos.first?.projectID, report.createdProject)
        XCTAssertEqual(persisted.photos, draft.photos)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.root.appendingPathComponent("Originals").path).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testImportJobRecoversFromPerFileErrorsAndSkipsEmptyProject() async throws {
        let input = temporary.appendingPathComponent("Input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        let unsupported = input.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: unsupported)
        let valid = try fixture("valid.png", directory: input)
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        let result = await ImportJob.run(urls: [input], options: ImportOptions(), repository: repo, projectID: nil,
                                         albumID: nil, into: &library)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors.first?.contains("bad.png") == true)
        let empty = await ImportJob.run(urls: [valid, unsupported], options: ImportOptions(), repository: repo,
                                        projectID: nil, albumID: nil, newProjectName: "Empty", into: &library)
        XCTAssertEqual(empty.duplicates, 1)
        XCTAssertEqual(empty.imported, 0)
        XCTAssertNil(empty.createdProject)
        XCTAssertTrue(library.projects.isEmpty)
        XCTAssertTrue(try repo.load().projects.isEmpty)
    }

    func testReferencedOriginalRelinkExportAndConsolidation() throws {
        let source = try fixture()
        let fm = FileManager.default
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertNil(try JSONDecoder().decode(ImportOptions.self, from: JSONEncoder().encode(ImportOptions())).storage)
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library, options: options))
        XCTAssertEqual(library.version, 2)
        let photo = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(try repo.availableOriginalURL(photo), source.resolvingSymlinksInPath())
        let originals = repo.root.appendingPathComponent("Originals")
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: originals.path).isEmpty)

        let moved = temporary.appendingPathComponent("moved.dat")
        try fm.moveItem(at: source, to: moved)
        let wrong = temporary.appendingPathComponent("wrong.png")
        try Data("wrong".utf8).write(to: wrong)
        XCTAssertThrowsError(try repo.availableOriginalURL(photo))
        XCTAssertThrowsError(try LibraryBackup.verify(repo))
        XCTAssertThrowsError(try repo.relinkOriginal(photo.id, to: wrong, in: &library))
        XCTAssertEqual(try repo.load().photos, [photo])
        try repo.relinkOriginal(photo.id, to: moved, in: &library)
        let relinked = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(relinked.id, photo.id)
        XCTAssertEqual(relinked.referencedPath, moved.resolvingSymlinksInPath().path)
        XCTAssertEqual(try LibraryBackup.verify(repo), 1)
        let originalExport = temporary.appendingPathComponent("export.png")
        var export = ExportOptions()
        export.format = .original
        try Renderer.export(relinked, repository: repo, to: originalExport, options: export)
        XCTAssertEqual(try LibraryRepository.digest(originalExport), photo.sha256)
        try Renderer.export(relinked, repository: repo, to: temporary.appendingPathComponent("edited.jpg"))

        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let saved = try Data(contentsOf: catalogue)
        try fm.removeItem(at: catalogue)
        try fm.createDirectory(at: catalogue, withIntermediateDirectories: false)
        XCTAssertThrowsError(try repo.consolidateOriginal(photo.id, in: &library))
        XCTAssertEqual(library.photos, [relinked])
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: originals.path).isEmpty)
        try fm.removeItem(at: catalogue)
        try saved.write(to: catalogue)

        try repo.consolidateOriginal(photo.id, in: &library)
        let managed = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(managed.id, photo.id)
        XCTAssertEqual(managed.sha256, photo.sha256)
        XCTAssertNil(managed.referencedPath)
        XCTAssertEqual(try LibraryRepository.digest(moved), photo.sha256)
        XCTAssertEqual(try LibraryRepository.digest(repo.availableOriginalURL(managed)), photo.sha256)
    }

    func testBackupRetainsOfflineReferenceAndMissingManagedOriginalCanBeRestored() throws {
        let fm = FileManager.default
        let source = try fixture()
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library, options: options))
        let photo = try XCTUnwrap(library.photos.first)
        let moved = temporary.appendingPathComponent("moved.png")
        try fm.moveItem(at: source, to: moved)

        let backup = temporary.appendingPathComponent("Backup")
        let restored = temporary.appendingPathComponent("Restored")
        try LibraryBackup.create(from: repo, to: backup)
        XCTAssertEqual(try LibraryBackup.validateBackup(backup), 1)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: backup.appendingPathComponent("Originals").path).isEmpty)
        try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
        let (restoredRepo, snapshot) = try LibraryBackup.openVerified(restored)
        XCTAssertEqual(snapshot.photos, [photo])
        XCTAssertThrowsError(try restoredRepo.availableOriginalURL(photo))

        var repaired = snapshot
        try restoredRepo.relinkOriginal(photo.id, to: moved, in: &repaired)
        try restoredRepo.consolidateOriginal(photo.id, in: &repaired)
        let managed = try XCTUnwrap(repaired.photos.first)
        let copy = try restoredRepo.availableOriginalURL(managed)
        try fm.removeItem(at: copy)
        XCTAssertEqual(try LibraryBackup.openVerified(restored).1.photos, [managed])
        XCTAssertThrowsError(try LibraryBackup.verify(restoredRepo))
        try restoredRepo.relinkOriginal(managed.id, to: moved, in: &repaired)
        XCTAssertEqual(try LibraryBackup.verify(restoredRepo), 1)
        XCTAssertThrowsError(try restoredRepo.relinkOriginal(managed.id, to: moved, in: &repaired))
        XCTAssertEqual(try LibraryRepository.digest(copy), photo.sha256)

        var downgraded = snapshot
        downgraded.version = 1
        XCTAssertThrowsError(try restoredRepo.save(downgraded))
        XCTAssertThrowsError(try repo.relinkOriginal(photo.id, to: repo.root.appendingPathComponent("Originals/invalid.png"), in: &library))
    }

    func testNewLibraryDoesNotReuseExistingOrNestedLocations() throws {
        let fm = FileManager.default
        let root = temporary.appendingPathComponent("Client Library")
        let repo = try LibraryRepository.createEmpty(at: root)
        XCTAssertEqual(try LibraryBackup.verify(repo), 0)
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(fixture(), projectID: nil, into: &library))
        let separate = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Personal Library"))
        XCTAssertTrue(try separate.load().photos.isEmpty)
        XCTAssertThrowsError(try LibraryRepository.createEmpty(at: root))
        XCTAssertThrowsError(try LibraryRepository.createEmpty(at: root.appendingPathComponent("Originals/Nested")))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Originals/Nested").path))
        let existing = temporary.appendingPathComponent("Empty")
        try fm.createDirectory(at: existing, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LibraryRepository.createEmpty(at: existing))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: existing.path).isEmpty)
        XCTAssertThrowsError(try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Legacy.aplibrary/Nested")))
        XCTAssertEqual(try LibraryBackup.openVerified(root).1.photos, library.photos)
    }

    func testPhotoTrashPersistsWithOriginalEditsMembershipAndBackup() throws {
        let source = try fixture()
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        let project = Collection(name: "Project"), album = Collection(name: "Album")
        library.projects = [project]; library.albums = [album]
        XCTAssertTrue(try repo.importPhoto(source, projectID: project.id, into: &library, albumID: album.id))
        library.photos[0].caption = "Delivery"
        library.photos[0].adjustments.exposure = 1
        library.photos[0].stackID = UUID()
        let photo = library.photos[0]
        let removedAt = Date(timeIntervalSinceReferenceDate: 77)
        XCTAssertEqual(library.setPhotosTrashed([photo.id], at: removedAt), [photo])
        XCTAssertTrue(library.setPhotosTrashed([photo.id], at: Date()).isEmpty)
        XCTAssertTrue(library.activePhotos.isEmpty)
        try repo.save(library)
        XCTAssertFalse(try repo.importPhoto(source, projectID: nil, into: &library))
        XCTAssertEqual(try repo.load().photos.first?.trashedAt, removedAt)

        let backup = temporary.appendingPathComponent("Backup")
        let restored = temporary.appendingPathComponent("Restored")
        try LibraryBackup.create(from: repo, to: backup)
        try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
        let (restoredRepo, snapshot) = try LibraryBackup.openVerified(restored)
        var restoredLibrary = snapshot
        XCTAssertEqual(restoredLibrary.setPhotosTrashed([photo.id], at: nil).first?.trashedAt, removedAt)
        try restoredRepo.save(restoredLibrary)
        XCTAssertEqual(try restoredRepo.load().activePhotos, [photo])
        XCTAssertEqual(try LibraryRepository.digest(restoredRepo.originalURL(photo)), try LibraryRepository.digest(source))
        XCTAssertEqual(try repo.load().photos.first?.trashedAt, removedAt)
    }

    func testImportCommitsFinalMetadataAndMembershipTogether() throws {
        let source = try fixture()
        let sidecar = source.deletingPathExtension().appendingPathExtension("xmp")
        try """
        <photos><photo filename="source.png"><caption>Sidecar</caption><rating>4</rating></photo></photos>
        """.write(to: sidecar, atomically: true, encoding: .utf8)
        let repo = try LibraryRepository(root: temporary.appendingPathComponent("library"))
        var library = Library()
        let project = Collection(name: "Client"), album = Collection(name: "Delivery")
        library.projects = [project]; library.albums = [album]
        var options = ImportOptions()
        options.prefix = "Shoot"; options.applyMetadata = true; options.caption = "Preset"
        options.keywords = "portrait"; options.readSidecars = true
        XCTAssertTrue(try repo.importPhoto(source, projectID: project.id, into: &library, options: options, albumID: album.id))

        let saved = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(saved, library.photos.first)
        XCTAssertEqual(saved.originalName, "Shoot-source.png")
        XCTAssertEqual(saved.sourceName, "source.png")
        XCTAssertEqual(saved.projectID, project.id)
        XCTAssertEqual(saved.albumIDs, [album.id])
        XCTAssertEqual(saved.caption, "Sidecar")
        XCTAssertEqual(saved.keywords, "portrait")
        XCTAssertEqual(saved.rating, 4)
        XCTAssertEqual(try LibraryRepository.digest(source), try LibraryRepository.digest(repo.originalURL(saved)))

        try "<invalid>".write(to: sidecar, atomically: true, encoding: .utf8)
        XCTAssertFalse(try repo.importPhoto(source, projectID: nil, into: &library, options: options))
        XCTAssertEqual(try repo.load().photos, [saved])
    }

    func testImportFailureRollsBackRecordAndCopyAndRetryImportsResolvedLink() throws {
        let source = try fixture()
        let alias = temporary.appendingPathComponent("linked.png")
        let fm = FileManager.default
        try fm.createSymbolicLink(at: alias, withDestinationURL: source)
        let repo = try LibraryRepository(root: temporary.appendingPathComponent("library"))
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let originals = repo.root.appendingPathComponent("Originals")
        var library = Library()
        try fm.createDirectory(at: catalogue, withIntermediateDirectories: false)
        XCTAssertThrowsError(try repo.importPhoto(alias, projectID: nil, into: &library))
        XCTAssertTrue(library.photos.isEmpty)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: originals.path).isEmpty)
        try fm.removeItem(at: catalogue)

        let sidecar = alias.deletingPathExtension().appendingPathExtension("xmp")
        try "<invalid>".write(to: sidecar, atomically: true, encoding: .utf8)
        var options = ImportOptions()
        options.readSidecars = true
        XCTAssertThrowsError(try repo.importPhoto(alias, projectID: nil, into: &library, options: options))
        XCTAssertTrue(library.photos.isEmpty)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: originals.path).isEmpty)

        try fm.removeItem(at: sidecar)
        XCTAssertTrue(try repo.importPhoto(alias, projectID: nil, into: &library, options: options))
        let photo = try XCTUnwrap(repo.load().photos.first)
        let copy = originals.appendingPathComponent(photo.filename)
        XCTAssertEqual(photo.sourceName, "linked.png")
        XCTAssertEqual(try copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, false)
        try fm.removeItem(at: alias)
        try fm.removeItem(at: source)
        XCTAssertEqual(try LibraryRepository.digest(copy), photo.sha256)
    }

    func testImportPairingAndNamingPreset() throws {
        let raw = URL(fileURLWithPath: "/shoot/A.nef")
        let jpeg = URL(fileURLWithPath: "/shoot/A.jpg")
        let other = URL(fileURLWithPath: "/other/A.jpg")
        var options = ImportOptions()
        options.pairing = .raw
        XCTAssertEqual(Set(options.files([raw, jpeg, other, raw])), Set([raw, other]))
        options.pairing = .jpeg
        XCTAssertEqual(Set(options.files([raw, jpeg, other])), Set([jpeg, other]))
        options.pairing = .linked
        XCTAssertEqual(options.files([raw, jpeg]).count, 2)
        var photo = Photo(filename: "managed.jpg", originalName: "A.jpg", projectID: nil, width: 32, height: 24, camera: "", captureDate: "", sha256: "hash")
        photo.caption = "embedded"
        options.prefix = "Client/Set"; options.caption = "preset"; options.rating = 9
        XCTAssertEqual(options.applying(to: photo).caption, "embedded")
        options.applyMetadata = true
        let imported = options.applying(to: photo)
        XCTAssertEqual(imported.originalName, "Client-Set-A.jpg")
        XCTAssertEqual(imported.filename, photo.filename)
        XCTAssertEqual(imported.caption, "preset"); XCTAssertEqual(imported.rating, 5)
        XCTAssertEqual(try JSONDecoder().decode(ImportOptions.self, from: JSONEncoder().encode(options)), options)
    }
    func testRecoveredImportDefaultAndStrictFormatFilters() throws {
        var options = ImportOptions()
        XCTAssertEqual(options.pairing, .linked)
        let raw = URL(fileURLWithPath: "/shoot/A.NEF")
        let jpeg = URL(fileURLWithPath: "/shoot/A.JPG")
        let unpairedRAW = URL(fileURLWithPath: "/shoot/B.dng")
        let unpairedJPEG = URL(fileURLWithPath: "/shoot/C.jpeg")
        let png = URL(fileURLWithPath: "/shoot/D.png")
        let files = [raw, jpeg, unpairedRAW, unpairedJPEG, png]
        XCTAssertEqual(Set(options.files(files)), Set(files))
        options.pairing = .onlyJPEG
        XCTAssertEqual(Set(options.files(files)), Set([jpeg, unpairedJPEG]))
        options.pairing = .onlyRAW
        XCTAssertEqual(Set(options.files(files)), Set([raw, unpairedRAW]))
        options.pairing = .linkedRAW
        XCTAssertEqual(Set(options.files(files)), Set(files))
        // Existing preferences and presets retain their old meaning after this update.
        for mode in [PairingMode.separate, .linked, .raw, .jpeg] {
            let encoded = try JSONEncoder().encode(mode.rawValue)
            XCTAssertEqual(try JSONDecoder().decode(PairingMode.self, from: encoded), mode)
        }
    }
    func testXMLAndXMPSidecarMetadata() throws {
        let url = temporary.appendingPathComponent("source.xmp")
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"><dc:description><rdf:Alt><rdf:li xml:lang="x-default">A &amp; B</rdf:li></rdf:Alt></dc:description><dc:subject><rdf:Bag><rdf:li>travel</rdf:li><rdf:li>night</rdf:li></rdf:Bag></dc:subject></rdf:Description></rdf:RDF></x:xmpmeta>
        """
        try xmp.write(to: url, atomically: true, encoding: .utf8)
        let record = try XCTUnwrap(MetadataXML.read(url).first)
        XCTAssertEqual(record.caption, "A & B"); XCTAssertEqual(record.keywords, "travel, night"); XCTAssertEqual(record.rating, 4)
        try "<photos><photo filename=\"A.jpg\"><caption></caption><rating>-1</rating></photo></photos>".write(to: url, atomically: true, encoding: .utf8)
        let xml = try XCTUnwrap(MetadataXML.read(url).first)
        XCTAssertEqual(xml.filename, "A.jpg"); XCTAssertEqual(xml.caption, ""); XCTAssertEqual(xml.rating, -1)
        try "<invalid>".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MetadataXML.read(url))
    }
    func testAlbumDataMetadataAndPersistentHistoryCompatibility() throws {
        let url = temporary.appendingPathComponent("AlbumData.xml")
        let plist: [String: Any] = ["Master Image List": ["1": ["ImagePath": "/old/A.jpg", "Comment": "Legacy", "Rating": 3]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        let record = try XCTUnwrap(MetadataXML.read(url).first)
        XCTAssertEqual(record.filename, "A.jpg"); XCTAssertEqual(record.caption, "Legacy")
        let old = try JSONDecoder().decode(Library.self, from: Data(#"{"version":1,"photos":[],"projects":[],"albums":[]}"#.utf8))
        XCTAssertNil(old.history)
        let repo = try LibraryRepository(root: temporary.appendingPathComponent("history"))
        var library = Library()
        XCTAssertTrue(try repo.importPhoto(fixture(), projectID: nil, into: &library))
        library.history = EditHistory()
        for _ in 0..<110 { library.history?.record(library.photos[0]) }
        library.photos[0].caption = "After edit"
        try repo.save(library)
        let reopened = try repo.load()
        XCTAssertEqual(reopened.history?.undo.count, 100)
        XCTAssertEqual(reopened.history?.undo.last?.photo?.caption, "")
        XCTAssertEqual(reopened.photos[0].caption, "After edit")
        library.history = nil; try repo.save(library); XCTAssertNil(try repo.load().history)
    }
    func testLensPreviewExportAndRGBProofing() throws {
        let source = try fixture()
        var settings = Adjustments(); settings.lensDistortion = 0.6
        let image = try Renderer.render(source, adjustments: settings)
        XCTAssertEqual(image.width, 32); XCTAssertEqual(image.height, 24)
        let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData()) as Data
        let proof = try Renderer.proof(image, profile: profile)
        XCTAssertEqual(proof.width, 32)
        XCTAssertThrowsError(try Renderer.proof(image, profile: Data("bad".utf8)))
        let old = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(old.lensDistortion, 0)
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(settings)).lensDistortion, 0.6)
        XCTAssertEqual(settings.stamping(onto: old, groups: [.geometry]).lensDistortion, 0.6)
        XCTAssertEqual(settings.stamping(onto: old, groups: [.tone]).lensDistortion, 0)
    }
    var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    func fixture(_ name: String = "source.png", directory: URL? = nil, red: CGFloat = 0.25) throws -> URL {
        let url = (directory ?? temporary).appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.65, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }
    func testImportPersistenceAdjustmentsAndExportPreserveOriginal() throws {
        let source = try fixture()
        let hash = try LibraryRepository.digest(source)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library()
        let project = Collection(name: "Commission")
        let album = Collection(name: "Selects")
        library.projects.append(project); library.albums.append(album)
        XCTAssertTrue(try repository.importPhoto(source, projectID: project.id, into: &library))
        XCTAssertFalse(try repository.importPhoto(source, projectID: project.id, into: &library))
        XCTAssertEqual(library.photos.count, 1)
        XCTAssertEqual(library.photos[0].width, 32)
        XCTAssertEqual(library.photos[0].height, 24)
        library.photos[0].rating = 4
        library.photos[0].albumIDs.insert(album.id)
        library.photos[0].caption = "Blue study"
        library.photos[0].adjustments.exposure = 1
        try repository.save(library)
        let loaded = try repository.load()
        XCTAssertEqual(loaded.photos, library.photos)
        let destination = temporary.appendingPathComponent("edited.jpg")
        try Renderer.export(loaded.photos[0], repository: repository, to: destination)
        let rendered = CGImageSourceCreateWithURL(destination as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(rendered, 0, nil)! as NSDictionary
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 32)
        let originalImage = try Renderer.render(source, adjustments: Adjustments())
        let editedImage = try Renderer.render(source, adjustments: loaded.photos[0].adjustments)
        XCTAssertNotEqual(originalImage.dataProvider?.data as Data?, editedImage.dataProvider?.data as Data?)
        XCTAssertEqual(try LibraryRepository.digest(source), hash)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(loaded.photos[0])), hash)
        XCTAssertThrowsError(try Renderer.export(loaded.photos[0], repository: repository, to: destination))
        XCTAssertThrowsError(try Renderer.export(loaded.photos[0], repository: repository, to: repository.originalURL(loaded.photos[0])))
    }
    func testPublicRendererExposureMatchesSRGBReferenceValues() throws {
        // Known sRGB middle-gray values: ±1 EV must operate in linear light.
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2,
            bitsPerComponent: 8, bytesPerRow: 8, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let gray = 128.0 / 255.0
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [gray, gray, gray, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let source = temporary.appendingPathComponent("srgb.png")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        for (ev, expected) in [(0.0, 128), (1.0, 176), (-1.0, 92)] {
            var settings = Adjustments(); settings.exposure = ev
            let rendered = try Renderer.render(source, adjustments: settings)
            let bytes = try XCTUnwrap(rendered.dataProvider?.data) as Data
            for channel in 0..<3 { XCTAssertEqual(Double(bytes[channel]), Double(expected), accuracy: 1) }
            XCTAssertEqual(bytes[3], 255)
        }
    }
    func testBrightnessVibrancyAndSepiaAffectPixelsAndMatchPNGExport() throws {
        let source = try fixture()
        let digest = try LibraryRepository.digest(source)
        func channels(_ settings: Adjustments) throws -> [Int] {
            let image = try Renderer.render(source, adjustments: settings)
            return (try XCTUnwrap(image.dataProvider?.data) as Data).prefix(4).map(Int.init)
        }
        let neutral = try channels(Adjustments())
        var settings = Adjustments()
        settings.brightness = 0.7
        let lighter = try channels(settings)
        XCTAssertTrue(zip(lighter.prefix(3), neutral.prefix(3)).allSatisfy { $0 > $1 })
        settings.brightness = -0.7
        let darker = try channels(settings)
        XCTAssertTrue(zip(darker.prefix(3), neutral.prefix(3)).allSatisfy { $0 < $1 })

        settings = Adjustments()
        settings.vibrancy = 1
        let vibrant = try channels(settings)
        settings.vibrancy = -1
        let muted = try channels(settings)
        XCTAssertGreaterThan(vibrant[2] - vibrant[0], neutral[2] - neutral[0])
        XCTAssertLessThan(muted[2] - muted[0], neutral[2] - neutral[0])

        settings = AdjustmentPreset.sepia.applying(to: Adjustments())
        let warm = try channels(settings)
        XCTAssertGreaterThan(warm[0], warm[1])
        XCTAssertGreaterThan(warm[1], warm[2])
        XCTAssertEqual(warm[3], 255)
        settings.brightness = 0.4
        settings.vibrancy = 0.3
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments = settings
        try repo.save(library)
        let photo = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(photo.adjustments, settings)
        XCTAssertEqual(settings.stamping(onto: Adjustments(), groups: [.basic]), settings)
        let destination = temporary.appendingPathComponent("edited.png")
        var options = ExportOptions()
        options.format = .png
        try Renderer.export(photo, repository: repo, to: destination, options: options)
        let output = try Renderer.render(destination, adjustments: Adjustments())
        let expected = try Renderer.render(source, adjustments: settings)
        let outputBytes = try XCTUnwrap(output.dataProvider?.data) as Data
        let expectedBytes = try XCTUnwrap(expected.dataProvider?.data) as Data
        XCTAssertEqual(outputBytes.count, expectedBytes.count)
        XCTAssertTrue(zip(outputBytes, expectedBytes).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        XCTAssertEqual(try LibraryRepository.digest(repo.originalURL(photo)), digest)
    }

    func testLegacyRecoveryCopiesAndVerifiesWithoutChangingSource() throws {
        let legacy = temporary.appendingPathComponent("Fixture.aplibrary")
        let masters = legacy.appendingPathComponent("Masters/2026")
        try FileManager.default.createDirectory(at: masters, withIntermediateDirectories: true)
        let source = try fixture(directory: masters)
        let database = legacy.appendingPathComponent("Library.apdb")
        try Data("opaque database must remain unchanged".utf8).write(to: database)
        let hash = try LibraryRepository.digest(source), databaseHash = try LibraryRepository.digest(database)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("recovered"))
        var library = Library()
        let result = try repository.recoverLegacy(legacy, into: &library)
        XCTAssertEqual(result.imported, 1); XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(try LibraryRepository.digest(source), hash)
        XCTAssertEqual(try LibraryRepository.digest(database), databaseHash)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(try XCTUnwrap(library.photos.first))), hash)
        XCTAssertEqual(library.projects.count, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: repository.root.path).contains { $0.hasPrefix("Recovery-") })
        XCTAssertThrowsError(try LibraryRepository(root: legacy))
    }
    func testRecoveryPreservesEmbeddedMetadataAndReportsSkippedFiles() throws {
        let legacy = temporary.appendingPathComponent("Metadata.aplibrary")
        let masters = legacy.appendingPathComponent("Masters")
        try FileManager.default.createDirectory(at: masters, withIntermediateDirectories: true)
        let plain = try fixture()
        let input = try XCTUnwrap(CGImageSourceCreateWithURL(plain as CFURL, nil))
        let image = masters.appendingPathComponent("tagged.tif")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(image as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        let properties: [String: Any] = [kCGImagePropertyIPTCDictionary as String: [
            kCGImagePropertyIPTCCaptionAbstract as String: "A retained caption — café",
            kCGImagePropertyIPTCKeywords as String: ["Travel", "Family"],
            kCGImagePropertyIPTCStarRating as String: 4
        ]]
        CGImageDestinationAddImageFromSource(writer, input, 0, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try FileManager.default.copyItem(at: image, to: masters.appendingPathComponent("duplicate.tif"))
        try Data("not a RAW file".utf8).write(to: masters.appendingPathComponent("broken.nef"))
        let sourceHash = try LibraryRepository.digest(image)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library()
        let result = try repository.recoverLegacy(legacy, into: &library)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.unsupported, ["Masters/broken.nef"])
        XCTAssertEqual(result.skipped, 2)
        let recovered = try XCTUnwrap(repository.load().photos.first)
        XCTAssertEqual(recovered.caption, "A retained caption — café")
        XCTAssertEqual(recovered.keywords, "Travel, Family")
        XCTAssertEqual(recovered.rating, 4)
        XCTAssertEqual(try LibraryRepository.digest(image), sourceHash)
        library.photos[0].caption = "My newer caption"
        library.photos[0].rating = 2
        try repository.save(library)
        let repeated = try repository.recoverLegacy(legacy, into: &library)
        XCTAssertEqual(repeated.imported, 0)
        XCTAssertEqual(repeated.duplicates, 2)
        XCTAssertEqual(library.photos[0].caption, "My newer caption")
        XCTAssertEqual(library.photos[0].rating, 2)
    }
    func testEmbeddedXMPRatingsAreReadWithoutChangingOriginal() throws {
        let plain = try fixture()
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(plain as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library()
        for (value, expected) in [("-1", -1), ("5", 5), ("99", 5), ("invalid", 0)] {
            let metadata = CGImageMetadataCreateMutable()
            XCTAssertTrue(CGImageMetadataRegisterNamespaceForPrefix(metadata, "http://ns.adobe.com/xap/1.0/" as CFString, "xmp" as CFString, nil))
            XCTAssertTrue(CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, value as CFString))
            let file = temporary.appendingPathComponent(value + ".tif")
            let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.tiff.identifier as CFString, 1, nil))
            CGImageDestinationAddImageAndMetadata(writer, pixels, metadata, nil)
            XCTAssertTrue(CGImageDestinationFinalize(writer))
            let hash = try LibraryRepository.digest(file)
            XCTAssertTrue(try repository.importPhoto(file, projectID: nil, into: &library))
            XCTAssertEqual(library.photos.last?.rating, expected)
            XCTAssertEqual(try LibraryRepository.digest(file), hash)
        }
    }
    func testUnsafeCatalogueAndSymlinksAreRejected() throws {
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        let source = try fixture()
        var library = Library()
        _ = try repository.importPhoto(source, projectID: nil, into: &library)
        library.photos[0].filename = "../../source.png"
        try repository.save(library)
        XCTAssertThrowsError(try repository.load())
        library.photos[0].filename = "linked.png"
        try FileManager.default.createSymbolicLink(at: repository.root.appendingPathComponent("Originals/linked.png"), withDestinationURL: source)
        XCTAssertThrowsError(try repository.originalURL(library.photos[0]))
    }
    func testInvalidImageDoesNotLeaveManagedFiles() throws {
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        let invalid = temporary.appendingPathComponent("invalid.nef")
        try Data("not a photo".utf8).write(to: invalid)
        var library = Library()
        XCTAssertTrue(LibraryRepository.imageFiles(in: temporary).contains { $0.lastPathComponent == invalid.lastPathComponent })
        XCTAssertThrowsError(try repository.importPhoto(invalid, projectID: nil, into: &library))
        XCTAssertEqual(library.photos.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repository.root.appendingPathComponent("Originals").path).count, 0)
    }
    func testRecoveredRatingFilterTruthTable() {
        let ratings = Array(-1...5)
        let expected: [(RatingFilter, [Int])] = [
            (.all, [-1, 0, 1, 2, 3, 4, 5]), (.unratedAndAbove, [0, 1, 2, 3, 4, 5]),
            (.oneAndAbove, [1, 2, 3, 4, 5]), (.twoAndAbove, [2, 3, 4, 5]),
            (.threeAndAbove, [3, 4, 5]), (.fourAndAbove, [4, 5]),
            (.five, [5]), (.unrated, [0]), (.rejected, [-1])
        ]
        for (filter, matches) in expected {
            XCTAssertEqual(ratings.filter(filter.includes), matches, filter.label)
        }
        // Index 6 disables the original predicate; it must not mean rating >= 0.
        XCTAssertTrue(RatingFilter(rawValue: 6)!.includes(-1))
        XCTAssertFalse(RatingFilter(rawValue: 7)!.includes(1))
        XCTAssertFalse(RatingFilter(rawValue: 8)!.includes(0))
    }
    func testRecoveredRatingRulesAndCatalogueCompatibility() throws {
        XCTAssertEqual((-1...5).map { RatingRules.adjusting($0, by: 1) }, [0, 1, 2, 3, 4, 5, 5])
        XCTAssertEqual((-1...5).map { RatingRules.adjusting($0, by: -1) }, [-1, -1, 0, 1, 2, 3, 4])
        XCTAssertEqual(RatingRules.adjusting(Int.max, by: 1), 5)
        XCTAssertEqual(RatingRules.adjusting(Int.min, by: -1), -1)
        XCTAssertEqual([-100, -2, -1, 0, 1, 4, 5, 6, Int.max].map(RatingRules.clamp), [-1, -1, -1, 0, 1, 4, 5, 5, 5])
        XCTAssertEqual(RatingRules.rejectionRating(isRejected: true), -1)
        XCTAssertEqual(RatingRules.rejectionRating(isRejected: false), 0)
        XCTAssertEqual(RatingRules.stars(-1), "")
        XCTAssertEqual(RatingRules.stars(5), "★★★★★")
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library()
        _ = try repository.importPhoto(fixture(), projectID: nil, into: &library)
        let original = try repository.originalURL(library.photos[0])
        let digest = try LibraryRepository.digest(original)
        for rating in [-1, 0, 4, 5] {
            library.photos[0].rating = rating
            try repository.save(library)
            let loaded = try repository.load()
            XCTAssertEqual(loaded.version, 1)
            XCTAssertEqual(loaded.photos[0].rating, rating)
            XCTAssertEqual(loaded.photos[0].id, library.photos[0].id)
        }
        // Older catalogues use the same integer field; out-of-range inputs normalize.
        library.photos[0].rating = 99
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        try JSONEncoder().encode(library).write(to: catalogue)
        XCTAssertEqual(try repository.load().photos[0].rating, 5)
        library.photos[0].rating = -100
        try repository.save(library)
        XCTAssertEqual(try repository.load().photos[0].rating, -1)
        XCTAssertEqual(try LibraryRepository.digest(original), digest)
    }
    func testSavedStraightenBoundsMatchRestoredInspectorAndRenderer() throws {
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("angle-bounds"))
        let source = try fixture()
        let digest = try LibraryRepository.digest(source)
        var library = Library()
        _ = try repository.importPhoto(source, projectID: nil, into: &library)
        let crop = PhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        library.photos[0].adjustments.crop = crop
        for (input, expected) in [(90.0, 45.0), (-90, -45), (12.5, 12.5)] {
            library.photos[0].adjustments.straighten = input
            let catalogue = repository.root.appendingPathComponent("catalog.json")
            // Simulate a catalogue written before load/save normalization existed.
            try JSONEncoder().encode(library).write(to: catalogue)
            let restored = try repository.load()
            XCTAssertEqual(restored.photos[0].adjustments.straighten, expected)
            XCTAssertEqual(restored.photos[0].adjustments.crop, crop)
            try repository.save(library)
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalogue)) as? [String: Any])
            let photos = try XCTUnwrap(raw["photos"] as? [[String: Any]])
            let adjustments = try XCTUnwrap(photos.first?["adjustments"] as? [String: Any])
            XCTAssertEqual(adjustments["straighten"] as? Double, expected)
            let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: catalogue))
            XCTAssertEqual(saved.photos[0].adjustments.straighten, expected)
            XCTAssertEqual(saved.photos[0].id, library.photos[0].id)
        }
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
    }
    func testOlderRecipesDecodeAndNewGeometryPersistsAndExports() throws {
        let old = Data(#"{"exposure":1,"contrast":1.1,"saturation":0.8}"#.utf8)
        let decoded = try JSONDecoder().decode(Adjustments.self, from: old)
        XCTAssertEqual(decoded.exposure, 1); XCTAssertEqual(decoded.quarterTurns, 0)
        XCTAssertEqual(decoded.straighten, 0); XCTAssertNil(decoded.crop)
        XCTAssertEqual(decoded.brightness, 0)
        XCTAssertEqual(decoded.vibrancy, 0)
        XCTAssertEqual(decoded.sepia, 0)
        XCTAssertFalse(decoded.flipHorizontal)
        XCTAssertFalse(decoded.flipVertical)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("geometry"))
        let source = try fixture()
        let digest = try LibraryRepository.digest(source)
        var library = Library()
        _ = try repository.importPhoto(source, projectID: nil, into: &library)
        library.photos[0].adjustments.quarterTurns = 1
        library.photos[0].adjustments.toggleFlip(.horizontal)
        library.photos[0].adjustments.crop = PhotoCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        try repository.save(library)
        let photo = try XCTUnwrap(repository.load().photos.first)
        XCTAssertEqual(photo.adjustments, library.photos[0].adjustments)
        let preview = try Renderer.render(source, adjustments: photo.adjustments)
        let cpu = try Renderer.renderOnCPU(source, adjustments: photo.adjustments, maxDimension: nil)
        XCTAssertEqual(preview.width, 12); XCTAssertEqual(preview.height, 16)
        XCTAssertEqual(cpu.width, preview.width); XCTAssertEqual(cpu.height, preview.height)
        let destination = temporary.appendingPathComponent("geometry.jpg")
        try Renderer.export(photo, repository: repository, to: destination)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(image, 0, nil))
        XCTAssertEqual(exported.width, preview.width); XCTAssertEqual(exported.height, preview.height)
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(photo)), digest)
    }
    func testRotationDirectionCropOriginAndStraighteningHaveNoBlankCorners() throws {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
        let image = try XCTUnwrap(context.makeImage())
        func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
            let data = image.dataProvider!.data! as Data
            let offset = y * image.bytesPerRow + x * 4
            return Array(data[offset..<(offset + 4)])
        }
        var settings = Adjustments()
        settings.quarterTurns = 1
        let right = try Renderer.applyGeometry(image, adjustments: settings)
        XCTAssertEqual(right.width, 20); XCTAssertEqual(right.height, 40)
        XCTAssertGreaterThan(pixel(right, 15, 5)[0], 240) // top left red moves to top right
        settings.quarterTurns = -1
        let left = try Renderer.applyGeometry(image, adjustments: settings)
        XCTAssertGreaterThan(pixel(left, 5, 35)[0], 240)
        settings = Adjustments()
        settings.crop = PhotoCrop(x: 0, y: 0, width: 0.5, height: 0.5)
        let topLeft = try Renderer.applyGeometry(image, adjustments: settings)
        XCTAssertEqual(topLeft.width, 20); XCTAssertEqual(topLeft.height, 10)
        XCTAssertGreaterThan(pixel(topLeft, 5, 5)[0], 240)
        settings.toggleFlip(.horizontal)
        XCTAssertEqual(settings.crop?.x, 0.5)
        let croppedAfterFlip = try Renderer.applyGeometry(image, adjustments: settings)
        XCTAssertEqual(croppedAfterFlip.width, 20)
        XCTAssertGreaterThan(pixel(croppedAfterFlip, 5, 5)[0], 240)
        settings.toggleFlip(.vertical)
        XCTAssertEqual(settings.crop?.y, 0.5)
        XCTAssertGreaterThan(pixel(try Renderer.applyGeometry(image, adjustments: settings), 5, 5)[0], 240)
        settings.crop = nil
        let flipped = try Renderer.applyGeometry(image, adjustments: settings)
        XCTAssertGreaterThan(pixel(flipped, 35, 15)[0], 240)
        XCTAssertGreaterThan(pixel(flipped, 5, 5)[2], 240)
        XCTAssertEqual(settings.stamping(onto: Adjustments(), groups: [.geometry]), settings)
        settings = Adjustments()
        settings.quarterTurns = 4
        XCTAssertEqual(try Renderer.applyGeometry(image, adjustments: settings).dataProvider?.data as Data?, image.dataProvider?.data as Data?)
        for angle in [-45.0, -20, -5, 5, 20, 45] {
            settings.straighten = angle
            let straightened = try Renderer.applyGeometry(image, adjustments: settings)
            XCTAssertLessThan(straightened.width, image.width)
            for (x, y) in [(0, 0), (straightened.width - 1, 0), (0, straightened.height - 1), (straightened.width - 1, straightened.height - 1)] {
                XCTAssertGreaterThan(pixel(straightened, x, y)[3], 245, "Blank corner at \(angle)°")
            }
        }
    }
    func testRecoveredStraightenBoundsReachRenderer() throws {
        let source = try fixture()
        XCTAssertEqual(StraightenRules.clamp(-46), -45)
        XCTAssertEqual(StraightenRules.clamp(46), 45)
        XCTAssertEqual(StraightenRules.clamp(12.5), 12.5)
        // Clamp each delta: reversing after an overshoot must leave the limit immediately.
        var angle = 44.0
        for delta in [10.0, -2.0] { angle = StraightenRules.applying(rotation: delta, to: angle) }
        XCTAssertEqual(angle, 43)
        XCTAssertEqual(StraightenRules.applying(rotation: -10, to: -44), -45)
        XCTAssertEqual(StraightenRules.applying(rotation: 2, to: -45), -43)
        XCTAssertEqual(StraightenRules.applying(rotation: .nan, to: 12), 12)
        var settings = Adjustments()
        for (requested, expected) in [(-90.0, -45.0), (90, 45), (Double.nan, 0), (angle, 43)] {
            settings.straighten = requested
            let actual = try Renderer.renderOnCPU(source, adjustments: settings, maxDimension: nil)
            settings.straighten = expected
            let bounded = try Renderer.renderOnCPU(source, adjustments: settings, maxDimension: nil)
            XCTAssertEqual(actual.width, bounded.width)
            XCTAssertEqual(actual.height, bounded.height)
            XCTAssertEqual(actual.dataProvider?.data as Data?, bounded.dataProvider?.data as Data?)
        }
    }
    func testNewInspectorSettingsPersistAndExportWithoutChangingOriginal() throws {
        let source = try fixture()
        let digest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("inspector"))
        var library = Library()
        _ = try repository.importPhoto(source, projectID: nil, into: &library)
        var settings = Adjustments()
        settings.warmth = 0.4; settings.tint = -0.2; settings.shadows = 0.6; settings.highlights = -0.5
        library.photos[0].adjustments = settings
        try repository.save(library)
        let loaded = try XCTUnwrap(repository.load().photos.first)
        XCTAssertEqual(loaded.adjustments, settings)
        let cpu = try Renderer.renderOnCPU(source, adjustments: settings, maxDimension: nil)
        let neutral = try Renderer.renderOnCPU(source, adjustments: Adjustments(), maxDimension: nil)
        XCTAssertNotEqual(cpu.dataProvider?.data as Data?, neutral.dataProvider?.data as Data?)
        let destination = temporary.appendingPathComponent("inspector.jpg")
        try Renderer.export(loaded, repository: repository, to: destination)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(exported.width, cpu.width); XCTAssertEqual(exported.height, cpu.height)
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(loaded)), digest)
        let old = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"exposure":0,"contrast":1,"saturation":1}"#.utf8))
        XCTAssertEqual(old, Adjustments())
    }
    func testToneControlsHaveExpectedDirectionAndNeutralBypassesConversion() throws {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(try Renderer.applyTone(image, adjustments: Adjustments()).dataProvider?.data as Data?, image.dataProvider?.data as Data?)
        func pixel(_ settings: Adjustments) throws -> [UInt8] {
            let result = try Renderer.applyTone(image, adjustments: settings)
            return Array((result.dataProvider!.data! as Data).prefix(4))
        }
        var settings = Adjustments()
        settings.warmth = 1
        let warm = try pixel(settings)
        XCTAssertGreaterThan(warm[0], warm[2]); XCTAssertEqual(warm[3], 255)
        settings.warmth = -1
        let cool = try pixel(settings)
        XCTAssertLessThan(cool[0], cool[2])
        settings = Adjustments(); settings.tint = 1
        let tinted = try pixel(settings)
        XCTAssertLessThan(tinted[1], tinted[0])
        settings = Adjustments(); settings.shadows = 1
        let lifted = try pixel(settings)
        settings = Adjustments(); settings.highlights = -1
        let recovered = try pixel(settings)
        XCTAssertGreaterThan(lifted[0], recovered[0])
        XCTAssertEqual(lifted[3], 255); XCTAssertEqual(recovered[3], 255)
    }
    func testSelectiveStampAndPresetsPreserveUnselectedSettings() throws {
        var target = Adjustments()
        target.exposure = -1; target.warmth = -0.5; target.shadows = 0.3
        target.quarterTurns = 1; target.straighten = 12
        target.crop = PhotoCrop(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        var lifted = Adjustments()
        lifted.exposure = 2; lifted.warmth = 0.8; lifted.shadows = 0.9
        XCTAssertEqual(lifted.stamping(onto: target, groups: []), target)
        let balanceOnly = lifted.stamping(onto: target, groups: [.whiteBalance])
        XCTAssertEqual(balanceOnly.warmth, lifted.warmth)
        XCTAssertEqual(balanceOnly.exposure, target.exposure)
        XCTAssertEqual(balanceOnly.shadows, target.shadows)
        XCTAssertEqual(balanceOnly.crop, target.crop)
        XCTAssertEqual(lifted.stamping(onto: target, groups: Set(AdjustmentGroup.allCases)), lifted)
        for preset in AdjustmentPreset.allCases {
            let result = preset.applying(to: target)
            XCTAssertEqual(result.crop, target.crop)
            XCTAssertEqual(result.quarterTurns, target.quarterTurns)
            XCTAssertEqual(result.straighten, target.straighten)
        }
        XCTAssertEqual(AdjustmentPreset.monochrome.applying(to: target).saturation, 0)
        XCTAssertEqual(AdjustmentPreset.natural.applying(to: target).exposure, 0)
    }

    func testExportOptionsFormatsSizeMetadataAndOriginalCopy() throws {
        let plain = try fixture()
        let pixels = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(plain as CFURL, nil)!, 0, nil)!
        let source = temporary.appendingPathComponent("camera.jpg")
        let writer = CGImageDestinationCreateWithURL(source as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2024:01:02 03:04:05"],
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 51.5, kCGImagePropertyGPSLatitudeRef as String: "N", kCGImagePropertyGPSLongitude as String: 0.1, kCGImagePropertyGPSLongitudeRef as String: "W"],
            kCGImagePropertyIPTCDictionary as String: [kCGImagePropertyIPTCCaptionAbstract as String: "Old caption"]
        ]
        CGImageDestinationAddImage(writer, pixels, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        var photo = library.photos[0]
        photo.caption = "Updated caption"; photo.keywords = "Travel, Family"; photo.rating = 4
        photo.adjustments.quarterTurns = 1
        let sourceHash = try LibraryRepository.digest(source)
        for format in [ExportFormat.jpeg, .png, .tiff] {
            for include in [false, true] {
                var options = ExportOptions(); options.format = format; options.maxDimension = 16
                options.exif = include; options.iptc = include; options.gps = include
                let output = temporary.appendingPathComponent("\(format.rawValue)-\(include).\(format.suffix)")
                try Renderer.export(photo, repository: repository, to: output, options: options)
                let exported = CGImageSourceCreateWithURL(output as CFURL, nil)!
                XCTAssertEqual(CGImageSourceGetType(exported) as String?, format.type.identifier)
                let result = CGImageSourceCopyPropertiesAtIndex(exported, 0, nil)! as NSDictionary
                XCTAssertEqual(result[kCGImagePropertyPixelWidth] as? Int, 12)
                XCTAssertEqual(result[kCGImagePropertyPixelHeight] as? Int, 16)
                let exif = result[kCGImagePropertyExifDictionary] as? NSDictionary
                let iptc = result[kCGImagePropertyIPTCDictionary] as? NSDictionary
                let gps = result[kCGImagePropertyGPSDictionary] as? NSDictionary
                XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, include ? "2024:01:02 03:04:05" : nil)
                XCTAssertEqual(iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String, include ? "Updated caption" : nil)
                XCTAssertEqual(iptc?[kCGImagePropertyIPTCKeywords] as? [String], include ? ["Travel", "Family"] : nil)
                XCTAssertEqual(iptc?[kCGImagePropertyIPTCStarRating] as? Int, include ? 4 : nil)
                XCTAssertEqual(gps?[kCGImagePropertyGPSLatitude] as? Double, include ? 51.5 : nil)
                XCTAssertThrowsError(try Renderer.export(photo, repository: repository, to: output, options: options))
            }
        }
        var originalOptions = ExportOptions(); originalOptions.format = .original; originalOptions.maxDimension = 1
        let copied = temporary.appendingPathComponent("original.jpg")
        try Renderer.export(photo, repository: repository, to: copied, options: originalOptions)
        XCTAssertEqual(try LibraryRepository.digest(copied), sourceHash)
        XCTAssertEqual(try LibraryRepository.digest(source), sourceHash)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(photo)), sourceHash)
        var quality = ExportOptions(); quality.quality = 0.1
        let low = temporary.appendingPathComponent("low.jpg"), high = temporary.appendingPathComponent("high.jpg")
        try Renderer.export(photo, repository: repository, to: low, options: quality)
        quality.quality = 1
        try Renderer.export(photo, repository: repository, to: high, options: quality)
        XCTAssertNotEqual(try Data(contentsOf: low), try Data(contentsOf: high))
        quality.maxDimension = 1000
        let noEnlarge = temporary.appendingPathComponent("no-enlarge.jpg")
        try Renderer.export(photo, repository: repository, to: noEnlarge, options: quality)
        let actual = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(noEnlarge as CFURL, nil)!, 0, nil)!
        XCTAssertEqual(actual.width, 24); XCTAssertEqual(actual.height, 32)
        let preset = ExportPreset(name: "Share", options: quality)
        XCTAssertEqual(try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(preset)).options, quality)
    }
    func testCropPixelPrecisionAspectAndGeometryDimensions() throws {
        let source = try fixture()
        var settings = Adjustments(); settings.quarterTurns = 1; settings.straighten = 10
        let size = try Renderer.dimensions(source, adjustments: settings)
        let rendered = try Renderer.render(source, adjustments: settings)
        XCTAssertEqual(size, CGSize(width: rendered.width, height: rendered.height))
        settings.crop = CropRules.pixels(width: 11, height: 13, image: size, current: PhotoCrop(x: 0.17, y: 0.21, width: 1, height: 1))
        let cropped = try Renderer.render(source, adjustments: settings)
        XCTAssertEqual(cropped.width, 11); XCTAssertEqual(cropped.height, 13)
        let locked = CropRules.fitted(x: 0.9, y: -0.2, width: 0.8, height: 0.2, image: CGSize(width: 4000, height: 3000), aspect: 2.0 / 3)
        XCTAssertEqual(locked.width * 4000 / (locked.height * 3000), 2.0 / 3, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(locked.x, 0); XCTAssertGreaterThanOrEqual(locked.y, 0)
        XCTAssertLessThanOrEqual(locked.x + locked.width, 1); XCTAssertLessThanOrEqual(locked.y + locked.height, 1)
    }
    func testMetadataStampOnlyTouchesCheckedFields() throws {
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("managed"))
        var library = Library(); _ = try repository.importPhoto(fixture(), projectID: nil, into: &library)
        var source = library.photos[0], target = library.photos[0]
        source.id = UUID(); source.caption = ""; source.keywords = "new"; source.rating = 5; source.adjustments.exposure = 2
        target.caption = "keep caption"; target.keywords = "keep keywords"; target.rating = 1
        let lifted = LiftedSettings(source)
        let captionOnly = lifted.applying(to: target, groups: [], metadata: [.caption])
        XCTAssertEqual(captionOnly.caption, ""); XCTAssertEqual(captionOnly.keywords, target.keywords)
        XCTAssertEqual(captionOnly.rating, target.rating); XCTAssertEqual(captionOnly.adjustments, target.adjustments)
        let stamped = lifted.applying(to: target, groups: [.basic], metadata: [.keywords, .rating])
        XCTAssertEqual(stamped.caption, target.caption); XCTAssertEqual(stamped.rating, 5); XCTAssertEqual(stamped.keywords, "new")
        XCTAssertEqual(stamped.adjustments.exposure, 2); XCTAssertEqual(stamped.id, target.id)
        XCTAssertEqual(stamped.filename, target.filename); XCTAssertEqual(stamped.sha256, target.sha256)
        XCTAssertEqual(lifted.applying(to: target, groups: [], metadata: []), target)
    }

}

extension LibraryTests {
    func testBrowsableVersionsShareOneOriginalAcrossExportsAndBackup() throws {
        let source = try fixture()
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 1
        library.photos[0].caption = "Initial"
        library.photos[0].rating = 4
        let original = library.photos[0]
        XCTAssertEqual(original.originalID, original.id)
        let duplicate = try XCTUnwrap(library.createVersion(of: original.id, from: .current))
        let neutral = try XCTUnwrap(library.createVersion(of: duplicate.id, from: .original))
        XCTAssertEqual(library.version, 3)
        XCTAssertEqual(Set(library.photos.map(\.originalID)), [original.id])
        XCTAssertEqual(Set(library.photos.map(\.id)).count, 3)
        XCTAssertEqual(duplicate.adjustments, original.adjustments)
        XCTAssertEqual(neutral.adjustments, Adjustments())
        XCTAssertEqual(neutral.caption, "Initial")
        XCTAssertEqual(neutral.rating, 4)
        XCTAssertNotEqual(neutral.displayName, duplicate.displayName)
        XCTAssertEqual(library.metadataTarget(named: original.originalName), original.id)

        _ = library.updatePhotos([duplicate.id]) {
            $0.caption = "Different"
            $0.rating = 2
        }
        try repo.save(library)
        var reloaded = try repo.load()
        XCTAssertEqual(reloaded.photos, library.photos)
        XCTAssertFalse(try repo.importPhoto(source, projectID: nil, into: &reloaded))
        XCTAssertEqual(try LibraryBackup.verify(repo), 1)
        let backup = temporary.appendingPathComponent("Backup")
        try LibraryBackup.create(from: repo, to: backup)
        XCTAssertEqual(try LibraryBackup.validateBackup(backup), 3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backup.appendingPathComponent("Originals").path).count, 1)
        let restored = temporary.appendingPathComponent("Restored")
        try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
        let (restoredRepo, restoredLibrary) = try LibraryBackup.openVerified(restored)
        XCTAssertEqual(restoredLibrary.photos, reloaded.photos)

        var options = ExportOptions()
        options.format = .png
        let edited = temporary.appendingPathComponent("edited.png")
        let unedited = temporary.appendingPathComponent("unedited.png")
        try Renderer.export(duplicate, repository: restoredRepo, to: edited, options: options)
        try Renderer.export(neutral, repository: restoredRepo, to: unedited, options: options)
        XCTAssertNotEqual(try LibraryRepository.digest(edited), try LibraryRepository.digest(unedited))
        options.format = .original
        let exportedOriginal = temporary.appendingPathComponent("original.png")
        try Renderer.export(neutral, repository: restoredRepo, to: exportedOriginal, options: options)
        XCTAssertEqual(try LibraryRepository.digest(exportedOriginal), try LibraryRepository.digest(source))
        XCTAssertEqual(try LibraryRepository.digest(restoredRepo.availableOriginalURL(original)), original.sha256)
    }

    func testRelinkConsolidationAndRedoUpdateAllVersionsIncludingTrash() throws {
        let source = try fixture()
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library, options: options))
        let base = library.photos[0]
        let duplicate = try XCTUnwrap(library.createVersion(of: base.id, from: .current))
        let another = try XCTUnwrap(library.createVersion(of: base.id, from: .original))
        _ = library.setPhotosTrashed([duplicate.id], at: Date())
        var history = EditHistory()
        history.record(.removeVersion(another))
        XCTAssertNotNil(history.step(in: &library, redoing: false))

        let relocated = temporary.appendingPathComponent("moved.png")
        try FileManager.default.moveItem(at: source, to: relocated)
        try repo.relinkOriginal(duplicate.id, to: relocated, in: &library)
        XCTAssertEqual(Set(library.photos.compactMap(\.referencedPath)), [relocated.resolvingSymlinksInPath().path])
        XCTAssertNotNil(history.step(in: &library, redoing: true))
        XCTAssertEqual(library.photos.last?.referencedPath, relocated.resolvingSymlinksInPath().path)

        try repo.consolidateOriginal(another.id, in: &library)
        XCTAssertTrue(library.photos.allSatisfy { $0.referencedPath == nil })
        XCTAssertEqual(try LibraryBackup.verify(repo), 1)
        XCTAssertEqual(try repo.load().photos.count, 3)
        XCTAssertEqual(try LibraryRepository.digest(relocated), base.sha256)
        let otherFile = try fixture("other.png", red: 0.65)
        XCTAssertTrue(try repo.importPhoto(otherFile, projectID: nil, into: &library, options: options))
        XCTAssertEqual(try repo.load().version, 3)
    }

    func testCatalogueRejectsInconsistentOriginalsAndInvalidVersionChains() throws {
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(fixture(), projectID: nil, into: &library))
        let first = library.photos[0]
        let second = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        _ = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        try repo.save(library)

        var invalid = library
        invalid.photos[1].sha256 = "invalid"
        XCTAssertThrowsError(try repo.save(invalid))
        invalid = library
        invalid.photos[2].sharedOriginalID = second.id
        XCTAssertThrowsError(try repo.save(invalid))
        invalid = library
        invalid.version = 2
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try repo.load().photos, library.photos)
    }
}
