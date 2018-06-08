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

import Dispatch
import NIO
import NIOIRC

/**
 * A base class for an IRC server.
 *
 * The object creates and maintains a NIO server channel, and the associated
 * handlers which are necessary for IRC.
 *
 * The IRC state handling actually lives in the `IRCServerContext`, which
 * maintains available channels, assigned nicks and such.
 *
 * Can be configured using the `IRCServer.Configuration` object. Checkout
 * `miniircd` for an example.
 */
open class IRCServer {
  
  open class Configuration {
    open var origin         : String?         = nil
    open var host           : String?         = nil // "127.0.0.1"
    open var port           : Int             = NIOIRC.DefaultIRCPort
    open var eventLoopGroup : EventLoopGroup? = nil
    open var logger         : IRCLogger       = IRCPrintLogger(logLevel: .Log)
    open var backlog        : Int             = 256

    public init(eventLoopGroup: EventLoopGroup? = nil) {
      self.eventLoopGroup = eventLoopGroup
    }
  }
  
  public let configuration  : Configuration
  public let eventLoopGroup : EventLoopGroup
  public let logger         : IRCLogger
  
  public private(set) var context       : IRCServerContext?
  public private(set) var serverChannel : Channel?

  public init(configuration: Configuration = Configuration()) {
    self.configuration  = configuration
    
    self.logger         = configuration.logger
    self.eventLoopGroup = configuration.eventLoopGroup
           ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  }
  
  open func stopOnSignal(_ signal: Int32) {
    logger.warn("Received SIGINT scheduling shutdown...")
    
    // Safe? Unsafe. No idea. Probably not :-)
    exit(0)
  }

  open func listenAndWait() {
    listen()
    
    do {
      try serverChannel?.closeFuture.wait() // no close, no exit
    }
    catch {
      logger.error("failed to wait on server:", error)
    }
  }
  
  open func listen() {
    let bootstrap = makeBootstrap()
    
    do {
      logStartupOnPort(configuration.port)
      
      let address : SocketAddress
      
      if let host = configuration.host {
        address = try SocketAddress
          .newAddressResolving(host: host, port: configuration.port)
      }
      else {
        var addr = sockaddr_in()
        addr.sin_port = in_port_t(configuration.port).bigEndian
        address = SocketAddress(addr, host: "*")
      }
      
      let origin : String = {
        let s = configuration.origin ?? address.ircOrigin
        if !s.isEmpty { return s }
        if let s = configuration.host { return s }
        return "no-origin" // TBD
      }()
      context = IRCServerContext(origin: origin, logger: logger)
      
      serverChannel = try bootstrap.bind(to: address)
                                   .wait()
      

      if let addr = serverChannel?.localAddress {
        logSetupOnAddress(addr)
      }
      else {
        logger.warn("server reported no local address?")
      }
    }
    catch let error as NIO.IOError {
      logger.error("failed to start server, errno:", error.errnoCode, "\n",
                   error.localizedDescription)
      self.context = nil
    }
    catch {
      logger.error("failed to start server:", type(of:error), error)
      self.context = nil
    }
  }
  
  func logStartupOnPort(_ port: Int) {
    let title = "Swift IRCd"
    let line1 = "Port: \(port)"
    let line2 = "PID:  \(getpid())"
    
    let logo = """
                __  __ _       _ _____ _____   _____
                |  \\/  (_)     (_)_   _|  __ \\ / ____|   \(title)
                | \\  / |_ _ __  _  | | | |__) | |
                | |\\/| | | '_ \\| | | | |  _  /| |        \(line1)
                | |  | | | | | | |_| |_| | \\ \\| |____    \(line2)
                |_|  |_|_|_| |_|_|_____|_|  \\_\\\\_____|
               """
    print(logo)
    print()
  }
  func logSetupOnAddress(_ address: SocketAddress) {
    logger.log("Ready to accept connections on:", address)
  }

  
  // MARK: - Bootstrap
  
  open func makeBootstrap() -> ServerBootstrap {
    let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                             SO_REUSEADDR)
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify backlog and enable SO_REUSEADDR for the server itself
      .serverChannelOption(ChannelOptions.backlog,
                           value: Int32(configuration.backlog))
      .serverChannelOption(reuseAddrOpt, value: 1)
      
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        channel.pipeline
          .add(name: "com.apple.nio.backpressure",
               handler: BackPressureHandler()) // Oh well :-)
          .then {
            channel.pipeline.add(name: "de.zeezide.nio.irc",
                                 handler: IRCChannelHandler())
          }
          .then {
            guard let context = self.context else {
              fatalError("lacking server context?!")
            }
            let handler = IRCSessionHandler(context: context)
            
            return channel.pipeline.add(name: "de.zeezide.nio.ircd",
                                        handler: handler)
        }
      }
      
      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY),
                          value: 1)
      .childChannelOption(reuseAddrOpt, value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    
    return bootstrap
  }
}

extension SocketAddress {

  var ircOrigin : String {
    return ""
  }
}
