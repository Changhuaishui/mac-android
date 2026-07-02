import Foundation
import Network

protocol TCPServerDelegate: AnyObject {
    /// TCP 连接已建立，但尚未收到 HELLO。可在此开始读取超时计时。
    func serverDidAcceptConnection(_ server: TCPServer)
    /// 收到 Android 发来的 HELLO payload。Mac Host 应解析并决定输出档位。
    func serverDidReceiveHello(_ server: TCPServer, data: Data)
    /// 连接丢失或发生错误。
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
    private var helloReceived = false

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
                if let self = self {
                    self.delegate?.serverDidLoseConnection(self, error: error)
                }
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
        }

        listener?.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        helloReceived = false
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
            case .ready:
                self.delegate?.serverDidAcceptConnection(self)
                self.receiveNextMessage()
                self.sendQueue.async {
                    self.processSendQueue()
                }
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

    // MARK: - Receiving (M1 只读取 HELLO)

    private func receiveNextMessage() {
        guard let connection = connection, !helloReceived else { return }
        connection.receive(minimumIncompleteLength: ProtocolHeader.size, maximumLength: ProtocolHeader.size) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.delegate?.serverDidLoseConnection(self, error: error)
                return
            }
            guard let data = data, data.count == ProtocolHeader.size else {
                // 连接可能正常关闭或数据异常
                self.delegate?.serverDidLoseConnection(self, error: ProtocolError.badHeader)
                return
            }
            guard let header = ProtocolHeader(data: data) else {
                self.delegate?.serverDidLoseConnection(self, error: ProtocolError.badHeader)
                return
            }
            self.receivePayload(header: header)
        }
    }

    private func receivePayload(header: ProtocolHeader) {
        guard let connection = connection else { return }
        let length = Int(header.payloadLength)
        guard length <= 8 * 1024 * 1024 else {
            delegate?.serverDidLoseConnection(self, error: ProtocolError.payloadTooLarge)
            return
        }
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.delegate?.serverDidLoseConnection(self, error: error)
                return
            }
            guard let data = data, data.count == length else {
                self.delegate?.serverDidLoseConnection(self, error: ProtocolError.badPayload)
                return
            }
            if header.type == .hello {
                self.helloReceived = true
                self.delegate?.serverDidReceiveHello(self, data: data)
            } else {
                // M1 在 HELLO 之后不应再收到需要处理的消息；为避免连接因未读取数据而卡死，继续读取并忽略。
                self.receiveNextMessage()
            }
        }
    }

    // MARK: - Sending

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

enum ProtocolError: LocalizedError {
    case badHeader
    case badPayload
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .badHeader:
            return "协议帧头解析失败"
        case .badPayload:
            return "协议 payload 读取失败"
        case .payloadTooLarge:
            return "协议 payload 超过 8MiB 上限"
        }
    }
}
