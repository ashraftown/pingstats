import Darwin
import Foundation

/// Outcome of one ICMP echo probe.
enum PingProbeResult: Equatable {
    /// Round-trip time in milliseconds.
    case latency(Double)
    /// No reply arrived before the timeout.
    case timeout
    /// A local or remote error, for example "No route to host".
    case failure(String)
}

/// One ICMP echo probe over an unprivileged datagram socket.
///
/// macOS allows `SOCK_DGRAM` sockets for ICMP without root, so the app needs no
/// extra privilege and no `ping` subprocess. IPv4 and IPv6 literals are
/// supported, including a zone id such as `fe80::1%en0`.
enum PingProbe {
    /// How long one probe may wait for a reply. It stays below the check
    /// interval so a dead link never holds up the next probe.
    static func timeout(forInterval seconds: Double) -> TimeInterval {
        min(2, max(0.3, seconds * 0.8))
    }

    /// Send one echo request to `address` and wait up to `timeout` seconds.
    /// The call blocks, so run it off the main thread.
    static func run(address: String, timeout: TimeInterval) -> PingProbeResult {
        guard let target = Target(address: address) else {
            return .failure("Invalid address")
        }
        let family = target.family
        let descriptor = socket(family.socketDomain, SOCK_DGRAM, family.protocolNumber)
        guard descriptor >= 0 else { return .failure(errorText()) }
        defer { close(descriptor) }

        guard target.withSockaddr({ connect(descriptor, $0, $1) }) == 0 else {
            return .failure(errorText())
        }

        let identifier = UInt16(truncatingIfNeeded: getpid())
        let sequence = UInt16(truncatingIfNeeded: DispatchTime.now().uptimeNanoseconds >> 20)
        let packet = echoRequest(family: family, identifier: identifier, sequence: sequence)
        let sentAt = DispatchTime.now().uptimeNanoseconds
        let sent = packet.withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, 0) }
        guard sent == packet.count else { return .failure(errorText()) }

        var buffer = [UInt8](repeating: 0, count: 1500)
        let deadline = sentAt + UInt64(max(timeout, 0.05) * 1_000_000_000)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return .timeout }
            guard setReceiveTimeout(descriptor, seconds: Double(deadline - now) / 1_000_000_000) else {
                return .failure(errorText())
            }

            let count = recv(descriptor, &buffer, buffer.count, 0)
            let receivedAt = DispatchTime.now().uptimeNanoseconds
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return .timeout }
                if errno == EINTR { continue }
                return .failure(errorText())
            }

            let reply = Array(buffer[0..<count])
            if let message = errorMessage(reply, family: family) { return .failure(message) }
            if isMatchingReply(reply, family: family, sequence: sequence) {
                return .latency(Double(receivedAt - sentAt) / 1_000_000)
            }
            // Ignore anything else, for example the loopback copy of our own
            // request that macOS delivers on ::1, or a reply for another probe.
        }
    }

    // MARK: Packet building

    /// Bytes placed after the 8-byte ICMP header. A reply must carry the same
    /// bytes, because macOS may rewrite the echo identifier.
    static let payloadTag = Array("PingStats-probe".utf8)

    static func echoRequest(family: AddressFamily, identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadTag.count)
        packet[0] = family == .ipv4 ? icmpEchoRequest : icmp6EchoRequest
        packet[1] = 0
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        packet.replaceSubrange(8..., with: payloadTag)
        if family == .ipv4 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xFF)
        }
        // The kernel fills the ICMPv6 checksum.
        return packet
    }

    /// Ones-complement checksum, as used by ICMP for IPv4. A packet that
    /// already carries a valid checksum sums to zero.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }

    // MARK: Packet parsing

    /// True when the packet is the echo reply for `sequence` and carries our
    /// payload tag.
    static func isMatchingReply(_ packet: [UInt8], family: AddressFamily, sequence: UInt16) -> Bool {
        guard let icmp = icmpPayload(packet, family: family),
              icmp.count >= 8 + payloadTag.count,
              icmp[icmp.startIndex] == (family == .ipv4 ? icmpEchoReply : icmp6EchoReply)
        else { return false }
        let start = icmp.startIndex
        let replySequence = UInt16(icmp[start + 6]) << 8 | UInt16(icmp[start + 7])
        guard replySequence == sequence else { return false }
        return Array(icmp[(start + 8)..<(start + 8 + payloadTag.count)]) == payloadTag
    }

    /// A short reason for an ICMP error packet, or nil for any other packet.
    static func errorMessage(_ packet: [UInt8], family: AddressFamily) -> String? {
        guard let icmp = icmpPayload(packet, family: family), icmp.count >= 2 else { return nil }
        let type = icmp[icmp.startIndex]
        let code = icmp[icmp.startIndex + 1]
        switch family {
        case .ipv4:
            switch type {
            case icmpDestinationUnreachable:
                switch code {
                case 0: return "Network unreachable"
                case 1: return "Host unreachable"
                case 13: return "Blocked by firewall"
                default: return "Destination unreachable"
                }
            case icmpTimeExceeded: return "Time exceeded"
            default: return nil
            }
        case .ipv6:
            switch type {
            case icmp6DestinationUnreachable:
                switch code {
                case 0: return "No route to host"
                case 1: return "Blocked by firewall"
                case 3: return "Address unreachable"
                default: return "Destination unreachable"
                }
            case icmp6PacketTooBig: return "Packet too big"
            case icmp6TimeExceeded: return "Time exceeded"
            default: return nil
            }
        }
    }

    /// Skip the IP header when the kernel includes it. macOS prepends it for
    /// IPv4 datagram ICMP replies but not for IPv6.
    static func icmpPayload(_ packet: [UInt8], family: AddressFamily) -> ArraySlice<UInt8>? {
        guard !packet.isEmpty else { return nil }
        let version = packet[0] >> 4
        if family == .ipv4, version == 4 {
            let headerLength = Int(packet[0] & 0x0F) * 4
            guard headerLength >= 20, packet.count > headerLength else { return nil }
            return packet[headerLength...]
        }
        if family == .ipv6, version == 6 {
            guard packet.count > 40 else { return nil }
            return packet[40...]
        }
        return packet[...]
    }

    // MARK: Socket helpers

    private static func setReceiveTimeout(_ descriptor: Int32, seconds: Double) -> Bool {
        let clamped = max(0.001, seconds)
        var timeout = timeval()
        timeout.tv_sec = Int(clamped)
        timeout.tv_usec = Int32((clamped - Double(Int(clamped))) * 1_000_000)
        return setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0
    }

    private static func errorText(_ code: Int32 = errno) -> String {
        switch code {
        case ENETUNREACH: return "Network unreachable"
        case EHOSTUNREACH: return "Host unreachable"
        case ECONNREFUSED: return "Connection refused"
        case EACCES: return "Permission denied"
        default: return String(cString: strerror(code))
        }
    }

    private static let icmpEchoReply: UInt8 = 0
    private static let icmpEchoRequest: UInt8 = 8
    private static let icmpDestinationUnreachable: UInt8 = 3
    private static let icmpTimeExceeded: UInt8 = 11
    private static let icmp6DestinationUnreachable: UInt8 = 1
    private static let icmp6PacketTooBig: UInt8 = 2
    private static let icmp6TimeExceeded: UInt8 = 3
    private static let icmp6EchoRequest: UInt8 = 128
    private static let icmp6EchoReply: UInt8 = 129
}

