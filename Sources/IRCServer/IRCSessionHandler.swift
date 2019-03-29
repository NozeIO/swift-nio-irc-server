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

import NIO
import NIOIRC

/**
 * NIO ChannelHandler which represents one IRC session.
 *
 * Processes the incoming `IRCMessage` items, and sends the appropriate
 * replies (in the `IRCSessionDispatcher`).
 */
open class IRCSessionHandler : ChannelInboundHandler,
                               IRCServerMessageTarget
{
  
  public typealias InboundIn  = IRCMessage
  
  public enum Error : Swift.Error {
    case disconnected
    case internalInconsistency
  }
  
  public enum State : Equatable {
    case initial
    case nickAssigned(IRCNickName)
    case userSet     (IRCUserInfo)
    case registered  (IRCNickName, IRCUserInfo)
    
    var nick : IRCNickName? {
      switch self {
        case .initial, .userSet:         return nil
        case .nickAssigned(let nick):    return nick
        case .registered  (let nick, _): return nick
      }
    }
    var userInfo : IRCUserInfo? {
      switch self {
        case .initial, .nickAssigned:  return nil
        case .userSet      (let info): return info
        case .registered(_, let info): return info
      }
    }
    var isRegistered : Bool {
      guard case .registered = self else { return false }
      return true
    }

    mutating func changeNick(to nick: IRCNickName) {
      switch self {
        case .initial:                 self = .nickAssigned(nick)
        case .nickAssigned:            self = .nickAssigned(nick)
        case .userSet      (let info): self = .registered(nick, info)
        case .registered(_, let info): self = .registered(nick, info)
      }
    }
    
    public static func ==(lhs: State, rhs: State) -> Bool {
      switch ( lhs, rhs ) {
        case ( .initial, .initial ):
          return true
        
        case ( .nickAssigned(let lhs), .nickAssigned(let rhs) ):
          return lhs == rhs
        
        case ( .userSet(let lhs), .userSet(let rhs) ):
          return lhs == rhs

        case ( .registered(let lu, let lui), .registered(let ru, let rui) ):
          return lu == ru && lui == rui
        
        default: return false
      }
    }
  }
  
  var state = State.initial {
    didSet {
      if oldValue.isRegistered != state.isRegistered && state.isRegistered {
        sendWelcome()
        sendCurrentMode()
      }
    }
  }
  var mode = IRCUserMode()
  
  static let serverCapabilities : Set<String> = [ "multi-prefix" ]
  var activeCapabilities = IRCSessionHandler.serverCapabilities

  var joinedChannels = Set<IRCChannelName>()

  var channel   : NIO.Channel?
  var eventLoop : NIO.EventLoop?
  let server    : IRCServerContext
  let logger    : IRCLogger
  
  var nick      : IRCNickName? { return state.nick }
  var userID    : IRCUserID? {
    guard case .registered(let nick, let info) = state else { return nil }
    return IRCUserID(nick: nick, user: info.username,
                     host: info.servername ?? origin)
  }
  
  init(context: IRCServerContext) {
    self.server = context
    self.logger = context.logger
  }
  
  // MARK: - Connect / Disconnect
  
  open func channelActive(context: ChannelHandlerContext) {
    assert(channel == nil, "channel is already set?!")
    self.channel   = context.channel
    self.eventLoop = context.channel.eventLoop
    
    assert(state == .initial)
    
    // TODO:
    // - ident lookup
    // - timeout until nick assignment!
    
    context.fireChannelActive()
  }

  open func channelInactive(context: ChannelHandlerContext) {
    for channel in joinedChannels {
      server.partChannel(channel, session: self)
    }
    
    if let nick = nick {
      do {
        try server.unregisterSession(self, nick: nick)
      }
      catch {
        logger.error("could not unregister session:", nick, self)
      }
    }
    
    context.fireChannelInactive()
    
    assert(channel === context.channel,
           "different channel \(context) \(channel as Optional)")
    channel = nil // release cycle
    
    // Note: we do NOT release the loop to avoid races!
  }
  
  
  // MARK: - Reading

  open func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let message = self.unwrapInboundIn(data)
    do {
      try irc_msgSend(message)
    }
    catch let error as IRCServerError {
      handleError(error, in: context)
    }
    catch {
      errorCaught(context: context, error: error)
    }
  }
  
  public func channelReadComplete(context: ChannelHandlerContext) {
    context.flush()
  }

  func handleError(_ error: IRCServerError, in context: ChannelHandlerContext) {
    switch error {
      case .nicknameInUse(let nick):
        sendError(.errorNicknameInUse, nick.stringValue)
      
      case .noSuchNick(let nick):
        sendError(.errorNoSuchNick, nick.stringValue)
      
      case .noSuchChannel(let channel):
        sendError(.errorNoSuchChannel, channel.stringValue)

      case .alreadyRegistered:
        assert(nick != nil, "nick not set, but 'already registered'?")
        sendError(.errorAlreadyRegistered, nick?.stringValue ?? "?")
      
      case .notRegistered:
        sendError(.errorNotRegistered)
      
      case .cantChangeModeForOtherUsers:
        sendError(.errorUsersDontMatch,
                  message: "Can't change mode for other users")
      
      case .doesNotRespondTo(let message):
        sendError(.errorUnknownCommand, message.command.commandAsString)
    }
  }

  func handleError(_ error: IRCParserError, in context: ChannelHandlerContext) {
    switch error {
      case .invalidNickName(let nick):
        sendError(.errorErrorneusNickname, nick,
                  "Invalid nickname")
      
      case .invalidArgumentCount(let command, _, _):
        sendError(.errorNeedMoreParams, command,
                  "Not enough parameters")
      
      case .invalidChannelName(let name):
        sendError(.errorIllegalChannelName, name,
                  "Illegal channel name")
      
      default:
        logger.error("Protocol error, sending unknown cmd", error)
        sendError(.errorUnknownCommand, // TODO
                  "?",
                  "Protocol error")
    }
  }
  
  open func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
    if let ircError = error as? IRCParserError {
      switch ircError {
        case .transportError, .notImplemented:
          context.fireErrorCaught(error)
        default:
          return handleError(ircError, in: context)
      }
    }
    
    context.fireErrorCaught(error)
  }

  
  // MARK: - Writing
  
  public var origin : String? { return server.origin }
  public var target : String  { return nick?.stringValue ?? "*" }

  public func sendMessages<T: Collection>(_ messages: T,
                                          promise: EventLoopPromise<Void>?)
                where T.Element == IRCMessage
  {
    // TBD: this looks a little more difficult than necessary.
    guard let channel = channel else {
      #if swift(>=5) // NIO 2 API
        promise?.fail(Error.disconnected)
      #else // NIO 1 API
        promise?.fail(error: Error.disconnected)
      #endif
      return
    }
    
    guard channel.eventLoop.inEventLoop else {
      return channel.eventLoop.execute {
        self.sendMessages(messages, promise: promise)
      }
    }
    
    let count = messages.count
    if count == 0 {
      #if swift(>=5) // NIO 2 API
        promise?.succeed(())
      #else
        promise?.succeed(result: ())
      #endif
      return
    }
    if count == 1 {
      return channel.writeAndFlush(messages.first!, promise: promise)
    }
    
    guard let promise = promise else {
      for message in messages {
        channel.write(message, promise: nil)
      }
      return channel.flush()
    }
    
    #if swift(>=5) // NIO 2 API
      EventLoopFuture<Void>
        .andAllSucceed(messages.map { channel.write($0) },
                       on: promise.futureResult.eventLoop)
        .cascade(to: promise)
    #else
      EventLoopFuture<Void>
        .andAll(messages.map { channel.write($0) },
                eventLoop: promise.futureResult.eventLoop)
        .cascade(promise: promise)
    #endif
    
    channel.flush()
  }
  
  open func sendCurrentMode() {
    guard let nick = nick else { return }
    let command = IRCCommand.MODE(nick, add: mode, remove: IRCUserMode())
    sendMessage(IRCMessage(origin: origin, command: command))
  }
  
  open func sendWelcome() {
    let nick   = state.nick?.stringValue ?? ""
    let origin = self.origin ?? "??"
    let info   = server.getServerInfo()
    
    sendReply(.replyWelcome,
              "Welcome to the NIO Internet Relay Chat Network \(nick)")
    sendReply(.replyYourHost, "Your host is \(origin), running miniircd")
    sendReply(.replyCreated, "This server was created \(server.created)")
    
    sendReply(.replyMyInfo, "\(origin) miniircd")
    sendReply(.replyBounce, "CHANTYPES=#", "CHANLIMIT=#:120", "NETWORK=NIO",
              "are supported by this server")
    
    sendReply(.replyLUserClient,
              "There are \(info.userCount) users and " +
              "\(info.invisibleCount) invisible on \(info.serverCount) servers")
    sendReply(.replyLUserOp, "\(info.operatorCount)", "IRC Operators online")
    sendReply(.replyLUserChannels, "\(info.channelCount)", "channels formed")

    sendMotD("""
             Welcome to \(origin) on the Interwebs.
             Thanks to https://www.zeezide.com/ for sponsoring
             this server!\n
             Thank you for using Swift NIO!\n\n
             """)
  }
  

  #if swift(>=5) // NIO 2 API - default
  #else // NIO 1 API Shims
    open func channelActive(ctx context: ChannelHandlerContext) {
      channelActive(context: context)
    }
    open func channelInactive(ctx context: ChannelHandlerContext) {
      channelInactive(context: context)
    }
    open func channelRead(ctx context: ChannelHandlerContext, data: NIOAny) {
      channelRead(context: context, data: data)
    }
    public func channelReadComplete(ctx context: ChannelHandlerContext) {
      channelReadComplete(context: context)
    }
    open func errorCaught(ctx context: ChannelHandlerContext,
                          error: Swift.Error)
    {
      errorCaught(context: context, error: error)
    }
  #endif // NIO 1 API Shims
}

extension IRCSessionHandler : EventLoopObject {}

extension IRCSessionHandler {
  
  /// Grab values from a collection of `IRCSessionHandler` objects. Since those
  /// can run in different threads, this thing gets a little more difficult
  /// than what you may think ;-)
  func getValues<C: Collection, T>(from sessions: C,
                                   map   : @escaping ( IRCSessionHandler ) -> T,
                                   yield : @escaping ( [ T ] ) -> Void)
          where C.Element == IRCSessionHandler
  {
    // Careful: This only works on sessions which have been activated,
    //          which in turn guarantees, that they have a loop!
    guard let yieldLoop = self.eventLoop else {
      assert(eventLoop != nil, "called getValues on handler w/o loop?! \(self)")
      return yield([])
    }
    
    #if swift(>=5) // NIO 2 API
      let promise = yieldLoop.makePromise(of: [ T ].self)
    #else
      let promise : EventLoopPromise<[ T ]> = yieldLoop.newPromise()
    #endif
    IRCSessionHandler.getValues(from: sessions, map: map, promise: promise)
    _ = promise.futureResult.map(yield)
  }
}
