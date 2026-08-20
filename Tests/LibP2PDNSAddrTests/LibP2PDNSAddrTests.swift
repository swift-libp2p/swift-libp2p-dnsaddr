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

@Suite("Libp2p DNSADDR Configuration Tests", .serialized)
struct LibP2PDNSAddrTests {

    @Test func testAppConfiguration() async throws {
        let app = try await Application.make(.detect(), peerID: .ephemeral())
        app.resolvers.use(.dnsaddr)
        try await app.startup()
        try await app.asyncShutdown()
    }

}

/// Deterministic, network-free tests for the recursive `dnsaddr` resolution logic.
///
/// These exercise ``DNSAddr/resolveConcreteAddresses(domain:peerID:maxDepth:fetch:)`` directly with a fake
/// TXT-record `fetch`, so recursion, suffix matching, aggregation, de-duplication, and the depth/cycle guards
/// can be verified without touching the network.
@Suite("Libp2p DNSADDR Resolution Logic Tests")
struct LibP2PDNSAddrResolutionLogicTests {

    static let peerA = "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    static let peerB = "QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa"

    /// Builds a fake `fetch` closure from a domain → dnsaddr-record-strings table.
    func fetcher(_ table: [String: [String]]) -> (String) async throws -> [Multiaddr] {
        { domain in
            try (table[domain] ?? []).map { try Multiaddr($0) }
        }
    }

    func peerID(_ id: String) throws -> PeerID {
        try Multiaddr("/ip4/1.2.3.4/tcp/1/p2p/\(id)").getPeerID()
    }

    /// A domain that publishes its concrete addresses directly (the spec's simplest form) must return *all* of
    /// them — not just the first. This is a regression test for the previous single-address behavior.
    @Test func testDirectConcreteRecordsReturnAllAddresses() async throws {
        let table = [
            "example.com": [
                "/ip4/1.2.3.4/tcp/4001/p2p/\(Self.peerA)",
                "/ip6/::1/tcp/4001/p2p/\(Self.peerA)",
                "/ip4/1.2.3.4/udp/4001/quic-v1/p2p/\(Self.peerA)",
            ]
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "example.com",
            peerID: try self.peerID(Self.peerA),
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 3)
    }

    /// Nested `/dnsaddr` records are followed until concrete addresses are reached.
    @Test func testRecursivelyFollowsNestedDNSAddrRecords() async throws {
        let table = [
            "bootstrap.example": ["/dnsaddr/region.example/p2p/\(Self.peerA)"],
            "region.example": [
                "/dns/region.example/tcp/4001/p2p/\(Self.peerA)",
                "/dns/region.example/udp/4001/quic-v1/p2p/\(Self.peerA)",
            ],
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "bootstrap.example",
            peerID: try self.peerID(Self.peerA),
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 2)
        #expect(resolved.allSatisfy { $0.addresses.first?.codec == .dns })
    }

    /// When a peer id suffix is supplied, records for other peers are dropped.
    @Test func testSuffixMatchingFiltersByPeerID() async throws {
        let table = [
            "shared.example": [
                "/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)",
                "/ip4/2.2.2.2/tcp/4001/p2p/\(Self.peerB)",
            ]
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "shared.example",
            peerID: try self.peerID(Self.peerA),
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 1)
        #expect(try resolved.first?.getPeerID() == self.peerID(Self.peerA))
    }

    /// Without a peer id filter, every advertised record is returned (a bare `/dnsaddr/domain` lookup).
    @Test func testNoPeerIDReturnsEveryRecord() async throws {
        let table = [
            "shared.example": [
                "/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)",
                "/ip4/2.2.2.2/tcp/4001/p2p/\(Self.peerB)",
            ]
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "shared.example",
            peerID: nil,
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 2)
    }

    /// Identical addresses advertised more than once are de-duplicated.
    @Test func testDuplicateAddressesAreDeduplicated() async throws {
        let table = [
            "dupes.example": [
                "/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)",
                "/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)",
            ]
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "dupes.example",
            peerID: nil,
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 1)
    }

    /// A cycle between two dnsaddr domains must terminate and still surface the reachable concrete address.
    @Test func testCyclesTerminate() async throws {
        let table = [
            "a.example": [
                "/dnsaddr/b.example/p2p/\(Self.peerA)",
                "/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)",
            ],
            "b.example": ["/dnsaddr/a.example/p2p/\(Self.peerA)"],
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "a.example",
            peerID: try self.peerID(Self.peerA),
            fetch: self.fetcher(table)
        )

        #expect(resolved.count == 1)
    }

