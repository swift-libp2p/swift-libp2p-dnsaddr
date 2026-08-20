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
import NIOConcurrencyHelpers

/// DNSAddr
/// Resolves `Multiaddr`s that use libp2p's DNS-based protocols into dialable addresses:
/// - `/dnsaddr` — recursively looks up multiaddrs published in `_dnsaddr.<domain>` TXT records.
/// - `/dns`, `/dns4`, `/dns6` — performs standard A/AAAA lookups and rewrites the name to `/ip4` / `/ip6`,
///   preserving the transport suffix (e.g. `/tcp/443/wss/p2p/...`).
/// - [Specification](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)
/// ```swift
/// // When configuring your libp2p instance
/// app.resolvers.use(.dnsaddr)
/// ...
/// // Later you can call resolve on any app or req object
/// try await app.resolve(ma) // [Multiaddr]
/// try await req.resolve(ma, for: [.ip4, .tcp]) // Multiaddr?
/// ```
public final class DNSAddr: AddressResolver, LifecycleHandler {

    public static let key: String = "DNSADDR"

    public enum Errors: Error {
        case clientNotInitialized
        case invalidMultiaddr
        case noMatchingHostFound
    }

    /// The `_dnsaddr.` label prepended to a domain before querying its TXT records.
    static let dnsAddrPrefix = "_dnsaddr."
    /// Valid `dnsaddr` TXT records begin with this prefix, followed by a single multiaddr.
    static let txtRecordPrefix = "dnsaddr="
    
    /// A safety cap on how many levels of `/dnsaddr` indirection we'll follow before bailing.
    /// The spec allows arbitrarily deep recursion; this bound simply prevents runaway lookups.
    static let maxRecursionDepth = 8

    let application: Application
    let eventLoop: EventLoop
    let logger: Logger
    let uuid: UUID
    let hosts: Array<SocketAddress>
    let recursionDepth: Int

    var client: DNSClient? {
        get { _client.withLockedValue { $0 } }
    }
    let _client: NIOLockedValueBox<DNSClient?>

    init(application: Application, hosts: [SocketAddress] = [], maxRecursionDepth: Int? = nil) {
        self.application = application
        self.eventLoop = application.eventLoopGroup.next()
        self.uuid = UUID()
        var logger = application.logger
        logger[metadataKey: DNSAddr.key] = .string("[\(uuid.uuidString.prefix(5))]")
        self.logger = logger
        self.hosts = Array(Set(hosts))
        let mrd = maxRecursionDepth ?? DNSAddr.maxRecursionDepth
        // clamp the actual recursion depth to sensible values
        self.recursionDepth = max(1, min(mrd, DNSAddr.maxRecursionDepth))
        self._client = .init(nil)
    }

    /// The upstream DNS resolver(s) to query.
    /// - Note: We connect over TCP rather than UDP because the combined size of a domain's
    ///   `dnsaddr` TXT records frequently exceeds the 512 byte UDP truncation limit.
    func resolverConfig() throws -> [SocketAddress] {
        if !self.hosts.isEmpty {
            return hosts
        }
        return [try SocketAddress(ipAddress: "1.1.1.1", port: 53)]
    }

    /// Resolves every dialable address advertised for the given `dnsaddr` multiaddr.
    /// - Returns: the resolved addresses, or `nil` when the domain advertises no matching records.
    func resolveAll(multiaddr ma: Multiaddr) async throws -> [Multiaddr]? {
        guard let first = ma.addresses.first else { throw Errors.invalidMultiaddr }

        // If the first codec isn't `dnsaddr` pass the resquest along to the A/AAAA name resolution
        guard first.codec == .dnsaddr else {
            return try await self.resolveDNSName(multiaddr: ma)
        }
        // Proceed with `dnsaddr` recursive TXT resolution
        guard let domain = first.addr else { throw Errors.invalidMultiaddr }

        // A trailing `/p2p/<id>` (if present) is used for spec-defined suffix matching.
        // When absent, we return every advertised record for the domain.
        let peerID = try? ma.getPeerID()

        let resolved = try await Self.resolveAddressesRecursively(
            domain: domain,
            peerID: peerID,
            maxDepth: recursionDepth,
            fetch: { try await self.dnsaddrRecords(forDomain: $0) }
        )

        return resolved.isEmpty ? nil : resolved
    }

