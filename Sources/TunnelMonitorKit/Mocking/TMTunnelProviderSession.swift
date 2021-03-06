//
//  TMTunnelProviderSession.swift
//  TunnelMonitorKit
//
//  Created by Chris J on 17/04/2022.
//  Copyright © 2022 Chris Janusiewicz. Distributed under the MIT License.
//

import Foundation
import NetworkExtension

/// A base class allowing native and mock sessions to be used interchangebly.
public class TMTunnelProviderSession {

    /// This method returns immediately after starting the process of connecting the tunnel.
    /// - Parameter options: A dictionary containing options to be passed to the Tunnel Provider extension.
    func startTunnel(options: [String: Any]?) throws { }

    /// This method returns immediately after starting the process of disconnecting the tunnel.
    func stopTunnel() { }

    /// Attempts to send a message to the tunnel session.
    /// - Parameters:
    ///   - message: The message to be sent
    ///   - responseHandler: Completion handler invoked with the response, if one is received.
    func sendProviderMessage(_ message: Data, responseHandler: ResponseCompletion) throws { }

    /// Returns the current session status.
    var status: NEVPNStatus { return .invalid }

}

/// A wrapper around a real NETunnelProviderSession.
public class TMTunnelProviderSessionNative: TMTunnelProviderSession {

    private let nativeSession: NETunnelProviderSession

    public init(nativeSession: NETunnelProviderSession) {
        self.nativeSession = nativeSession
    }

    override public var status: NEVPNStatus {
        return nativeSession.status
    }

    override public func stopTunnel() {
        nativeSession.stopTunnel()
    }

    override public func startTunnel(options: [String: Any]?) throws {
        try nativeSession.startTunnel(options: options)
    }

    override public func sendProviderMessage(_ message: Data, responseHandler: ResponseCompletion) throws {
        try nativeSession.sendProviderMessage(message, responseHandler: responseHandler)
    }
}

/// A mock tunnel provider session.
public class TMTunnelProviderSessionMock: TMTunnelProviderSession {

    public let mockMessageRouter = MessageRouter()
    private var currentStatus: NEVPNStatus = .invalid
    private var provider: TMPacketTunnelProvider?

    public func setProvider(_ provider: TMPacketTunnelProvider) {
        self.provider = provider
    }

    public func setStatus(_ status: NEVPNStatus) {
        currentStatus = status
    }

    override public var status: NEVPNStatus {
        return currentStatus
    }

    override public func stopTunnel() {
        currentStatus = NEVPNStatus.disconnected
    }

    override public func startTunnel(options: [String: Any]?) throws {
        currentStatus = NEVPNStatus.connected
    }

    override public func sendProviderMessage(_ message: Data, responseHandler: ResponseCompletion) throws {
        guard currentStatus == .connected else {
            throw TMCommunicationError.invalidState(currentStatus)
        }
        do {
            if let provider = provider {
                provider.handleAppMessage(message, completionHandler: responseHandler)
                return
            }
            let messageContainer = try JSONDecoder().decode(MessageContainer.self, from: message)
            mockMessageRouter.handle(message: messageContainer) { data in
                responseHandler?(data)
            }
        } catch {
            throw TMCommunicationError.responseDecodingError(decodeError: error)
        }
    }

}
