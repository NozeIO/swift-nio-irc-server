//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2019 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

struct Config {
  
  var ircURL    : URL?
  var webURL    : URL?
  var extWebURL : URL?
  var origin    : String?

  var ircPort : Int? { return ircURL?.port }
  var webPort : Int? { return webURL?.port }
  
  lazy var helpText : String = {
    let cmd = CommandLine.arguments.first ?? "miniircd"
    var help = ""
    help += "Usage: \(cmd) -h or --help\n"
    help += "\n"
    help += "Examples:\n"
    help += "       \(cmd) (run the server with default conf)\n"
    help += "       \(cmd) --irc    'irc://localhost:6667'\n"
    help += "       \(cmd) --web    'http://localhost:1337'\n"
    help += "       \(cmd) --extweb 'ws://irc.noze.io:1337'\n"
    help += "       \(cmd) --origin 'irc.noze.io'\n"
    return help
  }()
  
  init() {
    let args = CommandLine.arguments.dropFirst()
    if args.contains("--help") || args.contains("-h") {
      print(helpText)
      exit(0)
    }
    
    func grabArg(_ short: String, _ long: String? = nil) -> String? {
      let argNames : Set<String>
      if let long = long { argNames = Set([ short, long ]) }
      else { argNames = Set([short])}
      
      #if swift(>=5)
        guard let idx = args.firstIndex(where: { argNames.contains($0) }) else {
          return nil
        }
      #else
        guard let idx = args.index(where: { argNames.contains($0) }) else {
          return nil
        }
      #endif
      guard (idx + 1) < args.endIndex else {
        print("Missing or invalid value for", args[idx], "argument")
        return nil
      }
      return args[idx + 1]
    }
    func grabURLArg(_ short: String, _ long: String? = nil) -> URL? {
      guard let s = grabArg(short, long) else { return nil }
      guard let url = URL(string: s) else {
        print("Invalid URL value for", long ?? short, "argument:", s)
        return nil
      }
      return url
    }
    
    ircURL    = grabURLArg("-i", "--irc")
    webURL    = grabURLArg("-w", "--web")
    extWebURL = grabURLArg("-e", "--extweb") ?? webURL
    origin    = grabArg   ("-o", "--origin") ?? ircURL?.host
  }
}
