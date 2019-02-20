//
//  HeartbeatManager.swift
//  DSWebSocketKit
//
//  Created by sai on 2019/2/20.
//  Copyright © 2019 sai. All rights reserved.
//

import Foundation
import Starscream

/// 心跳管理器
open class HearbeatManager {
    // MARK: Public Properties
    
    /// 心跳管理器委托
    public weak var delegate: HeartbeatManagerDelegate?
    /// 是否运行中
    public private(set) var isRunning: Bool = false
    /// pinga时间间隔
    public var pingPariod: TimeInterval {
        didSet {
            if self.pingPariod <= 0 {
                self.pingPariod = oldValue
            }
        }
    }
    /// pong等待超时时间
    public var pongTimeout: TimeInterval {
        didSet {
            if self.pongTimeout <= 0 {
                self.pongTimeout = oldValue
            }
        }
    }
    
    // MARK: Private Properties
    
    // 执行任务的队列
    private var queue: DispatchQueue
    /// 任务的优先级
    private var qos: DispatchQoS
    /// 心跳定时器
    private var pingTimer: DispatchSourceTimer? {
        didSet {
            oldValue?.cancel()
        }
    }
    /// 超时检查定时器
    private var timeoutCheckTimer: DispatchSourceTimer? {
        didSet {
            oldValue?.cancel()
        }
    }
    
    // MARK: Lifecycle
    deinit {
        self.stop()
    }
    
    /// 构造心跳管理器
    ///
    /// - Parameters:
    ///  - queue: 执行任务的队列
    ///  - qos: 任务的优先级
    ///  - pingPeriod: ping时间间隔，默认为180秒
    ///  - pongTimeout: pong等待超时时间，默认为15秒
    public init(queue: DispatchQueue = .main, qos: DispatchQoS = .background, pingPariod: TimeInterval = 180, pongTimeout: TimeInterval = 15) {
        self.queue = queue
        self.qos = qos
        self.pingPariod = pingPariod
        self.pongTimeout = pongTimeout
    }
    
    // MARK: Public Methods
    
    /// 收到心跳响应
    public func receivePong() {
        self.delaySendPing()
    }
    
    /// 开启心跳，如果已开启，则忽略
    public func start() {
        if self.isRunning { return }
        self.isRunning = true
        self.delaySendPing()
    }
    
    /// 关闭心跳， 如果未开启， 则忽略
    public func stop() {
        if !self.isRunning { return }
        self.pingTimer = nil
        self.timeoutCheckTimer = nil
        self.isRunning = false
    }
    
    // MARK: Private Methods
    
    /// 延迟发送心跳包
    private func delaySendPing() {
        guard self.isRunning else { return }
        
        self.cancleCheckTimeout()
        
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        self.pingTimer = timer
        timer.schedule(deadline: .now() + self.pingPariod, repeating: .never)
        timer.setEventHandler(qos: self.qos) { [weak self] in
            self?.sendPing()
        }
        timer.resume()
    }
    
    /// 发送心跳包
    func sendPing() {
        self.delegate?.heartbeatManagerDoPing(self)
        self.checkTimeout()
    }
    
    /// 检查t心跳是否超时
    private func checkTimeout() {
        guard self.isRunning else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        self.timeoutCheckTimer = timer
        timer.schedule(deadline: .now() + self.pongTimeout, repeating: .never)
        timer.setEventHandler(qos: self.qos) { [weak self] in
            self?.waitTimeout()
        }
        timer.resume()
    }
    
    /// 心跳响应等待超时
    private func waitTimeout() {
        self.delegate?.heartbeatManagerPongWaitTimeout(self)
    }
    
    /// 取消心跳包超时检查
    private func cancleCheckTimeout() {
        self.timeoutCheckTimer = nil
    }
}


// MARK: - HearbeatManagerDelegate

// MARK: 心跳管理器委托
public protocol HeartbeatManagerDelegate: class {
    /// 执行心跳
    ///
    /// - Parameter manager: 心跳管理器
    func heartbeatManagerDoPing(_ manager: HearbeatManager)
    
    /// 心跳响应等待超时
    ///
    /// - Parameter manager: 心跳管理器
    func heartbeatManagerPongWaitTimeout(_ manager: HearbeatManager)
}

extension HearbeatManager: WebSocketPongDelegate {
    public func websocketDidReceivePong(socket: WebSocketClient, data: Data?) {
        self.receivePong()
    }
}
