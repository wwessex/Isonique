@preconcurrency import ImageCaptureCore
import XCTest
@testable import Isonique

final class NativeTetherTests: XCTestCase {
    func testRemoteShutterRequiresTheMacTriggeredCapability() {
        let shutter = ICDeviceCapability.cameraDeviceCanTakePicture.rawValue
        let onCamera = ICDeviceCapability.cameraDeviceCanTakePictureUsingShutterReleaseOnCamera.rawValue
        XCTAssertFalse(NativeTetherError.supportsRemoteShutter([]))
        XCTAssertFalse(NativeTetherError.supportsRemoteShutter([onCamera]))
        XCTAssertTrue(NativeTetherError.supportsRemoteShutter([shutter]))
        XCTAssertTrue(NativeTetherError.supportsRemoteShutter([shutter, onCamera]))
    }
}
