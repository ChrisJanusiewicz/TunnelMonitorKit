//
//  TMPacketTunnelProvider.swift
//  TunnelMonitorKit
//
//
//  Created by Chris J on 17/04/2022.
//  Copyright © 2022 Chris Janusiewicz. Distributed under the MIT License.
//

import Foundation
import NetworkExtension

/// Allows for a single implementation to be executed as a tunnel provider on network extension targets, as well as in
/// the container app target. This allows the tunnel provider implementation to be mocked and tested when deploying to
/// simulator target environments. Limitations include not having access to the packetFlow object when mocking, making
/// actual VPN implementations near impossible when running in the app layer.
///
/// TMPacketTunnelProvider must be a protocol, as instances of NEPacketTunnelProvider and its subclasses cannot be
/// instantiated on non-network extension targets, while a native packet tunnel provider must inherit from this class in
/// order to be instantiated by the system. The workaround is to define a generic subclass of a class that
/// implements the provider protocol for running on network extension targets
/// (`TMPacketTunnelProviderNative<T: TMPacketTunnelProvider>`), and create a class that inherits from the
/// same provider protocol implementation for mocking (`TMMockTunnelProviderManager`). This allows a single
/// implementation to instantiated on, and outside network extension targets.
///
/// The Packet Tunnel target must define a `TMPacketTunnelProviderNative` subclass constrained to an implementation of
/// the `TMPacketTunnelProvider` protocol, with the info.plist file pointing to it via the `NSExtensionPrincipalClass`
/// entry.
public protocol TMPacketTunnelProvider {

    init()

    // TODO #10: Add support for mocking NEPacketTunnelFlow

    /// This configuration function is invoked when the tunnel is being started by a TMTunnelProviderManager. It must
    /// perform any set up required to perform its job, and call the completion handler with `nil` after configuration
    /// is finished and the tunnel is ready to start, or with a `TMTunnelConfigurationError` when an unrecoverable
    /// error is encountered and the tunnel cannot be configured and started.
    ///
    /// Any specific functionality can be configured using the `userConfigurationData` object, which is a serialized
    /// representation of the user configuration object passed to the constructors of `TMTunnelProviderManager`
    /// mock and native subclasses.
    ///
    /// - Parameters:
    ///   - userConfigurationData: Serialized representation of the user configuration object passed to the constructors
    ///   of `TMTunnelProviderManager` subclasses, or nil if no user configuration was supplied.
    ///   - settingsApplicationBlock: The block which applies the tunnel's protocol configuration object.
    ///   - completionHandler: The completion handler which signals configuration completion to the provider manager.
    func configureTunnel(
        userConfigurationData: Data?,
        settingsApplicationBlock: @escaping (NETunnelNetworkSettings?, ((Error?) -> Void)?) -> Void,
        completionHandler: @escaping (TMTunnelConfigurationError?) -> Void
    )

    /// This method is invoked by the provider manager after configuration of the tunnel in the `configureTunnel`
    /// method finishes without any errors. The implementation should start the user defined service in this method and
    /// call the completion handler with `nil` after the service has been successfully started, otherwise with an Error.
    /// - Parameters:
    ///   - options: Currently unused options dictionary that may be used for extra configuration in the future.
    ///   - completionHandler: Completion handler used to report a successful startup, or any errors.
    func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void)

    /// This method is invoked by the provider manager when it receives a signal to stop the tunnel. The implementation
    /// should stop it's service and perform any necessary cleanup before calling the completion handler to indicate the
    /// tunnel has been stopped.
    /// - Parameters:
    ///   - reason: The reason for stopping the tunnel
    ///   - completionHandler: Completion handler used to signal that the tunne lhas been stopped.
    func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void)

    /// This method is invoked whenever the tunnel receives a message from the host application. This communication
    /// protocol is bi-directional, but can only be initiated by the host application. A response can be sent to the
    /// host application using the completion handler.
    ///
    /// The recommended usage is to define a `MessageRouter` on the implementation of this protocol and register
    /// handlers during tunnel configuration, for each type of request that the host application is able to send. It is
    /// a good idea to define a general request which is polled at a time interval, with a response that contains the
    /// general state of the tunnel, when real-time information about the tunnel is required.
    ///
    /// ```
    /// let request = try! decoder.decode(MessageContainer.self, from: messageData)
    /// appMessageRouter.handle(message: request, completionHandler: handler)
    /// ```
    ///
    /// - Parameters:
    ///   - messageData: A serialized representation of the incoming host application request.
    ///   - completionHandler: A block which sends a response to the host application.
    func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?)

}
