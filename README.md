# LibP2PDNSAddr

[![](https://img.shields.io/badge/made%20by-Breth-blue.svg?style=flat-square)](https://breth.app)
[![](https://img.shields.io/badge/project-libp2p-yellow.svg?style=flat-square)](http://libp2p.io/)
[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-compatible-blue.svg?style=flat-square)](https://github.com/apple/swift-package-manager)
![Build & Test (macos)](https://github.com/swift-libp2p/swift-libp2p-dnsaddr/actions/workflows/build+test.yml/badge.svg)

> DNSAddr Protocol Address / Name Resolution

## Table of Contents

- [Overview](#overview)
- [Install](#install)
- [Usage](#usage)
  - [Example](#example)
  - [API](#api)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Overview
dnsaddr is a protocol that instructs the resolver to lookup multiaddr(s) in DNS TXT records for the domain name in it's value section.

This package adds the ability to resolves multiaddr's of the form 

```Swift
// Given a multiaddr that uses the DNSADDR protocol
let ma = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")

// Resolve it by calling app.resolve
let resolvedAddresses = try await app.resolve(ma).get()

// Yields a list of dialable addresses advertised for that peer
// /dns/sv15.bootstrap.libp2p.io/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN
// /dns/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN
// /dns/sv15.bootstrap.libp2p.io/udp/4001/quic-v1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN
```

#### For more details see 
- [DNSAddr Spec](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)


## Install 
Include the following dependency in your Package.swift file
```Swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-dnsaddr.git", .upToNextMinor(from: "0.3.0"))
    ],
    ...
        .target(
            ...
            dependencies: [
                ...
                .product(name: "LibP2PDNSAddr", package: "swift-libp2p-dnsaddr"),
            ]),
    ...
)
```

## Usage

```Swift
import LibP2PDNSAddr

/// Add the resolver to the applications resolver list. 
app.resolvers.use(.dnsaddr)

/// Or explicitly set your preferred dns resolver
let cloudflareDNS = try SocketAddress(ipAddress: "1.1.1.1", port: 53)
app.resolvers.use(.dnsaddr(host: cloudflareDNS))

/// Or you can set multiple dns resolvers and a specific recursion depth (clamped between 1-8)
let googleDNS = try SocketAddress(ipAddress: "8.8.8.8", port: 53)
app.resolvers.use(.dnsaddr(hosts: [cloudflareDNS, googleDNS], maxRecursionDepth: 5))

/// From here on, when the application encounters a dnsaddr address it will use this package to attempt to resolve it.

```


### Example

```Swift
import LibP2PDNSAddr

app.resolvers.use(.dnsaddr)

let ma = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")

// Resolve every dialable address advertised for the peer
let all = try await app.resolve(ma).get()

// Or resolve a single address matching a preferred transport
let quic = try await app.resolve(ma, for: [.dns, .udp, .quic_v1]).get()
```

### API
```Swift
/// Resolve a `dnsaddr` multiaddr into every dialable address advertised for it.
/// Nested `/dnsaddr` records are followed recursively until concrete addresses are reached.
/// Returns `nil` if the domain advertises no matching records.
func resolve(multiaddr: Multiaddr) -> EventLoopFuture<[Multiaddr]?>

/// Resolve a `dnsaddr` multiaddr, returning the first address whose protocols are a
/// superset of the requested `codecs` (e.g. `[.dns, .tcp]`).
func resolve(multiaddr: Multiaddr, for: Set<MultiaddrProtocol>) -> EventLoopFuture<Multiaddr?>
```

## Contributing

Contributions are welcomed! This code is very much a proof of concept. I can guarantee you there's a better / safer way to accomplish the same results. Any suggestions, improvements, or even just critiques, are welcome! 

Let's make this code better together! 🤝

## Credits

- [DNSAddr Spec](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)

## License

[MIT](LICENSE) © 2026 Breth Inc.
