# Original behavior findings and implementation trace

## 9 November 2026: backup and restore main-program trace

Opened `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open` in Deep mode, SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Searched names, settings and messages with `native_strings_find`, followed references, and completed **nine sequential `native_function_pseudocode` calls**, reading each result before the next call. All nine reported `deep_engine_unavailable`: Ghidra gave no result; the tool supplied built-in fallback pseudo-C. This is completed fallback analysis, not successful Ghidra decompilation. Full results: [backup-restore-main-trace.json](evidence/backup-restore-main-trace.json).

### Strings and references

`validateVaultAtPath:` (`0x1005ee259`) → method metadata `0x1007fd258` → implementation pointer `0x1007fd268` = `0x10038c3f3`; selector `0x10087f0b8` → restore callback instruction `0x10038caff`. `restoreLibraryWithVaultAtPath:` (`0x1005ee118`) → selector `0x10087f058` → callback dispatch at `0x10038ccf2`; function search resolves manager `0x10049d53b` and dialog `0x10038c9c1`.

Settings/messages `restoreLibraryFolderRestricted`, `restoreLibraryPathUnsupported`, `restoreLibraryPathNotWritable`, `restoreLibraryPathNotFolder` (`0x100566d5a`, `0x100566d79`, `0x100566da6`, `0x100566dc4`) reference CFString text pointers. Following object bases 16 bytes before those pointers resolves chooser instructions `0x1001d34c5`, `0x1001d36f5`, `0x1001d3799`/`0x1001d38f5`, `0x1001d38c1`. String evidence `ev_e719064622d5053f99fefb35d8dd5d02d5cce80dcbbe1ea162eb74e5419846fd`; individual xref records are retained in the evidence file.

### Recovered values and rules used by the build

| Rule / formula | Original address and evidence | Application |
|---|---|---|
| Accept source schema when `sourceVersion == currentVersion`; equality returns **1**, mismatch **0**. | `RKRestoreDialog validateVaultAtPath:` `0x10038c3f3`; `mov bl,1` at `0x10038c41b`, compare `0x10038c424`, equality jump `0x10038c427`; mismatch clears bl. Selector `0x10087f078` resolves to `dataModelVersionForVaultAtPath:`. Pseudocode `ev_54e5d7de16f176cbde1ca0f52a527928b0378923cadfc3b8dd24c1a4eb117c3e`; assembly `ev_577478aaaed404b126289b7f6c6e87aac0fd9bbfffe60f3ce11a266fa44d9905`. | Existing Isonique manifest/catalogue version equality guards now run through new read-only `LibraryBackup.validateBackup` before destination selection. Isonique version **1** is an independent format number; Apple's imported `_RKDataModelVersion` / `_RKDataModelVersion_200` numeric values were not recovered here. Older mismatches may offer an external upgrade route; no legacy upgrader is implemented. |
| Validate source before subsequent restore prompt and manager dispatch; failure returns immediately. | `RKRestoreDialog restoreLibraryPanelDidEnd:returnCode:contextInfo:` `0x10038ca63`; validation call `0x10038cb0c`, test/jump `0x10038cb0f` / `0x10038cb11`. Assembly `ev_7c72c21f2cc171a0daf41d4f0d5ae51f0c6fe8db0270d9af044fe3a12f25ccdd`; pseudocode `ev_d5510da3ca44defc1cc519324f275064b9a2c6076504d00f1b1797308dbe12fe`. | Native Restore now checks the chosen backup off the UI thread before showing its destination panel. Restore rechecks the source before copying. This adapts the ordering to Isonique's new-folder workflow; original replacement-dialog behavior is not replicated. |
| Require writable directory; check parent for a nonexistent child. | `RKLibraryChooser _panel:isValidFilename:` `0x1001d346b`; parent load `0x1001d37d3`, writability selector `0x1001d37e0`, call `0x1001d37ed`, test/failure branch `0x1001d37f0` / `0x1001d37f6` leads to not-writable message. Selector `0x100874350` = `isWritableFileAtPath:`. Assembly `ev_abfd906847449643359903c75a9502b8ee009b7d4d6f6a05f835e3469cf57455`; typed selector `ev_38a7c7fc90fea80cd7dffb4cbe1cbb4458098f69c598cdf451a0f11263e32747`. | Shared backup/restore copy explicitly checks parent existence, directory type and writability before staging. Actual filesystem operations still handle permission changes/errors. Full legacy volume policy remains unresolved. |
| `canRestoreLibrary = (selectedItem.representedObject != nil)` → **0 or 1**. | `RKRestoreDialog canRestoreLibrary` `0x10038c648`; test/setne `0x10038c675` / `0x10038c678`; selectedItem and representedObject selectors resolved. Assembly `ev_6fa3c799e746e0c7cb2db6523246d58a4c9f4c29145b64d9aa4de26fcb4091a6`. | Existing accepted-panel + nonnil source URL guard retained. Selection presence alone does not establish integrity. |

### Every completed pseudocode read

| Function | Entry | What was read / limits |
|---|---|---|
| RKRestoreDialog validateVaultAtPath: | `0x10038c3f3` | Schema equality/mismatch; imported version numbers unresolved. |
| RKLibraryChooser _panel:isValidFilename: | `0x1001d346b` | Directory/writability/message routing; 14 fallback gotos prevent complete path-policy recovery. |
| RKRestoreDialog restoreLibraryWithVaultAtPath: | `0x10038c9c1` | Selection guard and dialog setup. |
| RKRestoreDialog restoreLibraryPanelDidEnd:returnCode:contextInfo: | `0x10038ca63` | Accepted panel return code 1, validation before prompt, guarded dispatch; computed tail jump. |
| RKRestoreDialog canRestoreLibrary | `0x10038c648` | Selected object nonnil → boolean. |
| RKVaultManager initialize | `0x10049e6d7` | Mount/unmount notification registration; no hash formula. |
| RKRestoreLibraryManager restoreLibraryWithVaultAtPath: | `0x10049d53b` | File/background/database setup; unstructured fallback does not establish complete legacy restore algorithm. |
| RKVaultManager updateVault:calculateDiskSpace: | `0x10049fb20` | Database/sync routing and imported status/error symbols; sync internals unresolved. |
| DebugWindowController verifyVaults: | `0x1001cce6a` | Delegates verification through a vault table; no hash algorithm recovered. |

Isonique's SHA-256 manifest, exact catalogue copy, staged publication, no-overwrite/new-folder restore, symlink restrictions and integrity scope remain independent choices. No legacy vault decoding, incremental sync or repair was recovered or added. Earlier proprietary pixel/grouping unknowns remain unchanged.

Inspected variants: sole maintained native SwiftUI macOS app (macOS 14+, arm64). No web/PWA, Windows, iOS or Android implementation exists here. Legacy original execution, Intel and older macOS runtime validation are unavailable. This pass's checks are recorded in `VALIDATION.md`.

## 9 November 2026: fresh review and tonal main-program trace

