//
//  ReconnectManager.swift
//  DSWebSocketKit
//
//  Created by sai on 2019/2/19.
//  Copyright © 2019 sai. All rights reserved.
//

import Foundation

// 重连管理器
open class ReconnectManager {
    
    // MARK: Public Properties
    
    /// 重连管理器委托
    public weak var delegate: ReconnectManagerDelegate?
    /// 是否可用
    public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                self.reset()
            }
        }
    }
    /// 重连最小延迟时间
    public var minDelayTime: Int {
        didSet {
            if self.minDelayTime < 1 {
                self.minDelayTime = oldValue
            }
        }
    }
    /// 重连最大延迟时间
    public var maxDelayTime: Int {
        didSet {
            if self.maxDelayTime < self.minDelayTime {
                self.maxDelayTime = oldValue
            }
        }
    }
    
    // MARK: Private Properties
    
    /// 执行任务的队列
    private let queue: DispatchQueue
    /// 任务的优先级
    private let qos: DispatchQoS
    /// 重连次数
    private(set) var retryTimes = 0
    /// 重连延迟时间
    private var delayTime: TimeInterval {
        return TimeInterval(min(self.minDelayTime << self.retryTimes, self.maxDelayTime))
    }
    /// 重连任务
    private var timer: DispatchSourceTimer? {
        didSet {
            oldValue?.cancel()
        }
    }
    // MARK: Lifecycle
    deinit {
        self.timer = nil
    }
    
    /// 构造重连管理器
    ///
    /// - Parameters:
    ///  - queue: 执行任务的队列
    ///  - qos: 任务的优先级
    ///  - isEnabled: 是否可用
    ///  - minDelayTime: 重连最小延迟时间，默认为1秒
    ///  - maxDelayTime: 重连最大延迟时间， 默认为60秒
    public init(queue: DispatchQueue = .main, qos: DispatchQoS = .background, isEnabled: Bool = true, minDelayTime: Int = 1, maxDelayTime: Int = 60) {
        self.queue = queue
        self.qos = qos
        self.isEnabled = isEnabled
        self.minDelayTime = minDelayTime
        self.maxDelayTime = maxDelayTime
    }
    
    //MARK: public Methods
    
    /// 延迟重连
    public func delayReconnect() {
        guard self.isEnabled else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        self.timer = timer
        timer.schedule(deadline: .now() + self.delayTime, repeating: .never)
        timer.setEventHandler(qos: self.qos) { [weak self] in
                self?.tryConnect()
        }
        timer.resume()
    }
    /// 取消重连任务，重置重连延续时间
    public func reset() {
        self.timer = nil
        self.retryTimes = 0
    }
    
    //MARK: private Methods
    
    // 尝试重连
    private func tryConnect() {
        self.retryTimes += 1
        self.delegate?.reconnectManagerDoReconnect(self)
    }
}

public protocol ReconnectManagerDelegate: class {
    /// 执行重连
    ///
    /// - Parameter manager: 重连管理器
    func reconnectManagerDoReconnect(_ manager: ReconnectManager)
}
