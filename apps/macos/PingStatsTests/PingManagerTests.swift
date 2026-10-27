import XCTest

final class PingManagerTests: XCTestCase {
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
        XCTAssertTrue(PingManager.isValidHost("fe80::1%en0"))
        XCTAssertFalse(PingManager.isValidHost("-c"))
        XCTAssertFalse(PingManager.isValidHost("bad host"))
        XCTAssertFalse(PingManager.isValidHost("fe80::1%en0%en1"))
        XCTAssertFalse(PingManager.isValidHost(""))
    }

    func testIsIPAddress() {
        XCTAssertTrue(PingManager.isIPAddress("8.8.8.8"))
        XCTAssertTrue(PingManager.isIPAddress("::1"))
        XCTAssertTrue(PingManager.isIPAddress("[fe80::1]"))
        XCTAssertTrue(PingManager.isIPAddress("fe80::1%en0"))
        XCTAssertFalse(PingManager.isIPAddress("example.com"))
        XCTAssertFalse(PingManager.isIPAddress(""))
    }

    func testProbeTimeoutStaysBelowInterval() {
        for interval in PingManager.supportedIntervals {
            let timeout = PingProbe.timeout(forInterval: interval)

            XCTAssertLessThan(timeout, interval)
            XCTAssertGreaterThanOrEqual(timeout, 0.3)
            XCTAssertLessThanOrEqual(timeout, 2)
        }
    }

    func testMonitorsLoopbackHost() {
        let manager = PingManager()
        manager.host = "localhost"
        manager.startPinging()

        let deadline = Date().addingTimeInterval(3)
        while !manager.isConnected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.resolvedIP, "127.0.0.1")
        XCTAssertGreaterThan(manager.latestLatencyMs ?? 0, 0)

        manager.stopPinging()
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.isConnected)
    }
}