Reopened the original main executable at `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open`; confirmed Deep mode. Binary SHA-256: `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Completed **12 sequential native_function_pseudocode calls**, awaiting and reading each result before the next. Every call reported Ghidra `deep_engine_unavailable`; fallback pseudo-C was returned. This is completed fallback analysis, not successful Ghidra decompilation. Full returned records, assembly and typed constants: [review-tonal-main-trace.json](evidence/review-tonal-main-trace.json).

### Names, settings and messages followed

String searches found Auto Stack actions, undo messages, histogram channel names, slideshow import-block messages, and display/fade selectors (`ev_c958fa2fea995c3793aa1df9059fc3dc8398628a373df8978ae14ec931a8e38d`, `ev_b50e0144c0a28328f8876369dd2e800345ef6e071b7587157538291ebd422e83`).
- `_autoStackList:withThreshold:previousValue:` string `0x100599541` → method metadata `0x10074bd70` and selector `0x10086ac68` → selected/all callers `0x1000440f7` / `0x10004413f`; named implementation `0x1000317b6`.
- `setDisplayTime:` string `0x1005a6f82` → selector `0x10086e230` → initializer instruction `0x10009f165`, corroborated by assembly `ev_e0a00156366c2d6af0d8472b04ecad14469e043991436e4663e833aa91002ead`.
- `_setDefaultsForChannel:` string `0x1005cb342` → selector `0x100877140` → five calls in `-[RKHistogramView setDefaults]` (`ev_b8fea888172a887d0e248671edfb08c23ccd4ec17e1b892dfe6097c33cd344fb`). Levels callback string `0x1005cb2f4` → selector `0x100877130` → histogram drag/parameter update callers (`ev_fcd2a941719db38f7e7f5238bf9022e077585ab0e83ecf8bb6af58e75a1f98ef`).
- Import-block message CFStrings have their text pointers at `0x1008a8a18` / `0x1008a8a38`; static xrefs at those interior addresses were empty. Full assembly instead establishes CFString object bases `0x1008a8a08` / `0x1008a8a28` in the import-block branch. `isImportInProgress` selector `0x10086af58` is referenced at `0x100049620`; typed pointer evidence `ev_263d1a12e1700fdd9bcf507552618a4a8b82bac4301d4cabd25d4da978ef9d2e`.

### Recovered values and rules

All addresses below are unslid addresses in the main executable.

| Rule/value | Function and instructions/data | Application |
|---|---|---|
| Initial display time = **3.0 seconds** | `-[RKSlideshowPreset init]` `0x10009ef9f`; `movsd` at `0x10009f15d` loads f64 `0x10054fe40=3.0`; selector at `0x10009f165` is `setDisplayTime:`. Pseudocode `ev_897e46652a86dc9ed27f1a31c2c3d64037089da91d6ae85bcfb541af706af27d`, typed data `ev_54e75c2bc3b4a5ada25a458781a16d3b32c5e2b2cfe4bb8d559614bb1aa4cb41`. | `SlideshowRules.defaultDisplayTime` replaces the previous 5-second initial choice in the native slideshow. This is the original preset initializer value, not proof that every factory theme uses it. |
| Import in progress → alert and return before slideshow setup | `-[RKSelectionMgr _runSlideshowPromptForSettings:]` `0x1000495f1`; call at `0x10004962a`, `test al,al` at `0x10004962d`, zero branch at `0x10004962f`; nonzero path loads import-block messages. Pseudocode `ev_e31cb97211b5f25778bc85868b4b98798b1e04800110e1e556ca6590a1ee8869`; assembly `ev_175ef8797c08ef8a812afe159abe1bead2c066b9278dd5676d6a30c871704347`. | Both native menu and toolbar now call guarded `startSlideshow()`, using explicit import state. Toolbar also disables during busy operations; export/recovery exclusion is an independent concurrency policy. Alert wording is independent. |
| Preset fade time = **2.0 seconds**; screen fade out/in = **1.0/1.0**; slideshow fade out/in = **1.5/1.0** | Same initializer: `0x10054fdd0=2.0` → `setFadeTime:`; `0x100554fa8=1.0`, `0x100554fb0=1.0`, `0x100554fc0=1.5`, `0x100554fb8=1.0` → four resolved fade selectors. Assembly and typed reads retained. | Documented only. Current slideshow has no fade pipeline; these are not substituted for display time or falsely presented as implemented transitions. |

### Every completed pseudocode read and its limits

| Original function | Address | What the read establishes |
|---|---|---|
| RKAutostackController windowDidLoad | `0x10015f4f6` | Control/notification setup; no recovered initial threshold. |
| RKAutostackController setSliderValue: | `0x10015eefd` | Updates controls and stored previous value; fallback omits floating argument semantics. |
| RKAutostackController a_doAutoStack: | `0x10015ee59` | Routes changed value to selection manager; computed tail jump limits reconstruction. |
| RKSelectionMgr _autoStackList:withThreshold:previousValue: | `0x1000317b6` | EXIF date/file-name sorting inputs and delegation to `autoStackItems:withThreshold:previousValue:`; malformed fallback loop does not establish grouping formula or boundary equality. |
| RKAutostackController awakeFromNib | `0x10015ee3a` | Sends zero argument to a control selector; no threshold claim. |
| RKHistogramView _setDefaultsForChannel: | `0x100205a31` | Registers per-channel numeric control defaults; no pixel histogram luminance formula. |
| DGLevelsViewController initialize | `0x1003ff3cd` | Preference registration with integer 3 and boolean 0; unresolved key semantics prevent treating these as gamma/range values. |
| DGCurvesCustomViewController initialize | `0x1003f324c` | Conditional preference initialization, including floating values; no curve interpolation algorithm established. |
| RKSlideshowPreset init | `0x10009ef9f` | Defaults verified above against assembly, typed f64 reads and selectors. |
| RKSelectionMgr a_slideShow: | `0x100049926` | View-type dispatch; type value 8 alone is insufficient to map independent UI modes. |
| RKSelectionMgr _runSlideshowPromptForSettings: | `0x1000495f1` | Import guard verified above; selection fallback/ordering is more complex than our snapshot policy. |
| DGLevelsViewController histogram:parameterChangedValue:forChannel: | `0x1003ffa90` | Maps edited histogram parameters to operation keys and guards updates; no image-processing exponent recovered. |

The earlier Levels exponent, quarter-point linear curve, histogram coefficients, Auto Stack consecutive-gap formula, exclusions, 0–60-second range and 2-second initial gap remain **independent implementation choices**. They are not newly claimed as original formulas. Recovering the underlying framework implementations remains outstanding; UI routing and preferences do not establish proprietary pixel or grouping behavior. Existing catalogue fields and neutral defaults are unchanged.

Inspected variants: sole maintained native SwiftUI macOS app (macOS 14+, arm64 release). No web/PWA, Windows, iOS or Android implementation is present. Intel, older macOS, physical mobile devices and execution of the legacy original were not validated.

## 9 November 2026: batch and organization main-program trace

Opened the original main program with `core_target_open`: `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture`, SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Session confirmed Deep mode. Searched names, settings and messages with `native_strings_find`, followed Objective-C method-name references to implementation pointers, and followed the Lift message and Stamp preference CFStrings to code. **Twelve separate pseudocode calls completed sequentially; each result was awaited and read before the next.** Every call reported `deep_engine_unavailable`: Ghidra returned no result, and the tool supplied fallback pseudo-C. Numeric rules below use assembly/data corroboration; incomplete fallback flow is not treated as a recovered algorithm. Full results: [organization-main-trace.json](evidence/organization-main-trace.json).

| Completed function read | Main-program entry | Pseudocode evidence |
|---|---|---|
| `-[RKSourceListController newSmartAlbum:userQuery:showHUD:]` | `0x1002ea087` | `ev_3066c1aaf6d391b51a6f2a1a3746fb6765b2c68cbb2958698dfda218336bb879` |
| `-[RKSelectionMgr _autoStackList:withThreshold:previousValue:]` | `0x1000317b6` | `ev_a204d60e7cbe569334adeff385e71073a41a0503672c79dea49e2a46ddef20ab` |
| `-[RKAutostackController a_doAutoStack:]` | `0x10015ee59` | `ev_3918056c3d7151a5e8289ea1ee0ee2cd101c61a3010a3dd310949a87151a2230` |
| `-[RKFilterFieldController setRatingFilterIndex:]` | `0x100157a19` | `ev_80724a82ed999943771eae99a1526f87df36086a5ab66234bd4a445db0d16aa2` |
| `-[RKFilterFieldController setFlaggedFilter]` | `0x100157c47` | `ev_13b48217bfad429241772433d90d1f672ae57bfd1b3257c896bfcce60bfd310f` |
| `-[RKSelectionMgr a_liftAdjustments:]` | `0x100049366` | `ev_c28bfd9591925afb7e0441431abea970f5580f99eb867213e88b0b036fd89341` |
| `-[RKSelectionMgr a_stack:]` | `0x100044f0a` | `ev_42ee81c115e229ff0f10d6cd1a4c866c5eab0491c06583f8f505a8e0a0d5e34e` |
| `-[RKSelectionMgr a_newVersion:]` | `0x100046242` | `ev_70f7aea50f78f1a83872973bdc17c7f12909785d6f26f330ba4cefefe5fc989e` |
| `-[RKSelectionMgr duplicateVersionRef:options:]` | `0x10003d67f` | `ev_9b4b40b00e637b261d771d44b3b28fae46f530165f592bd7591e0b50ab270a20` |
| `+[RKLiftStampTool initialize]` | `0x1000babff` | `ev_d89100a5bd0d01164e0ee586aea342d8005ed3e1d96807cc93b5185ac437a925` |
| `-[RKLiftStampTool setReplaceOnStamp:]` | `0x1000bc6a1` | `ev_d3b165e4b7479ccf26cebbf5683083ff76dd271aa515d16cb7dc2b50ca7995c7` |
| `-[RKLiftStampTool replaceOnStamp]` | `0x1000bc6e2` | `ev_0854dd84ea715f6c6eecff6e653e2e093bd6b6aa3662633f5ead61c0269a1684` |

**Recovered rating formulas.** `setRatingFilterIndex:` at **0x100157a19** uses index **6** to disable its rating predicate. Indices **1–4** mean `rating >= index`; **5** means `rating == 5`; **7** means `rating == 0`; **8** means `rating == -1`; remaining indices mean `rating >= 0`. Assembly `ev_bb58ca1c6433723d4f6d9e201febf431aa309159bf626a1c9ef0e7371d2be2d6` indexes eight-byte tables at **0x100551590** (qualifiers **[8,8,8,8,5,8,5,5]**) and **0x1005515d0** (values **[1,2,3,4,5,0,0,-1]**). All sixteen fresh i64 reads are retained. Qualifier **5 = equals**, **8 = greater-or-equal** comes from the earlier verified original RedRock comparator **0x43759**, with signed jump-table and CFString evidence documented below; those meanings are not guessed from the main-program tables.

**Recovered flagged rule.** `setFlaggedFilter` at **0x100157c47** enables query type **22**, property `RKVersionIsFlagged`, qualifier **5**, integer value **1**. Formula for the replacement is `!flaggedOnly || photo.flagged`. Combining rating, flag and text with AND in a smart album is our supported query policy, not proof of the original's entire smart-album engine.

**Recovered stack prerequisite.** `a_stack:` at **0x100044f0a** compares the item count to **2** at **0x100044f4f** and returns when below it (`jb` at **0x100044f53**). Full assembly evidence: `ev_ea94337245c7a28f9d7b9dafcab24fc9d3ae3d2fc0df54b68989853ff1375bd8`. This is a necessary prerequisite, not the complete original eligibility rule: the function also has an earlier guard and a later property check. Main reference chain: selector **0x10059812c** → method record **0x10074ce08** → implementation pointer **0x10074ce18** → **0x100044f0a**. The app now tests the number of actual selected catalogue photos, so stale selection IDs cannot satisfy the two-item prerequisite.

**Smart albums and versions: observed boundaries.** Smart-album selector **0x1005e063f** → method record **0x1007c4290** → implementation **0x1002ea087**. Its non-null supplied query is reconstructed through `initWithInfoDictionary:` (selector **0x10087bec8**) and `setUserQuery:` (**0x10087bbd0**). This does not recover all query operators or defaults. Version action **0x100046242** calls `_makeNewVersionFromOriginal:addToSelection:actionName:` with **0, 0**; selector **0x10086ad80** confirms its name. The duplicate wrapper **0x10003d67f** delegates with options; fallback register aliasing prevents claiming complete copy semantics. Isonique's named adjustment snapshots remain an independent feature, not a reconstruction of Aperture's version database.

**Settings and messages.** `RKLiftStampToolReplaceOnStamp` string **0x10055f075** → CFString **0x1008af268** → initialization **0x1000bac30**, setter reference **0x1000bc6c5**, getter reference **0x1000bc706**. The initialized value is **0** (previous assembly corroboration below). The setter/getter persist/read this preference; they do not reveal the proprietary adjustment merge formula. `noLiftedAdjustmentsMessage` string **0x10055a0c8** → CFString **0x1008a89e8** → **0x100049441** inside Lift **0x100049366**; the action passes metadata **0**, adjustments **1**, change-tool **0** and conditionally warns if nothing was lifted. Autostack wrappers **0x1000317b6 / 0x10015ee59** delegate through imported machinery; time grouping, threshold units and defaults remain unresolved. No estimated values were added.

**Build integration.** Smart albums now offer all nine recovered rating filters, including exact Unrated and Rejected, using the same `RatingFilter` and `BrowserFilterRules` as the browser. An optional `ratingFilterIndex` persists the original index. Missing/unknown indices retain the saved `minimumRating` behavior; existing catalogue rules keep their membership. Previous executables cannot represent the new exact-only filters and may discard this optional field, reverting to their stored threshold. New smart albums retain the existing unrated-and-above default as our choice. `StackRules` applies the recovered minimum count in both the UI and action. Original stack joining, autostacking, version relationships, pixel/RAW processing and full catalogue fidelity remain unknown.

Only the native Apple Silicon macOS app is maintained in this workspace. No web/PWA, mobile or separate native desktop variant exists. Validation and build results for this pass are in `VALIDATION.md`.

## 9 November 2026: fresh import and proofing decompilation

Reopened the original main executable with `core_target_open` in Deep mode: `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture`, SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Searched names, settings and messages with `native_strings_find`. **Seven individual `native_function_pseudocode` calls completed sequentially, each awaited and read before proceeding.** Ghidra returned no result for every call; these are completed fallback pseudo-C reads, not successful Ghidra decompilation. Assembly and selector pointers resolve the numeric findings below. Full retained results: `evidence/import-proofing-main-trace.json`.

| Function | Address | Recovered observation |
|---|---|---|
| `+[RKImportTypeController initialize]` | `0x100184c73` | Registers import defaults including numeric 1 for `RKImportFolderRAWPlusJPEGFilterType`; fallback argument aliasing is imperfect, so the separate reset below is the basis for the implemented default. |
| `-[RKImportRAWPlusJPEGPairsTileController resetToDefaults]` | `0x1003f28e9` | Calls superclass reset, then `selectItemWithTag:1`. Immediate at `0x1003f2926`, selector pointer `0x10086f1e8`. |
| `-[RKImportRAWPlusJPEGPairsTileController awakeFromNib]` | `0x1003f263d` | Reads `preset.RAWPlusJPEGFilterType` and selects its tag, confirming saved preset choice takes priority when opening the UI. |
| `-[RKImportRAWPlusJPEGFilterTypeIsNotMatchingRAWValueTransformer transformedValue:]` | `0x1002b5bcd` | Exact Boolean formula **integerValue(input) != 6**. Assembly `cmp eax,6` at `0x1002b5be9`, `setne` at `0x1002b5bec`; fallback omits the comparison. Tag 6 is Matching RAW files. This UI transformer is not a file-matching algorithm. |
| `-[RKImportTypeController addImportTypeOptions:withPolicyOffset:]` | `0x100183804` | Reads folder RAW+JPEG preference into import options. Naming policy offset addition is visible, but no naming-template expansion or filename-pairing formula is established. The requested interior address `0x100183980` resolves to this entry. |
| `-[RKLoupeView setProofingProfile:]` | `0x1001f4aa9` | Replaces profile on pointer change and conditionally requests view work. Does not reveal ICC rendering intent, color transform or a lens-distortion formula. |
| `-[RKSelectionMgr a_liftAdjustments:]` | `0x100049366` | Re-read alert reference: Lift uses metadata=0, adjustments=1, changeTool=0. Missing lifted adjustments checks a warning-suppression preference before its message. No stamp-merge formula recovered. |

Reference chains: `RKImportFolderRAWPlusJPEGFilterType` string `0x100564812` → CFString base `0x1008b8d28` → initialization `0x100184d2c` and import options `0x100183b9f`; `RAWPlusJPEGFileFilteringEnabled` string `0x10057c611` → CFString base `0x1008d1b68` → `importPresetVisibilityKey` at `0x1003f287e`; `ProofProfileName` string `0x100558919` → CFString base `0x1008a6ec8` → viewer `drawRect:` reference `0x10001fd80`. A CFString's character pointer lies 16 bytes after its base: following the pointer field alone misses code references. Message string `noLiftedAdjustmentsMessage` at `0x10055a0c8` → CFString base `0x1008a89e8` → Lift code `0x100049441`.

**Interface mapping:** decoded the original `English.lproj/ImportRAWPlusJPEGPairs.nib` using `apple_nib_decode` (`ev_f4285ecc1f2943dcbfe47ecab2eb65b366ef7134fea2261e86bf6d81f017db3c`). Its selectedTag binding targets `preset.RAWPlusJPEGFilterType`. Menu tags: **1 Both (Use JPEG as Original), 2 Both (Use RAW as Original), 3 Both (Separate Originals), 4 JPEG files only, 5 RAW files only, 6 Matching RAW files**. The nib's design-time selection is tag 3; the executable's explicit reset selects tag 1. This does not establish every first-launch preference path. Reset pseudo-C `ev_a1f3be4385ea9cf843d05832a797c919adb63d9a1101beeb658bb0c456425d75`, assembly `ev_7c6878a0328d8f2478ca5de4d6282994be5717829e86638ebfb19ec56c7aec8a`. Transformer pseudo-C `ev_441dcd75a7297647763bd80efcfc2e522ad9f95f6890a2917578e98cb01c8a5b`, assembly `ev_35a1576e57bb62059c66f94365526f9d1025f1b839eea6303a1dd3d815439c83`.

**Build changes:** new import options default to Both/JPEG, using the recovered reset choice as our default policy. Existing saved options/presets retain their selection and serialized values. Added Both/RAW and strict JPEG-only / RAW-only options. Both modes retain and link newly imported companions, selecting the chosen format after import. This uses our existing separate-photo catalogue, not Aperture's master/version model. Extension-based RAW recognition and same-folder/base matching remain independent approximations. Existing Prefer options remain for compatibility; they are independent choices, not original tags 4/5. Matching RAW into existing masters (tag 6) remains unavailable because its database-dependent matching has not been recovered. No original pairing, naming, XML, persistent-history, proofing or lens pixel algorithms are claimed as reconstructed.

The earlier verified formulas remain active: rating `min(5,max(-1,current+delta))` from `0x100032854` / `0x1001c35de`; reject state 1 gives -1, otherwise 0 at `0x1004320d4`; finite straighten `min(45,max(-45,current+delta))` at `0x10042f5e6`; crop aspect `abs(width)/abs(height)`, inverted only at rotation 90/270, at `0x1001e709b`. Their earlier assembly/constants and integration details follow below. Independent lens coefficient 0.35, history limit 100, XML size limit 16 MiB and relative-colorimetric proofing were not recovered from the original and remain independent implementation choices.

Only the native Apple Silicon macOS app is maintained here. No web/PWA, mobile or independent Windows/native variants exist. Validation for this pass is in `VALIDATION.md`.

## 9 November 2026: main-program reads and Rating menu integration

Opened `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open`; session confirmed Deep mode. Original SHA-256: `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Searched names, settings and messages with `native_strings_find`, followed string/selector references and read method implementation pointers. Six `native_function_pseudocode` calls completed sequentially; every result was awaited and read before the next. Ghidra returned no result for all six; the supplied fallback pseudo-C is imperfect. Conditional moves in assembly were used to correct its rating and rejection output. Full current trace: `evidence/rating-menu-main-trace.json`.

