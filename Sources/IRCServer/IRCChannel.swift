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

/**
 * Object used to track channels. This is owned and maintained by the
 * IRCServerContext.
 */
open class IRCChannel {
  
  /// When a consumer wants information about a channel, we put it into this
  /// immutable object and return it.
  public struct Info {
    let name        : IRCChannelName
    let welcome     : String
    let operators   : Set<IRCNickName>
    let subscribers : [ IRCSessionHandler ]
    let mode        : IRCChannelMode
  }
  
  weak var context : IRCServerContext?
  public let name  : IRCChannelName
  
  // Careful: owned and write protected by ServerContext
  var welcome      : String
  var operators    = Set<IRCNickName>()
  var subscribers  = [ IRCSessionHandler ]()
  var mode         : IRCChannelMode = [ .noOutsideClients,
                                        .topicOnlyByOperator ]

  // TODO: mode, e.g. can be invite-only (needs a invite list)
  
  public init(name: IRCChannelName, welcome: String? = nil,
              context: IRCServerContext)
  {
    self.name    = name
    self.context = context
    self.welcome = welcome ?? "Welcome to \(name.stringValue)!"
  }
  
  
  // MARK: - Subscription

  /// Returns an immutable copy of the channel state
  open func getInfo() -> Info { // T: r+lock by ctx
    return Info(name        : name,
                welcome     : welcome,
                operators   : operators,
                subscribers : subscribers,
                mode        : mode)
  }
  
  open func join(_ session: IRCSessionHandler) -> Bool { // T: wlock by ctx
    guard subscribers.index(where: {$0 === session}) == nil else {
      return false // already subscribed
    }
    
    subscribers.append(session)
    return true
  }
  
  open func part(_ session: IRCSessionHandler) -> Bool { // T: wlock by ctx
    guard let idx = subscribers.index(where: {$0 === session}) else {
      return false // not subscribed
    }
    
    subscribers.remove(at: idx)
    return true
  }
}
