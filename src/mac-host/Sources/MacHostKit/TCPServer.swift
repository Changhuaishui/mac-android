import Foundation
import Darwin

private func tcpServerLog(_ message: String) {
    let date = ISO8601DateFormatter().string(from: Date())
    let full = "[\(date)] [TCPSERVER] \(message)\n"
    FileHandle.standardOutput.write(Data(full.utf8))
}

protocol TCPServerDelegate: AnyObject {
    /// TCP 连接已建立，但尚未收到 HELLO。可在此开始读取超时计时。
    func serverDidAcceptConnection(_ server: TCPServer)
    /// 收到 Android 发来的 HELLO payload。Mac Host 应解析并决定输出档位。
    func serverDidReceiveHello(_ server: TCPServer, data: Data)
    /// 收到 PING。Mac Host 可选择原样回复或仅更新连接状态。
    func serverDidReceivePing(_ server: TCPServer, data: Data)
    /// 收到 INPUT_EVENT payload。Mac Host 应解析并注入。
    func server(_ server: TCPServer, didReceiveInputEvent data: Data)
    /// 收到对端 ERROR payload。Mac Host 应记录诊断日志。
    func server(_ server: TCPServer, didReceiveError data: Data)
    /// 连接丢失或发生错误。
    func serverDidLoseConnection(_ server: TCPServer, error: Error?)
}

/// 双栈 POSIX socket TCP server。
/// M1 只服务一个 client；连接建立后关闭监听器。
final class TCPServer {
    weak var delegate: TCPServerDelegate?
    private let port: UInt16
    private var listenerSockets: [Int32] = []
    private var listenerSources: [DispatchSourceRead] = []
    private var clientSocket: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.macandroid.machost.tcp")
    private let sendQueue = DispatchQueue(label: "com.macandroid.machost.tcp.send")
    private var pendingSends: [Data] = []
    private var isSending = false
    private var helloReceived = false
    private var readBuffer = Data()
    private var isStopped = false

    var isConnected: Bool { clientSocket >= 0 }

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        // IPv6 监听器（V6ONLY=1），只处理 IPv6；与 IPv4 监听器分离，保证 127.0.0.1 / adb reverse 可用。
        if let v6 = createListener(family: AF_INET6, v6Only: true) {
            listenerSockets.append(v6)
        }

        // 独立 IPv4 监听器，确保 127.0.0.1 / adb reverse / 局域网 IPv4 一定可达。
        if let v4 = createListener(family: AF_INET, v6Only: nil) {
            listenerSockets.append(v4)
        }

        guard !listenerSockets.isEmpty else {
            throw TCPServerError.bindFailed
        }

