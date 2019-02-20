//
//  WebSocketManager.swift
//  DSWebSocketKit
//
//  Created by sai on 2019/2/19.
//  Copyright © 2019 sai. All rights reserved.
//

import Foundation
import Starscream
import SwiftyRSA
import Reachability

// WebSocket管理器
open class DSWebSocketManager {
    // MARK: Public Properties
    
    /// 接口版本号
    public let apiVersion: Int
    /// 是否启用
    public private(set) var isEnabled: Bool = false {
        didSet {
            self.reconnectManager.isEnabled = self.isEnabled
        }
    }
    
    /// 服务器时间
    public fileprivate(set) var serverTime = ServerTime() {
        didSet {
            self.observers.forEach {
                $0.webSocketManager(self, didChangeServerTime: self.serverTime)
            }
        }
    }
    
    // MARK: Private Properties
    
    // 观察者合集
    fileprivate var _observers = NSHashTable<AnyObject>.weakObjects()
    fileprivate var observers: [DSWebSocketManagerObserver] {
        return _observers.objectEnumerator().compactMap({ $0 as? DSWebSocketManagerObserver })
    }
    /// WebSocket
    fileprivate let webSocket: WebSocketClient
    /// 私钥
    fileprivate let privateKey: PrivateKey
    /// 心跳管理器
    fileprivate let heartbeatManager: HearbeatManager
    /// 重连管理器
    fileprivate let reconnectManager: ReconnectManager
    /// 监听网络状态工具
    fileprivate let reachability = Reachability()!
    /// 连接标识
    fileprivate var connectionIdentifier: String? {
        didSet {
            if let connectionIdentifier = self.connectionIdentifier {
                self.authenticate(connectionIdentifier: connectionIdentifier)
            }
        }
    }
    
    // MARK: Lifecycle
    
    deinit {
        self.reachability.stopNotifier()
    }
    
    /// 构建WebScoket管理器
    ///
    /// - Parameters:
    ///  - webSocket: WebSocket实例
    ///  - privateKey: 私钥
    ///  - apiVersion: 接口版本号
    public init(webSocket: WebSocketClient, privateKey: PrivateKey, apiVersion: Int = 1) {
        self.webSocket = webSocket
        self.privateKey = privateKey
        self.apiVersion = apiVersion
        self.heartbeatManager = HearbeatManager()
        self.reconnectManager = ReconnectManager(isEnabled: self.isEnabled)
        
        self.webSocket.delegate = self
        self.webSocket.pongDelegate = self
        self.heartbeatManager.delegate = self
        self.reconnectManager.delegate = self
        
        self.reachability.whenReachable = { [unowned self] _ in
            if self.isEnabled && !self.webSocket.isConnected {
                self.reconnectManager.reset()
                self.doConnect()
            }
        }
        try? reachability.startNotifier()
    }
    
    /// 构建webSocket管理器
    ///
    /// - Parameters:
    ///  - url: webSocket地址
    ///  - protocols: 支持的协议
    ///  - privateKey: 私钥
    public convenience init(url: URL, protocols: [String] = ["chat", "superchat"], privateKey: PrivateKey) {
        self.init(webSocket: WebSocket(url: url, protocols: protocols), privateKey: privateKey)
    }
    
    // MARK: Observer
    
    /// 注册观察者
    ///
    /// 注: 不会保持观察者的引用
    ///
    /// - Parameter observer: 观察者
    public func regsiterObserver(_ observer: DSWebSocketManagerObserver) {
        if self._observers.contains(observer) {
            return
        }
        self._observers.add(observer)
    }
    
    /// 注销观察者
    ///
    /// - Parameter observer: 观察者
    public func unregsiterObserver(_ observer: DSWebSocketManagerObserver) {
        self._observers.remove(observer)
    }
    
    /// 建立连接
    public func connect() {
        self.isEnabled = true
        self.doConnect()
    }
    
    /// 断开连接
    public func disconnect() {
        self.isEnabled = false
        self.doDisconnect()
    }
    
    /// 断开重新建立连接
    public func reconnect() {
        self.disconnect()
        self.connect()
    }
    
    // MARK: Send
    
    /// 发送命令
    ///
    /// - Parameter command: 命令
    public func sendCommand(_ command: Command) {
        guard self.webSocket.isConnected,
            let data = try? command.asWebsocket_Command().serializedData() else {
                return
        }
        self.webSocket.write(data: data)
    }
    
    /// 发送心跳
    public func sendPing() {
        guard self.webSocket.isConnected else { return }
        self.webSocket.write(data: Data())
    }
    
    // MARK: Private Methods
    
    // 建立webSocket连接， 如果已连接， 则忽略
    fileprivate func doConnect() {
        if !self.isEnabled || self.webSocket.isConnected {
            return
        }
        self.webSocket.connect()
    }
    
