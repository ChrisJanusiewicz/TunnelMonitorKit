//
//  TunnelMonitor.swift
//  TunnelMonitorKit
// 
//  Created by Chris J on 20/03/2022.
//  Copyright © 2022 Chris Janusiewicz. Distributed under the MIT License.
//

import Foundation
import NetworkExtension

/// Responsible for communication with the an NEPacketTunnelProvider or NEAppProxyProvider. Continuously sends status
/// update requests to the network extension, such that the extension can use these requests to notify the host app of
/// any changes of state. The session to be monitored must be set using setSession after the session has connected.
open class TunnelMonitor {

    private var session: TMTunnelProviderSession?
    private var pollTimer: Timer?

    public init() { }

    /// Sets the session to be monitored. The session must be set before it can be monitored.
    /// - Parameter session: The session to be monitored.
    public func setSession(session: TMTunnelProviderSession?) {
        self.session = session
    }

    /// Starts monitoring the current NETunnelProviderSession using status requests generated by the given request
    /// builder at the specified interval.
    /// - Parameters:
    ///   - session: The session to start monitoring.
    ///   - requestBuilder: The block responsible for constructing a status request.
    ///   - handler: The response handler which is invoked for every status response.
    ///   - interval: The interval at which to request status updates
    public func startMonitoring<T: Codable, U: Codable>(
        session: TMTunnelProviderSession,
        withRequestBuilder requestBuilder: @escaping () -> T,
        responseHandler handler: @escaping (Result<U, TMCommunicationError>) -> Void,
        pollInterval interval: TimeInterval = 1.0
    ) {
        self.session = session

        let queryBlock: (Timer) -> Void = { _ in
            self.send(message: requestBuilder()) { (result: Result<U, TMCommunicationError>) in
                handler(result)
            }
        }

        pollTimer?.invalidate()
        // Schedule a timer to invoke the block repeatedly, and execute it once immediately
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true,
            block: queryBlock
        )
        queryBlock(timer)

        pollTimer = timer
    }

    /// Stops requesting status updates
    public func stopMonitoring() {
        pollTimer?.invalidate()
    }

    /// Sends a generic message to the session without decoding the response.
    /// - Parameters:
    ///   - message: The message to be encoded and sent to the session.
    ///   - responseHandler: Completion block to be invoked when a response is received.
    private func send<T: Codable>(
        message: T,
        responseHandler: @escaping (Result<Data, TMCommunicationError>) -> Void
    ) {
        guard let session = session else {
            responseHandler(.failure(.invalidExtension))
            return
        }
        guard session.status == .connected else {
            responseHandler(.failure(.invalidState(session.status)))
            return
        }

        do {
            let container = try MessageContainer.make(message: message)
            let messageData = try JSONEncoder().encode(container)
            let sendDate = Date()

            log(.debug, "Sending \(messageData.count) bytes to session")
            try session.sendProviderMessage(messageData) { data in
                guard let data = data else {
                    responseHandler(.failure(.nilResponse))
                    return
                }
                let rtt = Date().timeIntervalSince(sendDate)
                log(.info, "Response received, rtt: \(String(format: "%.1f", rtt * 1000))ms")
                responseHandler(.success(data))
            }
        } catch {
            // Rethrow as TMCommunicationError wrapping the original error
            if error is EncodingError {
                responseHandler(.failure(.containerSerializationError(encodeError: error)))
            }
            responseHandler(.failure(.sendFailure(error: error)))
        }
    }

    /// Convenience function for sending a generic message and automatically decoding the response.
    /// - Parameters:
    ///   - message: The message to be encoded and sent to the session.
    ///   - responseHandler: Completion block to be invoked when a response is received.
    public func send<T: Codable, U: Codable>(
        message: T,
        responseHandler: @escaping (Result<U, TMCommunicationError>
    ) -> Void) {
        send(message: message) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(U.self, from: data)
                    responseHandler(.success(response))
                } catch {
                    responseHandler(.failure(.responseDecodingError(decodeError: error)))
                }
            case .failure(let error):
                responseHandler(.failure(error))
            }
        }
    }
}
