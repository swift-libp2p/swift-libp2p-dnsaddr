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

import DNS
import LibP2P
import XCTest

@testable import LibP2PDNSAddr

final class LibP2PDNSAddrTests: XCTestCase {
    #if canImport(dnssd)
    //    func testDNSTextRecordQuery() throws {
    //        let firstResolution = DNSAddr.query(domainName: "_dnsaddr.bootstrap.libp2p.io")
    //        print(firstResolution ?? "NIL")
    //        XCTAssertGreaterThan(firstResolution!.count, 0)
    //
    //        print("Resolving Next...")
    //        guard
    //            let host = firstResolution?.first(where: { key, val in
    //                key.contains("QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")
    //            })
    //        else {
    //            XCTFail("Failed to find host during first round of DNS TXT Resolution")
    //            return
    //        }
    //
    //        guard let hostMA = try? Multiaddr(host.key) else {
    //            XCTFail("Failed to instantiated Multiaddress from dnsaddr text record.")
    //            return
    //        }
    //
    //        print("Attempting to resolve `\("_dnsaddr.\(hostMA.addresses.first!.addr!)")`")
    //        let secondResolution = DNSAddr.query(domainName: "_dnsaddr.\(hostMA.addresses.first!.addr!)")
    //        print(secondResolution ?? "NIL")
    //    }

    //    func testDNSADDRToMultiaddr_IPv4_TCP() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress = "/ip4/139.178.91.71/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.ip4, .tcp]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }
    //
    //    func testDNSADDRToMultiaddr_IPv4_UDP() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress = "/ip4/139.178.91.71/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.ip4, .udp, .quic_v1]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }
    //
    //    func testDNSADDRToMultiaddr_IPv6_TCP() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress = "/ip6/2604:1380:45e3:6e00::1/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.ip6, .tcp]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }
    //
    //    func testDNSADDRToMultiaddr_IPv6_UDP() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress =
    //            "/ip6/2604:1380:45e3:6e00::1/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.ip6, .udp, .quic_v1]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }
    //
    //    func testDNSADDRToMultiaddr_DNS4_TCP_WSS() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress =
    //            "/dns4/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.dns4, .tcp, .wss]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }
    //
    //    func testDNSADDRToMultiaddr_DNS6_TCP_WSS() throws {
    //
    //        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //        let expectedAddress =
    //            "/dns6/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
    //
    //        let resolvedExpectation = expectation(description: "DNSAddrResolved")
    //
    //        do {
    //            DNSAddr.resolve(address: try Multiaddr(address), for: [.dns6, .tcp, .wss]) { resolvedAddress in
    //                XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    //                resolvedExpectation.fulfill()
    //            }
    //        } catch {
    //            XCTFail("\(error)")
    //            resolvedExpectation.fulfill()
    //        }
    //
    //        waitForExpectations(timeout: 3)
    //    }

    // Last try
    func testResolveDNSADDR_Base() throws {
        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let ma = try Multiaddr(address)
        guard ma.addresses.first?.codec == .dnsaddr, let domain = ma.addresses.first?.addr else {
            return XCTFail("Invalid DNSADDR Multiaddr")
        }

        let dnsAddrPrefix = "_dnsaddr."
        let domainToResolve = dnsAddrPrefix + domain

        let resolvedExpectation = expectation(description: "DNSAddrResolved")

        let resolver = DNSRecordResolver()

        DispatchQueue.global().async {
            resolver.resolve(query: domainToResolve) { result in
                switch result {
                case .success(let txtRecord):
                    print("First Results")
                    print(txtRecord.TXTRecords)
                    XCTAssertGreaterThan(txtRecord.TXTRecords.count, 0)
                case .failure(let error):
                    XCTFail("Error 1: \(error)")
                }
                resolvedExpectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)

        let resolvedExpectation2 = expectation(description: "DNSAddrResolved2")

        let domainToResolve2 = "_dnsaddr.sv15.bootstrap.libp2p.io"
        DispatchQueue.global().async {
            resolver.resolve(query: domainToResolve2) { result in
                switch result {
                case .success(let txtRecord):
                    print("Second Results")
                    print(txtRecord.TXTRecords)
                    XCTAssertGreaterThan(txtRecord.TXTRecords.count, 0)
                case .failure(let error):
                    XCTFail("Error 2: \(error)")
                }
                resolvedExpectation2.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
    }

    #endif
}
