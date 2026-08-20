import XCTest
@testable import TeamsLight

final class PresenceResolverTests: XCTestCase {
    let resolver = PresenceResolver()
    func signal(_ state: PresenceState) -> PresenceSignal { .init(provider: state.rawValue, state: state, detail: "test") }
    func testPresentingWins() { XCTAssertEqual(resolver.resolve([signal(.available), signal(.inCall), signal(.presenting)]), .presenting) }
    func testCallWinsOverBusyAndAway() { XCTAssertEqual(resolver.resolve([signal(.busy), signal(.away), signal(.inCall)]), .inCall) }
    func testEachStateResolvesWhenItIsTheOnlySignal() {
        for state in PresenceState.allCases {
            XCTAssertEqual(resolver.resolve([signal(state)]), state, "Expected \(state) to resolve itself")
        }
    }
    func testResolutionOrderIsIndependentOfSignalOrder() {
        let signals = [signal(.unknown), signal(.offline), signal(.available), signal(.away), signal(.busy), signal(.dnd), signal(.inMeeting), signal(.inCall), signal(.presenting)]
        XCTAssertEqual(resolver.resolve(signals), .presenting)
        XCTAssertEqual(resolver.resolve(Array(signals.reversed())), .presenting)
    }
    func testUnknownWhenNoSignals() { XCTAssertEqual(resolver.resolve([]), .unknown) }
    func testUSBCommandWireValuesAndBrightnessBounds() {
        XCTAssertEqual(USBCommand.presence(.dnd).wireValue, "DND")
        XCTAssertEqual(USBCommand.brightness(99).wireValue, "BRIGHTNESS 15")
        XCTAssertEqual(USBCommand.brightness(-1).wireValue, "BRIGHTNESS 0")
        XCTAssertEqual(USBCommand.brightness(12).wireValue, "BRIGHTNESS 12")
        XCTAssertEqual(USBCommand.color(1, 2, 3).wireValue, "COLOR 1 2 3")
        XCTAssertEqual(USBCommand.ping.wireValue, "PING")
        XCTAssertEqual(USBCommand.status.wireValue, "STATUS")
        XCTAssertEqual(USBCommand.test.wireValue, "TEST")
        XCTAssertEqual(USBCommand.fiveThree.wireValue, "FIVE_THREE")
        XCTAssertEqual(USBCommand.off.wireValue, "OFF")
    }
    func testPresencePresentationAndSignalEquality() {
        XCTAssertEqual(PresenceState.inMeeting.title, "In Meeting")
        XCTAssertEqual(PresenceState.dnd.title, "Do Not Disturb")
        XCTAssertEqual(PresenceState.dnd.menuBarSystemImage, "hand.raised.fill")
        XCTAssertEqual(signal(.busy), signal(.busy))
        XCTAssertNotEqual(signal(.busy), signal(.away))
    }
    func testKuandoBusylightMatchingAndColorReports() {
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x04D8, productID: 0xF848))
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x3BCA))
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x3BCF))
        XCTAssertFalse(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x1234))
        let available = KuandoBusylightCommand.colorReport(for: .available)
        XCTAssertEqual(available.count, 65) // report ID plus 64-byte HID payload
        XCTAssertEqual(Array(available.prefix(9)), [0, 0x10, 0, 0, 255, 0, 1, 0, 128])
        XCTAssertEqual(Array(available[58...62]), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(available.suffix(2)), [0x06, 0x8B])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .presenting).prefix(9)), [0, 0x10, 0, 170, 0, 255, 1, 0, 128])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .dnd).prefix(9)), [0, 0x10, 0, 255, 0, 255, 1, 0, 128])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .offline).prefix(9)), [0, 0x10, 0, 0, 0, 0, 1, 0, 128])
        let halfBrightness = KuandoBusylightCommand.scaled(red: 255, green: 100, blue: 1, brightnessPercent: 50)
        XCTAssertEqual([halfBrightness.0, halfBrightness.1, halfBrightness.2], [128, 50, 1])
        let zeroBrightness = KuandoBusylightCommand.scaled(red: 255, green: 255, blue: 255, brightnessPercent: -1)
        XCTAssertEqual([zeroBrightness.0, zeroBrightness.1, zeroBrightness.2], [0, 0, 0])
    }
    func testUnavailableTransportIsRepresentedByNoDevice() {
        let transport = USBSerialTransport()
        XCTAssertFalse(transport.isConnected)
        XCTAssertNil(transport.deviceName)
    }
    func testUSBSerialCandidateNamesCoverNativeAndBridgeDevices() {
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.usbmodem2101"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.usbserial-0001"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.SLAB_USBtoUART"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.wchusbserial1420"))
        XCTAssertFalse(USBSerialTransport.isCandidateDeviceName("tty.usbserial-0001"))
        XCTAssertFalse(USBSerialTransport.isCandidateDeviceName("cu.Bluetooth-Incoming-Port"))
    }
}