    /// 断开webSocket连接，如果未连接，则忽略
    fileprivate func doDisconnect() {
        if !self.webSocket.isConnected { return }
        self.connectionIdentifier = nil
        self.webSocket.disconnect()
    }
    
    /// 认证
    ///
    /// - Parameter connectionIdentifier: 连接标识
    fileprivate func authenticate(connectionIdentifier: String) {
        guard self.webSocket.isConnected else {
            return
        }
        
        // 签名内容: “<连接标识><接口版本号><客户端标识><客户端类型><客户端构建版本><客户端版本><设备id>”
        
        let client = Websocket_Client.current
        let string = "\(connectionIdentifier)\(self.apiVersion)\(client.identifier)\(client.name)\(client.kind.rawValue)\(client.version.code)\(client.version.name)\(client.deviceID)"
        let signature = try! ClearMessage(string: string, using: .utf8)
            .signed(with: privateKey, digestType: .sha1).data.base64EncodedString()
        
        var value = Websocket_Authenticate()
        value.signature = signature
        value.client = client
        value.apiVersion = Int32(self.apiVersion)
        
        self.sendCommand(.authenticate(value))
        self.observers.forEach {
            $0.webSocketManagerDidAuthenticate(self)
        }
    }
    
    /// 收到命令
    ///
    /// - Parameter command: 命令
    fileprivate func receiveCommand(_ command: Command) {
        switch command {
        case .requireAuthenticate(let value):
            self.connectionIdentifier = value.connectionIdentifier
        case .currentTime(let value):
            self.serverTime = value.asServerTime()
        default:()
        }
        
        self.observers.forEach {
            $0.webSocketManager(self, didReceiveCommand: command)
        }
    }
}

extension DSWebSocketManager {
    /// 是否已连接
    public var isConnected: Bool {
        return webSocket.isConnected
    }
    /// 心跳周期
    public var heartbeatPeriod: TimeInterval {
        get {
            return self.heartbeatManager.pingPariod
        }
        set {
            self.heartbeatManager.pingPariod = newValue
        }
    }
    /// 心跳超时时间
    public var hfeartbeatTimeout: TimeInterval {
        get {
            return self.heartbeatManager.pongTimeout
        }
        set {
            self.heartbeatManager.pongTimeout = newValue
        }
    }
    /// 重连最小延迟时间, 单位秒
    public var minDelayTime: Int {
        get {
            return self.reconnectManager.minDelayTime
        }
        set {
            self.reconnectManager.minDelayTime = newValue
        }
    }
    /// 重连最大延迟时间，单位秒
    public var maxDelayTime: Int {
        get {
            return self.reconnectManager.maxDelayTime
        }
        set {
            self.reconnectManager.maxDelayTime = newValue
        }
    }
}

extension DSWebSocketManager {
    public func encrypt(_ data: Data, key: Data? = nil) -> Data? {
        guard let connectionIdentifier = self.connectionIdentifier?.data(using: .utf8) else {
            return nil
        }
        let secretKey: Data = {
            var secretKey = Data()
            secretKey.append(connectionIdentifier)
            if let key = key {
                secretKey.append(key)
            }
            return secretKey
        }()
        
        var encryptedData = Data()
        for index in 0..<data.count {
            let secretIndex = index % secretKey.count
            let value = data[index] ^ secretKey[secretIndex]
            encryptedData.append(value)
        }
        return encryptedData
    }
}

// MARK: - WebsocketManagerDelegate

/// WebSocket管理器的观察者
public protocol DSWebSocketManagerObserver: class {
    /// 连接已建立
    ///
    /// - Parameter manager: Websocket管理器
    func webSocketManagerDidConect(_ manager: DSWebSocketManager)
    
    /// 连接已建立
    ///
    /// - Parameters:
    ///  - manager: WebSocket管理器
    ///  - error: 错误
    ///  - retryTimes: 重连次数
    func webSocketManager(_ manager: DSWebSocketManager, didDidconnectWithError error: Error?, retryTimes: Int)
    
    /// 收到命令
    ///
    /// - Parameters:
    ///  - manager: WebSocket管理器
    ///  - command: 命令
    func webSocketManager(_ manager: DSWebSocketManager, didReceiveCommand command: Command)
    
    /// 已发送认证信息给服务端 (如果认证失败，服务端会断开连接)
    ///
    /// - Parameters:
    ///  - manager: Websocket管理器
    func webSocketManagerDidAuthenticate(_ manager: DSWebSocketManager)
    
    /// 服务器时间发生变化
    ///
    /// - Parameters:
    ///  - manager: Websocket管理器
    ///  - serverTime: 服务器时间
    func webSocketManager(_ manager: DSWebSocketManager, didChangeServerTime serverTime: ServerTime)
    
