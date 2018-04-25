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

import Foundation

final class RWLock {
  
  private var lock = pthread_rwlock_t()
  
  public init() {
    pthread_rwlock_init(&lock, nil)
  }
  deinit {
    pthread_rwlock_destroy(&lock)
  }
  
  @inline(__always)
  func lockForReading() {
    pthread_rwlock_rdlock(&lock)
  }
  
  @inline(__always)
  func lockForWriting() {
    pthread_rwlock_wrlock(&lock)
  }
  
  @inline(__always)
  func unlock() {
    pthread_rwlock_unlock(&lock)
  }
  
}

import protocol NIO.EventLoop
import struct   NIO.EventLoopPromise

protocol EventLoopObject {
  
  var eventLoop : EventLoop? { get }
  
}

import class Dispatch.DispatchQueue

extension EventLoopObject {
  
  static func getValues<C: Collection, T>(from objects: C,
                                          map : @escaping ( C.Element ) -> T,
                                          promise : EventLoopPromise<[ T ]>)
                where C.Element : EventLoopObject
  {
    guard !objects.isEmpty else { return promise.succeed(result: []) }
    
    var expectedCount = 0
    var loopToObjects = [ ObjectIdentifier : [ C.Element ] ]()
    for object in objects {
      guard let hLoop = object.eventLoop else {
        // TBD: we could fail the promise, but here we just skip
        assert(object.eventLoop != nil,
               "called \(#function) on object w/o loop!")
        continue
      }
      
      let oid = ObjectIdentifier(hLoop)
      if nil == loopToObjects[oid]?.append(object) {
        loopToObjects[oid] = [ object ]
      }
      expectedCount += 1
    }
    
    let syncQueue = DispatchQueue(label: "de.zeezide.nio.util.collector")
    var values = [ T ]()
    #if swift(>=4.1)
      values.reserveCapacity(objects.count)
    #endif
    
    for ( _, handlerGroup ) in loopToObjects {
      let loop = handlerGroup[0].eventLoop!
      loop.execute {
        let elValues = Array(handlerGroup.map(map))
        syncQueue.async {
          values.append(contentsOf: elValues)
          expectedCount -= elValues.count
          if expectedCount < 1 {
            promise.succeed(result: values)
          }
        }
      }
    }
  }
}
