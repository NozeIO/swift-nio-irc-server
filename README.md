# SwiftNIO IRC Server

NIOIRC is a Internet Relay Chat protocol implementation for
[SwiftNIO](https://github.com/apple/swift-nio),
a basis for building your own IRC servers and clients,
a sample IRC server, as well as some IRC bots written in the
[Swift](http://swift.org) programming language.

*SwiftNIO IRC Server* is a framework to build IRC servers on top of this.

Want to build a customer-support chat system?
And your customers happen to be Unix people from the 80s?
What a great match!

This Swift package contains the reusable `IRCServer` module,
and the `MiniIRCd`, a small and working IRC sample server.

MiniIRCd also configures and runs:

- [swift-nio-irc-webclient](https://github.com/NozeIO/swift-nio-irc-webclient) -
  a simple IRC webclient + WebSocket gateway based on this module, and
- [swift-nio-irc-eliza](https://github.com/NozeIO/swift-nio-irc-eliza) -
  a cheap yet scalable therapist.


## Importing the module using Swift Package Manager

An example `Package.swift `importing the necessary modules:

```swift
// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "MyOwnIRCServer",
    dependencies: [
        .package(url: "https://github.com/NozeIO/swift-nio-irc-server.git",
                 from: "0.5.0")
    ],
    targets: [
        .target(name: "MyOwnIRCServer",
                dependencies: [ "IRCServer" ])
    ]
)
```


### Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.

NIOIRC is a SwiftNIO port of the
[Noze.io miniirc](https://github.com/NozeIO/Noze.io/tree/master/Samples/miniirc)
example from 2016.
