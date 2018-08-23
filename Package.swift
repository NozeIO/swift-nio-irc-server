// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "swift-nio-irc-server",
    products: [
        .library   (name: "IRCServer", targets: [ "IRCServer" ]),
        .executable(name: "miniircd",  targets: [ "miniircd"  ])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", 
                 from: "1.9.2"),
        .package(url: "https://github.com/SwiftNIOExtras/swift-nio-irc.git",
                 from: "0.6.1"),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-eliza.git",
                 from: "0.5.2"),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-webclient.git",
                 from: "0.6.1")
    ],
    targets: [
        .target(name: "IRCServer", dependencies: [ "NIO", "NIOIRC" ]),
        .target(name: "miniircd",  dependencies: [ "IRCServer",
                                                   "IRCWebClient",
                                                   "IRCElizaBot" ])
    ]
)
