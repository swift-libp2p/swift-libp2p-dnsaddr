//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import DNSClient
import LibP2P
import Testing

@testable import LibP2PDNSAddr

@Suite("Libp2p DNSADDR Tests", .serialized)
struct LibP2PDNSAddrTests {

    @Test func testAppConfiguration() async throws {
        let app = try await Application.make(.detect(), peerID: .ephemeral())
        app.resolvers.use(.dnsaddr)
        try await app.startup()
        try await app.asyncShutdown()
    }

}

@Suite("Libp2p DNSADDR Resolution Tests", .serialized)
final class LibP2PDNSAddrResolutionTests {
    var app: Application!

    init() throws {
        app = try Application(.detect())
        // On some github workers, the default dns provider locks.
        // We can fix this by hardcoding a resolver (such as cloudflare or google)
        let cloudflareDNS = try SocketAddress(ipAddress: "1.1.1.1", port: 53)
        app.resolvers.use(.dnsaddr(host: cloudflareDNS))
        try app.start()
    }

    deinit {
        app.shutdown()
    }

    @Test(arguments: [
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
        "/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ",
    ])
    func testDNSADDRToMultiaddr(_ address: String) async throws {
        let ma = try Multiaddr(address)

        let resolvedAddresses = try await app.resolve(ma).get()

        if ma.protocols().contains(.ip4) {
            // An already resolved address should result in a nil return value
            #expect(resolvedAddresses == nil)
        } else {
            guard let resolvedAddresses else {
                Issue.record("No Resolved Multiaddr")
                return
            }

            for ra in resolvedAddresses {
                print(ra)
            }

            #expect(resolvedAddresses.count > 0)
        }
    }

    @Test func testDNSADDRToMultiaddr_IPv4_TCP() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/139.178.91.71/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.ip4, .tcp]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }

    @Test func testDNSADDRToMultiaddr_IPv4_UDP() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/139.178.91.71/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.ip4, .udp, .quic_v1]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }

    @Test func testDNSADDRToMultiaddr_IPv6_TCP() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip6/2604:1380:45e3:6e00::1/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.ip6, .tcp]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }

    @Test func testDNSADDRToMultiaddr_IPv6_UDP() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/ip6/2604:1380:45e3:6e00::1/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.ip6, .udp, .quic_v1]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }

    @Test func testDNSADDRToMultiaddr_DNS4_TCP_WSS() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns4/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.dns4, .tcp, .wss]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }

    @Test func testDNSADDRToMultiaddr_DNS6_TCP_WSS() async throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns6/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try await app.resolve(try Multiaddr(address), for: [.dns6, .tcp, .wss]).get()

        #expect(try resolvedAddress == Multiaddr(expectedAddress))
    }
}