    /// Resolves a `dnsaddr` multiaddr and returns the first address whose protocols are a superset of `codecs`.
    func resolveMatching(multiaddr ma: Multiaddr, for codecs: Set<MultiaddrProtocol>) async throws -> Multiaddr? {
        guard let resolved = try await self.resolveAll(multiaddr: ma) else { return nil }
        return resolved.first { address in
            Set(address.addresses.map { $0.codec }).isSuperset(of: codecs)
        }
    }

    /// Rescursive `dnsaddr` resolution
    ///
    /// - Parameters:
    ///   - domain: the initial domain (without the `_dnsaddr.` prefix).
    ///   - peerID: optional suffix filter; when set, only records carrying this peer id are kept and followed.
    ///   - maxDepth: the maximum number of `/dnsaddr` indirections to follow.
    ///   - fetch: returns the multiaddrs parsed from the `_dnsaddr.<domain>` TXT records.
    /// - Returns: the de-duplicated set of concrete (non-`dnsaddr`) addresses, preserving discovery order.
    static func resolveAddressesRecursively(
        domain: String,
        peerID: PeerID?,
        maxDepth: Int = DNSAddr.maxRecursionDepth,
        fetch: (_ domain: String) async throws -> [Multiaddr]
    ) async throws -> [Multiaddr] {
        var resolved: [Multiaddr] = []
        var visited: Set<String> = []
        var frontier: [String] = [domain]
        var depth = 0

        while !frontier.isEmpty, depth < maxDepth {
            var next: [String] = []
            for domain in frontier {
                // never resolve the same domain twice.
                guard visited.insert(domain).inserted else { continue }

                for record in try await fetch(domain) {
                    // Spec suffix matching: drop records whose peer id doesn't match the requested one.
                    if let peerID {
                        guard let recordPeerID = try? record.getPeerID(), recordPeerID == peerID else { continue }
                    }

                    if record.addresses.first?.codec == .dnsaddr, let nested = record.addresses.first?.addr {
                        // Another dnsaddr — follow it on the next pass.
                        next.append(nested)
                    } else {
                        resolved.append(record)
                    }
                }
            }
            frontier = next
            depth += 1
        }

        if !frontier.isEmpty {
            // We hit the recursion limit with dnsaddr records still unresolved.
            // Lets return whatever concrete addresses we did find rather than an error.
        }

        // De-duplicate while preserving the order in which addresses were discovered.
        var seen: Set<Multiaddr> = []
        return resolved.filter { seen.insert($0).inserted }
    }

    /// Queries the `_dnsaddr.<domain>` TXT records and parses each `dnsaddr=` entry into a `Multiaddr`.
    private func dnsaddrRecords(forDomain domain: String) async throws -> [Multiaddr] {
        guard let client = self.client else { throw Errors.clientNotInitialized }

        let message = try await client.sendQuery(forHost: Self.dnsAddrPrefix + domain, type: .txt).get()

        var addresses: [Multiaddr] = []
        for answer in message.answers {
            guard case .txt(let record) = answer else { continue }
            for raw in record.resource.rawValues {
                // Valid dnsaddr TXT records begin with `dnsaddr=`, followed by a single multiaddr.
                guard raw.hasPrefix(Self.txtRecordPrefix) else { continue }
                let value = String(raw.dropFirst(Self.txtRecordPrefix.count))
                guard let ma = try? Multiaddr(value) else { continue }
                addresses.append(ma)
            }
        }
        return addresses
    }
}

// MARK: - A/AAAA DNS Resolution

extension DNSAddr {

