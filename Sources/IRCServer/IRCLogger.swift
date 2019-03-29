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

/**
 * A logger object.
 *
 * A concrete implementation is the `IRCPrintLogger`.
 */
public protocol IRCLogger {
  
  typealias LogLevel = IRCLogLevel

  func primaryLog(_ logLevel: LogLevel, _ msgfunc: () -> String,
                  _ values: [ Any? ] )
}

public extension IRCLogger {
  
  func error(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Error, msg, values)
  }
  func warn (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Warn, msg, values)
  }
  func log  (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Log, msg, values)
  }
  func info (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Info, msg, values)
  }
  func trace(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Trace, msg, values)
  }
  
}

/**
 * IRC log levels.
 */
public enum IRCLogLevel : Int8 {
  case Error
  case Warn
  case Log
  case Info
  case Trace
  
  var logPrefix : String {
    switch self {
      case .Error: return "ERROR: "
      case .Warn:  return "WARN:  "
      case .Info:  return "INFO:  "
      case .Trace: return "Trace: "
      case .Log:   return ""
    }
  }
}


// MARK: - Simple Default Logger

/**
 * Simple default logger which logs using, well, `print`. :-)
 */
public struct IRCPrintLogger : IRCLogger {
  
  public let logLevel : LogLevel
  
  public init(logLevel: LogLevel = .Log) {
    self.logLevel = logLevel
  }
  
  public func primaryLog(_ logLevel : LogLevel,
                         _ msgfunc  : () -> String,
                         _ values   : [ Any? ] )
  {
    guard logLevel.rawValue <= self.logLevel.rawValue else { return }
    
    let prefix = logLevel.logPrefix
    let s = msgfunc()
    
    if values.isEmpty {
      print("\(prefix)\(s)")
    }
    else {
      var ms = ""
      appendValues(values, to: &ms)
      print("\(prefix)\(s)\(ms)")
    }
  }
  
  func appendValues(_ values: [ Any? ], to ms: inout String) {
    for v in values {
      ms += " "
      
      if      let v = v as? CustomStringConvertible { ms += v.description }
      else if let v = v as? String                  { ms += v }
      else if let v = v                             { ms += "\(v)" }
      else                                          { ms += "<nil>" }
    }
  }
}
