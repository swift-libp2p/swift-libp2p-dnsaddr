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

import LibP2P

#if canImport(dnssd)
import dnssd
#endif

public final class DNSAddr: AddressResolver {
    public static var key: String = "DNSADDR"

    private weak var application: Application!
    private var eventLoop: EventLoop
    private var logger: Logger
    private let uuid: UUID

    init(application: Application) {
        self.application = application
        self.eventLoop = application.eventLoopGroup.next()
        self.logger = application.logger
        self.uuid = UUID()

        self.logger[metadataKey: DNSAddr.key] = .string("[\(uuid.uuidString.prefix(5))]")
    }

    /// Attempts to resovle a DNSADDR record
    public func resolve(multiaddr: Multiaddr, cb: @escaping ([Multiaddr]?) -> Void) {
        DNSAddr.resolve(address: multiaddr, cb: cb)
    }

    public func resolve(
        multiaddr: Multiaddr,
        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp],
        cb: @escaping (Multiaddr?) -> Void
    ) {
        DNSAddr.resolve(address: multiaddr, for: codecs, cb: cb)
    }

    public func resolve(multiaddr: Multiaddr) -> EventLoopFuture<[Multiaddr]?> {
        let promise = eventLoop.makePromise(of: [Multiaddr]?.self)
        DNSAddr.resolve(address: multiaddr) { ma in
            promise.succeed(ma)
        }
        return promise.futureResult
    }

    public func resolve(
        multiaddr: Multiaddr,
        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp]
    ) -> EventLoopFuture<Multiaddr?> {
        let promise = eventLoop.makePromise(of: Multiaddr?.self)
        DNSAddr.resolve(address: multiaddr, for: codecs) { ma in
            promise.succeed(ma)
        }
        return promise.futureResult
    }

    /// Provided a Multiaddr that uses the `dnsaddr` codec, this method will attempt to resolve the domain into it's underyling ip address.
    /// - Note: this method is not recusrive, it will only resolve `dnsaddr`s that are at most 2 layers deep.
    /// - Info: https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md
    static func resolve(
        address ma: Multiaddr,
        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp],
        cb: @escaping (Multiaddr?) -> Void
    ) {
        DNSAddr.resolve(address: ma) { addresses in
            guard let addresses else {
                cb(nil)
                return
            }

            cb(
                addresses.first(where: { addy in
                    Set(addy.addresses.map { $0.codec }).isSuperset(of: codecs)
                })
            )
        }
    }

    //    static func resolve(address ma: Multiaddr) -> [Multiaddr]? {
    //        /// Only proceed if the Mutliaddr is a dnsaddr proto and has a p2p peerID present
    //        guard ma.addresses.first?.codec == .dnsaddr, let domain = ma.addresses.first?.addr, let pid = ma.getPeerID()
    //        else {
    //            print("Error: Multiaddr isn't dnsaddr comppatible.")
    //            return nil
    //        }
    //        let dnsAddrPrefix = "_dnsaddr."
    //
    //        let firstResolution = query(domainName: dnsAddrPrefix + domain)
    //        print(firstResolution)
    //
    //        /// This might resolve to a few different Multiaddr, but if we cant find a MA with the same peerID we bail...
    //        guard
    //            let host = firstResolution?.first(where: { key, val in
    //                key.contains(pid)
    //            })
    //        else {
    //            print("Error: Failed to find host during first round of DNS TXT Resolution")
    //            return nil
    //        }
    //
    //        guard let hostMA = try? Multiaddr(host.key) else {
    //            print("Error: Failed to instantiate Multiaddress from dnsaddr text record.")
    //            return nil
    //        }
    //
    //        /// If the resolved address is another dnsaddr, attempt to resolve it...
    //        guard hostMA.addresses.first?.codec == .dnsaddr, let domain2 = hostMA.addresses.first?.addr,
    //            let pid2 = hostMA.getPeerID(), pid == pid2
    //        else {
    //            return [hostMA]
    //        }
    //
    //        print("Attempting to resolve `\(dnsAddrPrefix + domain2)`")
    //        let secondResolution = query(domainName: dnsAddrPrefix + domain2)
    //        print(secondResolution)
    //
    //        let addresses = secondResolution?.compactMap({ key, val -> Multiaddr? in
    //            /// Ensure its a valid multiaddr
    //            guard let ma = try? Multiaddr(key) else {
    //                print("Error: Invalid Multiaddr -> \(key).")
    //                return nil
    //            }
    //            /// Ensure the PeerID is present and equals that of the original multiaddr
    //            guard let ogPeerID = ma.getPeerID(), ogPeerID == pid else {
    //                print("Error: PeerID Mismatch -> \(pid) != \(ma.getPeerID() ?? "NIL").")
    //                return nil
    //            }
    //            /// return the multiaddr
    //            return ma
    //        })
    //
    //        if let addresses = addresses, !addresses.isEmpty {
    //            return addresses
    //        } else {
    //            print("Error: No Addresses Resolved")
    //            return nil
    //        }
    //    }
    static func resolveSingle(address ma: Multiaddr, cb: @escaping ([Multiaddr]?) -> Void) {
        guard ma.addresses.first?.codec == .dnsaddr, let domain = ma.addresses.first?.addr, let pid = ma.getPeerID()
        else {
            print("Error: Multiaddr isn't dnsaddr comppatible.")
            return cb(nil)
        }
        let dnsAddrPrefix = "_dnsaddr."

        let resolver = DNSRecordResolver()
        resolver.resolve(query: dnsAddrPrefix + domain) { result in
            guard case .success(let firstResolution) = result else {
                print("First resolution failed")
                return cb(nil)
            }
            print(firstResolution)

            /// This might resolve to a few different Multiaddr, but if we cant find a MA with the same peerID we bail...
            guard let host = firstResolution.TXTRecords.first(where: { $0.value.contains(pid) }) else {
                print("Error: Failed to find host during first round of DNS TXT Resolution")
                return cb(nil)
            }

            guard let hostMA = try? Multiaddr(host.value) else {
                print("Error: Failed to instantiate Multiaddress from dnsaddr text record.")
                return cb(nil)
            }

            return cb([hostMA])
        }
    }

    static func resolve(address ma: Multiaddr, cb: @escaping ([Multiaddr]?) -> Void) {
        /// Only proceed if the Mutliaddr is a dnsaddr proto and has a p2p peerID present
        guard ma.addresses.first?.codec == .dnsaddr, let domain = ma.addresses.first?.addr, let pid = ma.getPeerID()
        else {
            print("Error: Multiaddr isn't dnsaddr comppatible.")
            return cb(nil)
        }
        let dnsAddrPrefix = "_dnsaddr."

        let resolver = DNSRecordResolver()
        resolver.resolve(query: dnsAddrPrefix + domain) { result in
            guard case .success(let firstResolution) = result else {
                print("First resolution failed")
                return cb(nil)
            }
            print(firstResolution)

            /// This might resolve to a few different Multiaddr, but if we cant find a MA with the same peerID we bail...
            guard let host = firstResolution.TXTRecords.first(where: { $0.value.contains(pid) }) else {
                print("Error: Failed to find host during first round of DNS TXT Resolution")
                return cb(nil)
            }

            guard let hostMA = try? Multiaddr(host.value) else {
                print("Error: Failed to instantiate Multiaddress from dnsaddr text record.")
                return cb(nil)
            }

            /// If the resolved address is another dnsaddr, attempt to resolve it...
            guard hostMA.addresses.first?.codec == .dnsaddr, let domain2 = hostMA.addresses.first?.addr,
                let pid2 = hostMA.getPeerID(), pid == pid2
            else {
                return cb([hostMA])
            }

            print("Attempting to resolve `\(dnsAddrPrefix + domain2)`")
            let resolver2 = DNSRecordResolver()
            resolver2.resolve(query: dnsAddrPrefix + domain2) { secondResult in
                guard case .success(let secondResolution) = secondResult else {
                    print("Second resolution failed")
                    return cb(nil)
                }
                print(secondResolution)

                let addresses = secondResolution.TXTRecords.compactMap({ record -> Multiaddr? in
                    /// Ensure its a valid multiaddr
                    guard let ma = try? Multiaddr(record.value) else {
                        print("Error: Invalid Multiaddr -> \(key).")
                        return nil
                    }
                    /// Ensure the PeerID is present and equals that of the original multiaddr
                    guard let ogPeerID = ma.getPeerID(), ogPeerID == pid else {
                        print("Error: PeerID Mismatch -> \(pid) != \(ma.getPeerID() ?? "NIL").")
                        return nil
                    }
                    /// return the multiaddr
                    return ma
                })

                if !addresses.isEmpty {
                    return cb(addresses)
                } else {
                    print("Error: No Addresses Resolved")
                    return cb(nil)
                }
            }
        }
    }

    //private func fetchTextRecords(_ ma:Multiaddr)

    /// This method actually performs the DNS Text Record Query using the standard DNS library `dnssd`
    /// - Note: The Key Value dictionary that this method returns is kinda backwards. Due to their being multiple of the same text records, `dnsaddr` in this case, we save the value as the unique key and the record type as the value.
    /// - Instead of this: ["dnsaddr": "/ip4/147.75.109.213/udp/4001/quic/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"]
    /// - We return this:  ["/ip4/147.75.109.213/udp/4001/quic/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN": "dnsaddr"]
    /// - Note: I grabbed this code from this gist (https://gist.github.com/fikeminkel/a9c4bc4d0348527e8df3690e242038d3)
    //    static func query(domainName: String) -> [String: String]? {
    //        #if !canImport(dnssd)
    //        print("LibP2PDNSAddr is not supported on non darwin machines yet")
    //        return nil
    //        #else
    //        var result: [String: String] = [:]
    //        var recordHandler: ([String: String]?) -> Void = {
    //            (record) -> Void in
    //            if record != nil {
    //                for (k, v) in record! {
    //                    result.updateValue(v, forKey: k)
    //                }
    //            }
    //        }
    //
    //        let callback: DNSServiceQueryRecordReply = {
    //            (sdRef, flags, interfaceIndex, errorCode, fullname, rrtype, rrclass, rdlen, rdata, ttl, context) -> Void in
    //            guard let handlerPtr = context?.assumingMemoryBound(to: (([String: String]?) -> Void).self) else {
    //                return
    //            }
    //            let handler = handlerPtr.pointee
    //            if errorCode != kDNSServiceErr_NoError {
    //                return
    //            }
    //            guard let txtPtr = rdata?.assumingMemoryBound(to: UInt8.self) else {
    //                return
    //            }
    //            let txt = String(cString: txtPtr.advanced(by: 1))
    //            var record: [String: String] = [:]
    //            let parts = txt.components(separatedBy: "=")
    //
    //            record[parts[1]] = parts[0]
    //
    //            handler(record)
    //        }
    //
    //        let serviceRef: UnsafeMutablePointer<DNSServiceRef?> = UnsafeMutablePointer.allocate(
    //            capacity: MemoryLayout<DNSServiceRef>.size
    //        )
    //        let code = DNSServiceQueryRecord(
    //            serviceRef,
    //            kDNSServiceFlagsTimeout,
    //            0,
    //            domainName,
    //            UInt16(kDNSServiceType_TXT),
    //            UInt16(kDNSServiceClass_IN),
    //            callback,
    //            &recordHandler
    //        )
    //        if code != kDNSServiceErr_NoError {
    //            return nil
    //        }
    //        DNSServiceProcessResult(serviceRef.pointee)
    //        DNSServiceRefDeallocate(serviceRef.pointee)
    //
    //        return result
    //        #endif
    //    }

    //    static func query(domainName: String, cb: @escaping ([String: String]?) -> Void) {
    //        #if !canImport(dnssd)
    //        print("LibP2PDNSAddr is not supported on non darwin machines yet")
    //        return nil
    //        #else
    //        DispatchQueue.global().async {
    //            var result: [String: String] = [:]
    //            var recordHandler: ([String: String]?) -> Void = {
    //                (record) -> Void in
    //                if record != nil {
    //                    for (k, v) in record! {
    //                        result.updateValue(v, forKey: k)
    //                    }
    //                }
    //            }
    //
    //            let callback: DNSServiceQueryRecordReply = {
    //                (
    //                    sdRef,
    //                    flags,
    //                    interfaceIndex,
    //                    errorCode,
    //                    fullname,
    //                    rrtype,
    //                    rrclass,
    //                    rdlen,
    //                    rdata,
    //                    ttl,
    //                    context
    //                ) -> Void
    //                in
    //                guard let handlerPtr = context?.assumingMemoryBound(to: (([String: String]?) -> Void).self) else {
    //                    return
    //                }
    //                let handler = handlerPtr.pointee
    //                if errorCode != kDNSServiceErr_NoError {
    //                    return
    //                }
    //                guard let txtPtr = rdata?.assumingMemoryBound(to: UInt8.self) else {
    //                    return
    //                }
    //                let txt = String(cString: txtPtr.advanced(by: 1))
    //                var record: [String: String] = [:]
    //                let parts = txt.components(separatedBy: "=")
    //
    //                record[parts[1]] = parts[0]
    //
    //                handler(record)
    //            }
    //
    //            let serviceRef: UnsafeMutablePointer<DNSServiceRef?> = UnsafeMutablePointer.allocate(
    //                capacity: MemoryLayout<DNSServiceRef>.size
    //            )
    //            let code = DNSServiceQueryRecord(
    //                serviceRef,
    //                kDNSServiceFlagsTimeout,
    //                0,
    //                domainName,
    //                UInt16(kDNSServiceType_TXT),
    //                UInt16(kDNSServiceClass_IN),
    //                callback,
    //                &recordHandler
    //            )
    //            DNSServiceProcessResult(serviceRef.pointee)
    //
    //            if code != kDNSServiceErr_NoError {
    //                cb(nil)
    //                DNSServiceRefDeallocate(serviceRef.pointee)
    //                return
    //            }
    //
    //            DNSServiceRefDeallocate(serviceRef.pointee)
    //
    //            cb(result)
    //            return
    //        }
    //        #endif
    //    }
}

extension Multiaddr {

    public func resolve(for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp], cb: @escaping (Multiaddr?) -> Void) {
        DNSAddr.resolve(address: self, for: codecs, cb: cb)
    }

    public func resolve(
        address ma: Multiaddr,
        for codecs: Set<MultiaddrProtocol> = [.ip4, .tcp],
        callback: @escaping (Multiaddr?) -> Void
    ) {
        DNSAddr.resolve(address: self, for: codecs, cb: callback)
    }

}