| Original function | Main address | Rule or observed behavior |
|---|---|---|
| `-[RKSelectionMgr _node:adjustRatingBy:]` | `0x100032854` | Adds supplied delta to current node rating at `0x100032879`, then calls the rating setter. |
| `-[RKScriptingVersion setScriptingMainRating:]` | `0x1001c35de` | Clamps to imported `_kMinRating` / `_kMaxRating`; earlier RedRock reads establish **-1 / 5**. Combined app formula: **min(5,max(-1,current+delta))**. Combining these two entry points is our integration policy. |
| `-[RKMetadataRatingItemView changeReject:]` | `0x1004320d4` | State exactly **1** supplies **-1**; other states supply **0**, verified at `0x100432107` / `0x10043210b`. Thus unchecking rejection resets to unrated, without restoring an earlier star value. |
| `-[RKCropStraightenGestureTracker rotate:]` | `0x10042f5e6` | Adds rotation delta, bounds at **-45 / 45 degrees**. Formula and typed constants verified in earlier assembly records below; fallback float conditions are unreliable. |
| `-[RKSelectionMgr a_liftAdjustments:]` | `0x100049366` | Calls lift with **metadata=0, adjustments=1, changeTool=0**; checks availability and suppression preference before a no-adjustments alert. Does not establish proprietary stamp merge behavior. |
| `+[RKWorkspaceController toggleFlagOnVersions:]` | `0x1000584e5` | Delegates to an imported class and sets undo/action information. Does not establish a batch flag-toggle formula. No new flag rule is invented. |

Reference chains: `_node:adjustRatingBy:` string `0x100599af9` → method entry `0x10074be48` → implementation `0x100032854`; scripting setter `0x1005c48c2` → `0x10079fb48` → `0x1001c35de`; reject `0x1005fbecf` → `0x100825698` → `0x1004320d4`; rotate `0x1005946ca` → `0x100824840` → `0x10042f5e6`. Search evidence `ev_dea4e27c04f678e11b120d297eb2868b4cebbe26ac40efc87bfc55674305fb01`; method pointer evidence is retained in the trace. Settings/message search `ev_45286740e7b5a9d8a1dbb43b7104937cc73b37cdbe6d03b9da91d3e335cbeb49` found `RKLiftStampToolReplaceOnStamp` and `noLiftedAdjustmentsMessage`; CFString reference `0x1008a89e8` leads to lift code `0x100049441` (`ev_fbba1dd596450df41132f1256e31a31bc59acfb5235b5d1c0922248f3d8b9b19`).

Current pseudocode evidence: rating delta `ev_620c00281705f448f3af27f9aceeb1075a998abb2e693a0ad19eca672459e96b`; bounds `ev_985011a10bf1628babcf021296a083d74eeb999e81b9123018465f540f4b4f0d`; rejection `ev_f75d430788a434ecffb3b178c05046d59b248ef53d0b37949a8a6dcf89f716f8`; straighten `ev_21c1f0b83c6f022e8ec81d4edea45f9531620d90f4c7fe89e9f795d103ce6930`; lift `ev_c28bfd9591925afb7e0441431abea970f5580f99eb867213e88b0b036fd89341`; flag wrapper `ev_7dbb7772831bb930a7ea9a02a9eeead6f333315637461db77c2e3024081b84ec`. Assembly evidence: delta `ev_6228704d1dfc57f749806966a90c8bebb1bed34a8112571fc0eb0db5adde1f85`, bounds `ev_b62d895ddfe01394adaa86d57addd08c24d8252e207e133b586f92ef7512913f`, rejection `ev_0e0116876ce19cb8bf16b89bbc4e528a5541632134a6a7c872300293fd5f0fd8`.