    /// Resolves a `/dns`, `/dns4`, or `/dns6` multiaddr into concrete `/ip4` / `/ip6` addresses via standard
    /// A/AAAA DNS lookups, preserving the transport suffix (e.g. `/tcp/443/wss/p2p/...`).
    ///
    /// - `/dns4` performs an A (IPv4) lookup, `/dns6` an AAAA (IPv6) lookup, and `/dns` both.
    /// - Returns `nil` for any address that isn't a `/dns*` name (it's already concrete, so there's nothing to do).
    func resolveDNSName(multiaddr ma: Multiaddr) async throws -> [Multiaddr]? {
        guard let host = ma.addresses.first?.addr else { throw Errors.invalidMultiaddr }

        // Which address families to look up, and the ip codec each maps onto.
        let lookups: [(ipv6: Bool, ipCodec: MultiaddrProtocol)]
        switch ma.addresses.first?.codec {
        case .dns4: lookups = [(false, .ip4)]
        case .dns6: lookups = [(true, .ip6)]
        case .dns: lookups = [(false, .ip4), (true, .ip6)]
        default: return nil
        }

        guard let client = self.client else { throw Errors.clientNotInitialized }

        var resolved: [Multiaddr] = []
        for lookup in lookups {
            let socketAddresses: [SocketAddress]
            do {
                if lookup.ipv6 {
                    socketAddresses = try await client.initiateAAAAQuery(host: host, port: 0).get()
                } else {
                    socketAddresses = try await client.initiateAQuery(host: host, port: 0).get()
                }
            } catch {
                // A single family failing (e.g. a name with no AAAA records) shouldn't discard the other's results.
                self.logger.debug("DNS \(lookup.ipv6 ? "AAAA" : "A") lookup failed for \(host): \(error)")
                continue
            }

            for socketAddress in socketAddresses {
                guard let ip = socketAddress.ipAddress else { continue }
                if let rewritten = Self.replacingLeadingHost(of: ma, withIP: ip, codec: lookup.ipCodec) {
                    resolved.append(rewritten)
                }
            }
        }

        // De-duplicate while preserving discovery order.
        var seen: Set<Multiaddr> = []
        let unique = resolved.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique
    }

    /// Returns a copy of `ma` with its leading `/dns*` component replaced by an `/ip4` or `/ip6` component,
    /// preserving every subsequent component (transport, security, `/p2p/...`, etc.).
    static func replacingLeadingHost(of ma: Multiaddr, withIP ip: String, codec: MultiaddrProtocol) -> Multiaddr? {
        do {
            var result = try Multiaddr(codec, address: ip)
            for component in ma.addresses.dropFirst() {
                result = try result.encapsulate(proto: component.codec, address: component.addr)
            }
            return result
        } catch {
            return nil
        }
    }
}

// MARK: - AddressResolver Conformance

extension DNSAddr {

    /// Resolves a DNS-based Multiaddr (`/dnsaddr`, `/dns`, `/dns4`, `/dns6`) into a single underlying address
    /// whose protocols are a superset of the requested `codecs`.
    public func resolve(
        multiaddr ma: Multiaddr,
        for codecs: Set<MultiaddrProtocol>
    ) -> EventLoopFuture<Multiaddr?> {
        self.eventLoop.makeFutureWithTask {
            try await self.resolveMatching(multiaddr: ma, for: codecs)
        }
    }

    /// Resolves a DNS-based Multiaddr into all of its underlying addresses. For `/dnsaddr`, resolution is
    /// recursive — nested `/dnsaddr` records are followed until dialable addresses are reached (bounded by
    /// ``maxRecursionDepth``). For `/dns`, `/dns4`, `/dns6`, A/AAAA records are resolved to `/ip4` / `/ip6`.
    public func resolve(multiaddr ma: Multiaddr) -> EventLoopFuture<[Multiaddr]?> {
        self.eventLoop.makeFutureWithTask {
            try await self.resolveAll(multiaddr: ma)
        }
    }
}

// MARK: Lifecycle conformance

extension DNSAddr {
    /// Synchronous boot hook (used when the application is started via `app.start()`).
    public func willBoot(_ application: Application) throws {
        self.logger.trace("Initializing")
        try self._client.withLockedValue {
            $0 = try DNSClient.connectTCP(on: self.eventLoop, config: self.resolverConfig()).wait()
        }
    }
    
    /// Asynchronous boot hook (used when the application is started via `Application.make(...)`).
    public func willBootAsync(_ application: Application) async throws {
        self.logger.trace("Initializing")
        let client = try await DNSClient.connectTCP(on: self.eventLoop, config: self.resolverConfig()).get()
        self._client.withLockedValue { $0 = client }
    }
    
    public func willShutdown(_ application: Application) {
        self.logger.trace("Shutting Down")
        self.client?.cancelQueries()
        let _ = self.client?.close()
    }
    
    public func willShutdownAsync(_ application: Application) async {
        self.logger.trace("Shutting Down")
        self.client?.cancelQueries()
        try? await self.client?.close().get()
    }
}
