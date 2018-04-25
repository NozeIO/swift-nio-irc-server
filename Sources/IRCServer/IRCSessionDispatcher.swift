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

import NIO
import NIOIRC

extension IRCSessionHandler : IRCDispatcher {
  
  public func doPing(_ server: String, server2: String? = nil) throws {
    let msg : IRCMessage
    
    if let server2 = server2, server2 != self.server.origin {
      return sendError(.errorNoSuchServer, server2)
    }

    msg = IRCMessage(origin: origin,
                     command: .PONG(server: self.server.origin,
                                    server2: server))
    sendMessage(msg)
  }
  
  public func doNick(_ nick: IRCNickName) throws {
    if let oldNick = state.nick {
      if oldNick == nick { return } // same, nothing to do
      
      let maskBeforeRename = userID?.stringValue
      
      try server.renameNick(from: oldNick, to: nick)
      state.changeNick(to: nick)

      let msg = IRCMessage(origin: maskBeforeRename ?? origin,
                           command: .NICK(nick))
      sendMessage(msg)
    }
    else {
      try server.registerSession(self, nick: nick)
      state.changeNick(to: nick)
    }
  }
  
  public func doUserInfo(_ info: IRCUserInfo) throws {
    guard !state.isRegistered else {
      throw IRCServerError.alreadyRegistered
    }
    
    if let nick = state.nick {
      state = .registered(nick, info)
      assert(state.isRegistered)
    }
    else {
      state = .userSet(info)
    }
  }

  public func doModeGet(nick: IRCNickName) throws {
    guard state.isRegistered, let myNick = self.nick else {
      throw IRCServerError.notRegistered
    }
    guard nick == myNick else { // same error on freenode
      throw IRCServerError.cantChangeModeForOtherUsers
    }
    
    if mode.isEmpty { sendReply(.replyUModeIs, "") }
    else            { sendReply(.replyUModeIs, "+" + mode.stringValue) }
  }

  public func doMode(nick: IRCNickName, add: IRCUserMode, remove: IRCUserMode)
                throws
  {
    guard state.isRegistered, let myNick = self.nick else {
      throw IRCServerError.notRegistered
    }
    guard nick == myNick else {
      throw IRCServerError.cantChangeModeForOtherUsers
    }
    
    var newMode = mode
    newMode.subtract(remove)
    newMode.formUnion(add)
    
    guard newMode != mode else { return } // no reply if the same
    mode = newMode
    
    let command = IRCCommand.MODE(nick, add: mode, remove: remove)
    sendMessage(IRCMessage(origin: origin, command: command))
  }
  
  public func doModeGet(channel: IRCChannelName) throws {
    guard state.isRegistered else { throw IRCServerError.notRegistered }
    
    guard let mode = server.getChannelMode(channel) else {
      throw IRCServerError.noSuchChannel(channel)
    }
    
    let s = mode.isEmpty ? "" : "+" + mode.stringValue
    sendReply(.replyChannelModeIs, channel.stringValue, s)
  }
  
  public func doGetBanMask(_ channel: IRCChannelName) throws {
    guard state.isRegistered else { throw IRCServerError.notRegistered }
    
    // we don't ban yet :-)
    sendReply(.replyEndOfBanList, channel.stringValue,
              "End of Channel Ban List")
  }

  public func doCAP(_ cmd: IRCCommand.CAPSubCommand, _ capIDs: [ String ])
                throws
  {
    let reply : IRCCommand
    
    switch cmd {
      case .LS:
        reply = .CAP(.LS, Array(IRCSessionHandler.serverCapabilities))
      
      case .REQ:
        for id in capIDs {
          guard IRCSessionHandler.serverCapabilities.contains(id) else {
            throw IRCParserError.invalidCAPCommand(cmd.commandAsString)
          }
        }
        activeCapabilities = Set(capIDs)
        reply = .CAP(.ACK, Array(activeCapabilities))
      
      case .END:
        return // no reply
      
      default: throw IRCParserError.invalidCAPCommand(cmd.commandAsString)
    }

    sendMessage(IRCMessage(origin: origin, target: target, command: reply))
  }
  