**Build change:** the new native Rating menu raises/lowers by one and rejects/unrejects using `Workspace.adjustRating(by:)` and `setRejected(_:)`. The inspector now calls these same actions. Both paths use `RatingRules`, save through the existing edit operation and participate in Undo/Redo. For example, raising 4 gives 5; lowering 0 gives -1; unrejecting -1 gives 0. Menu placement, labels, unit step, disabling at limits and integer-overflow protection are independent interface/safety choices. Existing straighten/crop/filter rules remain in use. Proprietary pixel/RAW rendering, catalogue relationships and stamp merge rules remain unresolved.

Only the native macOS Swift app is present. There are no maintained web/PWA, mobile or separate desktop-wrapper sources in this workspace. Validation results for this pass are recorded in `VALIDATION.md`; Intel, older macOS and physical mobile devices are not validated.

## Latest pass: crop options traced from the main executable

Reopened `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open` in confirmed Deep mode, SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Searched names, settings and messages with `native_strings_find`, then followed CFString references and Objective-C method implementation pointers. Full tool results are in `evidence/crop-options-main-trace.json`. Seven `native_function_pseudocode` calls were made sequentially, awaited and read individually. All seven completed using the fallback lifter because Ghidra returned no result; none is represented as successful Ghidra output.

| Function | Address | Recovered result |
|---|---|---|
| `-[RKCropToolController _calculatedAspectRatioFromUI]` | `0x1001e709b` | `abs(width)/abs(height)` normally; `abs(height)/abs(width)` when `rotationAsInteger` is exactly **90** or **270**. |
| `-[RKCropToolController _widthAndHeightFromUI:height:]` | `0x1001e6fde` | Reads the same two numeric controls and branches on 90/270 to exchange dimensions. Fallback flag handling is incomplete; the ratio formula above is independently verified in assembly. |
| `-[RKCropToolController aspectRatioChanged:]` | `0x1001e8619` | Routes a ratio change through controller updates and a saved preference. This is not the crop rectangle solver. |
| `-[RKLiftStampTool shouldStampAdjustmentsOntoVersionRef:]` | `0x1000bb32d` | Tests option masks **32** and **1**, lifted objects and a target predicate. Mask meanings and imported predicate remain unresolved; no replacement/merge formula inferred. |
| `-[RKFileNamingManager exportMasterMetadataMode]` | `0x1004a53ab` | Reads integer preference `masterExportMetadataMode` through `standardUserDefaults` and `integerForKey:`. Does not reveal the mode mapping, default, JPEG quality or metadata embedding policy. |
| `-[RKSelectionMgr a_liftAdjustments:]` | `0x100049366` | Calls Lift with metadata **0**, adjustments **1**, changeTool **0**; checks lifted data and optional no-adjustments warning. |
| `+[RKLiftStampTool initialize]` | `0x1000babff` | Registers numeric **0** for `RKLiftStampToolReplaceOnStamp`, consistent with the earlier trace. This is only a preference default. |

**Ratio evidence:** search `ev_8cfe1405003903b4a038544b13ac4dc7b921f54096a00e5bc5fb6b8782e71bdc`; method pointer `0x1007a87e8` → `0x1001e709b` (`ev_8c76045254c93b554713a4a7b780eb9b37bd666272929ff95b9a95e5e349c26a`); pseudocode `ev_5dd53ca4d1e0441dca3696ac291bc1d0137bbb2e7bbf664333001c7f72957104`; complete assembly `ev_54832cd6c965f7d77efb50427bf7fb615b412f2294aca841f24086dc07563fea`. Selector `0x1008683a8` is `doubleValue` and `0x10086f280` is `rotationAsInteger` (`ev_415d4d584314012c3b0bbb43a788943da11965456f8c52301a6beb02733898e4`, `ev_c6ca4933556093a56de0f5692a1fbb4baa2edfb9c3951121c3ea62398d0b5882`). Bytes at `0x100551d10` are `ffffffffffffff7f` twice, the **0x7fffffffffffffff** sign-clearing mask (`ev_767d94fda04003de5ad85e5576ab1b8071ee08f8c15138b2f054ef6ee2644c26`). The decimal u64 output rounds this mask, so the exact bytes, not the rounded number, establish absolute value. Comparisons at `0x1001e7117`/`0x1001e711d` use 90/270; divisions at `0x1001e7125`/`0x1001e712b` establish the two formulas.

**Build integration:** `CropRules.aspectRatio` implements that formula. Custom ratio fields, pixel ratio updates and locking the current crop use it. The UI operates on an already rotated render, so these calls use display coordinates (rotation 0); the helper's source-coordinate 90/270 branches are tested separately. The custom ratio UI, rejection of zero/nonfinite/overflow input, fitting/centering, pixel rounding and remembered lock behavior are independent implementation decisions. Existing stored positive aspect values keep their meaning. Export defaults and selective Stamp behavior remain independent implementations; proprietary crop solving, RAW rendering and full catalogue fidelity remain unresolved.

Only the native macOS Swift application is maintained here; no web/PWA, separate desktop implementation or mobile sources were found. Build and test results for this pass are recorded in `VALIDATION.md`.

## Fresh main-program traces — 8 November 2026

Opened `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open` in Deep mode; hash matches the original below. Fresh `native_strings_find` searches covered action names, `RKLiftStampToolReplaceOnStamp` and `noLiftedAdjustmentsMessage`. Followed string references, Objective-C method pointers and selector references. Complete records: `evidence/current-main-program-trace.json`.

Completed and read **nine sequential, awaited `native_function_pseudocode` results**, one per call:

| Main-program function | Address | Result and scope |
|---|---|---|
| `-[RKSelectionMgr a_liftAdjustments:]` | `0x100049366` | Passes metadata=0, adjustments=1, changeTool=0; checks lifted data and optional alert. Message CFString `0x1008a89e8` is referenced at `0x100049441`. |
| `-[RKWorkspaceController a_flagVersion:]` | `0x1000585bc` | Dispatches through `toggleFlagOnVersions:`. Method-name pointer `0x1007512e8`, implementation pointer `0x1007512f8`. No batch inversion policy established. |
| `+[RKWorkspaceController toggleFlagOnVersions:]` | `0x1000584e5` | Delegates flag work and registers an undo action. Fallback loses a conditional selection; no batch-toggle formula inferred. |
| `-[ImportBrowserController a_flagVersion:]` | `0x100125886` | Empty return. Identical action names in different controllers do not establish identical behavior. |
| `-[RKFilterFieldController setFlaggedFilter]` | `0x100157c47` | Creates or updates query type **22 (0x16)**, property `RKVersionIsFlagged`, qualifier **5 (equals)**, integer first value **1**, enabled **1**. |
| `-[RKFilterFieldController setRatingFilterIndex:]` | `0x100157a19` | Re-read table dispatch; earlier table decoding below remains required. Index 6 disables the rating predicate. |
| `-[RKScriptingVersion setScriptingMainRating:]` | `0x1001c35de` | Re-read setter; fallback mishandles conditional moves. Earlier assembly/constants establish `min(5,max(-1,rating))`. |
| `-[RKCropStraightenGestureTracker rotate:]` | `0x10042f5e6` | Re-read addition/comparisons. Earlier assembly/typed constants establish `min(45,max(-45,current+delta))` for finite inputs. |
| `+[RKLiftStampTool initialize]` | `0x1000babff` | Re-read registration of default **0** for `RKLiftStampToolReplaceOnStamp`; does not establish the merge algorithm. |

All nine reported `deep_engine_unavailable`: Ghidra returned no result and the tool supplied its built-in register-level decompiler. These are completed fallback decompilation reads, not successful Ghidra decompilation or evidence of full application fidelity.

**New verified flag rule:** `flaggedOnly ? (flagged == true) : true`. Assembly `ev_8de68cf92bf67eda93f7405436fe7434677f01984bf25c961d6509586bc7dbed` confirms immediates and the `RKVersionIsFlagged` import; pseudocode `ev_13b48217bfad429241772433d90d1f672ae57bfd1b3257c896bfcce60bfd310f`. Selector `0x100873548` resolves to `setQualifier:`, `0x1008728d0` to `initWithQueryType:propertyKey:qualifier:firstValue:secondValue:`, `0x10086b040` to `setIsEnabled:`. Constructor selector `0x100869190` resolves to `numberWithInteger:` at `0x10059353d`, checked by bytes `ev_9d843d7978609618e62865931a2cd1a2881b2f961bf4bed29b18b6a34f43ba4b`. Qualifier 5's meaning uses earlier verified RedRock comparator evidence below.

**Build integration:** `BrowserFilterRules.includes` now owns this recovered predicate and composes it with the recovered rating predicate. The native browser uses it, and rating comparisons use `RatingRules` constants instead of duplicated literals. This consolidates existing correct visible filtering behavior. Composition with project/album/text filters is our policy; no original global filter reset policy is inferred. Proprietary rendering, crop solving and catalogue semantics remain unresolved. Only the native macOS implementation exists; no web/PWA or mobile variant is present.

## Current pass: restored straighten bounds — 8 November 2026

