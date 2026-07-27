import Foundation

enum OBDError: LocalizedError {
    case noData(String)
    case negative(UInt8)
    case badResponse(String)
    case timeout(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .noData(let s):      return Loc.t("Нет данных: \(s)", "No data: \(s)")
        case .negative(let nrc):  return Loc.t("Блок отказал (NRC 0x\(String(nrc, radix: 16, uppercase: true)))",
                                               "ECU refused (NRC 0x\(String(nrc, radix: 16, uppercase: true)))")
        case .badResponse(let s): return Loc.t("Непонятный ответ: \(s)", "Unexpected response: \(s)")
        case .timeout(let s):     return Loc.t("Таймаут: \(s)", "Timeout: \(s)")
        case .notConnected:       return Loc.t("Нет подключения", "Not connected")
        }
    }
}

struct AdapterInfo {
    var identity: String        // ответ на ATI, напр. "ELM327 v1.5"
    var protocolName: String    // ответ на ATDP
    var protocolNumber: String  // ответ на ATDPN
    var voltage: Double?        // ATRV
}

/// Сессия с адаптером ELM327 поверх любого транспорта.
actor ELM327 {
    private let transport: Transport
    private(set) var info = AdapterInfo(identity: "—", protocolName: "—",
                                        protocolNumber: "—", voltage: nil)

    /// Лог всего обмена — показывается в UI и попадает в отчёт.
    private(set) var traffic: [String] = []
    private let trafficLimit = 4000

    init(transport: Transport) {
        self.transport = transport
    }

    var channelDescription: String { transport.descriptionText }

    private func log(_ s: String) {
        traffic.append(s)
        if traffic.count > trafficLimit { traffic.removeFirst(traffic.count - trafficLimit) }
    }

    func trafficLog() -> [String] { traffic }

    // MARK: - Низкий уровень

    /// Отправляет строку и ждёт приглашение '>'.
    private func exchange(_ cmd: String, timeout: TimeInterval) async throws -> String {
        _ = transport.readAvailable()                 // сбрасываем хвосты прошлого ответа
        guard let payload = (cmd + "\r").data(using: .ascii) else {
            throw OBDError.badResponse(cmd)
        }
        try transport.write(payload)
        log("→ \(cmd)")

        var acc = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chunk = transport.readAvailable()
            if !chunk.isEmpty {
                acc.append(chunk)
                if acc.contains(0x3E) { break }        // '>'
            } else {
                try await Task.sleep(nanoseconds: 8_000_000)
            }
        }

        guard !acc.isEmpty else {
            log("← (тишина)")
            throw OBDError.timeout(cmd)
        }

        let text = String(decoding: acc, as: UTF8.self)
            .components(separatedBy: ">").first ?? ""
        for line in text.split(whereSeparator: \.isNewline) where !line.trimmed.isEmpty {
            log("← \(line.trimmed)")
        }
        return text
    }

    /// Ответ, очищенный от эха и служебных строк.
    private func lines(_ cmd: String, timeout: TimeInterval) async throws -> [String] {
        let text = try await exchange(cmd, timeout: timeout)
        let wanted = cmd.replacingOccurrences(of: " ", with: "").uppercased()
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let line = raw.trimmed
            if line.isEmpty { continue }
            let compact = line.replacingOccurrences(of: " ", with: "").uppercased()
            if compact == wanted { continue }                       // эхо команды
            if compact == "SEARCHING..." || compact.hasPrefix("BUSINIT") { continue }
            out.append(line)
        }
        return out
    }

    // MARK: - Инициализация

    func connect() async throws -> AdapterInfo {
        // ATZ полностью перезагружает адаптер, ему нужно до 5 секунд
        _ = try? await exchange("ATZ", timeout: 6)
        try await Task.sleep(nanoseconds: 400_000_000)

        _ = try? await lines("ATE0", timeout: 3)     // без эха
        _ = try? await lines("ATL0", timeout: 2)     // без лишних \n
        _ = try? await lines("ATS1", timeout: 2)     // пробелы между байтами
        _ = try? await lines("ATH0", timeout: 2)     // без CAN-заголовков
        _ = try? await lines("ATAT1", timeout: 2)    // адаптивные тайминги
        _ = try? await lines("ATSP0", timeout: 2)    // автоопределение протокола

        let identity = (try? await lines("ATI", timeout: 3))?.first ?? "—"

        // первый реальный запрос заставляет адаптер выбрать протокол
        _ = try? await request(mode: 0x01, pid: 0x00, timeout: 8)

        let dp  = (try? await lines("ATDP",  timeout: 3))?.first ?? "—"
        let dpn = (try? await lines("ATDPN", timeout: 3))?.first ?? "—"

        info = AdapterInfo(identity: identity,
                           protocolName: dp,
                           protocolNumber: dpn,
                           voltage: try? await readVoltage())
        return info
    }

    /// Напряжение бортсети по данным адаптера (ATRV).
    func readVoltage() async throws -> Double? {
        guard let raw = (try? await lines("ATRV", timeout: 3))?.first else { return nil }
        let cleaned = raw.uppercased()
            .replacingOccurrences(of: "V", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    // MARK: - Разбор ответов

    /// Собирает байты из строк ответа ELM327.
    /// Понимает одиночный кадр, многокадровый CAN ('0:', '1:'…) и ответы нескольких блоков.
    private static func assemble(_ lines: [String], expect: UInt8) throws -> [UInt8] {
        for l in lines {
            let u = l.uppercased()
            if u.contains("NO DATA") || u.contains("UNABLE TO CONNECT")
                || u.contains("CAN ERROR") || u.contains("BUS ERROR")
                || u.contains("STOPPED") || u.contains("?") || u.contains("ERROR") {
                throw OBDError.noData(l)
            }
        }

        // многокадровый ответ
        let framed = lines.compactMap { line -> (Int, [UInt8])? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let idxPart = line[line.startIndex..<colon].trimmed
            guard let idx = Int(idxPart, radix: 16) else { return nil }
            let bytes = hexBytes(String(line[line.index(after: colon)...]))
            return (idx, bytes)
        }
        if !framed.isEmpty {
            var data: [UInt8] = []
            for (_, bytes) in framed.sorted(by: { $0.0 < $1.0 }) { data += bytes }
            guard let start = data.firstIndex(of: expect) else {
                throw OBDError.badResponse(lines.joined(separator: " | "))
            }
            return Array(data[start...])
        }

        // одиночные кадры: берём первый, начинающийся с ожидаемого байта
        for line in lines {
            let bytes = hexBytes(line)
            guard !bytes.isEmpty else { continue }
            if bytes[0] == 0x7F, bytes.count >= 3 { throw OBDError.negative(bytes[2]) }
            if bytes[0] == expect { return bytes }
        }

        throw OBDError.badResponse(lines.joined(separator: " | "))
    }

    private static func hexBytes(_ s: String) -> [UInt8] {
        let compact = s.uppercased().filter { $0.isHexDigit }
        guard compact.count >= 2 else { return [] }
        var out: [UInt8] = []
        var it = compact.startIndex
        while let next = compact.index(it, offsetBy: 2, limitedBy: compact.endIndex) {
            if let b = UInt8(compact[it..<next], radix: 16) { out.append(b) }
            it = next
        }
        return out
    }

    // MARK: - Запросы

    /// Полный ответ, включая байты режима и PID.
    func request(mode: UInt8, pid: UInt8? = nil, timeout: TimeInterval = 5) async throws -> [UInt8] {
        var cmd = String(format: "%02X", mode)
        if let pid { cmd += String(format: "%02X", pid) }
        let ls = try await lines(cmd, timeout: timeout)
        guard !ls.isEmpty else { throw OBDError.noData(cmd) }
        return try Self.assemble(ls, expect: mode &+ 0x40)
    }

    /// Произвольная команда (нужна там, где запрос длиннее «режим + PID»).
    func rawRequest(command: String, expect: UInt8, timeout: TimeInterval = 5) async throws -> [UInt8] {
        let ls = try await lines(command, timeout: timeout)
        guard !ls.isEmpty else { throw OBDError.noData(command) }
        return try Self.assemble(ls, expect: expect)
    }

    /// Стоп-кадр (Mode 02): условия в момент возникновения ошибки.
    func freezeFrame(pid: UInt8, frame: UInt8 = 0, timeout: TimeInterval = 5) async throws -> [UInt8] {
        let cmd = String(format: "02%02X%02X", pid, frame)
        let full = try await rawRequest(command: cmd, expect: 0x42, timeout: timeout)
        guard full.count > 3 else { throw OBDError.noData(cmd) }
        return Array(full[3...])          // пропускаем 42, PID, номер кадра
    }

    /// Стереть коды ошибок и данные стоп-кадра (Mode 04).
    func clearDTCs(timeout: TimeInterval = 8) async throws {
        let ls = try await lines("04", timeout: timeout)
        for l in ls where l.uppercased().contains("44") { return }
        for l in ls {
            let u = l.uppercased()
            if u.contains("NO DATA") || u.contains("ERROR") || u.contains("UNABLE") {
                throw OBDError.noData(l)
            }
        }
    }

    /// Полезная нагрузка без заголовка (без байта режима и PID).
    func payload(mode: UInt8, pid: UInt8? = nil, timeout: TimeInterval = 5) async throws -> [UInt8] {
        let full = try await request(mode: mode, pid: pid, timeout: timeout)
        let skip = (pid != nil) ? 2 : 1
        guard full.count > skip else { throw OBDError.noData("пустая нагрузка") }
        return Array(full[skip...])
    }

    func close() {
        transport.close()
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
