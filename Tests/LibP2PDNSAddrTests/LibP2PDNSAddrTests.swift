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
import LibP2PTesting
import NIOConcurrencyHelpers
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

    @Test func canResolveAddress() throws {
        let resolvableAddresses = [
            "/dns/region.example/tcp/1",
            "/dns4/example.com/tcp/443/wss",
            "/dns6/example.com/udp/4001/quic-v1",
            "/dnsaddr/b.example",
            "/dns/region.example/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dns4/example.com/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dns6/example.com/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dnsaddr/b.example/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        ]

        let unresolvableAddresses = [
            "/ip4/1.2.3.4/tcp/1",
            "/ip6/::1/tcp/1",
            "/ip4/1.2.3.4/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/ip6/::1/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dns/region.local/tcp/1",
            "/dns4/example.local/tcp/443/wss",
            "/dns6/example.local/udp/4001/quic-v1",
            "/dnsaddr/b.example.local",
            "/dns/region.example.local/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dns4/example.local/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dns6/example.local/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
            "/dnsaddr/b.example.local/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        ]

        for address in resolvableAddresses {
            let multiaddr = try Multiaddr(address)
            #expect(DNSAddr.isResolvable(multiaddr))
        }

        for address in unresolvableAddresses {
            let multiaddr = try Multiaddr(address)
            #expect(DNSAddr.isResolvable(multiaddr) == false)
        }
    }

}

/// Deterministic, network-free tests for the recursive `dnsaddr` resolution logic.
///
/// These exercise ``DNSAddr/resolveConcreteAddresses(domain:peerID:maxDepth:fetch:)`` directly with a fake
/// TXT-record `fetch`, so recursion, suffix matching, aggregation, de-duplication, and the depth/cycle guards
/// can be verified without touching the network.
@Suite("Libp2p DNSADDR Resolution Logic Tests", .serialized)
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

    // MARK: /dns → /ip rewrite (the pure step used by the A/AAAA resolver)

    @Test func testReplacingLeadingHostRewritesDNS4ToIPv4() throws {
        let ma = try Multiaddr("/dns4/example.com/tcp/443/wss/p2p/\(Self.peerA)")
        let rewritten = try #require(DNSAddr.replacingLeadingHost(of: ma, withIP: "1.2.3.4", codec: .ip4))
        let expected = try Multiaddr("/ip4/1.2.3.4/tcp/443/wss/p2p/\(Self.peerA)")
        #expect(rewritten == expected)
    }

    @Test func testReplacingLeadingHostRewritesDNS6ToIPv6() throws {
        let ma = try Multiaddr("/dns6/example.com/udp/4001/quic-v1/p2p/\(Self.peerA)")
        let rewritten = try #require(DNSAddr.replacingLeadingHost(of: ma, withIP: "2606:4700:4700::1111", codec: .ip6))
        let expected = try Multiaddr("/ip6/2606:4700:4700::1111/udp/4001/quic-v1/p2p/\(Self.peerA)")
        #expect(rewritten == expected)
    }
}

/// Deterministic tests for `Application.resolve`'s coalescing, TTL cache and per-resolver timeout.
///
/// These tests install a mock resolver instead of `DNSAddr` that records how many times we
/// get called by `Application`.
@Suite("Libp2p Address Resolution Cache Tests", .serialized)
struct LibP2PResolutionCacheTests {

    static let peerA = "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

    func address(_ domain: String) throws -> Multiaddr {
        try Multiaddr("/dnsaddr/\(domain)/p2p/\(Self.peerA)")
    }

    /// Aggregation preserves the order a resolver reported its addresses in.
    ///
    /// That order carries intent — a peer's `dnsaddr` records list its preferred endpoints first, and
    /// `resolve(_:for:)` hands back the first address matching the requested codecs — so it's asserted
    /// exactly, here and in every other comparison against ``CountingResolver/addresses(for:)``.
    @Test func testResolvedAddressesPreserveResolverOrder() async throws {
        try await withCountingResolver { app, _ in
            let ma = try self.address("ordered.example")
            #expect(try await app.resolve(ma) == CountingResolver.addresses(for: ma))
        }
    }

