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
import XCTest

@testable import LibP2PDNSAddr

final class LibP2PDNSAddrTests: XCTestCase {
    var app: Application!

    override func setUpWithError() throws {
        app = try Application(.detect())
        app.resolvers.use(.dnsaddr)
        try app.start()
    }

    override func tearDownWithError() throws {
        app.shutdown()
    }

    func testDNSADDRToMultiaddr() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddresses = try app.resolve(try Multiaddr(address)).wait()

        guard let resolvedAddresses else {
            XCTFail("No Resolved Multiaddr")
            return
        }
        XCTAssertGreaterThan(resolvedAddresses.count, 0)
    }

    func testDNSADDRToMultiaddr_IPv4_TCP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/139.178.91.71/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.ip4, .tcp]).wait()

        XCTAssertEqual(resolvedAddress, try Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv4_UDP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/139.178.91.71/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.ip4, .udp, .quic_v1]).wait()

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv6_TCP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip6/2604:1380:45e3:6e00::1/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.ip6, .tcp]).wait()

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv6_UDP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/ip6/2604:1380:45e3:6e00::1/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.ip6, .udp, .quic_v1]).wait()

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_DNS4_TCP_WSS() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns4/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.dns4, .tcp, .wss]).wait()

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_DNS6_TCP_WSS() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns6/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = try app.resolve(try Multiaddr(address), for: [.dns6, .tcp, .wss]).wait()

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

}
