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
//
//  SRVResolver.swift
//  NoMAD
//
//  Created by Joel Rennich on 1/1/21.
//

import Foundation

#if canImport(dnssd)
import dnssd
#endif

public enum DNSResolverError: String, Error, Codable {
    case unsupportedPlatform = "Unsupported platform"
    case unableToComplete = "Unable to complete lookup"
}

public typealias TXTResolverResult = Result<TXTResult, DNSResolverError>
public typealias TXTResolverCompletion = (TXTResolverResult) -> Void

#if canImport(dnssd)
class DNSRecordResolver {
    private let queue = DispatchQueue.init(label: "DNSResolution-\(UUID().uuidString.prefix(5))")
    private var dispatchSourceRead: DispatchSourceRead?
    private var timeoutTimer: DispatchSourceTimer?
    private var serviceRef: DNSServiceRef?
    private var socket: dnssd_sock_t = -1
    private var query: String?

    // default to 5 sec lookups, we could maybe make this longer
    // but if you take more than 5 secs to look things up, you'll
    // probably have other problems

    private let timeout = TimeInterval(3)

    var results = [TXTRecord]()
    var completion: TXTResolverCompletion?

    // this processes any results from the system DNS resolver
    // we could parse all the things, but we don't really need the info...

    let queryCallback: DNSServiceQueryRecordReply = {
        (sdRef, flags, interfaceIndex, errorCode, fullname, rrtype, rrclass, rdlen, rdata, ttl, context) -> Void in

        guard let context = context else { return }

        let request: DNSRecordResolver = DNSRecordResolver.bridge(context)

        if let data = rdata?.assumingMemoryBound(to: UInt8.self),
            let record = TXTRecord(data: Data.init(bytes: data, count: Int(rdlen)))
        {
            request.results.append(record)
        }

        if (flags & kDNSServiceFlagsMoreComing) == 0 {
            request.success()
        }
    }

    // These allow for the ObjC -> Swift conversion of a pointer
    // The DNS APIs are a bit... unique

    static func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(obj).toOpaque()
    }

    static func bridge<T: AnyObject>(_ ptr: UnsafeMutableRawPointer) -> T {
        Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }

    func fail() {
        stopQuery()
        completion?(TXTResolverResult.failure(.unableToComplete))
    }

    func success() {
        stopQuery()
        let result = TXTResult(TXTRecords: results, query: query ?? "Unknown Query")
        completion?(TXTResolverResult.success(result))
    }

    private func stopQuery() {
        // be nice and clean things up
        self.timeoutTimer?.cancel()
        self.dispatchSourceRead?.cancel()
    }

    func resolve(query: String, completion: @escaping TXTResolverCompletion) {

        self.completion = completion

        self.query = query
        let namec = query.cString(using: .utf8)

        let result = DNSServiceQueryRecord(
            &self.serviceRef,
            kDNSServiceFlagsReturnIntermediates,
            UInt32(0),
            namec,
            UInt16(kDNSServiceType_TXT),
            UInt16(kDNSServiceClass_IN),
            queryCallback,
            DNSRecordResolver.bridge(self)
        )

        switch result {
        case DNSServiceErrorType(kDNSServiceErr_NoError):

            guard let sdRef = self.serviceRef else {
                fail()
                return
            }

            self.socket = DNSServiceRefSockFD(self.serviceRef)

            guard self.socket != -1 else {
                fail()
                return
            }

            self.dispatchSourceRead = DispatchSource.makeReadSource(fileDescriptor: self.socket, queue: self.queue)

            self.dispatchSourceRead?.setEventHandler(handler: {
                let res = DNSServiceProcessResult(sdRef)
                if res != kDNSServiceErr_NoError {
                    self.fail()
                }
            })

            self.dispatchSourceRead?.setCancelHandler(handler: {
                DNSServiceRefDeallocate(self.serviceRef)
            })

            self.dispatchSourceRead?.resume()

            self.timeoutTimer = DispatchSource.makeTimerSource(flags: [], queue: self.queue)

            self.timeoutTimer?.setEventHandler(handler: {
                self.fail()
            })

            let deadline = DispatchTime(
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(timeout * Double(NSEC_PER_SEC))
            )
            self.timeoutTimer?.schedule(deadline: deadline, repeating: .infinity, leeway: DispatchTimeInterval.never)
            self.timeoutTimer?.resume()

        default:
            self.fail()
        }
    }
}
#else
class DNSRecordResolver {

    func resolve(query: String, completion: @escaping TXTResolverCompletion) {
        print("Multiaddr::DNSADDR Resolution not supported on this platform.")
        completion(.failure(DNSResolverError.unsupportedPlatform))
    }

}
#endif

public struct TXTResult {
    let TXTRecords: [TXTRecord]
    let query: String
}

extension TXTResult: CustomStringConvertible {
    public var description: String {
        var result = "Query for: \(query)"
        result += "\n\tRecord Count: \(TXTRecords.count)"
        for record in TXTRecords {
            result += "\n\t\(record.description)"
        }
        return result
    }
}

public struct TXTRecord: Codable, Equatable {

    let key: String
    let value: String

    init?(data: Data) {
        guard data.count > 1 else { return nil }
        guard let txt = String(data: data.dropFirst(), encoding: .utf8) else {
            print("TXT Record data is not valid utf8 string")
            return nil
        }

        let parts = txt.components(separatedBy: "=")

        key = parts[0]
        value = parts[1]
    }
}

extension TXTRecord: CustomStringConvertible {
    public var description: String {
        "\(key)=\(value)"
    }
}
