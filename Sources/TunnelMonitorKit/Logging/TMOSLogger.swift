//
//  TMOSLogger.swift
//  TunnelMonitorKit
//
//  Created by Chris J on 23/03/2022.
//  Copyright © 2022 Chris Janusiewicz. Distributed under the MIT License.
//

import Foundation
import os.log

/// A TunnelMonitor Logger implementation, based on the system logger. Distinguishes logs originating from the host
/// application and network extension.
public class TMBasicLogger: TMLogger {

    // TODO #11: Add format and arguments log function to add support for access modifiers

    let targetPrefix = Bundle.main.bundlePath.hasSuffix(".appex") ? "TUN" : "APP"
    var minimumLogLevel: LogLevel = .info

    public init() { }

    public func setLogLevel(_ level: LogLevel) {
        minimumLogLevel = level
    }

    public func log(_ level: LogLevel, _ message: String) {
        if level.rawValue >= minimumLogLevel.rawValue {
            print("[TM:\(targetPrefix)] \(level.description): \(message)")
        }
    }
}

/// A TunnelMonitor Logger implementation, based on the system logger. Distinguishes logs originating from the host
/// application and network extension.
public class TMOSLogger: TMBasicLogger {

    // TODO #11: Support OSLog log levels

    override public func log(_ level: LogLevel, _ message: String) {
        if level.rawValue >= minimumLogLevel.rawValue {
            os_log("%{public}s", "[TM:\(targetPrefix)] \(level.description): \(message)")
        }
    }
}
