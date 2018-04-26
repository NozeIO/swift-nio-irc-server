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
                 from: "1.5.1"),
        .package(url: "https://github.com/NozeIO/swift-nio-irc",
                 from: "0.5.0"),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-eliza",
                 from: "0.5.0"),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-webclient",
                 from: "0.5.1")
    ],
    targets: [
        .target(name: "IRCServer", dependencies: [ "NIO", "NIOIRC" ]),
        .target(name: "miniircd",  dependencies: [ "IRCServer",
                                                   "IRCWebClient",
                                                   "IRCElizaBot" ])
    ]
)