/// Address family of one probe target.
enum AddressFamily: Equatable {
    case ipv4
    case ipv6

    var socketDomain: Int32 { self == .ipv4 ? AF_INET : AF_INET6 }
    var protocolNumber: Int32 { self == .ipv4 ? IPPROTO_ICMP : IPPROTO_ICMPV6 }
}

/// A parsed probe target, ready to pass to `connect`.
private enum Target {
    case ipv4(sockaddr_in)
    case ipv6(sockaddr_in6)

    init?(address raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("["), text.hasSuffix("]"), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        var zone: String?
        if let separator = text.firstIndex(of: "%") {
            zone = String(text[text.index(after: separator)...])
            text = String(text[..<separator])
        }

        if text.contains(":") {
            var address = sockaddr_in6()
            guard text.withCString({ inet_pton(AF_INET6, $0, &address.sin6_addr) }) == 1 else { return nil }
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            if let zone, !zone.isEmpty {
                let index = zone.withCString { if_nametoindex($0) }
                guard index != 0 else { return nil }
                address.sin6_scope_id = index
            }
            self = .ipv6(address)
        } else {
            var address = sockaddr_in()
            guard text.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return nil }
            address.sin_family = sa_family_t(AF_INET)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            self = .ipv4(address)
        }
    }

    var family: AddressFamily {
        switch self {
        case .ipv4: return .ipv4
        case .ipv6: return .ipv6
        }
    }

    func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        switch self {
        case .ipv4(let address):
            var copy = address
            return withUnsafePointer(to: &copy) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case .ipv6(let address):
            var copy = address
            return withUnsafePointer(to: &copy) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    body($0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }
}