  public func doWhoIs(server: String?, usermasks: [ String ]) throws {
    guard let myNick = self.nick, let info = state.userInfo else {
      throw IRCServerError.notRegistered
    }
    if let server = server, server != self.server.origin {
      return sendError(.errorNoSuchServer, server)
    }
    
    for mask in usermasks {
      // TODO: here we would need to query the other connections for the user.
      guard myNick.stringValue == mask else { continue } // yeah
      
      sendReply(.replyWhoIsUser, mask,
                "~" + info.username,
                target, // IP of user connection
                "*", info.realname)
    }
    
    sendReply(.replyWhoIsServer, origin ?? "??", "The Interwebs")
    
    // for other users Freenode also sends a 330 (is logged in as)
    // for own: 378 :is connecting from
    // for own: replyWhoIsIdle (317) // 2 1524052910 :seconds idle, signon time
    
    sendReply(.replyEndOfWhoIs, usermasks.joined(separator: ","),
              "End of /WHOIS list")
  }

  public func doWho(mask: String?, operatorsOnly opOnly: Bool) throws {
    // WHO #nio
    let sessions : [ IRCSessionHandler ]
    let channel  : IRCChannelName?
    
    if let mask = mask, let channelName = IRCChannelName(mask) {
      guard let cs = server.getSessions(in: channelName) else {
        throw IRCServerError.noSuchChannel(channelName)
      }
      channel  = channelName
      sessions = cs
    }
    else {
      channel  = nil
      sessions = server.getSessions()
    }
    
    struct WhoInfo {
      let nick     : IRCNickName
      let userInfo : IRCUserInfo
      let target   : String
      let hostmask : String?
    }
    func getSessionInfo(_ session : IRCSessionHandler) -> WhoInfo? {
      guard let nick = session.nick, let info = session.state.userInfo else {
        return nil
      }
      return WhoInfo(nick: nick, userInfo: info, target: session.target,
                     hostmask: session.userID?.stringValue)
    }
    
    getValues(from: sessions, map: getSessionInfo) { infos in
      for info in infos {
        guard let info = info else { continue }
        
        self.sendReply(.replyWhoReply,
                       channel?.stringValue ?? "*",
                       info.userInfo.username,
                       info.target, // TBD
                       info.userInfo.servername ?? self.origin ?? "?",
                       info.nick.stringValue,
                       "H", // TODO: not explained in the RFCs ...
                       "0 \(info.userInfo.realname)")
      }
      self.sendReply(.replyEndOfWho, mask ?? "*", "End of /WHO list")

      self.channel?.flush()
    }
  }

  public func doJoin(_ channelNames: [ IRCChannelName ]) throws {
    guard state.isRegistered else { throw IRCServerError.notRegistered }
    guard !channelNames.isEmpty else { return }
    
    var nicksRequested       = [ ObjectIdentifier : IRCSessionHandler ]()
    var channelToNickRequest = [ IRCChannelName : [ ObjectIdentifier ] ]()
    
    for name in channelNames {
      guard !joinedChannels.contains(name) else { continue }
      
      let info = server.joinChannel(name, session: self)
      joinedChannels.insert(info.name)
      
      let msg = IRCMessage(origin: userID?.stringValue,
                           command: .JOIN(channels: [name], keys: nil))
      server.getSessions(in: name)?.forEach { $0.sendMessage(msg) }

      sendReply(.replyTopic, name.stringValue, info.welcome) // topic vs welcome
      
      // Freenode also sends a 333, unknown
      channelToNickRequest[name] = info.subscribers.map { ObjectIdentifier($0) }
      for session in info.subscribers {
        nicksRequested[ObjectIdentifier(session)] = session
      }
      
      // TBD: Do the clients need the member reply ordered? Or can they properly
      //      key on the channel name?
    }
    
    getValues(from: nicksRequested.values,
              map: { (ObjectIdentifier($0), $0.nick) })
    { oidNickPairs in
      
      var oidToNick = [ ObjectIdentifier : IRCNickName ]()
      oidToNick.reserveCapacity(oidNickPairs.count)
      
      for ( oid, nick ) in oidNickPairs {
        oidToNick[oid] = nick
      }
      
      for ( channelName, oids ) in channelToNickRequest {
        var members = [ IRCNickName ]()
        members.reserveCapacity(oids.count)
        for oid in oids {
          guard let nick = oidToNick[oid] else { continue }
          members.append(nick)
        }
        
        self.sendReply(.replyNameReply, "=", channelName.stringValue,
                       members.map { $0.stringValue }.joined(separator: " "))
        self.sendReply(.replyEndOfNames, channelName.stringValue,
                       "End of /NAMES list")
      }
      
      self.channel?.flush()
    }
  }
  
