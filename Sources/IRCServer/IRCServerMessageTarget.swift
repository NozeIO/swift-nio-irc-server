//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOIRC

public protocol IRCServerMessageTarget : IRCMessageTarget {
  
  var target : String { get }
  
}

public extension IRCServerMessageTarget {
  
  public func sendError(_ code: NIOIRC.IRCCommandCode, message: String? = nil,
                        _ args: String...)
  {
    let enrichedArgs = args + [ message ?? code.errorMessage ]
    let message =
      IRCMessage(origin: origin, target: target, command: .numeric(code, enrichedArgs))
    sendMessage(message)
  }
  
  public func sendReply(_ code: NIOIRC.IRCCommandCode, _ args: String...) {
    let message = IRCMessage(origin: origin, target: target,
                             command: .numeric(code, args))
    sendMessage(message)
  }
  
  public func sendMotD(_ message: String) {
    guard !message.isEmpty else { return }
    let origin = self.origin ?? "??"
    sendReply(.replyMotDStart, "- \(origin) Message of the Day -")
    
    let lines = message.components(separatedBy: "\n")
                       .map { $0.replacingOccurrences(of: "\r", with: "") }
                       .map { "- " + $0 }
    
    let messages = lines.map {
      IRCMessage(origin: origin, command: .numeric(.replyMotD, [ target, $0 ]))
    }
    sendMessages(messages, promise: nil)
    sendReply(.replyEndOfMotD, "End of /MOTD command.")
  }
  
}
