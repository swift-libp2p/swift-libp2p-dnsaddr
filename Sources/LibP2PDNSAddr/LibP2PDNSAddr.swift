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

/// DNSAddr
/// Is a protocol used by libp2p to resolve `Multiaddr`s that use the `dnsaddr` protocol.
/// - [Specification](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)
/// ```swift
/// // When configuring your libp2p instance
/// app.resolvers.use(.dnsaddr)
/// ...
/// // Later you can call resolve on any app or req object
/// app.resolve(ma).map { resolvedMultiaddr in ... }
/// req.resolve(ma, for: [.ip4, .tcp]).map { resolvedMultiaddr in ... }
/// ```
public final class DNSAddr: AddressResolver, LifecycleHandler {

    public static var key: String = "DNSADDR"

    public enum Errors: Error {
        case clientNotInitialized
        case invalidMultiaddr
        case noMatchingHostFound
    }

    private weak var application: Application!
    private var eventLoop: EventLoop
    private var logger: Logger
    private let uuid: UUID
    private var client: DNSClient!

    init(application: Application) {
        self.application = application
        self.eventLoop = application.eventLoopGroup.next()
        self.logger = application.logger
        self.uuid = UUID()

        self.logger[metadataKey: DNSAddr.key] = .string("[\(uuid.uuidString.prefix(5))]")
    }

    public func willBoot(_ application: Application) throws {
        self.logger.trace("Initializing")
        // We connect with TCP due to UDP packet size contstraints (UPD seems to max out at 4 records)
        let googleDNS = try SocketAddress(ipAddress: "8.8.8.8", port: 53)
        self.client = try DNSClient.connectTCP(on: self.eventLoop.next(), config: [googleDNS]).wait()
    }

    public func shutdown(_ application: Application) {
        self.logger.trace("Shutting Down")
        self.client?.cancelQueries()
    }

    /// Provided a Multiaddr that uses the `dnsaddr` codec, this method will attempt to resolve the domain into it's underyling ip address.
    /// - Note: this method is not recusrive, it will only resolve `dnsaddr`s that are at most 2 layers deep.
    public func resolve(
        multiaddr: Multiaddr,
        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp]
    ) -> EventLoopFuture<Multiaddr?> {
        self.resolve(multiaddr: multiaddr).map { addresses -> Multiaddr? in
            guard let addresses else { return nil }
            return addresses.first(where: { addy in
                Set(addy.addresses.map { $0.codec }).isSuperset(of: codecs)
            })
        }
    }

    /// Provided a Multiaddr that uses the `dnsaddr` codec, this method will attempt to resolve the domain into it's underyling ip addresses.
    /// - Note: this method is not recusrive, it will only resolve `dnsaddr`s that are at most 2 layers deep.
    public func resolve(multiaddr ma: Multiaddr) -> EventLoopFuture<[Multiaddr]?> {
        let promise = self.eventLoop.makePromise(of: [Multiaddr]?.self)

        self.eventLoop.execute {

            // Only proceed if the Mutliaddr is a dnsaddr proto and has a p2p peerID present
            guard ma.addresses.first?.codec == .dnsaddr, let domain = ma.addresses.first?.addr, let pid = ma.getPeerID()
            else { return promise.fail(Errors.invalidMultiaddr) }

            // Peform the first resolution
            let dnsAddrPrefix = "_dnsaddr."
            let _ = self.resolveAddresses(forHost: dnsAddrPrefix + domain).map { resovledAddresses in

                // This might resolve to a few different Multiaddr, but if we cant find a MA with the same peerID we bail...
                guard let host = resovledAddresses.first(where: { $0.getPeerID() == pid }) else {
                    return promise.fail(Errors.noMatchingHostFound)
                }

                // If the resolved address is another dnsaddr, attempt to resolve it...
                guard host.addresses.first?.codec == .dnsaddr, let domain2 = host.addresses.first?.addr,
                    let pid2 = host.getPeerID(), pid == pid2
                else {
                    return promise.succeed([host])
                }

                let _ = self.resolveAddresses(forHost: dnsAddrPrefix + domain2, enforcingPeerID: pid).map {
                    resovledAddresses2 in
                    if !resovledAddresses2.isEmpty {
                        return promise.succeed(resovledAddresses2)
                    } else {
                        return promise.fail(Errors.noMatchingHostFound)
                    }
                }
            }
        }

        return promise.futureResult
    }

    private func resolveAddresses(forHost host: String, enforcingPeerID: String? = nil) -> EventLoopFuture<[Multiaddr]>
    {
        self.resolveTXTRecords(forHost: host).map { txtRecords in
            // Convert our txtRecords to Multiaddr
            var resovledAddresses: [Multiaddr] = []
            for txtRecord in txtRecords {
                for entry in txtRecord.values {
                    // Ensure the txt records key equals "dnsaddr"
                    guard entry.key == "dnsaddr" else { continue }
                    // Ensure the ttx records value is a valid Multiaddr
                    guard let ma = try? Multiaddr(entry.value) else { continue }
                    // If we're validating the PeerID
                    if let enforcingPeerID {
                        // Ensure that the Multiaddr contains the expected PeerID
                        guard ma.getPeerID() == enforcingPeerID else { continue }
                    }
                    resovledAddresses.append(ma)
                }
            }
            return resovledAddresses
        }
    }

    private func resolveTXTRecords(forHost host: String) -> EventLoopFuture<[TXTRecord]> {
        self.client!.sendQuery(forHost: host, type: .txt).map { results -> [TXTRecord] in
            var values: [TXTRecord] = []
            for answer in results.answers {
                switch answer {
                case .txt(let txtRecord):
                    values.append(txtRecord.resource)
                default:
                    continue
                }
            }
            return values
        }
    }
}