    /// Concurrent resolutions of the same address are coalesced into a single result
    @Test func testConcurrentResolvesAreCoalesced() async throws {
        try await withCountingResolver { app, resolver in
            let ma = try self.address("coalesce.example")
            // Slow enough that every task is waiting before the first resolution settles.
            resolver.delay = .milliseconds(250)

            let results = try await withThrowingTaskGroup(of: [Multiaddr]?.self) { group in
                for _ in 0..<8 { group.addTask { try await app.resolve(ma) } }
                var results: [[Multiaddr]?] = []
                for try await result in group { results.append(result) }
                return results
            }

            #expect(results.count == 8)
            #expect(results.allSatisfy { $0 == CountingResolver.addresses(for: ma) })
            // Eight callers, one resolution.
            #expect(resolver.calls(for: ma) == 1)
        }
    }

    /// Coalescing is per address, two different addresses resolved concurrently are both resolved.
    @Test func testConcurrentResolvesOfDifferentAddressesAreNotCoalesced() async throws {
        try await withCountingResolver { app, resolver in
            let first = try self.address("one.example")
            let second = try self.address("two.example")
            resolver.delay = .milliseconds(100)

            async let a = app.resolve(first)
            async let b = app.resolve(second)
            _ = try await (a, b)

            #expect(resolver.calls(for: first) == 1)
            #expect(resolver.calls(for: second) == 1)
        }
    }

    /// A repeat resolution inside the TTL is served from the cache without touching the resolver.
    @Test func testRepeatResolveIsServedFromCache() async throws {
        try await withCountingResolver(cacheTTL: .minutes(5)) { app, resolver in
            let ma = try self.address("cached.example")

            let first = try await app.resolve(ma)
            let second = try await app.resolve(ma)

            #expect(first == second)
            #expect(second == CountingResolver.addresses(for: ma))
            #expect(resolver.calls(for: ma) == 1)
        }
    }

    /// Once the TTL lapses the entry is no longer served and the address is resolved again.
    @Test func testCacheEntryExpiresAfterTTL() async throws {
        try await withCountingResolver(cacheTTL: .milliseconds(200)) { app, resolver in
            let ma = try self.address("expiring.example")

            _ = try await app.resolve(ma)
            #expect(resolver.calls(for: ma) == 1)

            try await Task.sleep(nanoseconds: 400_000_000)

            _ = try await app.resolve(ma)
            #expect(resolver.calls(for: ma) == 2)
        }
    }

    /// `skipCache` forces a fresh resolution, and the result it produces becomes the new cache entry.
    @Test func testSkipCacheForcesFreshResolution() async throws {
        try await withCountingResolver(cacheTTL: .minutes(5)) { app, resolver in
            let ma = try self.address("skip.example")

            _ = try await app.resolve(ma)
            #expect(resolver.calls(for: ma) == 1)

            let fresh = try await app.resolve(ma, skipCache: true)
            #expect(fresh == CountingResolver.addresses(for: ma))
            #expect(resolver.calls(for: ma) == 2)

            // The fresh resolution replaced the entry it bypassed, so we're cached again.
            _ = try await app.resolve(ma)
            #expect(resolver.calls(for: ma) == 2)
        }
    }

    /// `clearCache()` is the manual prune, every completed entry is dropped.
    @Test func testClearCacheDropsCachedEntries() async throws {
        try await withCountingResolver(cacheTTL: .minutes(5)) { app, resolver in
            let first = try self.address("clear-one.example")
            let second = try self.address("clear-two.example")

            _ = try await app.resolve(first)
            _ = try await app.resolve(second)
            #expect(resolver.totalCalls == 2)

            app.resolvers.clearCache()

            _ = try await app.resolve(first)
            _ = try await app.resolve(second)
            #expect(resolver.totalCalls == 4)
        }
    }

