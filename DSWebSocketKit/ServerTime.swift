//
//  ServerTime.swift
//  DSWebSocketKit
//
//  Created by sai on 2019/2/19.
//  Copyright © 2019 sai. All rights reserved.
//

import Foundation

/// 服务器时间
public struct ServerTime {
    /// 服务器时间与本地时间的偏差
    public let offset: TimeInterval
    
    public init(offset: TimeInterval = 0) {
        self.offset = offset
    }
    
    public init(currentTime: Date) {
        self.init(offset: currentTime.timeIntervalSinceNow)
    }
    
    /// 获取服务器当前时间
    ///
    /// - Returns: 服务器当前时间
    public func currentTime() -> Date {
        return Date(timeIntervalSinceNow: offset)
    }
    
    /// 服务器时区
    public var timeZone: TimeZone {
        return TimeZone(secondsFromGMT: Int(offset) + TimeZone.current.secondsFromGMT())!
    }
}

extension Websocket_DateTime {
    public func asServerTime() -> ServerTime {
        return ServerTime(currentTime: Date(timeIntervalSince1970: TimeInterval(self.unixTimestamp)))
    }
}