  public func doPart(_ channelNames: [ IRCChannelName ], message: String?)
                throws
  {
    guard !channelNames.isEmpty else { return }
    
    for name in channelNames {
      guard joinedChannels.contains(name) else { continue }
      
      let msg = IRCMessage(origin: userID?.stringValue,
                           command: .PART(channels: [name], message: message))
      server.getSessions(in: name)?.forEach { $0.sendMessage(msg) }
      
      server.partChannel(name, session: self)
      joinedChannels.remove(name)
    }
  }
  
  public func doMessage(sender: IRCUserID?,
                        recipients: [ IRCMessageRecipient ], message: String)
                throws
  {
    let sender = userID?.stringValue // Note: we do ignore the sender!
    
    for target in recipients {
      switch target {
        case .everything:
          sendReply(.errorNoSuchNick, "*", "No such nick/channel")
        
        case .nickname(let nick):
          guard let targetSession = server.getSession(of: nick) else {
            sendReply(.errorNoSuchNick, nick.stringValue,
                      "No such nick/channel '\(nick.stringValue)'")
            continue
          }
          
          let message = IRCMessage(origin: sender,
                                   command: .PRIVMSG([ target ], message))
          targetSession.sendMessage(message)
        
        case .channel(let channelName):
          // TODO: complicated: exclude self?! No => OID
          guard let targetSessions = server.getSessions(in: channelName) else {
            sendReply(.errorNoSuchChannel, channelName.stringValue,
                      "No such channel '\(channelName.stringValue)'")
            continue
          }
          
          let message = IRCMessage(origin: sender,
                                   command: .PRIVMSG([ target ], message))
          for session in targetSessions {
            guard session !== self else { continue }
            session.sendMessage(message)
          }
      }
    }
  }
  
  public func doIsOnline(_ nicks: [ IRCNickName ]) throws {
    guard state.isRegistered else { throw IRCServerError.notRegistered }
    
    let requestedNicks = Set(nicks)
    let result = requestedNicks.intersection(server.getNicksOnline())
    let s = result.map { $0.stringValue }.joined(separator: " ")
    sendReply(.replyISON, s)
  }
  
  public func doList(_ channels: [ IRCChannelName ]?, _ target: String?)
                throws
  {
    guard state.isRegistered else { throw IRCServerError.notRegistered }
    
    if let server = target, server != self.server.origin {
      return sendError(.errorNoSuchServer, server)
    }
    
    sendReply(.replyListStart, "Channel", "Users  Name")
    for info in server.getChannelInfos(channels) {
      sendReply(.replyList,
                info.name.stringValue,
                String(info.subscribers.count),
                info.welcome)
    }
    sendReply(.replyListEnd, "End of /LIST")
  }

  public func doPartAll() throws {
    try doPart(Array(joinedChannels), message: nil)
  }

  public func doQuit(_ message  : String?) throws {
    // TBD: send quit message to channels or what?
    channel?.close(mode: .all, promise: nil)
  }
}

