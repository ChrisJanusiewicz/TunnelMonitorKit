//
//  TMTunnelProviderManager.swift
//  TunnelMonitorKit
//
//  Created by Chris J on 14/05/2022.
//  Copyright © 2022 Chris Janusiewicz. Distributed under the MIT License.
//

import NetworkExtension
import Foundation

/// Defines events describing changes to the state of the tunnel provider, and the specific service it provides.
public protocol TMTunnelProviderManagerDelegate: AnyObject {

    /// Invoked whenever the tunnel provider state changes.
    func tunnelStateChanged(to state: NEVPNStatus)

    /// Invoked every time the service state changes. This contains information specific to the service provided by the
    /// tunnel provider, represented by an instance the generic parameter `ServiceInfo`.`
    func serviceStateChanged<ServiceInfo: Codable>(to state: ServiceInfo)
}

/// A base class allowing native and mock network extensions to be used interchangebly. Its subclasses are responsible
/// for creating, managing and monitoring a tunnel session. The host/container application should create an instance of
/// `TMMockTunnelProviderManager` or `TMNativeTunnelProviderManager` using `TMMockTunnelProviderManagerFactory`, based
/// on whether mocking is desired or not.
public class TMTunnelProviderManager {

    init() {}

    var session: TMTunnelProviderSession? { fatalError("Must override") }

    var tunnelMonitor: TunnelMonitor { fatalError("Must override") }

    /// Starts the tunnel.
    public func startTunnel() { }

    /// Stops the tunnel.
    public func stopTunnel() { }

    /// The delegate to which events are sent about the state of the tunnel provider and the service it provides.
    public weak var delegate: TMTunnelProviderManagerDelegate?

    /// Current status of the network extension
    public var tunnelStatus: NEVPNStatus { fatalError("Must override") }

    /// Sends a message request to the tunnel provider.
    ///
    /// Automatically decoding any response to the type specified in the response handler. Use `send(_: Request)` when
    /// you don't expect a response or don't care about decoding it or
    /// its value.
    /// - Parameters:
    ///   - message: The message to send to the network extesion.
    ///   - responseHandler: A response handler containing either a successfully decoded response, or an error.
    public func send<Request: Codable, Response: Codable>(
        message: Request,
        responseHandler: @escaping (Result<Response, TMCommunicationError>) -> Void
    ) {
        tunnelMonitor.send(message: message, responseHandler: responseHandler)
    }

    /// Sends a message request to the tunnel provider, ignoring any response that is returned.
    ///
    /// Use `send(_: Request, _: @escaping (Result<Response, TMCommunicationError>) -> Void)` if you want to decode the
    /// response to a specific Codable type.
    /// - Parameters:
    ///   - message: The message to send to the network extesion.
    public func send<Request: Codable>(message: Request) {
        tunnelMonitor.send(message: message) { (_: Result<Data, TMCommunicationError>) in }
    }

    /// Starts monitoring the current network extension using state requests generated by the given request builder at
    /// the specified interval.
    /// - Parameters:
    ///   - requestBuilder: The block responsible for constructing a status request.
    ///   - responseHandler: The response handler which is invoked for every status response.
    ///   - pollInterval: The interval at which to request status updates.
    public func startMonitoring<ServiceInfoRequest: Codable, ServiceInfoResponse: Codable>(
        withRequestBuilder requestBuilder: @escaping () -> ServiceInfoRequest,
        responseHandler: @escaping (Result<ServiceInfoResponse, TMCommunicationError>) -> Void,
        pollInterval: TimeInterval = 1.0
    ) {
        guard let session = session, session.status == .connected else {
            log(.error, "Unable to monitor session - incorrect state")
            return
        }
        tunnelMonitor.startMonitoring(
            session: session,
            withRequestBuilder: requestBuilder,
            responseHandler: responseHandler,
            pollInterval: pollInterval
        )
    }

    /// Stops monitoring the tunnel provider session.
    public func stopMonitoring() {
        tunnelMonitor.stopMonitoring()
    }

}

/// A mock tunnel provider manager which allows the functionality of a specific TMPacketTunnelProvider to be executed on
/// host/container app targets and simulator target environments.
public class TMMockTunnelProviderManager: TMTunnelProviderManager {

    private let provider: TMPacketTunnelProvider
    private let mockSession = TMTunnelProviderSessionMock()
    private let monitor = TunnelMonitor()
    private let networkSettings: TMNetworkSettings
    private let userConfigurationData: Data?

    private var currentTunnelStatus: NEVPNStatus = .invalid {
        didSet {
            mockSession.setStatus(currentTunnelStatus)
            log(.debug, "Notifying delegate of status change: \(oldValue) -> \(currentTunnelStatus)")
            delegate?.tunnelStateChanged(to: currentTunnelStatus)
        }
    }

    init<UserConfiguration: Codable>(
        provider: TMPacketTunnelProvider,
        networkSettings: TMNetworkSettings,
        userConfiguration: UserConfiguration?
    ) throws {
        self.provider = provider
        self.networkSettings = networkSettings

        if let userConfiguration = userConfiguration {
            self.userConfigurationData = try JSONEncoder().encode(userConfiguration)
        } else {
            self.userConfigurationData = nil
        }

        mockSession.setProvider(provider)
    }

    override var session: TMTunnelProviderSession? { mockSession }
    override public var tunnelStatus: NEVPNStatus { currentTunnelStatus }
    override public var tunnelMonitor: TunnelMonitor { monitor }

    private func configureProvider(completionHandler: @escaping (TMTunnelConfigurationError?) -> Void) {
        provider.configureTunnel(
            userConfigurationData: userConfigurationData,
            settingsApplicationBlock: { _, completion in completion?(nil) },
            completionHandler: completionHandler
        )
    }

    override public func startTunnel() {
        currentTunnelStatus = .connecting
        log(.info, "Configuring mock packet tunnel provider...")

        configureProvider { error in
            if let error = error {
                log(.error, "Failed to configure mock tunnel provider: \(error)")
                return
            }

            self.provider.startTunnel(options: nil) { error in
                if let error = error {
                    self.currentTunnelStatus = .disconnecting
                    self.currentTunnelStatus = .disconnected
                    log(.error, "Failed to start mock tunnel provider: \(error)")
                    return
                }
                self.currentTunnelStatus = .connected
                self.monitor.setSession(session: self.mockSession)
                log(.info, "Mock packet tunnel provider successfully started")
            }
        }
    }

    override public func stopTunnel() {
        provider.stopTunnel(with: .userInitiated) {
            log(.info, "Mock packet tunnel stopped")
        }
    }
}