    /// The cache is bounded, so a long lived host can't grow it without limit. Exceeding the bound evicts the
    /// entries closest to expiry, even though their TTL hasn't lapsed, while recent entries survive.
    @Test func testCacheEvictsEntriesClosestToExpiryWhenFull() async throws {
        try await withCountingResolver(cacheTTL: .minutes(5)) { app, resolver in
            // The oldest entry, and so the first one up for eviction.
            let oldest = try self.address("oldest.example")
            _ = try await app.resolve(oldest)
            #expect(resolver.calls(for: oldest) == 1)

            // Push the cache past its 256 entry bound. Pruning happens as later resolutions are claimed.
            for i in 0..<300 {
                _ = try await app.resolve(try self.address("host-\(i).example"))
            }

            // A recently resolved address is still cached...
            let newest = try self.address("host-299.example")
            _ = try await app.resolve(newest)
            #expect(resolver.calls(for: newest) == 1)

            // ...while the oldest one was evicted despite its five minute TTL.
            _ = try await app.resolve(oldest)
            #expect(resolver.calls(for: oldest) == 2)
        }
    }

    /// A resolver that takes longer than `timeout` doesn't hold up the caller, and the abandoned attempt
    /// isn't cached as a negative result.
    @Test func testSlowResolverTimesOut() async throws {
        try await withCountingResolver { app, resolver in
            let ma = try self.address("slow.example")
            resolver.delay = .seconds(5)

            let start = NIODeadline.now()
            let resolved = try await app.resolve(ma, timeout: .milliseconds(100))
            let elapsed = NIODeadline.now() - start

            #expect(resolved == nil)
            #expect(elapsed < .milliseconds(2500))

            // Nothing was cached, so a subsequent resolution succeeds.
            resolver.delay = .zero
            #expect(try await app.resolve(ma) == CountingResolver.addresses(for: ma))
            #expect(resolver.calls(for: ma) == 2)
        }
    }

    /// A failing resolver yields `nil` rather than an error, and the failure isn't cached, the next caller
    /// retries instead of inheriting a negative result for the full TTL.
    @Test func testFailedResolutionIsNotCached() async throws {
        try await withCountingResolver(cacheTTL: .minutes(5)) { app, resolver in
            let ma = try self.address("failing.example")
            resolver.fails = true

            #expect(try await app.resolve(ma) == nil)
            #expect(resolver.calls(for: ma) == 1)

            resolver.fails = false
            #expect(try await app.resolve(ma) == CountingResolver.addresses(for: ma))
            #expect(resolver.calls(for: ma) == 2)
        }
    }

    /// Resolved addresses are published to the peerstore under the peer id they were filed against.
    @Test func testResolvedAddressesArePublishedToPeerStore() async throws {
        try await withCountingResolver { app, _ in
            let ma = try self.address("peerstore.example")
            let pid = try ma.getPeerID()
            // The peerstore only holds addresses for peers it knows about.
            try await app.peers.add(key: pid)

            let resolved = try #require(try await app.resolve(ma))

            let stored = try await app.peers.getAddresses(forPeer: pid)
            #expect(Set(stored).isSuperset(of: Set(resolved)))
        }
    }
}

/// Live, network-dependent resolution tests against the public libp2p bootstrap nodes.
///
/// - Note: These require outbound DNS and depend on records the libp2p project controls, so assertions check
///   structural invariants (peer id suffix, requested transports, non-empty results) rather than exact addresses.
@Suite("Libp2p DNSADDR Resolution Tests (live)", .serialized)
struct LibP2PDNSAddrLiveResolutionTests {

    static let peerA = "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

