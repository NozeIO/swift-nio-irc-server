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

public typealias IRCServerError = IRCDispatcherError

extension IRCCommandCode {
  
  var errorMessage : String {
    return errorMap[self] ??  "Unmapped error code \(self.rawValue)"
  }
}

fileprivate let errorMap : [ IRCCommandCode : String ] = [
  .errorUnknownCommand:    "No such command.",
  .errorNoSuchServer:      "No such server.",
  .errorNicknameInUse:     "Nickname is already in use.",
  .errorNoSuchNick:        "No such nick.",
  .errorAlreadyRegistered: "You may not reregister.",
  .errorNotRegistered:     "You have not registered",
  .errorUsersDontMatch:    "Users don't match",
  .errorNoSuchChannel:     "No such channel"
]
