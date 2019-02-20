//
//  Command.swift
//  DSWebSocketKit
//
//  Created by sai on 2019/2/19.
//  Copyright © 2019 sai. All rights reserved.
//

import Foundation
import SwiftProtobuf
import Gzip

/// 命令
///
/// - connectionIdentifier: 连接标识
/// - authenticate: 认证
/// - getCurrentTime: 获取当前时间
/// - currentTime: 当前时间
/// - topicSubscribe: 话题订阅
/// - topicUnsubscribe: 话题退订
/// - topicConfigure: 话题配置
/// - topicPush: 话题推送
/// - UNRECOGNIZED: 无法识别
public enum Command {
    case requireAuthenticate(Websocket_RequireAuthenticate)
    case authenticate(Websocket_Authenticate)
    case getCurrentTime
    case currentTime(Websocket_DateTime)
    case topicSubscribe(Websocket_TopicSubscribe)
    case topicUnsubscribe(Websocket_TopicUnsubscribe)
    case topicConfigure(Websocket_TopicConfigure)
    case topicPush(Websocket_TopicPush)
    case UNRECOGNIZED(Websocket_Command)
}

extension Command {
    public func asWebsocket_Command() throws -> Websocket_Command {
        switch self {
        case .requireAuthenticate(let v):
            var command = Websocket_Command()
            command.code = .requireAuthenticate
            command.payload = try v.serializedData()
            return command
        case .authenticate(let v):
            var command = Websocket_Command()
            command.code = .authenticate
            command.payload = try v.serializedData()
            return command
        case .getCurrentTime:
            var command = Websocket_Command()
            command.code = .getCurrentTime
            return command
        case .currentTime(let v):
            var command = Websocket_Command()
            command.code = .currentTime
            command.payload = try v.serializedData()
            return command
        case .topicSubscribe(let v):
            var command = Websocket_Command()
            command.code = .topicSubscribe
            command.payload = try v.serializedData()
            return command
        case .topicUnsubscribe(let v):
            var command = Websocket_Command()
            command.code = .topicUnsubscribe
            command.payload = try v.serializedData()
            return command
        case .topicConfigure(let v):
            var command = Websocket_Command()
            command.code = .topicConfigure
            command.payload = try v.serializedData()
            return command
        case .topicPush(let v):
            var command = Websocket_Command()
            command.code = .topicPush
            command.payload = try v.serializedData()
            return command
        case .UNRECOGNIZED(let v):
            return v
        }
    }
}

extension Websocket_Command {
    public func asCommand() throws -> Command {
        let payload: Data
        if self.isGzip {
            payload = try self.payload.gunzipped()
        } else {
            payload = self.payload
        }
        
        switch self.code {
        case .requireAuthenticate:
            return .requireAuthenticate(try Websocket_RequireAuthenticate(serializedData: payload))
        case .authenticate:
            return .authenticate(try Websocket_Authenticate(serializedData: payload))
        case .getCurrentTime:
            return .getCurrentTime
        case .currentTime:
            return .currentTime(try Websocket_DateTime(serializedData: payload))
        case .topicSubscribe:
            return .topicSubscribe(try Websocket_TopicSubscribe(serializedData: payload))
        case .topicUnsubscribe:
            return .topicUnsubscribe(try Websocket_TopicUnsubscribe(serializedData: payload))
        case .topicConfigure:
            return .topicConfigure(try Websocket_TopicConfigure(serializedData: payload))
        case .topicPush:
            return .topicPush(try Websocket_TopicPush(serializedData: payload))
        case .UNRECOGNIZED:
            return .UNRECOGNIZED(self)
        }
    }
}