    /// Resolution stops once the recursion depth cap is exceeded rather than looping forever.
    @Test func testDepthCapStopsResolution() async throws {
        // A chain deeper than the supplied maxDepth: only the reachable hops resolve.
        let table = [
            "0.example": ["/dnsaddr/1.example/p2p/\(Self.peerA)"],
            "1.example": ["/dnsaddr/2.example/p2p/\(Self.peerA)"],
            "2.example": ["/ip4/1.1.1.1/tcp/4001/p2p/\(Self.peerA)"],
        ]

        let resolved = try await DNSAddr.resolveAddressesRecursively(
            domain: "0.example",
            peerID: try self.peerID(Self.peerA),
            maxDepth: 1,
            fetch: self.fetcher(table)
        )

        // With maxDepth 1 we only resolve the first hop, which yields another dnsaddr — no concrete address yet.
        #expect(resolved.isEmpty)
        
        let resolved2 = try await DNSAddr.resolveAddressesRecursively(
            domain: "0.example",
            peerID: try self.peerID(Self.peerA),
            maxDepth: 2,
            fetch: self.fetcher(table)
        )
        
        // With maxDepth 2 we only resolve the second hop, which yields another dnsaddr — no concrete address yet.
        #expect(resolved2.isEmpty)
        
        let resolved3 = try await DNSAddr.resolveAddressesRecursively(
            domain: "0.example",
            peerID: try self.peerID(Self.peerA),
            maxDepth: 3,
            fetch: self.fetcher(table)
        )
        
        #expect(resolved3.count == 1)
    }
}

/// Live, network-dependent resolution tests against the public libp2p bootstrap nodes.
///
/// - Note: These require outbound DNS and depend on records the libp2p project controls, so assertions check
///   structural invariants (peer id suffix, requested transports, non-empty results) rather than exact addresses.
@Suite("Libp2p DNSADDR Resolution Tests (live)", .serialized)
struct LibP2PDNSAddrLiveResolutionTests {

    /// Spins up an application with a hardcoded resolver (some CI workers lock on the default DNS provider),
    /// runs the body, and always tears the application back down.
    func withApp(maxRecursionDepth: Int? = nil, _ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.detect(), peerID: .ephemeral())
        let cloudflareDNS = try SocketAddress(ipAddress: "1.1.1.1", port: 53)
        app.resolvers.use(.dnsaddr(host: cloudflareDNS, maxRecursionDepth: maxRecursionDepth))
        try await app.startup()
        do {
            try await body(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test(arguments: [
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
    ])
    func testDNSADDRResolvesToConcreteAddresses(_ address: String) async throws {
        try await self.withApp { app in
            let ma = try Multiaddr(address)
            let expectedPeerID = try ma.getPeerID()

            guard let resolved = try await app.resolve(ma).get() else {
                Issue.record("No resolved Multiaddr for \(address)")
                return
            }

            print(resolved)
            #expect(!resolved.isEmpty)
            // Every resolved address must carry the requested peer id (spec suffix matching).
            for ra in resolved {
                #expect(try ra.getPeerID() == expectedPeerID)
            }
            // None of the returned addresses should still be an unresolved dnsaddr.
            #expect(resolved.allSatisfy { $0.addresses.first?.codec != .dnsaddr })
        }
    }
    
    @Test(arguments: [
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
    ])
    func testDNSADDRRespectsConfiguredMaxRecursionDepth(_ address: String) async throws {
        // These DNSAddr require two hops to resolve
        try await self.withApp(maxRecursionDepth: 1) { app in
            let ma = try Multiaddr(address)

            #expect(try await app.resolve(ma).get() == nil)
        }
    }

    @Test func testAlreadyResolvedAddressReturnsNil() async throws {
        try await self.withApp { app in
            let ma = try Multiaddr("/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ")
            let resolved = try await app.resolve(ma).get()
            #expect(resolved == nil)
        }
    }

    @Test func testResolveForRequestedTransport() async throws {
        try await self.withApp { app in
            let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
            let ma = try Multiaddr(address)
            let requested: Set<MultiaddrProtocol> = [.dns, .tcp]

            guard let resolved = try await app.resolve(ma, for: requested).get() else {
                Issue.record("No address resolved for requested transports \(requested)")
                return
            }

            #expect(Set(resolved.addresses.map { $0.codec }).isSuperset(of: requested))
            #expect(try resolved.getPeerID() == ma.getPeerID())
        }
    }
}
