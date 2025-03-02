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
    /// An example response from querying `_dnsaddr.bootstrap.libp2p.io` for their text records
    /// DNS Response(
    ///     id: 0,
    ///     returnCode: 0,
    ///     authoritativeAnswer: false,
    ///     truncation: false,
    ///     recursionDesired: false,
    ///     recursionAvailable: true,
    ///     questions: [
    ///         DNS.Question(name: "_dnsaddr.bootstrap.libp2p.io.", type: TXT, unique: false, internetClass: A)
    ///     ],
    ///     answers: [],
    ///     authorities: [
    ///         DNS.Record(name: "libp2p.io.", type: NS, internetClass: A, unique: false, ttl: 819, data: 18 bytes),
    ///         DNS.Record(name: "libp2p.io.", type: NS, internetClass: A, unique: false, ttl: 819, data: 6 bytes),
    ///         DNS.Record(name: "libp2p.io.", type: NS, internetClass: A, unique: false, ttl: 819, data: 6 bytes),
    ///         DNS.Record(name: "libp2p.io.", type: NS, internetClass: A, unique: false, ttl: 819, data: 6 bytes)
    ///     ],
    ///     additional: [
    ///         DNS.HostRecord<DNS.IPv4>(name: "ns4.dnsimple.com.", unique: false, internetClass: A, ttl: 41571, ip: 162.159.27.4),
    ///         DNS.HostRecord<DNS.IPv6>(name: "ns4.dnsimple.com.", unique: false, internetClass: A, ttl: 163418, ip: 2400:cb00:2049:1::a29f:1b04),
    ///         DNS.HostRecord<DNS.IPv4>(name: "ns2.dnsimple.com.", unique: false, internetClass: A, ttl: 41571, ip: 162.159.25.4),
    ///         DNS.HostRecord<DNS.IPv6>(name: "ns2.dnsimple.com.", unique: false, internetClass: A, ttl: 169707, ip: 2400:cb00:2049:1::a29f:1904),
    ///         DNS.HostRecord<DNS.IPv4>(name: "ns1.dnsimple.com.", unique: false, internetClass: A, ttl: 41571, ip: 162.159.24.4),
    ///         DNS.HostRecord<DNS.IPv6>(name: "ns1.dnsimple.com.", unique: false, internetClass: A, ttl: 182, ip: 2400:cb00:2049:1::a29f:1804),
    ///         DNS.HostRecord<DNS.IPv4>(name: "ns3.dnsimple.com.", unique: false, internetClass: A, ttl: 41571, ip: 162.159.26.4),
    ///         DNS.HostRecord<DNS.IPv6>(name: "ns3.dnsimple.com.", unique: false, internetClass: A, ttl: 169707, ip: 2400:cb00:2049:1::a29f:1a04)
    ///     ]
    /// )
    ///
    /// DNS Response(
    ///     id: 0,
    ///     returnCode: 0,
    ///     authoritativeAnswer: false,
    ///     truncation: false,
    ///     recursionDesired: false,
    ///     recursionAvailable: true,
    ///     questions: [
    ///         DNS.Question(name: "_dnsaddr.scj-1.bootstrap.162.159.26.4.", type: TXT, unique: false, internetClass: A)
    ///     ],
    ///     answers: [],
    ///     authorities: [
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 20 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes),
    ///         DNS.Record(name: ".", type: NS, internetClass: A, unique: false, ttl: 32603, data: 4 bytes)
    ///     ],
    ///     additional: [
    ///         DNS.HostRecord<DNS.IPv4>(name: "l.root-servers.net.", unique: false, internetClass: A, ttl: 3546547, ip: 199.7.83.42),
    ///         DNS.HostRecord<DNS.IPv6>(name: "l.root-servers.net.", unique: false, internetClass: A, ttl: 3547397, ip: 2001:500:9f::42),
    ///         DNS.HostRecord<DNS.IPv4>(name: "k.root-servers.net.", unique: false, internetClass: A, ttl: 3546282, ip: 193.0.14.129),
    ///         DNS.HostRecord<DNS.IPv6>(name: "k.root-servers.net.", unique: false, internetClass: A, ttl: 3541719, ip: 2001:7fd::1),
    ///         DNS.HostRecord<DNS.IPv4>(name: "j.root-servers.net.", unique: false, internetClass: A, ttl: 3546529, ip: 192.58.128.30),
    ///         DNS.HostRecord<DNS.IPv6>(name: "j.root-servers.net.", unique: false, internetClass: A, ttl: 3548206, ip: 2001:503:c27::2:30),
    ///         DNS.HostRecord<DNS.IPv4>(name: "i.root-servers.net.", unique: false, internetClass: A, ttl: 3546283, ip: 192.36.148.17),
    ///         DNS.HostRecord<DNS.IPv6>(name: "i.root-servers.net.", unique: false, internetClass: A, ttl: 3541307, ip: 2001:7fe::53),
    ///         DNS.HostRecord<DNS.IPv4>(name: "a.root-servers.net.", unique: false, internetClass: A, ttl: 3549702, ip: 198.41.0.4),
    ///         DNS.HostRecord<DNS.IPv6>(name: "a.root-servers.net.", unique: false, internetClass: A, ttl: 3594219, ip: 2001:503:ba3e::2:30),
    ///         DNS.HostRecord<DNS.IPv4>(name: "h.root-servers.net.", unique: false, internetClass: A, ttl: 3547432, ip: 198.97.190.53)
    ///     ]
    /// )
    //    func testUDP_DNS_Serivce_Query() throws {
    //        /// 192.168.1.1:53 UDP is the local networks router DNS portal (change this to match your network setup)
    //        let remoteAddress = try! SocketAddress(ipAddress: "192.168.1.1", port: 53)
    //        //let remoteAddress = try! SocketAddress(ipAddress: "162.159.26.4", port: 53)
    //        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    //
    //        let bootstrap = DatagramBootstrap(group: group)
    //            // Enable SO_REUSEADDR.
    //            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    //            .channelInitializer { channel in
    //                channel.pipeline.addHandler(DNSHandler(remoteAddress: remoteAddress))
    //        }
    //
    //        let channel = try bootstrap.bind(host: "192.168.1.15", port: 1234).wait()
    //
    //        try channel.closeFuture.wait()
    //
    //        try! group.syncShutdownGracefully()
    //    }

    private final class DNSHandler: ChannelInboundHandler {
        public typealias InboundIn = AddressedEnvelope<ByteBuffer>
        public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

        private let remoteAddress: SocketAddress

        private var didReceiveData: Bool = false
        //private var buf:ByteBuffer = ByteBuffer()

        init(remoteAddress: SocketAddress) {
            self.remoteAddress = remoteAddress
        }

        public func channelActive(context: ChannelHandlerContext) {

            do {
                // Channel is available. It's time to send the message to the server to initialize the ping-pong sequence.

                // Get the server address.
                //let remoteAddress = try self.remoteAddress

                print("Sending DNS Query...")

                //let question = Question(name: "_dnsaddr.bootstrap.libp2p.io", type: .pointer)
                let question = Question(name: "_dnsaddr.sjc-1.bootstrap.libp2p.io", type: .text)
                //let question = Question(name: "143.244.60.109", type: .text)
                //let question = Question(name: "apple.com", type: .pointer)
                //                let question = Question(name: "google.com", type: .pointer)
                //let question = Question(name: "brandontoms.com", type: .text)

                let query = Message(
                    ///id: UInt16.random(in: 0...UInt16.max),
                    type: .query,
                    recursionDesired: false,
                    questions: [question]
                )

                // Set the transmission data.
                let buffer = context.channel.allocator.buffer(bytes: try query.serialize())

                // Forward the data.
                let envelope = AddressedEnvelope<ByteBuffer>(remoteAddress: remoteAddress, data: buffer)

                context.writeAndFlush(self.wrapOutboundOut(envelope), promise: nil)

            } catch {
                print("Could not resolve remote address")
            }
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let envelope = self.unwrapInboundIn(data)
            let byteBuffer = envelope.data
            //            buf. += envelope.data

            let responseData = Data(byteBuffer.readableBytesView)
            let response = try! DNS.Message.init(deserialize: responseData)
            print(response)

            //let string = String(buffer: byteBuffer)
            //print(string)

            if !didReceiveData {
                didReceiveData = true
                context.eventLoop.scheduleTask(in: .seconds(2)) {

                    context.close(promise: nil)
                }
            }
        }

        public func errorCaught(context: ChannelHandlerContext, error: Error) {
            print("error: ", error)

            // As we are not really interested getting notified on success or failure we just pass nil as promise to
            // reduce allocations.
            context.close(promise: nil)
        }
    }

    func testDNSTextRecordQuery() throws {
        let firstResolution = DNSAddr.query(domainName: "_dnsaddr.bootstrap.libp2p.io")
        print(firstResolution ?? "NIL")
        XCTAssertEqual(firstResolution!.count, 6)

        print("Resolving Next...")
        guard
            let host = firstResolution?.first(where: { key, val in
                key.contains("QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")
            })
        else {
            XCTFail("Failed to find host during first round of DNS TXT Resolution")
            return
        }

        guard let hostMA = try? Multiaddr(host.key) else {
            XCTFail("Failed to instantiated Multiaddress from dnsaddr text record.")
            return
        }

        print("Attempting to resolve `\("_dnsaddr.\(hostMA.addresses.first!.addr!)")`")
        let secondResolution = DNSAddr.query(domainName: "_dnsaddr.\(hostMA.addresses.first!.addr!)")
        print(secondResolution ?? "NIL")
    }

    func testDNSADDRToMultiaddr_IPv4_TCP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/147.75.109.213/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.ip4, .tcp])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv4_UDP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip4/147.75.109.213/udp/4001/quic/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.ip4, .udp, .quic])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv6_TCP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress = "/ip6/2604:1380:1000:6000::1/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.ip6, .tcp])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_IPv6_UDP() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/ip6/2604:1380:1000:6000::1/udp/4001/quic/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.ip6, .udp])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_DNS4_TCP_WSS() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns4/sjc-1.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.dns4, .tcp, .wss])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    func testDNSADDRToMultiaddr_DNS6_TCP_WSS() throws {

        let address = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
        let expectedAddress =
            "/dns6/sjc-1.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"

        let resolvedAddress = DNSAddr.resolve(address: try! Multiaddr(address), for: [.dns6, .tcp, .wss])

        XCTAssertEqual(resolvedAddress, try! Multiaddr(expectedAddress))
    }

    static var allTests = [
        //("testUDP_DNS_Serivce_Query", testUDP_DNS_Serivce_Query),
        ("testDNSTextRecordQuery", testDNSTextRecordQuery),
        ("testDNSADDRToMultiaddr_IPv4_TCP", testDNSADDRToMultiaddr_IPv4_TCP),
        ("testDNSADDRToMultiaddr_IPv4_UDP", testDNSADDRToMultiaddr_IPv4_UDP),
        ("testDNSADDRToMultiaddr_IPv6_TCP", testDNSADDRToMultiaddr_IPv6_TCP),
        ("testDNSADDRToMultiaddr_IPv6_UDP", testDNSADDRToMultiaddr_IPv6_UDP),
        ("testDNSADDRToMultiaddr_DNS4_TCP_WSS", testDNSADDRToMultiaddr_DNS4_TCP_WSS),
        ("testDNSADDRToMultiaddr_DNS6_TCP_WSS", testDNSADDRToMultiaddr_DNS6_TCP_WSS),
    ]
}
