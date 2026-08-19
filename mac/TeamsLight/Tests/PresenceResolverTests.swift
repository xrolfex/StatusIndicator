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
        XCTAssertEqual(USBCommand.off.wireValue, "OFF")
    }
    func testPresencePresentationAndSignalEquality() {
        XCTAssertEqual(PresenceState.inMeeting.title, "In Meeting")
        XCTAssertEqual(PresenceState.dnd.title, "Do Not Disturb")
        XCTAssertEqual(PresenceState.dnd.menuBarSystemImage, "hand.raised.fill")
        XCTAssertEqual(signal(.busy), signal(.busy))
        XCTAssertNotEqual(signal(.busy), signal(.away))
    }
    func testUnavailableTransportIsRepresentedByNoDevice() {
        let transport = USBSerialTransport()
        XCTAssertFalse(transport.isConnected)
        XCTAssertNil(transport.deviceName)
    }
}
