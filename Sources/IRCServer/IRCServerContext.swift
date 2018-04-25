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

import struct Foundation.Date
import NIOIRC

/**
 * All the state related to an IRC server. Assigned nicks, channels, etc.
 *
 * This object is created as part of the `IRCServer` setup. It encapsulates the
 * IRC specific data.
 * It also maintains a Readers-Writers lock to protect cross-eventloop access
 * to the context.
 */
open class IRCServerContext {
  
  typealias Error = IRCServerError
  
  public let origin  : String
  public let logger  : IRCLogger
  public let created = Date()
  
  private var lock          = RWLock()
  private var nickToSession = [ IRCNickName    : IRCSessionHandler ]()
  private var nameToChannel = [ IRCChannelName : IRCChannel ]()
  
  /// When a consumer queries server information, we snapshot that as part of
  /// this immutable ServerInfo object (which we create, release the lock and
  /// then return).
  public struct ServerInfo {
    let userCount      : Int
    let invisibleCount : Int
    let serverCount    : Int
    let operatorCount  : Int
    let channelCount   : Int
  }
  
  init(origin: String, logger: IRCLogger) {
    self.origin = origin
    self.logger = logger

    registerDefaultChannels()
  }
  
  open func registerDefaultChannels() {
    let defaultChannels = [
      "#NIO",
      "#SwiftDE",
      "#NozeIO", "#ZeeQL", "#ApacheExpress", "#PLSwift", "#SwiftXcode",
      "#mod_swift",
      "#ZeeZide"
    ]
    for channel in defaultChannels {
      guard let name = IRCChannelName(channel) else {
        fatalError("invalid channel name: \(channel)")
      }
      nameToChannel[name] = IRCChannel(name: name, context: self)
    }
  }
  
  func getServerInfo() -> ServerInfo {
    lock.lockForReading(); defer { lock.unlock() }
    let info = ServerInfo(userCount      : nickToSession.count,
                          invisibleCount : 0,
                          serverCount    : 1,
                          operatorCount  : 1,
                          channelCount   : nameToChannel.count)
    return info
  }
  
  func getSessions() -> [ IRCSessionHandler ] {
    lock.lockForReading(); defer { lock.unlock() }
    return Array(nickToSession.values)
  }
  
  func getSessions(in channel: IRCChannelName) -> [ IRCSessionHandler ]? {
    lock.lockForReading(); defer { lock.unlock() }
    guard let existingChannel = nameToChannel[channel] else { return nil }
    return existingChannel.subscribers
  }
  func getSession(of nick: IRCNickName) -> IRCSessionHandler? {
    lock.lockForReading(); defer { lock.unlock() }
    return nickToSession[nick]
  }
  
  func getNicksOnline() -> [ IRCNickName ] {
    lock.lockForReading(); defer { lock.unlock() }
    return Array(nickToSession.keys)
  }
  
  // MARK: - Channels
  
  func getChannelMode(_ name: IRCChannelName) -> IRCChannelMode? {
    lock.lockForReading(); defer { lock.unlock() }
    return nameToChannel[name]?.mode
  }
  
  func getChannelInfos(_ channels: [ IRCChannelName ]?) -> [ IRCChannel.Info ] {
    lock.lockForReading(); defer { lock.unlock() }
    
    if let channelNames = channels {
      #if swift(>=4.1)
        let channels = channelNames.compactMap({ self.nameToChannel[$0] })
      #else
        let channels = channelNames.flatMap({ self.nameToChannel[$0] })
      #endif
      
      return channels.map { $0.getInfo() }
    }
    else {
      return nameToChannel.values.map { $0.getInfo() }
    }
  }
  
  func joinChannel(_ name: IRCChannelName, session: IRCSessionHandler)
         -> IRCChannel.Info
  {
    lock.lockForWriting(); defer { lock.unlock() }
    
    let channel : IRCChannel
    
    if let existingChannel = nameToChannel[name] {
      channel = existingChannel
    }
    else {
      channel = IRCChannel(name: name, context: self)
      nameToChannel[name] = channel
      
      // only works because we happen run in the session thread
      assert(session.channel?.eventLoop.inEventLoop ?? false,
             "not running in session eventloop")
      if let nick = session.nick {
        channel.operators.insert(nick)
      }
    }
    
    _ = channel.join(session)
    
    return channel.getInfo()
  }
  
  func partChannel(_ name: IRCChannelName, session: IRCSessionHandler) {
    lock.lockForWriting(); defer { lock.unlock() }
    guard let existingChannel = nameToChannel[name] else { return }
    _ = existingChannel.part(session)
  }
  
  
  // MARK: - Nick handling
  
  func renameNick(from oldNick: IRCNickName, to newNick: IRCNickName) throws {
    guard oldNick != newNick else { return }
    lock.lockForWriting(); defer { lock.unlock() }
    
    guard nickToSession[newNick] == nil else {
      throw Error.nicknameInUse(newNick)
    }
    
    guard let session = nickToSession.removeValue(forKey: oldNick) else {
      throw Error.noSuchNick(oldNick)
    }
    
    nickToSession[newNick] = session
  }
  
  func registerSession(_ session: IRCSessionHandler, nick: IRCNickName) throws {
    lock.lockForWriting(); defer { lock.unlock() }
    
    guard nickToSession[nick] == nil else {
      throw Error.nicknameInUse(nick)
    }
    nickToSession[nick] = session
  }

  func unregisterSession(_ session: IRCSessionHandler, nick: IRCNickName)
         throws
  {
    lock.lockForWriting(); defer { lock.unlock() }
    
    guard nickToSession[nick] != nil else { throw Error.noSuchNick(nick) }
    guard nickToSession[nick] === session else {
      assert(nickToSession[nick] === session,
             "attempt to unregister nick of different session \(nick)?")
      return
    }
    
    nickToSession.removeValue(forKey: nick)
  }
}
