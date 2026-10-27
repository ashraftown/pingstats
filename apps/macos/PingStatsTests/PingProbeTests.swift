import XCTest

final class PingProbeTests: XCTestCase {
    func testIPv4EchoRequestHasValidChecksum() {
        let packet = PingProbe.echoRequest(family: .ipv4, identifier: 0x1234, sequence: 1)

        XCTAssertEqual(packet.count, 8 + PingProbe.payloadTag.count)
        XCTAssertEqual(packet[0], 8)
        XCTAssertEqual(packet[4], 0x12)
        XCTAssertEqual(packet[5], 0x34)
        XCTAssertEqual(packet[6], 0x00)
        XCTAssertEqual(packet[7], 0x01)
        XCTAssertEqual(UInt16(packet[2]) << 8 | UInt16(packet[3]), 0xBA0E)
        XCTAssertEqual(PingProbe.checksum(packet), 0)
    }

    func testIPv6EchoRequestLeavesChecksumToKernel() {
        let packet = PingProbe.echoRequest(family: .ipv6, identifier: 1, sequence: 2)

        XCTAssertEqual(packet[0], 128)
        XCTAssertEqual(packet[2], 0)
        XCTAssertEqual(packet[3], 0)
        XCTAssertEqual(Array(packet[8...]), PingProbe.payloadTag)
    }

    func testMatchesReplyBehindIPv4Header() {
        let packet = ipv4Packet(reply(family: .ipv4, sequence: 7))

        XCTAssertTrue(PingProbe.isMatchingReply(packet, family: .ipv4, sequence: 7))
        XCTAssertFalse(PingProbe.isMatchingReply(packet, family: .ipv4, sequence: 8))
    }

    func testMatchesReplyWithoutIPv4Header() {
        let packet = reply(family: .ipv4, sequence: 3)

        XCTAssertTrue(PingProbe.isMatchingReply(packet, family: .ipv4, sequence: 3))
    }

    func testRejectsOwnRequestAndStrayPayload() {
        let request = PingProbe.echoRequest(family: .ipv6, identifier: 1, sequence: 4)
        XCTAssertFalse(PingProbe.isMatchingReply(request, family: .ipv6, sequence: 4))

        var strayPayload = reply(family: .ipv6, sequence: 4)
        strayPayload[8] = 0x00
        XCTAssertFalse(PingProbe.isMatchingReply(strayPayload, family: .ipv6, sequence: 4))
    }

    func testReportsIPv6Unreachable() {
        let packet: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]

        XCTAssertEqual(PingProbe.errorMessage(packet, family: .ipv6), "No route to host")
    }

    func testReportsIPv4DestinationUnreachable() {
        let packet: [UInt8] = [3, 1, 0, 0, 0, 0, 0, 0]

        XCTAssertEqual(PingProbe.errorMessage(packet, family: .ipv4), "Host unreachable")
    }

    func testIgnoresReplyPacketsAsErrors() {
        let packet = reply(family: .ipv4, sequence: 1)

        XCTAssertNil(PingProbe.errorMessage(packet, family: .ipv4))
    }

    func testProbesIPv4Loopback() {
        let result = PingProbe.run(address: "127.0.0.1", timeout: 1)

        guard case .latency(let milliseconds) = result else {
            return XCTFail("expected a loopback reply, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
        XCTAssertLessThan(milliseconds, 1000)
    }

    func testProbesIPv6Loopback() {
        let result = PingProbe.run(address: "::1", timeout: 1)

        guard case .latency(let milliseconds) = result else {
            return XCTFail("expected an IPv6 loopback reply, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
        XCTAssertLessThan(milliseconds, 1000)
    }

    func testDeadTargetDoesNotReportLatency() {
        let result = PingProbe.run(address: "192.0.2.1", timeout: 0.2)

        if case .latency = result {
            XCTFail("reserved test address must not answer")
        }
    }

    // MARK: Helpers

    private func reply(family: AddressFamily, sequence: UInt16) -> [UInt8] {
        var packet = PingProbe.echoRequest(family: family, identifier: 0x99, sequence: sequence)
        packet[0] = family == .ipv4 ? 0 : 129
        return packet
    }

    private func ipv4Packet(_ icmp: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[0] = 0x45
        header[3] = UInt8(20 + icmp.count)
        return header + icmp
    }
}