    /// 命令反序列化失败
    ///
    /// - Parameters:
    ///  - manager: Websocket管理器
    ///  - error: 反序列化错误
    func webSocketManager(_ manager: DSWebSocketManager, didCommandDeserializeFailure error: Error)
    
    /// 发送了心跳
    ///
    /// - Parameters: manager: WebSocket管理器
    func webSocketManagerDidSendHeartbeat(_ manager: DSWebSocketManager)
    
    /// 收到心跳响应
    ///
    /// -Parameter: manager: WebSocket管理器
    func webSocketManagerDidReceiveHeartbeatRespose(_ manager: DSWebSocketManager)
    
    /// 心跳超时
    ///
    /// - Parameter manager: WebSocket管理器
    func webSocketManagerDidHeartbeatTimeout(_ manager: DSWebSocketManager)
    
    /// 将要执行重连
    ///
    /// - Parameter manager: WebSocket管理器
    func webSocketManagerWillReconnect(_ manager: DSWebSocketManager)
}

// 实现这些方法是为了在q观察者中不必再实现
extension DSWebSocketManagerObserver {
    public func webSocketManagerDidAuthenticated(_ manager: DSWebSocketManager) {}
    public func webSocketManager(_ manager: DSWebSocketManager, didChangeServerTime serverTime: ServerTime) {}
    public func webSocketManager(_ manager: DSWebSocketManager, didCommandDeserializeFailure error: Error) {}
    public func webSocketManagerDidSendHeartbeat(_ manager: DSWebSocketManager) {}
    public func webSocketManagerDidReceiveHeartbeatResponse(_ manager: DSWebSocketManager) {}
    public func webSocketManagerDidHeartbeatTimeout(_ manager: DSWebSocketManager) {}
    public func webSocketManagerWillReconnect(_ manager: DSWebSocketManager) {}
}

// MARK: - WebSocketDelegate

extension DSWebSocketManager: WebSocketDelegate {
    public func websocketDidConnect(socket: WebSocketClient) {
        self.observers.forEach { $0.webSocketManagerDidConect(self) }
        
        self.heartbeatManager.start()
        self.reconnectManager.reset()
        
        self.sendCommand(.getCurrentTime)
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        self.connectionIdentifier = nil
        
        let retryTimes = self.reconnectManager.retryTimes
        self.observers.forEach {
            $0.webSocketManager(self, didDidconnectWithError: error, retryTimes: retryTimes)
        }
        
        self.heartbeatManager.stop()
        self.reconnectManager.delayReconnect()
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        self.heartbeatManager.receivePong()
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        self.heartbeatManager.receivePong()
        
        do {
            self.receiveCommand(try Websocket_Command(serializedData: data).asCommand())
        } catch {
            self.observers.forEach {
                $0.webSocketManager(self, didCommandDeserializeFailure: error)
            }
        }
    }
}

// MARK: - WebSocketPongDelegate
extension DSWebSocketManager: WebSocketPongDelegate {
    public func websocketDidReceivePong(socket: WebSocketClient, data: Data?) {
        self.observers.forEach {
            $0.webSocketManagerDidReceiveHeartbeatRespose(self)
        }
        
        self.heartbeatManager.receivePong()
    }
}

// MARK: - HeartbeatManagerDelegate

extension DSWebSocketManager: HeartbeatManagerDelegate {
    public func heartbeatManagerDoPing(_ manager: HearbeatManager) {
        sendPing()
        
        self.observers.forEach {
            $0.webSocketManagerDidSendHeartbeat(self)
        }
    }
    
    public func heartbeatManagerPongWaitTimeout(_ manager: HearbeatManager) {
        self.observers.forEach {
            $0.webSocketManagerDidHeartbeatTimeout(self)
        }
        
        self.doDisconnect()
    }
}

// MARK: ReconnectManagerDelegate

extension DSWebSocketManager: ReconnectManagerDelegate {
    public func reconnectManagerDoReconnect(_ manager: ReconnectManager) {
        self.observers.forEach {
            $0.webSocketManagerWillReconnect(self)
        }
        
        self.doConnect()
    }
}

// MARK: - WebSocket_Client

extension Websocket_Client {
    fileprivate static let current: Websocket_Client = {
        var version = Websocket_Client.Version()
        version.name = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        version.code = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        
        var client = Websocket_Client()
        client.identifier = Bundle.main.bundleIdentifier ?? ""
        client.name = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? ""
        client.kind = .ios
        client.version = version
        client.deviceID = {
            let key = "WebSocketKit.Client.deviceID"
            if let deviceID = UserDefaults.standard.string(forKey: key) {
                return deviceID
            }
            
            let deviceID = UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: key)
            UserDefaults.standard.synchronize()
            return deviceID
        }()
        return client
    }()
}
