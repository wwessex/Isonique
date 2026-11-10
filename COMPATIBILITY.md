# Isonique library compatibility

Isonique stores its catalogue and edit recipes in `catalog.json` and uses its own backup format. Its macOS bundle identifier is `local.craftanything.isonique`. A library cannot be created inside an application bundle or a legacy photo library.

## Isonique catalogues

New default libraries use `~/Library/Application Support/Isonique/Library`. If that location has no catalogue and the earlier default `~/Library/Application Support/ApertureNative/Library` exists, Isonique opens the earlier Isonique library in place. This fallback is for Isonique data. An explicit `--library` argument or a saved library selection takes precedence. File → Open Isonique Library can select another existing library.

Isonique reads catalogue formats 1–15. Referenced originals and compound or project-scoped Smart Albums require format 2 or later. Browsable versions and stack controls require format 3 or later. Local brushes, channel curves, channel Levels and quarter-tones require formats 4, 5, 6 and 7 respectively. Persistent Undo/Redo for capture date changes requires format 8. Persistent batch caption and keyword history requires format 9. Vocabulary path assignments, saved path rules and their edit history require format 10. IPTC title, creator, copyright and credit and their edit history require format 11. Smart Album rules for those IPTC fields require format 12. Persistent grouped Lift and Stamp history requires format 13. Saved EXIF capture values and EXIF Smart Album rules require format 14. Saved GPS coordinates and GPS Smart Album rules require format 15. Saving a feature that needs a later format upgrades the catalogue. Older builds may reject newer formats or discard fields they do not understand.

Isonique backups copy the saved catalogue and its managed originals, including photos in Trash. A manifest records the catalogue hash and the original hashes are verified. Referenced originals remain at their external paths and need separate backups. Restore creates a new library folder. Preferences, uncatalogued files, library merging and automatic catalogue repair are outside this workflow.

## Recovery from Aperture libraries

**File → Recover Aperture Originals** makes a temporary copy of the selected library, verifies file hashes and recovers embedded originals from `Masters` and `Originals`. Symbolic links are refused and the source is opened read-only. Embedded captions, keywords, title, creator, copyright, credit and supported ratings are carried over when ImageIO exposes them. XMP takes precedence over IPTC. Duplicate photos retain their current Isonique metadata, and unsupported files are reported separately.

Allow space for a complete temporary copy. The recovery workflow is limited to embedded originals and supported metadata in those files. Database projects, albums, relationships, previews, referenced originals, legacy edits and vaults are outside its scope. Tests cover a synthetic `.aplibrary` fixture with a generated image and a mock database. A real legacy library has not been tested.

Normal import reads embedded Lightroom-style keyword paths when ImageIO exposes them and can apply matching XMP sidecars. **File → Import XML / XMP Metadata** accepts XMP, Isonique photo records and supported `AlbumData.xml` metadata. **Write matching XMP sidecar** in Export saves current keyword paths, flat keywords, caption, rating, title, creator, copyright and credit alongside rendered or original files. Keep each sidecar with its matching image when moving exports. [Historical workflow comparison](docs/APERTURE_FEATURE_PARITY.md)

## Platform and image processing

The maintained app targets Apple Silicon and macOS 14 or later. Camera RAW support depends on system ImageIO codecs. Edited output uses 8-bit sRGB. The rendering notes describe the processing choices and the test record identifies the camera samples and OS tested. [Processing notes](PROCESSING_ALTERNATIVES.md) · [Test results](docs/APERTURE_TEST_RESULTS.md)