        for socketFD in listenerSockets {
            let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
            source.setEventHandler { [weak self] in
                self?.handleAccept(listenerFD: socketFD)
            }
            source.setCancelHandler { [socketFD] in
                close(socketFD)
            }
            source.resume()
            listenerSources.append(source)
        }
    }

    func stop() {
        isStopped = true
        listenerSources.forEach { $0.cancel() }
        listenerSources.removeAll()
        listenerSockets.removeAll()
        closeClient()
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

    // MARK: - Listener creation

    private func createListener(family: Int32, v6Only: Bool?) -> Int32? {
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        if family == AF_INET6, let v6Only = v6Only {
            var value: Int32 = v6Only ? 1 : 0
            setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &value, socklen_t(MemoryLayout<Int32>.size))
        }

        let bindResult: Int32
        if family == AF_INET6 {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = in6addr_any
            bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard bindResult == 0, listen(fd, 1) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    // MARK: - Accept

    private func handleAccept(listenerFD: Int32) {
        guard !isStopped, clientSocket == -1 else { return }

        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let accepted = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenerFD, $0, &len)
            }
        }
        guard accepted >= 0 else { return }

        // 关闭 Nagle 算法，降低小包延迟。
        var noDelay: Int32 = 1
        setsockopt(accepted, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

        // M1 只服务一个 client，连接成功后关闭所有监听器。
        stopListening()
        clientSocket = accepted
        setupClientReadSource()
        delegate?.serverDidAcceptConnection(self)
    }

    private func stopListening() {
        listenerSources.forEach { $0.cancel() }
        listenerSources.removeAll()
        listenerSockets.removeAll()
    }

    // MARK: - Client read

    private func setupClientReadSource() {
        guard clientSocket >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: clientSocket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleClientData()
        }
        source.setCancelHandler { [weak self] in
            self?.closeClient()
        }
        source.resume()
        clientSource = source
    }

    private func handleClientData() {
        guard clientSocket >= 0 else { return }
        var buffer: [UInt8] = Array(repeating: 0, count: 65536)
        let readCount = recv(clientSocket, &buffer, buffer.count, 0)
        if readCount <= 0 {
            let err = readCount == 0 ? nil : TCPServerError.readFailed(errno)
            tcpServerLog("recv returned \(readCount), errno=\(errno), closing client")
            closeClient()
            delegate?.serverDidLoseConnection(self, error: err)
            return
        }
        tcpServerLog("recv \(readCount) bytes, total buffered: \(readBuffer.count + Int(readCount))")
        readBuffer.append(contentsOf: buffer.prefix(Int(readCount)))
        processReadBuffer()
    }

    private func processReadBuffer() {
        while true {
            guard readBuffer.count >= ProtocolHeader.size else { return }
            let headerData = readBuffer.prefix(ProtocolHeader.size)
            guard let header = ProtocolHeader(data: Data(headerData)) else {
                tcpServerLog("bad header, first 32 bytes: \(readBuffer.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
                closeClient()
                delegate?.serverDidLoseConnection(self, error: TCPServerError.badHeader)
                return
            }
            let payloadLen = Int(header.payloadLength)
            tcpServerLog("header ok: type=\(header.type) payload_len=\(payloadLen)")
            guard payloadLen <= 8 * 1024 * 1024 else {
                tcpServerLog("payload too large: \(payloadLen)")
                closeClient()
                delegate?.serverDidLoseConnection(self, error: TCPServerError.payloadTooLarge)
                return
            }
            guard readBuffer.count >= ProtocolHeader.size + payloadLen else {
                tcpServerLog("waiting for payload, have \(readBuffer.count - ProtocolHeader.size) need \(payloadLen)")
                return
            }
            let payload = readBuffer.subdata(in: ProtocolHeader.size..<ProtocolHeader.size + payloadLen)
            readBuffer.removeFirst(ProtocolHeader.size + payloadLen)

            switch header.type {
            case .hello:
                let jsonPreview = String(data: payload.prefix(2048), encoding: .utf8) ?? "<non-utf8>"
                tcpServerLog("HELLO payload (truncated 2KB): \(jsonPreview)")
                helloReceived = true
                delegate?.serverDidReceiveHello(self, data: payload)
            case .inputEvent:
                delegate?.server(self, didReceiveInputEvent: payload)
            case .ping:
                tcpServerLog("PING received (payload=\(payload.count) bytes)")
                delegate?.serverDidReceivePing(self, data: payload)
            case .error:
                let preview = String(data: payload.prefix(512), encoding: .utf8) ?? "<non-utf8>"
                tcpServerLog("ERROR received: \(preview)")
                delegate?.server(self, didReceiveError: payload)
            case .videoConfig, .videoFrame:
                // Mac Host 是发送端，不应收到这些类型；记录后忽略，保持连接。
                tcpServerLog("unexpected message type=\(header.type), ignoring")
            }
        }
    }

    // MARK: - Client send

    private func processSendQueue() {
        guard !isSending, clientSocket >= 0, !pendingSends.isEmpty else { return }
        isSending = true
        let data = pendingSends.removeFirst()
        sendQueue.async { [weak self] in
            guard let self = self, self.clientSocket >= 0 else {
                self?.isSending = false
                return
            }
            var totalSent = 0
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                while totalSent < data.count {
                    let sent = Darwin.send(self.clientSocket, base.advanced(by: totalSent), data.count - totalSent, 0)
                    if sent <= 0 { break }
                    totalSent += sent
                }
            }
            if totalSent < data.count {
                self.queue.async {
                    self.closeClient()
                    self.delegate?.serverDidLoseConnection(self, error: TCPServerError.sendFailed)
                }
            } else {
                self.sendQueue.async {
                    self.isSending = false
                    self.processSendQueue()
                }
            }
        }
    }

    // MARK: - Cleanup

    private func closeClient() {
        clientSource?.cancel()
        clientSource = nil
        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
        helloReceived = false
        readBuffer.removeAll()
    }
}

enum TCPServerError: LocalizedError {
    case bindFailed
    case readFailed(Int32)
    case sendFailed
    case badHeader
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .bindFailed:
            return "绑定 TCP 监听端口失败"
        case .readFailed(let errno):
            return "读取客户端数据失败 (errno \(errno))"
        case .sendFailed:
            return "发送数据失败"
        case .badHeader:
            return "协议帧头解析失败"
        case .payloadTooLarge:
            return "协议 payload 超过 8MiB 上限"
        }
    }
}
