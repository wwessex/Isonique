# Isonique development provenance

Isonique is a separate Swift application with its own executable, catalogue, edit recipes and backup format. It uses public macOS APIs for its interface, system image decoding, metadata and colour management. The Swift package declares no third-party dependencies. Research into alternative processing libraries is documented separately. [Processing notes](PROCESSING_ALTERNATIVES.md)

## Historical Aperture research

Earlier development used public manuals and screenshots alongside direct analysis of the proprietary Aperture 3.6 executable and resources. That analysis informed some defaults, input ranges, rules and interaction ordering. This was not a clean-room process. The source review found the following areas to carry forward for provenance review.

| Isonique area | Historical influence documented in the project |
| --- | --- |
| Ratings and review filters | Rating bounds, rejection transitions, rating deltas and the stored filter values and predicates. |
| Crop and straighten | Gesture accumulation and bounds, and crop aspect-ratio calculations. |
| Import, Lift and Stamp | RAW+JPEG choices and default, and the handling of missing lifted adjustments. The RAW-primary option retains its earlier serialized key so stored presets continue to decode. |
| Organisation and slideshow | Minimum stack size, default slide duration and withholding slideshow startup during import. |
| Backup and restore | The sequence of validating the source before selecting a writable destination. Isonique uses its own JSON catalogue and SHA-256 manifest. |

The review found Swift implementations of these behaviours and no bundled Aperture executable, private framework, original interface resource or application artwork in the current build inputs. It did not establish the authorship or redistribution rights of each line or value. The photo renderer is implemented in the Isonique source, with system decoding and colour APIs. There is no claim of legacy pixel fidelity.

Raw disassembly, decompiler output and extracted strings were removed from the working source tree. Earlier repository snapshots and separate local research records may still contain them. Those records need a rights and provenance review before redistribution. Changing the product name and removing raw outputs from the current tree does not settle the provenance of behaviour informed by the earlier analysis.

## External fixtures

Most tests generate small images and synthetic catalogues. The opt-in RAW workflow test uses separately downloaded camera samples described as CC0 by the publisher. The samples are external to the source checkout and app bundle. [Sample release](https://github.com/tellodaniel/revelraw-sample-raw-files/releases/tag/v1)
