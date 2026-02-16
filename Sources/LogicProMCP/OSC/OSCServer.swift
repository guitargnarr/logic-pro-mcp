import Foundation
import Network

/// Receives OSC messages from Logic Pro over UDP using Network.framework.
actor OSCServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?

    /// Stream of inbound OSC messages.
    let messages: AsyncStream<OSCMessage>
    private let continuation: AsyncStream<OSCMessage>.Continuation

    init(port: UInt16 = ServerConfig.oscReceivePort) {
        self.port = NWEndpoint.Port(rawValue: port)!
        let (stream, continuation) = AsyncStream<OSCMessage>.makeStream()
        self.messages = stream
        self.continuation = continuation
    }

    /// Start listening for UDP datagrams.
    func start() throws {
        guard listener == nil else { return }

        let params = NWParameters.udp
        let newListener = try NWListener(using: params, on: port)

        let continuation = self.continuation
        newListener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.receiveLoop(connection: connection, continuation: continuation)
        }

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Log.info("OSCServer listening on port \(self.port)", subsystem: "osc")
            case .failed(let error):
                Log.error("OSCServer listener failed: \(error)", subsystem: "osc")
            case .cancelled:
                Log.info("OSCServer listener cancelled", subsystem: "osc")
            default:
                break
            }
        }

        newListener.start(queue: .global(qos: .userInitiated))
        self.listener = newListener
    }

    /// Stop listening.
    func stop() {
        listener?.cancel()
        listener = nil
        continuation.finish()
        Log.info("OSCServer stopped", subsystem: "osc")
    }

    var isListening: Bool { listener != nil }

    // MARK: - Private

    private static func receiveLoop(connection: NWConnection, continuation: AsyncStream<OSCMessage>.Continuation) {
        connection.receiveMessage { data, _, _, error in
            if let error {
                Log.error("OSCServer receive error: \(error)", subsystem: "osc")
                return
            }
            if let data, let message = OSCMessage.decode(data) {
                continuation.yield(message)
                Log.debug("OSC received: \(message.address)", subsystem: "osc")
            }
            // Continue receiving.
            Self.receiveLoop(connection: connection, continuation: continuation)
        }
    }
}
