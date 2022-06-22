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

This package add the ability to resolves multiaddr's of the form 

```Swift
Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa")
```

#### Heads up ‼️
- This package uses the `dnssd` library and doesn't work on Linux at the moment.

#### For more details see 
- [DNSAddr Spec](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)


## Install 
Include the following dependency in your Package.swift file
```Swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-dnsaddr.git", .upToNextMajor(from: "0.0.1"))
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

/// From here on, when the application encounters a dnsaddr address it will use this package to attempt to resolve it.

```


### Example

```Swift

N/A

```

### API
```Swift

N/A

```

## Contributing

Contributions are welcomed! This code is very much a proof of concept. I can guarantee you there's a better / safer way to accomplish the same results. Any suggestions, improvements, or even just critques, are welcome! 

Let's make this code better together! 🤝

## Credits

- [DNSAddr Spec](https://github.com/multiformats/multiaddr/blob/master/protocols/DNSADDR.md)

## License

[MIT](LICENSE) © 2022 Breth Inc.
