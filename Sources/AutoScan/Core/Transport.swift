import Foundation

// MARK: - Общий интерфейс транспорта

/// Ошибки уровня подключения к адаптеру.
enum TransportError: LocalizedError {
    case openFailed(String)
    case notConnected
    case writeFailed(String)
    case bleUnavailable(String)
    case bleNotFound
    case bleNoCharacteristics

    var errorDescription: String? {
        switch self {
        case .openFailed(let s):      return "Не удалось открыть подключение: \(s)"
        case .notConnected:           return "Нет подключения к адаптеру"
        case .writeFailed(let s):     return "Ошибка отправки: \(s)"
        case .bleUnavailable(let s):  return "Bluetooth недоступен: \(s)"
        case .bleNotFound:            return "BLE-адаптер OBD не найден"
        case .bleNoCharacteristics:   return "У BLE-устройства нет пригодных характеристик"
        }
    }
}

/// Потокобезопасный буфер входящих байт.
final class RXBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    /// Забирает всё накопленное.
    func drain() -> Data {
        lock.lock(); defer { lock.unlock() }
        let out = data
        data.removeAll(keepingCapacity: true)
        return out
    }

    func clear() {
        lock.lock(); data.removeAll(keepingCapacity: true); lock.unlock()
    }
}

protocol Transport: AnyObject {
    /// Человекочитаемое описание канала (показывается в UI).
    var descriptionText: String { get }
    var isOpen: Bool { get }

    func open() async throws
    func write(_ data: Data) throws
    /// Возвращает всё, что пришло с прошлого вызова (может быть пусто).
    func readAvailable() -> Data
    func close()
}

// MARK: - Описание доступного адаптера

/// Способ подключения, выбранный пользователем в UI.
enum AdapterKind: Hashable {
    case wifi(host: String, port: Int)
    case serial(path: String)
    case ble(uuid: UUID?)

    var iconName: String {
        switch self {
        case .wifi:   return "wifi"
        case .serial: return "cable.connector"
        case .ble:    return "dot.radiowaves.left.and.right"
        }
    }
}

struct AdapterCandidate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let kind: AdapterKind
}

// MARK: - TCP (Wi-Fi донглы)

/// Wi-Fi ELM327. Типовой адрес — 192.168.0.10:35000.
final class TCPTransport: Transport, @unchecked Sendable {
    private let host: String
    private let port: Int
    private var fd: Int32 = -1
    private let rx = RXBuffer()
    private var reader: Thread?
    private var running = false

    let descriptionText: String
    var isOpen: Bool { fd >= 0 }

    init(host: String, port: Int) {
        self.host = host
        self.port = port
        self.descriptionText = "Wi-Fi \(host):\(port)"
    }

    func open() async throws {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC,
                             ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &info)
        guard rc == 0, let list = info else {
            throw TransportError.openFailed("адрес \(host) не разрешается")
        }
        defer { freeaddrinfo(info) }

        var lastError = "нет ответа"
        var node: UnsafeMutablePointer<addrinfo>? = list
        while let cur = node {
            let s = socket(cur.pointee.ai_family, cur.pointee.ai_socktype, cur.pointee.ai_protocol)
            if s >= 0 {
                // таймаут на чтение, чтобы поток-читатель не залипал навсегда
                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var one: Int32 = 1
                setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))

                if connect(s, cur.pointee.ai_addr, cur.pointee.ai_addrlen) == 0 {
                    fd = s
                    startReader()
                    return
                }
                lastError = String(cString: strerror(errno))
                Darwin.close(s)
            }
            node = cur.pointee.ai_next
        }
        throw TransportError.openFailed(lastError)
    }

    private func startReader() {
        running = true
        let t = Thread { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 1024)
            while self.running, self.fd >= 0 {
                let n = Darwin.read(self.fd, &buf, buf.count)
                if n > 0 {
                    self.rx.append(Data(buf[0..<n]))
                } else if n == 0 {
                    break                       // соединение закрыто
                } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    break
                }
            }
        }
        t.name = "AutoScan.TCPReader"
        t.start()
        reader = t
    }

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw TransportError.notConnected }
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { throw TransportError.writeFailed(String(cString: strerror(errno))) }
                sent += n
            }
        }
    }

    func readAvailable() -> Data { rx.drain() }

    func close() {
        running = false
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        rx.clear()
    }
}

// MARK: - Последовательный порт (USB и классический Bluetooth)

/// USB-адаптеры (/dev/cu.usbserial-*) и спаренные BT-SPP (/dev/cu.OBDII*).
final class SerialTransport: Transport, @unchecked Sendable {
    private let path: String
    private let baud: speed_t
    private var fd: Int32 = -1
    private let rx = RXBuffer()
    private var reader: Thread?
    private var running = false

    let descriptionText: String
    var isOpen: Bool { fd >= 0 }

    init(path: String, baud: Int = 38400) {
        self.path = path
        self.baud = speed_t(baud)
        self.descriptionText = "Порт \((path as NSString).lastPathComponent)"
    }

    func open() async throws {
        let handle = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard handle >= 0 else {
            throw TransportError.openFailed("\(path): \(String(cString: strerror(errno)))")
        }

        // снимаем эксклюзивную блокировку, если осталась от прошлого процесса
        _ = ioctl(handle, TIOCEXCL)

        var opts = termios()
        guard tcgetattr(handle, &opts) == 0 else {
            Darwin.close(handle)
            throw TransportError.openFailed("не читаются параметры порта")
        }
        cfmakeraw(&opts)
        cfsetispeed(&opts, baud)
        cfsetospeed(&opts, baud)
        opts.c_cflag |= tcflag_t(CREAD | CLOCAL)
        opts.c_cflag &= ~tcflag_t(PARENB)          // без паритета
        opts.c_cflag &= ~tcflag_t(CSTOPB)          // 1 стоп-бит
        opts.c_cflag &= ~tcflag_t(CRTSCTS)         // без аппаратного потока

        guard tcsetattr(handle, TCSANOW, &opts) == 0 else {
            Darwin.close(handle)
            throw TransportError.openFailed("не применяются параметры порта")
        }
        tcflush(handle, TCIOFLUSH)

        fd = handle
        startReader()
        // адаптеру нужно время после открытия порта
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func startReader() {
        running = true
        let t = Thread { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 1024)
            while self.running, self.fd >= 0 {
                let n = Darwin.read(self.fd, &buf, buf.count)
                if n > 0 {
                    self.rx.append(Data(buf[0..<n]))
                } else if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    break
                } else {
                    usleep(5000)
                }
            }
        }
        t.name = "AutoScan.SerialReader"
        t.start()
        reader = t
    }

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw TransportError.notConnected }
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 {
                    if errno == EAGAIN { usleep(2000); continue }
                    throw TransportError.writeFailed(String(cString: strerror(errno)))
                }
                sent += n
            }
        }
    }

    func readAvailable() -> Data { rx.drain() }

    func close() {
        running = false
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        rx.clear()
    }

    /// Список последовательных портов в системе.
    static func availablePorts() -> [String] {
        let fm = FileManager.default
        guard let all = try? fm.contentsOfDirectory(atPath: "/dev") else { return [] }
        return all.filter { $0.hasPrefix("cu.") }
                  .map { "/dev/" + $0 }
                  .sorted()
    }
}