    @Test(arguments: [
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
    ])
    func testDNSADDRResolvesToDialableAddresses(_ address: String) async throws {
        try await withApp(configure: configured()) { app in
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
        try await withApp(configure: configured(maxRecursionDepth: 1)) { app in
            let ma = try Multiaddr(address)

            #expect(try await app.resolve(ma).get() == nil)
        }
    }

    @Test func testAlreadyResolvedAddressReturnsNil() async throws {
        try await withApp(configure: configured()) { app in
            let ma = try Multiaddr("/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ")
            let resolved = try await app.resolve(ma).get()
            #expect(resolved == nil)
        }
    }

    @Test func testResolveForRequestedTransport() async throws {
        try await withApp(configure: configured()) { app in
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

/// Live, network-dependent tests for standard `/dns`, `/dns4`, `/dns6` (A/AAAA) name resolution.
///
/// - Note: `Application.resolve` only dispatches `/dnsaddr` addresses to resolvers, so these exercise the
///   `DNSAddr` resolver directly. `one.one.one.one` is a stable dual-stack name (Cloudflare's `1.1.1.1`).
@Suite("Libp2p DNS (A/AAAA) Resolution Tests (live)", .serialized)
struct LibP2PDNSNameResolutionTests {

    @Test func testDNS4ResolvesToIPv4PreservingTail() async throws {
        try await withApp(configure: configured()) { app in
            let ma = try Multiaddr("/dns4/one.one.one.one/tcp/443")
            guard let resolved = try await app.resolve(ma) else {
                Issue.record("No A records resolved")
                return
            }
            #expect(!resolved.isEmpty)
            #expect(resolved.allSatisfy { $0.addresses.first?.codec == .ip4 })
            // The transport tail must be preserved through the rewrite
            #expect(resolved.allSatisfy { $0.protocols().contains(.tcp) })

            // Ensure our resolve(ma, for:) method returns a match
            guard let resolved2 = try await app.resolve(ma, for: [.ip4, .tcp]) else {
                Issue.record("No A records resolved")
                return
            }
            #expect(resolved2.addresses.first?.codec == .ip4)
            #expect(resolved2.protocols().contains(.tcp))

            // Since there's no ip6 addresses being resolved this should return nil
            #expect(try await app.resolve(ma, for: [.ip6]) == nil)
        }
    }

    @Test func testDNS6ResolvesToIPv6() async throws {
        try await withApp(configure: configured()) { app in
            let ma = try Multiaddr("/dns6/one.one.one.one/tcp/443")
            guard let resolved = try await app.resolve(ma) else {
                Issue.record("No AAAA records resolved")
                return
            }
            #expect(!resolved.isEmpty)
            #expect(resolved.allSatisfy { $0.addresses.first?.codec == .ip6 })
        }
    }

    @Test func testDNSResolvesToBothFamilies() async throws {
        try await withApp(configure: configured()) { app in
            let ma = try Multiaddr("/dns/one.one.one.one/tcp/443")
            guard let resolved = try await app.resolve(ma) else {
                Issue.record("No records resolved")
                return
            }
            #expect(!resolved.isEmpty)
            let codecs = Set(resolved.compactMap { $0.addresses.first?.codec })
            #expect(codecs.allSatisfy { $0 == .ip4 || $0 == .ip6 })
            #expect(codecs.contains(.ip4))
            #expect(codecs.contains(.ip6))
        }
    }

    @Test func testConcreteAddressResolvesToNil() async throws {
        try await withApp(configure: configured()) { app in
            // Not a /dns* name — there's nothing to resolve, so we get nil rather than an error.
            let ma = try Multiaddr("/ip4/1.2.3.4/tcp/4001")
            #expect(try await app.resolve(ma) == nil)
        }
    }
}

/// Configures an application with a hardcoded resolver (some CI workers lock up when using the default DNS provider)
private func configured(maxRecursionDepth: Int? = nil) -> ((Application) async throws -> Void)? {
    { app in
        let cloudflareDNS = try SocketAddress(ipAddress: "1.1.1.1", port: 53)
        app.resolvers.use(.dnsaddr(host: cloudflareDNS, maxRecursionDepth: maxRecursionDepth))
    }
}

/// An `AddressResolver` stand-in that answers from a fixed template and records how many times it was asked.
///
/// Because `app.resolve` coalesces and caches, the only way to tell a cache hit from a fresh resolution is to
/// count the resolutions the resolver was actually asked to perform — which is what this exists for. Its
/// latency and failure mode are settable so timeouts and non-cached failures can be exercised too.
final class CountingResolver: AddressResolver {

    static let key: String = "COUNTING"

    enum Failure: Error { case requested }

    private struct Behavior {
        var delay: TimeAmount = .zero
        var fails: Bool = false
        var calls: [Multiaddr: Int] = [:]
    }

    private let eventLoop: EventLoop
    private let behavior: NIOLockedValueBox<Behavior>

    init(application: Application) {
        self.eventLoop = application.eventLoopGroup.next()
        self.behavior = .init(.init())
    }

    // MARK: Test controls

    /// How long the resolver takes to answer.
    var delay: TimeAmount {
        get { self.behavior.withLockedValue { $0.delay } }
        set { self.behavior.withLockedValue { $0.delay = newValue } }
    }

    /// When `true`, every resolution fails with ``Failure/requested``.
    var fails: Bool {
        get { self.behavior.withLockedValue { $0.fails } }
        set { self.behavior.withLockedValue { $0.fails = newValue } }
    }

    /// The number of resolutions this resolver was asked to perform for `ma`.
    func calls(for ma: Multiaddr) -> Int {
        self.behavior.withLockedValue { $0.calls[ma] ?? 0 }
    }

    /// The number of resolutions this resolver was asked to perform, across every address.
    var totalCalls: Int {
        self.behavior.withLockedValue { $0.calls.values.reduce(0, +) }
    }

    /// The addresses this resolver answers with, preserving any `/p2p/<id>` suffix so that resolved addresses
    /// can be filed in the peerstore.
    static func addresses(for ma: Multiaddr) -> [Multiaddr] {
        let peerID = try? ma.getPeerID().b58String
        return ["/ip4/1.2.3.4/tcp/4001", "/ip4/5.6.7.8/udp/4001/quic-v1"].compactMap { base in
            try? Multiaddr(peerID.map { "\(base)/p2p/\($0)" } ?? base)
        }
    }

    // MARK: AddressResolver

    func can(resolve ma: Multiaddr) -> Bool {
        DNSAddr.isResolvable(ma)
    }

    func resolve(multiaddr ma: Multiaddr) -> EventLoopFuture<[Multiaddr]?> {
        let (delay, fails) = self.behavior.withLockedValue { behavior -> (TimeAmount, Bool) in
            behavior.calls[ma, default: 0] += 1
            return (behavior.delay, behavior.fails)
        }

        let answer: @Sendable () throws -> [Multiaddr]? = {
            if fails { throw Failure.requested }
            return Self.addresses(for: ma)
        }

        guard delay > .zero else { return self.eventLoop.submit(answer) }
        return self.eventLoop.scheduleTask(in: delay, answer).futureResult
    }
}

/// Runs `test` against an application whose only resolver is a ``CountingResolver``.
private func withCountingResolver<T>(
    cacheTTL: TimeAmount? = nil,
    _ test: (Application, CountingResolver) async throws -> T
) async throws -> T {
    let box = NIOLockedValueBox<CountingResolver?>(nil)
    let configuration: ((Application) async throws -> Void) = { app in
        app.resolvers.use { application in
            let resolver = CountingResolver(application: application)
            box.withLockedValue { $0 = resolver }
            return resolver
        }
        if let cacheTTL { app.resolvers.cacheTTL = cacheTTL }
    }
    return try await withApp(configure: configuration) { app in
        let resolver = try #require(box.withLockedValue { $0 })
        return try await test(app, resolver)
    }
}
