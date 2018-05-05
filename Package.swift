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
                 .branch("master")),
        .package(url: "https://github.com/NozeIO/swift-nio-irc.git",
                 .branch("nio/master")),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-eliza.git",
                 .branch("nio/master")),
        .package(url: "https://github.com/NozeIO/swift-nio-irc-webclient.git",
                 .branch("nio/master")),
    ],
    targets: [
        .target(name: "IRCServer", dependencies: [ "NIO", "NIOIRC" ]),
        .target(name: "miniircd",  dependencies: [ "IRCServer",
                                                   "IRCWebClient",
                                                   "IRCElizaBot" ])
    ]
)
