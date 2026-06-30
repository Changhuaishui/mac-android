import Foundation
import Network

protocol TCPServerDelegate: AnyObject {
    func serverDidAcceptConnection(_ server: TCPServer)
    func serverDidLoseConnection(_ server: TCPServer, error: Error?)
}

final class TCPServer {
    weak var delegate: TCPServerDelegate?
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.macandroid.machost.tcp")
    private let sendQueue = DispatchQueue(label: "com.macandroid.machost.tcp.send")
    private var pendingSends: [Data] = []
    private var isSending = false

    var isConnected: Bool {
        return connection?.state == .ready
    }

    init(port: UInt16) {
        self.port = NWEndpoint.Port(integerLiteral: port)
    }

    func start() throws {
        listener = try NWListener(using: .tcp, on: port)
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.delegate?.serverDidLoseConnection(self!, error: error)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { return }
            if self.connection != nil {
                // M1 只服务一个 client，拒绝后续连接
                newConnection.cancel()
                return
            }
            self.connection = newConnection
            self.setupConnection(newConnection)
            self.delegate?.serverDidAcceptConnection(self)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        sendQueue.async {
            self.pendingSends.removeAll()
            self.isSending = false
        }
    }

    func send(_ data: Data) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingSends.append(data)
            self.processSendQueue()
        }
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                self.connection = nil
                self.sendQueue.async {
                    self.pendingSends.removeAll()
                    self.isSending = false
                }
                self.delegate?.serverDidLoseConnection(self, error: error)
            case .cancelled:
                self.connection = nil
                self.sendQueue.async {
                    self.pendingSends.removeAll()
                    self.isSending = false
                }
                self.delegate?.serverDidLoseConnection(self, error: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func processSendQueue() {
        guard !isSending, let connection = connection, connection.state == .ready, !pendingSends.isEmpty else { return }
        isSending = true
        let data = pendingSends.removeFirst()
        connection.send(content: data, completion: .contentProcessed({ [weak self] _ in
            guard let self = self else { return }
            self.sendQueue.async {
                self.isSending = false
                self.processSendQueue()
            }
        }))
    }
}