Reopened the original main executable with `core_target_open` in confirmed Deep mode (SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`). Searched action names, settings and messages with `native_strings_find`, followed references and Objective-C method pointers, and completed **six separate sequential, awaited pseudocode reads**. Each result was read before the next call. Full records: `evidence/restored-angle-decompilation.json`. All six reported `deep_engine_unavailable`: Ghidra returned no result and the service supplied fallback pseudo-C. Assembly and typed data were checked for the numeric claims below.

| Function (unslid main executable address) | Recovered behavior |
|---|---|
| `-[RKCropStraightenGestureTracker rotate:]` **0x10042f5e6** | **next = min(45, max(-45, current + rotationDelta))** for finite inputs. Addition **0x10042f6f0**, comparisons **0x10042f6f4–0x10042f710**; f64 **0x100551808 = -45**, **0x100552090 = 45**. Pseudocode `ev_21c1f0b83c6f022e8ec81d4edea45f9531620d90f4c7fe89e9f795d103ce6930`; assembly `ev_e120649baf1ea97117849e9ff15227a88a1357503acaa127f04e6093a2feb462`. |
| `-[RKCropStraightenOSC rotate:]` **0x100428302** | Forwards the rotate event to its tracker. String **0x1005946ca** → method entry **0x100823e70** → implementation pointer **0x100823e80**. Tracker pointer **0x100824850** resolves **0x10042f5e6**. No additional angle formula is inferred. |
| `+[RKLiftStampTool initialize]` **0x1000babff** | Registers **0** for preference `RKLiftStampToolReplaceOnStamp`: `numberWithUnsignedInteger:0` → `dictionaryWithObject:forKey:` → `registerDefaults:`. The zero argument is explicit at **0x1000bac22**. Assembly `ev_95729f6ce2efaa78b3a09396283fc26c40d7fc265822982dcb15752fac916fab`; selector resolutions are in the JSON. This default does not establish append/merge rendering semantics. |
| `-[RKLiftStampTool setReplaceOnStamp:]` **0x1000bc6a1** | Stores the supplied preference boolean through CFString **0x1008af268**; no merge formula is present. |
| `-[RKSelectionMgr a_liftAdjustments:]` **0x100049366** | Adjustment-only lift routes flags **metadata=0, adjustments=1, changeTool=0** and checks lifted-data availability before an optional alert. Message **0x10055a0c8** → CFString **0x1008a89e8** → code **0x100049441**. |
| `-[RKBrowserController a_setFlaggedFilter:]` **0x1000145ae** | Forwards to `setFlaggedFilter` through selector **0x1008686c0**, reference **0x1000145bd**. No batch-toggle rule is inferred. |

**Build change:** restored adjustment recipes and catalogue saves now use the verified **[-45°, 45°]** bounds through `StraightenRules.clamp`. Previously the renderer clamped but decoding could show 90° in the inspector while rendering 45°. Loading 90° now restores 45°; loading -90° restores -45°; valid 12.5° stays 12.5°. Crop, photo identity, schema version and original files are preserved. Applying the gesture bounds at the catalogue boundary is our consistency policy, not evidence of Aperture's database-repair behavior. Nonfinite fallback to zero is also an independent safeguard.

The rating clamp, filter table and delta formulas documented below remain implemented. Proprietary RAW/pixel processing, crop solving and stamp merging remain unresolved; the recovered zero preference is documented but is not used to invent a merge algorithm. Only the native macOS app is maintained here; no web/PWA, desktop wrapper or mobile variant exists. Arm64 macOS 14+ is built; Intel, older macOS and device-specific execution are untested.

## Current session: rating delta implementation — 8 November 2026

Opened the original main executable again with `core_target_open`; session confirmed Deep mode and SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Ran `native_strings_find` for action names, the replace-on-stamp setting and the missing-lift message. Followed selector and CFString references, then made **six separate, sequential, awaited `native_function_pseudocode` calls**, reading every complete result before proceeding. Full fresh results: `evidence/rating-delta-decompilation.json`. Identical reads can retain the same evidence IDs as earlier sessions.

| Main executable function | Observed rule / limitation |
|---|---|
| `_node:adjustRatingBy:` **0x100032854** | Reads current node rating, adds supplied integer delta at **0x100032879**, and passes the sum to `_node:setRating:`. Pseudocode `ev_620c00281705f448f3af27f9aceeb1075a998abb2e693a0ad19eca672459e96b`; full assembly `ev_6228704d1dfc57f749806966a90c8bebb1bed34a8112571fc0eb0db5adde1f85`. Selector **0x100869e88** resolves `_nodeRating:` and **0x100869e98** resolves `_node:setRating:`. |
| `_node:setRating:` **0x100032740** | Tracks rating-change state and forwards to `changeMainRating:` on an editable version. Does not itself establish clamping. Pseudocode `ev_679aabab281aeab860b21d83f14d534c38cf9be427facefaadb150766c9c2ab7`. |
| `a_adjustRating:` **0x100046fd8** | Forwards to `_changeRating:adjustRating:` with adjustment mode **1**. This is a mode flag, not evidence that every action increments by one. Pseudocode `ev_e5947f8a05f828ef1910bb3eb628f541a87858f8f816332199f75b02ab678386`. |
| `setScriptingMainRating:` **0x1001c35de** | Re-read pseudocode and full assembly: **min(5,max(-1,requested))**, using the RedRock constants verified below. Assembly's signed branch and conditional move correct the fallback output. Evidence `ev_b62d895ddfe01394adaa86d57addd08c24d8252e207e133b586f92ef7512913f`. |
| `a_liftAdjustments:` **0x100049366** | Sends metadata=false, adjustments=true, changeTool=false; tests lifted-data availability before the suppressed-alert branch. Message CFString **0x1008a89e8** has code reference **0x100049441** (`ev_c9efe6f752ea265c87ed69e50299bb3eece0ec97a5310cc441dc7e68782c0110`). No pixel formula is present. |
| `setReplaceOnStamp:` **0x1000bc6a1** | Writes the supplied preference boolean via CFString **0x1008af268** for `RKLiftStampToolReplaceOnStamp`; not a recovered stamp-merging algorithm. Pseudocode `ev_25bc8dc4cedc50103ace42e25b2e55769c90ba15f057fb24e28e62f472c7184e`. |

All six reads report `deep_engine_unavailable`: Ghidra's bridge gave no result, and Craft Anything returned fallback register-level pseudo-C. Assembly and selector reads verify the delta addition; no claim of recovered high-level source is made.

**Build change:** `IsoniqueCore.RatingRules.adjusting(_:by:)` combines the observed addition with the separately recovered valid user bounds: **next = min(5,max(-1,current+delta))**. New Lower Rating / Raise Rating buttons in the Info inspector use −1/+1 deltas, existing save and Undo/Redo, and stop at the bounds. Thus rejected −1 raised once becomes unrated 0; unrated 0 lowered once becomes rejected −1. Button placement, unit steps, combining these two original paths, and protection against Swift integer overflow are implementation choices; the original node path's own overflow/clamp behavior is not established. Catalogue schema and stored integers remain compatible. Tests cover all seven rating states in both directions, bounds and overflow protection.

Only the native macOS Swift implementation is maintained here; no web/PWA or mobile implementation exists. Current build targets arm64, macOS 14+. Intel and older macOS execution, actual camera RAW files, original rendering and proprietary catalogue fidelity remain unvalidated.

## Fresh main-program trace and rebuild — 8 November 2026

Reopened `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open` in confirmed Deep mode; SHA-256 remains `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Searched names, settings and message keys with `native_strings_find`, followed string/selector/CFString references, and completed **eight sequential, individually awaited pseudocode reads**. Every result was read. Full fresh tool records are in `evidence/fresh-mechanics-decompilation.json`. Ghidra returned no result for all eight; these are fallback pseudo-C reads, with assembly/data verification where stated.

| Function (unslid main executable address) | Read result and implementation |
|---|---|
| `-[RKBrowserController a_setFlaggedFilter:]` `0x1000145ae` | Forwards to selector `setFlaggedFilter`; string `0x100590e2e` → selector `0x1008686c0` → code `0x1000145bd`. |
| `-[RKFilterFieldController setFlaggedFilter]` `0x100157c47` | Configures flag predicate (type `0x16`, qualifier `5`, boolean `1`) and enables it; current Flagged scope uses the photo boolean. Tail-call side effects are unresolved; no reset of other filters is inferred. |
| `+[RKWorkspaceController toggleFlagOnVersions:]` `0x1000584e5` | Workspace/undo routing is visible, but the lifter drops conditional operations. No new batch-toggle rule is inferred. |
| `-[RKCropStraightenGestureTracker rotate:]` `0x10042f5e6` | For finite inputs, **next = min(45, max(-45, current + rotationDelta))**. Assembly `0x10042f6e0` converts the event float to double; `0x10042f6f0` adds the current double; `0x10042f6f4`–`0x10042f710` clamp it. Typed f64 data: `0x100551808=-45`, `0x100552090=45`. |
| `-[RKSelectionMgr a_liftAdjustments:]` `0x100049366` | Lift routing supplies metadata=false, adjustments=true, changeTool=false; checks lifted data before the conditional alert. Message key `noLiftedAdjustmentsMessage` `0x10055a0c8` → CFString base `0x1008a89e8` → instruction `0x100049441`. It does not recover a pixel or selective-stamp formula. |
| `-[RKScriptingVersion setScriptingMainRating:]` `0x1001c35de` | Re-read the rating setter; the earlier assembly/RedRock verification below establishes `min(5,max(-1,requested))`. Fallback pseudo-C omits the conditional move and is insufficient alone. |
| `-[RKMetadataRatingItemView changeReject:]` `0x1004320d4` | Re-read reject routing; earlier assembly below establishes checked → `-1`, unchecked → `0`. The fallback omits the conditional move. |
| `-[RKFilterFieldController setRatingFilterIndex:]` `0x100157a19` | Re-read enable-byte/table routing; the typed table and comparator evidence below establish the full filter truth table already used by the build. |

Fresh string searches: `ev_dbd0745bb553052d24d6efca73d7b6875541339ac0329f1da7b2d1eb088dca1f`, `ev_1a2d70f50d90c796b3f8f5d717167bcb36cca8c915656808d22b54e62634fcdf`. Flag selector reference evidence: `ev_be08976e3a233b0867c4f9c9cb6edc92c13065237101b3adddad5ab168af242c`. Straighten pseudocode: `ev_21c1f0b83c6f022e8ec81d4edea45f9531620d90f4c7fe89e9f795d103ce6930`; assembly: `ev_e120649baf1ea97117849e9ff15227a88a1357503acaa127f04e6093a2feb462`; bounds data: `ev_a0e96d79eafba3d9f5424faa30bcd35d8002c59223ab8e32529938a195d067e1`, `ev_d5c238df7aa81e53967ec0e2e8063ff20c1541121c8f8c4d53734ee3ef39dd17`. The JSON records every other read and its evidence id.

**Build change:** `StraightenRules.applying(rotation:to:)` now implements the recovered incremental formula, and the Straighten strip has minus/plus controls wired through `Workspace.nudgeStraighten`. They use 0.1° deltas; that button step is our UI choice, not a recovered original constant. Clamping happens on each input (44 + 10 → 45; then −2 → 43). Edits use existing persistence and Undo/Redo. A nudge that leaves the angle unchanged preserves crop; changing geometry clears it under this build's existing crop policy. Nonfinite deltas are ignored as a reconstruction safeguard, not an original rule. No catalogue schema change is required. The original crop solver and trackpad event handling are not reproduced by these buttons.

Only the native macOS implementation exists in this workspace. No independent web/PWA/mobile variant was found. Original RAW/pixel formulas, proprietary catalogue relationships, presets and selective-stamp semantics remain unresolved; those parts retain the explicitly independent implementations documented below.

The current build is a separate SwiftUI implementation. The Deep-mode follow-up below recovers rating behavior and distinguishes verified constants from unresolved image processing. It does not establish full Aperture compatibility.

The runtime checklist in `mechanics.json` uses the checker-supported version 1 schema and scalar values. Historical startup constants and GNG adjustment metadata that this implementation does not execute are preserved, with their original values and sources, in `evidence/legacy-mechanics.json` and the findings below. They are not runtime implementation claims. The legacy pixel formulas remain unresolved.

## Inspector and rating-filter decompilation — 8 November 2026

Freshly opened the original main program with `core_target_open` at `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` (SHA-256 `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`), in confirmed Deep mode. This pass completed **11 individual, sequential, awaited `native_function_pseudocode` calls**. All results were read; none were left running. Full records are in `evidence/inspector-decompilation.json` and `evidence/inspector-reference-followup.json`. Ghidra returned no result for these calls; the fallback lifter supplied the pseudo-C. Only assembly/data-verified comparisons below are applied as recovered runtime rules.

### Rating filter: reference chain and actual runtime rules

`native_strings_find` `ev_721f002c9f86b78703de1fa811affa7577e1d516948eae58d3d3f030f1f7082a` found `setRatingFilterIndex:` at `0x100590dfe`, referenced by selector `0x1008686b0`. Following that selector (`ev_0cda5f008512253e3cfaf378003acc3ff076cac9cb032b0551dd82371869ba6c`) leads to browser action `-[RKBrowserController a_setRatingFilter:]` **0x100014532**, plus fullscreen actions. Its completed pseudocode (`ev_899ef66eed120d8e59c92d00ae10641debf4b5866c9ff2573a51728faf129d86`) forwards the sender's value to the filter controller. Function lookup `ev_b3f3e7cf5d2f4fe5d86f0479d01ebba100079944959a67ab5726fe0210b26da4` resolves the implementation.

`-[RKFilterFieldController setRatingFilterIndex:]` **0x100157a19**, pseudocode `ev_80724a82ed999943771eae99a1526f87df36086a5ab66234bd4a445db0d16aa2`, complete assembly `ev_bb58ca1c6433723d4f6d9e201febf431aa309159bf626a1c9ef0e7371d2be2d6`:

- Checks unsigned `index - 1 <= 7`. For valid indices, enable byte comes from `0x0101000101010101 >> (8*(index-1))`; index 6 disables the rating predicate.
- For enabled valid indices, reads qualifier from `0x100551590 + 8*(index-1)` and rating from `0x1005515d0 + 8*(index-1)`.
- Typed i64 reads establish qualifier table **[8,8,8,8,5,8,5,5]** and value table **[1,2,3,4,5,0,0,-1]**. All 16 evidence records, addresses and values are retained in the JSON.
- Other indices configure qualifier **8**, value **0**, enabled=true. Index 6 skips table application and disables the predicate. Resolved selectors `0x100873540=disableWithNoNotification`, `0x100873548=setQualifier:`, `0x100873530=setFirstValue:`, `0x10086b040=setIsEnabled:` are recorded in the evidence.

To establish qualifier meanings rather than guess enum values, opened the original **RedRock** executable (`Contents/Frameworks/RedRock.framework/Versions/A/RedRock`, SHA-256 `54d844fb55bce0cc4f0c882374cc51d3f58d324aa8b0d60b83acfa35be864e86`). Read `+[RKWherePredicate convertQualifierToComparator:]` **0x43759**, pseudocode `ev_930580690ccf8b8fc561069eec030023d2ea9d1a43c9df3d58680537d3648226`, assembly `ev_74c28bc8f4ed32a6e9fcdd32643d4bafb1bd93fd30c6739ad36832bcd0b88981`. The assembly sign-extends the jump-table entries (the fallback pseudo-C incorrectly shows unsigned). Qualifier 5 uses i32 `0x437d0=-72`, jumping from base `0x437c0` to `0x43778`, returning CFString `0x6800d0`; its pointer at `0x6800e0` targets **"="** at `0x40af7d` (`ev_e906d373570f72ea5a2530b3dfdbe7f9faa2dd2fe1ac1a2147de804afde6a1c8`). Qualifier 8 uses `0x437dc=-18`, reaches `0x437ae`, returns CFString `0x68fb50`, pointer `0x68fb60` targets **">="** at `0x418633` (`ev_98939b54032a498fe438f254176d63452147ab8c1162563c13bb09df6e2a22dc`). Reopened the main executable afterward.

| Original index | Recovered predicate | Build behavior |
|---|---|---|
| 1–4 | rating >= index | Corresponding star threshold |
| 5 | rating = 5 | Five stars only |
| 6 | Predicate disabled | All ratings, including rejects |
| 7 | rating = 0 | **Unrated only**, newly implemented |
| 8 | rating = -1 | **Rejected only**, newly implemented |
| Other (including 0) | rating >= 0 | Existing Unrated and above choice |

`IsoniqueCore.RatingFilter` encodes these actual indices and predicates. The native picker and browser filtering now use this shared rule instead of treating every option as a minimum threshold. Catalogue data and schema are unchanged. Regression coverage compares the complete filter truth table over ratings -1…5, including all/rejected/unrated distinctions. UI labels and placement are our own.

### Additional inspector functions read, with explicit limits

Names/settings/messages search `ev_4c8682ea4f32b41600cb8b5caf889cec21e75c767c8e36b3ba2942979b0f3763` finds `inputTemperature`, `inputTint`, preset keys and `noLiftedAdjustmentsMessage`. The message's CFString **base** `0x1008a89e8` has a code reference in `-[RKSelectionMgr a_liftAdjustments:]` **0x100049366** (`ev_5d97b892c42fb5b28da82b8ef3f4a9c38796d4b39b60f3444c21b69fd6394d11`). Re-read its complete pseudocode `ev_c28bfd9591925afb7e0441431abea970f5580f99eb867213e88b0b036fd89341`: adjustments-only lift sends metadata=false, adjustments=true, changeTool=false; if `hasLiftedData` is false and the suppression setting is false it routes a localized alert. These are keys, not English text; no invented original dialog is supplied.

The same settings search finds `RKLiftStampToolReplaceOnStamp` at `0x10055f075`. Read `setReplaceOnStamp:` **0x1000bc6a1** (`ev_25bc8dc4cedc50103ace42e25b2e55769c90ba15f057fb24e28e62f472c7184e`) and `replaceOnStamp` **0x1000bc6e2** (`ev_7ce2c153f1afd2e89b9e1786dae18c6929d389877cee5f5018711d7dd0f8f918`). They route a stored boolean through preferences. They do not recover the proprietary append/replace adjustment algorithm, so no new replacement semantics are claimed.

White-balance selector `setTemperatureAndTintFromX:andY:` **0x1005ec597** → `0x10087ea90` → call at `0x100374bc8` inside **0x100374791** (`ev_504c7f9f4d2314f9f117fd556e1b0b8501886e323177d7147f62f38142b367df`). Completed reads:

- `-[DGWhiteBalanceController _setTemperatureAndTintForRawV2Color:]` **0x100374791**, `ev_a4505ea8d06a9f6bb538bb3d2c22549eac5f38fbee9dccb9017fbe25154fa6d9`: ImageIO RAW reconstruction/property routing; unstructured fallback loops prevent a complete formula claim.
- `setTemperatureAndTintFromX:andY:` **0x100376040**, `ev_2be6385d6d0d35d26559f62fa82483e531459e99122fded4bddfdfe10d101810`: calls imported `_DG_XYToTempTint_dng`, then assigns two resulting values. Conversion implementation is outside this function.
- `setTemperatureAndTintFromXYZ:` **0x100375f74**, `ev_d9708b56a853ecdbcdcc409db19bb0ebf64c184d7f7e8ea6d17a0a55057c4267`: inline assembly computes `sum=X+Y+Z`, `x=X/sum`, `y=Y/sum`, calls `_DG_XYToTempTint`, then assigns results. This sampling conversion is not the build's normalized warmth control or a recovered pixel-rendering formula.
- `-[RKQueryRating qualifiers]` **0x10012a776**, `ev_5f0668a3426be9297a800028b5d36b5ea85ab5e170ec7cedbb572085a5c32287`, and RedRock `+[RKWherePredicate searchFormatForQualifier:]` **0xe4b4d**, `ev_048d9b3bf135cfe47b211a9044b208f980645470ac210ed276e169f5d3cb0a66`: read fully as supporting query routes; not needed for the verified numeric comparisons.

Warmth/tint, shadows/highlights, the four named presets and selective stamp groups remain independent implementations. Their original pixel formulas, ranges, defaults, color spaces and group mapping have **not** been established by these reads. Do not relabel these as recovered just because related controllers were read. Original rendering, full import/export/catalogue fidelity and preset recipes remain open work.

Only a native macOS Swift implementation exists in this workspace; no web/PWA, independent desktop shell or mobile source exists. This pass changes that sole maintained variant. Validation is recorded in `VALIDATION.md`.

## Deep-mode follow-up — 8 November 2026

### Editing-tool follow-up after the toolbar build

Reopened the original **main program** at `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture` with `core_target_open`. SHA-256 remains `ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4`. Session explicitly reports Deep mode. Ran fresh `native_strings_find` searches for names, settings and messages, followed their references, and awaited and read all nine new `native_function_pseudocode` results individually. Complete results are in `evidence/editing-decompilation.json`; the straighten assembly is in `evidence/straighten-assembly.json`. Ghidra again returned no result; every pseudo-C result uses the fallback lifter. Floating-point branch conditions in that output are unreliable; the clamp below is established by assembly and typed data reads.

**Reference trail.** Search `ev_ba0aaed57cb33d1cd8f04bd7db282f0fb0a1342dc4411c31c46e3f2b3a9cef66` locates `lift:metadata:adjustments:changeTool:` at `0x100599dc7` → method metadata `0x100765148` and selector `0x10086af20` (xref `ev_9a3f89c179da57011d0e4ae4da9431064b610fb09c377454aaa885688bb54f9f`). Method-name lookup `ev_1574b46e29a7e503cf64cbfdb4e94b87ab057fe214e438e50429ba6477d70853` identifies implementation `0x1000baca6`. Crop/settings/message search `ev_23ec28543c624f6dc1e1f01470c7d04009b43200e8d704b2ed969d04743288f8` also finds `CropLastCustomRatioSelectedByUserKey`, `_cropRatioForTag:`, `noLiftedAdjustmentsTitle` and `noLiftedAdjustmentsMessage`. The last two strings are localization **keys**, not recovered English dialog text. The lift action references their CFStrings and queries `hasLiftedData` via selector `0x10086a650` (resolved by `ev_b4fdb03e90f5f04c31ead62ca9d7eef1cfb31957f7fa322db36088578926a38c`). Objective-C metadata and resolved method names connect these functions; static xrefs alone do not resolve dynamic dispatch.

| Recovered rule | Function and evidence | Build use |
|---|---|---|
| For finite gesture inputs, `angle = min(45, max(-45, currentAngle + event.rotation))` | `-[RKCropStraightenGestureTracker rotate:]`, `0x10042f5e6`; pseudo-C `ev_21c1f0b83c6f022e8ec81d4edea45f9531620d90f4c7fe89e9f795d103ce6930`; complete assembly `ev_e120649baf1ea97117849e9ff15227a88a1357503acaa127f04e6093a2feb462` | `StraightenRules` supplies recovered bounds to both slider and shared preview/export geometry. Slider now reaches ±45° rather than ±20°. It supplies an absolute angle; this build has no rotation gesture. |
| Minimum `-45.0`, maximum `45.0` | Original f64 data `0x100551808` / `0x100552090`, reads `ev_a0e96d79eafba3d9f5424faa30bcd35d8002c59223ab8e32529938a195d067e1` / `ev_d5c238df7aa81e53967ec0e2e8063ff20c1541121c8f8c4d53734ee3ef39dd17`. Assembly adds at `0x10042f6f0`, compares lower at `0x10042f6f4`, upper at `0x10042f6fa`, stores at `0x10042f710`. | Both renderers already shared geometry; they now share named recovered bounds with the control. Nonfinite → 0 remains our defensive policy, not a recovered original rule. |
| Adjustments-only lift passes metadata=false, adjustments=true, changeTool=false | `-[RKSelectionMgr a_liftAdjustments:]`, `0x100049366`; `ev_c28bfd9591925afb7e0441431abea970f5580f99eb867213e88b0b036fd89341` | Existing Lift/Stamp retains photo metadata. No original HUD or proprietary adjustment serialization is claimed. |
| Missing source version returns before clipboard reset; valid source resets lifted items, then conditionally captures metadata/adjustments | `-[RKLiftStampTool lift:metadata:adjustments:changeTool:]`, `0x1000baca6`; `ev_513872242fa034fbba0578efb2141f5f25798ea66adba54c1277cf43cc34141e`. Resolved selectors `_versionRefForNode:` at `0x10086f250` and `_resetLiftedItems` at `0x10086f258`: `ev_d57fec1f253bb1bda84e223944cc0cafd76d8f27e9d13f41cef230a81c180dea`, `ev_fe3c8c417ba8b87dda372e4072a168685b820b52246f4b291d3baac8ee82fd22`. | Lift now returns without clearing the clipboard or reporting success when no photo is selected. Supported adjustment snapshot replaces the prior snapshot when a photo exists. |

**Additional functions read completely, with limits.**

- `-[RKCropToolController _cropRatioForTag:]` `0x1001e6e8b` (`ev_4a81a1590c61545c7ca8367850d428114993a1952a74b0b431440f10df62f321`) routes special negative tags and divides two values. Exact menu definitions are not recovered; this build's preset list is independent.
- `-[RKCropToolController _calculatedAspectRatioFromUI]` `0x1001e709b` (`ev_5dd53ca4d1e0441dca3696ac291bc1d0137bbb2e7bbf664333001c7f72957104`; checked against assembly `ev_54832cd6c965f7d77efb50427bf7fb615b412f2294aca841f24086dc07563fea`) reads two double controls, clears their sign bits, and divides second/first for rotation integers `90` or `270`, first/second otherwise. Selector `rotationAsInteger` at `0x10086f280` resolved in `ev_c6ca4933556093a56de0f5692a1fbb4baa2edfb9c3951121c3ea62398d0b5882`. This is a master-coordinate UI conversion; our crop presets operate directly on the displayed, already rotated image. Applying another reciprocal there would change their meaning. No claim of original crop rectangle fidelity.
- `-[RKCropToolController resetCrop:]` `0x1001e8cfb` (`ev_abc7ad2c8513e6ecd36ea698ed5693fc4f21ac6b23614b18359c6f93012b1658`) supplies `NSZeroRect` then tail-dispatches. Our optional crop reset is independently represented by nil.
- `-[RKSelectionMgr a_rotate:]` `0x100048d2f` (`ev_1721d9b6dccea608ec05a50eeb442e80ff24334ed851ec147e1291553ecf9c55`) routes selection, modifiers and undo. Fallback reconstruction has unstructured loops and is insufficient to establish orientation arithmetic or crop preservation.
- `-[RKLiftStampTool shouldStampAdjustmentsOntoVersionRef:]` `0x1000bb32d` (`ev_fa892879fadc695ccb7e99207800a9bae92f55d8f4990d5599b613a17b3c7a50`) tests option masks `0x20` and `1`, stored RAW data and target eligibility. `hasLiftedData` `0x1000bc814` (`ev_aff895afcac2cda85de28b58442152d28640db5cd3dc1872c2c16b367df7e2c5`) checks multiple stored items. Our simple snapshot clipboard does not implement the original selective/RAW stamping rules.

The crop validator selector `0x1005e6fc2` → `0x10087d998` has nine incoming code references, including the rotate gesture and crop tracker (`ev_02857a012c7bcb1b7f7fad17e56c5b513b6b4177ef681c7a6d56c472364e2079`). Main-program function search found no implementation (`ev_841ad2158313b302516f6b71d4a50131813aade7bfcf35f40446907f62d43009`); the original crop solver remains unresolved. The reconstruction's centered corner trimming, rotation/crop clearing, guides, session undo, import/export and rendering formulas remain independent unless explicitly established elsewhere below. This follow-up adds verified rules; it does not establish all built workflows as original-equivalent.

Only the native macOS implementation exists in this workspace. No web/PWA, desktop wrapper or separate mobile sources were found. Catalogue schema remains version 1; stored angles and adjustment snapshots remain readable.

Opened the original main program with `core_target_open` at `/Users/williamwessex/Downloads/Aperture.app/Contents/MacOS/Aperture`. Session reports `analysis_mode: deep`, `clean_room: false`. Every requested `native_function_pseudocode` call was awaited to completion and its result read. Ghidra's bridge returned no decompiler result for every function attempted; the service supplied its built-in register-level lifter. This is a material limitation: conditional moves and floating-point instructions can be absent from its pseudo-C. Rating formulas below were checked against assembly and resolved data. Completed follow-up pseudocode records are saved in `evidence/decompilation.json`.

### Names, settings, messages and reference trail

`native_strings_find` located `mainRating`, `_node:setRatingTo:`, `_node:adjustRatingBy:`, `a_setRatingAsSelect:`, `undoChangeRating`, `RAWAdjustExposureAndBias`, `inputContrast`, `inputSaturation`, and quality settings. Search evidence: `ev_633965cfded07fd13eba86461481c4afacb2bf11977a485e40ce55dee02eaace`, `ev_1199943f1ea5c9e6dcdd1abf9f95fa84f4edbf67a776e1542890856a27f4ebe2`, `ev_073edf2fb7156259b1790658b33274511671d5640df7c8ddf1199f4b7df9d00f`.

Followed string references with `native_xrefs_list`: `_node:setRatingTo:` at `0x100599ae6` → method metadata `0x10074be60` and selector `0x10086ae10`; `_node:adjustRatingBy:` at `0x100599af9` → metadata `0x10074be48` and selector `0x10086ae18`. Matched Objective-C method names using `native_functions_search` (`ev_e11bea6c810bd19dffc778b75bf8af62822cb0f7adfca31b0a4785524784dc2f`). Static references do not resolve all Objective-C dispatch. `RAWAdjustExposureAndBias` → CFString `0x1008c8e38`, `inputContrast` → `0x1008c2598`, `inputSaturation` → `0x1008c25b8`; these searches returned no incoming code edges to the CFStrings, so no direct code linkage is asserted for those labels.

### Recovered rating values and rules — used by the build

| Rule | Original function/data | Evidence |
|---|---|---|
| `rating = min(5, max(-1, requested))` in scripting setter | Aperture `-[RKScriptingVersion setScriptingMainRating:]`, `0x1001c35de`; compare/jump at `0x1001c35ef`, conditional move at `0x1001c3601` | pseudo-C `ev_985011a10bf1628babcf021296a083d74eeb999e81b9123018465f540f4b4f0d`; corrected against assembly `ev_b62d895ddfe01394adaa86d57addd08c24d8252e207e133b586f92ef7512913f` |
| Reject checkbox on → `-1`, off → `0`; invokes `_undoableSetProperty:` | Aperture `-[RKMetadataRatingItemView changeReject:]`, `0x1004320d4`; `cmp state,1` and `cmove` at `0x100432107`/`0x10043210b` | pseudo-C `ev_f75d430788a434ecffb3b178c05046d59b248ef53d0b37949a8a6dcf89f716f8`; assembly `ev_0e0116876ce19cb8bf16b89bbc4e528a5541632134a6a7c872300293fd5f0fd8` |
| Select rating action supplies `5` | Aperture `-[RKSelectionMgr a_setRatingAsSelect:]`, `0x100046e9f` | `ev_ed07d5cb132dfb822144c9b8f32af0112b9edda9fac851f95b579ec0357a6485` |
| Set-rating action forwards requested rating; adjustment action adds delta to current rating | Aperture `a_setRating:` `0x100046e8b`, `_changeRating:adjustRating:` `0x1000329f6`, `_node:adjustRatingBy:` `0x100032854`, `_node:setRatingTo:` `0x100032933`, `_node:setRating:` `0x100032740` | `ev_1749aada692e48a137e57a8162935bc1813fe9d4f4100f2f0e001ff6d51a82f3`, `ev_0337ccfe8cfa3b66152731567c913fb8d555b06dde2efd81db6e18542eac4a95`, assembly `ev_987bcf47045fd3bdf6b69014bbc28d55cc3f0bebd5b5bfab4395ca87de0a1b08`, `ev_620c00281705f448f3af27f9aceeb1075a998abb2e693a0ad19eca672459e96b`, `ev_1576e3964e17d58da613ab696f1caf8c03a46b24cc71eec9882b68f00fecb8ff`, `ev_679aabab281aeab860b21d83f14d534c38cf9be427facefaadb150766c9c2ab7` |

The main executable imports `_kMinRating`, `_kMaxRating`, `_kInvalidRating` from RedRock. Opened that original framework and resolved its actual data using `native_data_show` (i64), rather than assuming their values:

| RedRock symbol | Address within RedRock | Value | Evidence |
|---|---|---|---|
| `_kMinRating` | `0x4a9ca8` | `-1` | `ev_8258378d501efebc84afffd6bedf46178d64bff5e9bb07e10bdb179555fda85b` |
| `_kMaxRating` | `0x4a9cb0` | `5` | `ev_be9977ff973a19b3f43591b8824c4d05f47e2eebb264de77ce6135ed9d29dba1` |
| `_kInvalidRating` | `0x4a9ca0` | `-100` (internal sentinel) | `ev_eb3bc69d939f4ba85d5f03b5e1ccb077bd690f0dedc5a660e15f8786253a2d39` |

RedRock SHA-256: `54d844fb55bce0cc4f0c882374cc51d3f58d324aa8b0d60b83acfa35be864e86`. Addresses in this document are unslid and must be interpreted in the named binary.

Implementation: `RatingRules` in `Sources/IsoniqueCore/Library.swift` centralizes these constants, the clamp formula, rejection transitions and safe star display. The native UI now sets the requested star directly, provides explicit Unrated and Rejected controls, and includes rejected photos in its All ratings filter. Catalogue version remains 1; existing integer ratings remain compatible. Invalid external catalogue integers normalize to the recovered user range on load/save. That normalization boundary and inclusive All ratings filter are reconstruction policies, not claims about Aperture's catalogue repair or default filtering. The original undo registration is observed, but this build does not yet implement Aperture's rating undo history or delta/modifier/selection actions.

### Adjustments — recovered metadata, unresolved pixel formulas

Opened original Geode framework (SHA-256 `0a535ea052ed724ee2a86ec4435e8840495da7a73cf2ab000ae5d2f0546d5aa2`) after locating its exposure/saturation/contrast names using `native_strings_find` (`ev_cf6a252c503298e792a1946385e7952799a314c597ac3c9d6bd5c34592a3b83e`). These are specifically **GNG operations**, not a proven replacement for the current app's Core Image recipe.

| Metadata | Function | Recovered values |
|---|---|---|
| GNG saturation | `+[DGGNGSaturationOperation attributes]` `0xcf49a` | default `1.5`; identity `1`; min `0`; max `2` |
| GNG contrast | `+[DGGNGContrastOperation attributes]` `0xd0d9a` | default `0.25`; identity `0`; min `-1`; max `1`; slider min `-0.5`; slider max `0.5` |

Pseudocode evidence: `ev_17159d5abd32a77a7bcbb5bcfedcf8597f22f95ac6737ae210db34b268dfecd8`, `ev_69187e07b9a1efc3789103227ca5212931ae4b52089a945b6fe39167afa19b49`. Read referenced f64 data: `0x1957b0=1.5`, `0x18fe60=1`, `0x190e90=2`, `0x191330=0.25`, `0x190c20=-1`, `0x190f70=-0.5`, `0x1905a0=0.5`; zero is supplied by `xorps xmm0,xmm0`. Evidence respectively `ev_af3cb0f9bbed1568bbab420af3b09d455dbb27eb3172b776bd082467ce3aa719`, `ev_afa3890e57d6ce0f0de5c40308ac8a64e50871c898e49efa4741bcbc112ab26c`, `ev_562242030a964af8f6e5eab612211a4d1dcd7def6d0b7fe0836992f0fc011323`, `ev_b38434808269ad2cd6ee451abc2500be354f25ba370fef34c81d40ccd7add723`, `ev_426cd18172c2105fb12089e93c6ca859dcaa201b744643c1c2ddac0da3d3bad6`, `ev_aea1379b8c58e5068c310d49e3309a3e5925ef2b3f6146a4e4be40657c13817d`, `ev_6ebe53434ba53045fca292b35e277f0d8884b173f8579a27d8194a6fb2c45d29`.

Read `-[DGGNGSaturationOperation processImage:options:]` `0xcf429` and `-[DGGNGContrastOperation processImage:options:]` `0xd0d29` completely; they wrap a filter, set its image, request output, then clear the image. They do not reveal the pixel formula. Evidence `ev_63bc4868fdfcf87ceb4eb13304443fe6991ed04156efe37e7954a7dbfc778cc7`, `ev_4617c499f15836e2564769f8663d60f155d03983e77c5a4174d05080ce8c962c`.

Main-program functions also read completely: `_updateRAWSpecificControls` `0x1002f18a9` (`ev_c57fee18a0e57ab83790d80b21d289b239bb9ab905a838ae5c6f14e00ee064c6`), `sliderChange:` `0x1002f6fc5` (`ev_e501953513da179719d2aabbd2e38f6229aeb6d8b30d94d9d2e75fb1eec90d8e`), `restoreDefaults:` `0x1002f6960` (`ev_08213fa2c8e6781fb4c24bdb4b441cd38907e230412cac28382b6f154a75192e`). They expose control routing, RAW/version gating and reset routing, not a reliable exposure/contrast/saturation pixel formula. Exposure shader, pipeline ordering, color space and camera-specific defaults remain unknown.

The current build uses its independent CPU renderer for both preview and export, neutral recipe `(0,1,1)` and UI ranges exposure `[-4,4]`, contrast `[0.5,1.5]`, saturation `[0,2]`. The CPU renderer uses exposure multiplier `2^EV` after sRGB decoding, re-encodes sRGB, computes luminance `0.2126R+0.7152G+0.0722B`, saturation `L+(channel-L)*s`, contrast `(channel-0.5)*c+0.5`, then clamps to `[0,1]`. These formulas, JPEG quality `0.95`, hash-based deduplication, JSON catalogue and verified-copy recovery are independent implementation choices, not recovered Aperture mechanics. No recovered GNG default is applied to a different renderer. Original import/export rules and proprietary library relationships are still unresolved; the present work does not claim to have reconstructed every built workflow.

## Earlier startup investigation

## Evidence quality

The main executable is Aperture 3.6, x86_64 only, SHA-256 ec5b412048e771c120c67fa4c81bdd7428fe81ff1d7bc9b50504331b5019a7a4. Triage: ev_56a80cc3b2b6794d7bba56df1de141437635416e9348bbf81c31e35f22ca9ea8.

All four requested pseudocode calls completed. Ghidra returned no result through its bridge; the service fell back to its less exact register-level lifter. Therefore the following are provisional code observations and are not sufficient to reconstruct the full application.

## Startup — function 0x10000fa98

Evidence ev_c7d447aaff6caafce1f491dfe3c64098fb6b8c7b48d48607256eb03f5c21ad15.

- Reads the OS version through Gestalt major/minor/patch queries.
- When the queried version is 10.6.4 or earlier within 10.6, and CI_DISABLE_SWITCH is unset, sets that environment variable. This is an old rendering workaround, not evidence that changing the minimum OS version would fix modern compatibility.
- Contains a separate rendering warm-up branch for 10.7 patch <= 3, with additional memory conditions that were not fully recovered.
- The memory-query fallback integer is 2147483648 bytes (2 GiB). The surrounding floating-point calculations are not reliably recovered and must not be guessed.
- A conditional diagnostic timer is configured with interval 100000000 ns and tolerance 5000000 ns.
- Starts the UI through NSProApplicationMain, supplied by the legacy ProKit framework.
- Reads RAWCAMERA_LOAD_OBJC_EARLY, FE_ENABLE_CL_RGBA_14 and RAWCAMERA_ENABLE_PRELIMINARY_SUPPORT environment settings. The pointed-to text values were not resolved; none are invented here.

## Ratings — function 0x1000bc999

Evidence ev_d7fee7ed0c0486596407de2443fcc81c6f3ba3157b25ea27b52e14d5d44db126. The RKLiftStampTool main-rating setter stores the supplied integer in an instance field. No clamping is visible in this setter. The valid range cannot be inferred from this setter alone. The original scripting definition separately exposes a writable integer main rating and a five-star example; that example is not proof of validation rules.

## RAW controls — function 0x1002f18a9

Evidence ev_c57fee18a0e57ab83790d80b21d289b239bb9ab905a838ae5c6f14e00ee064c6. RAW-specific exposure controls depend on an image-method version comparison and Geode/RedRock objects. The fallback pseudocode has unresolved selectors and control flow. It does not establish an exposure formula, numeric range, or a compatible RAW pipeline.

## Entry — function 0x10000fa10

Evidence ev_7f203079e429d0f320c89a49ca34ca869c12950047fa30f00e033ff2667bcf8f. Initializes argument/environment pointers, calls startup 0x10000fa98, and exits with its result. This is not a portable source project.

## No estimated replacement values

Recovered observations and independent replacement formulas are distinguished above; independent formulas are documented in PROCESSING_ALTERNATIVES.md. Full library migration, plug-in fidelity, RAW rendering and UI behavior remain unverified. The companion JSON contains only the numeric/text observations above, each with a source.

## Independent review and tonal additions — 9 November 2026

These are new independent behaviors, not claims of recovered original mechanics. Levels maps input x to clamp((x-black)/(white-black),0,1)^(1/gamma). Input points are separated by at least .001 and gamma is clamped .1…4. The master curve linearly interpolates (0,0),(.25,shadowOutput),(.5,midtoneOutput),(.75,highlightOutput),(1,1). Both apply per unpremultiplied sRGB channel after existing tone controls, before lens/geometry, via one 256-entry table. Alpha is preserved. Histogram bins are rounded 0…255 luminance using .2126R+.7152G+.0722B on the edited preview, excluding fully transparent pixels. Auto Stack sorts valid unstacked capture times and joins consecutive gaps <= selected seconds; singleton groups are omitted. Slideshow uses a stable ordered photo snapshot and waits for rendering plus the chosen delay before advancing, wrapping after the last photo.
