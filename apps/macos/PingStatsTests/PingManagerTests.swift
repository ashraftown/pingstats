import XCTest

final class PingManagerTests: XCTestCase {
    func testParsePingOutput() {
        XCTAssertEqual(PingManager.parsePingOutput("64 bytes from 8.8.8.8: icmp_seq=0 ttl=117 time=12.5 ms"), 12.5)
        XCTAssertEqual(PingManager.parsePingOutput("time=0.4ms"), 0.4)
        XCTAssertNil(PingManager.parsePingOutput("Request timeout for icmp_seq 0"))
    }

    func testNormalizedInterval() {
        XCTAssertEqual(PingManager.normalizedInterval(7), 5)
        XCTAssertEqual(PingManager.normalizedInterval(0), 1)
        XCTAssertEqual(PingManager.normalizedInterval(100), 60)
        XCTAssertEqual(PingManager.normalizedInterval(45), 30)
    }

    func testHostValidation() {
        XCTAssertTrue(PingManager.isValidHost("8.8.8.8"))
        XCTAssertTrue(PingManager.isValidHost("example.com"))
        XCTAssertTrue(PingManager.isValidHost("fe80::1"))
        XCTAssertFalse(PingManager.isValidHost("-c"))
        XCTAssertFalse(PingManager.isValidHost("bad host"))
        XCTAssertFalse(PingManager.isValidHost(""))
    }

    func testPingArguments() {
        XCTAssertEqual(PingManager.pingArguments("8.8.8.8"), ["-c", "1", "-W", "2000", "8.8.8.8"])
        XCTAssertEqual(PingManager.pingArguments("fe80::1"), ["-6", "-c", "1", "-W", "2000", "fe80::1"])
        XCTAssertEqual(PingManager.pingArguments("[::1]"), ["-6", "-c", "1", "-W", "2000", "::1"])
    }
}
