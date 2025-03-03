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

/// - Info: https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md
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
    private var client: DNSClient? = nil

    init(application: Application) {
        self.application = application
        self.eventLoop = application.eventLoopGroup.next()
        self.logger = application.logger
        self.uuid = UUID()

        self.logger[metadataKey: DNSAddr.key] = .string("[\(uuid.uuidString.prefix(5))]")
    }

    public func willBoot(_ application: Application) throws {
        self.logger.trace("\(DNSAddr.key)::DNSClient Initializing")
        self.client = try DNSClient.connect(on: self.eventLoop.next()).wait()
    }

    public func shutdown(_ application: Application) {
        self.logger.trace("\(DNSAddr.key)::DNSClient Shutdown")
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
            let _ = self.resolveTXTRecords(forHost: dnsAddrPrefix + domain).map { txtRecords in

                var dict: [String: String] = [:]
                for txtRecord in txtRecords {
                    for entry in txtRecord.values {
                        dict[entry.value] = entry.key
                    }
                }

                // This might resolve to a few different Multiaddr, but if we cant find a MA with the same peerID we bail...
                guard
                    let host = dict.first(where: { $0.key.contains(pid) })?.key
                else {
                    print("Error: Failed to find host during first round of DNS TXT Resolution")
                    return promise.fail(Errors.noMatchingHostFound)
                }

                guard let hostMA = try? Multiaddr(host) else {
                    print("Error: Failed to instantiated Multiaddress from dnsaddr text record.")
                    return promise.fail(Errors.invalidMultiaddr)
                }

                // If the resolved address is another dnsaddr, attempt to resolve it...
                guard hostMA.addresses.first?.codec == .dnsaddr, let domain2 = hostMA.addresses.first?.addr,
                    let pid2 = hostMA.getPeerID(), pid == pid2
                else {
                    return promise.succeed([hostMA])
                }

                //print("Attempting to resolve `\(dnsAddrPrefix + domain2)`")
                let _ = self.resolveTXTRecords(forHost: dnsAddrPrefix + domain2).map { txtRecords2 in

                    var dict2: [String: String] = [:]
                    for txtRecord in txtRecords2 {
                        for entry in txtRecord.values {
                            dict2[entry.value] = entry.key
                        }
                    }

                    let addresses = dict2.compactMap({ key, val -> Multiaddr? in
                        // Ensure its a valid multiaddr
                        guard let ma = try? Multiaddr(key) else { return nil }
                        // Ensure the PeerID is present and equals that of the original multiaddr
                        guard ma.getPeerID() == pid else { return nil }
                        // return the multiaddr
                        return ma
                    })

                    if !addresses.isEmpty {
                        return promise.succeed(addresses)
                    } else {
                        return promise.fail(Errors.noMatchingHostFound)
                    }
                }
            }
        }

        return promise.futureResult
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

//extension Multiaddr {
//
//    public func resolve(for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp]) -> Multiaddr? {
//        nil
//        //DNSAddr.resolve(address: self, for: codecs)
//    }
//
//    public func resolve(
//        address ma: Multiaddr,
//        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp],
//        callback: @escaping (Multiaddr?) -> Void
//    ) {
//        callback(nil)
//        //DNSAddr.resolve(address: self, for: codecs, callback: callback)
//    }
//
//}
