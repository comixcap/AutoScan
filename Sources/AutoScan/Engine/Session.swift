import Foundation
import Combine

struct ChartPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

struct LiveValue: Identifiable {
    let pid: UInt8
    let name: String
    let category: PIDCategory
    var display: String
    var value: Double?
    var updated: Date
    var id: UInt8 { pid }
}

/// Единый источник данных приложения: подключение, полная проверка, мониторинг.
@MainActor
final class VehicleSession: ObservableObject {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case scanning
        case monitoring
    }

    // MARK: Публичное состояние

    @Published private(set) var state: State = .disconnected
    @Published private(set) var adapterInfo: AdapterInfo?
    @Published private(set) var channelDescription: String = "—"
    @Published var lastError: String?

    @Published private(set) var progress: Double = 0
    @Published private(set) var stageText: String = ""

    @Published private(set) var report: ScanReport?
    @Published private(set) var findings: [Finding] = []

    @Published private(set) var liveValues: [LiveValue] = []
    @Published private(set) var history: [UInt8: [ChartPoint]] = [:]
    @Published var monitoredPIDs: Set<UInt8> = []
    @Published private(set) var supportedPIDs: [UInt8] = []
    @Published private(set) var samplesPerSecond: Double = 0

    /// Полный лог обмена с адаптером — видно, что реально происходило.
    @Published private(set) var traffic: [String] = []

    private var elm: ELM327?
    private var transport: Transport?
    private var monitorTask: Task<Void, Never>?
    private let historyLimit = 1800

    var isBusy: Bool { state == .connecting || state == .scanning }
    var isConnected: Bool { state != .disconnected && state != .connecting }

    // MARK: Подключение

    func connect(to kind: AdapterKind) async {
        guard state == .disconnected else { return }
        state = .connecting
        lastError = nil
        stageText = Loc.t("Открываем канал…", "Opening channel…")

        let t: Transport
        switch kind {
        case .wifi(let host, let port): t = TCPTransport(host: host, port: port)
        case .serial(let path):         t = SerialTransport(path: path)
        case .ble(let uuid):            t = BLETransport(deviceID: uuid)
        }

        do {
            try await t.open()
            let session = ELM327(transport: t)
            stageText = Loc.t("Инициализируем адаптер…", "Initialising adapter…")
            let info = try await session.connect()

            transport = t
            elm = session
            adapterInfo = info
            channelDescription = t.descriptionText
            state = .connected
            stageText = Loc.t("Подключено", "Connected")
            traffic = await session.trafficLog()
        } catch {
            t.close()
            state = .disconnected
            stageText = ""
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        transport?.close()
        transport = nil
        elm = nil
        state = .disconnected
        adapterInfo = nil
        channelDescription = "—"
        stageText = ""
        liveValues = []
        history = [:]
        samplesPerSecond = 0
    }

    // MARK: Полная проверка

    func runFullScan() async {
        guard let elm, state == .connected else { return }
        state = .scanning
        progress = 0
        lastError = nil

        var r = ScanReport()
        r.adapter = adapterInfo
        r.channel = channelDescription

        func step(_ fraction: Double, _ ru: String, _ en: String) {
            progress = fraction
            stageText = Loc.t(ru, en)
        }

        // 1. Напряжение
        step(0.03, "Напряжение бортсети…", "Battery voltage…")
        r.batteryVoltage = try? await elm.readVoltage()

        // 2. Какие параметры вообще поддерживает машина
        step(0.08, "Опрашиваем список поддерживаемых параметров…", "Discovering supported parameters…")
        let supported = await discoverSupportedPIDs(elm)
        r.supportedPIDs = supported
        supportedPIDs = supported
        if supported.isEmpty {
            r.notes.append(Loc.t("Блок не ответил на запрос поддерживаемых параметров.",
                                 "The ECU did not answer the supported-parameters request."))
        }

        // 3. Статус мониторов и Check Engine
        step(0.14, "Читаем статус самодиагностики…", "Reading self-diagnostics status…")
        if let d = try? await elm.payload(mode: 0x01, pid: 0x01) {
            r.readiness = ReadinessReport.parse(d)
        } else {
            r.notes.append(Loc.t("Статус мониторов (PID 0101) недоступен.",
                                 "Monitor status (PID 0101) unavailable."))
        }

        // 4. Коды ошибок
        step(0.22, "Читаем коды ошибок…", "Reading fault codes…")
        r.storedDTCs = await readDTCs(elm, mode: 0x03, kind: .stored, into: &r)
        r.pendingDTCs = await readDTCs(elm, mode: 0x07, kind: .pending, into: &r)
        r.permanentDTCs = await readDTCs(elm, mode: 0x0A, kind: .permanent, into: &r)

        // 5. Паспорт машины
        step(0.32, "Читаем VIN и версию прошивки…", "Reading VIN and calibration…")
        r.identity = await readIdentity(elm, into: &r)
        if let vin = r.identity.vin { r.vinDetails = VINDetails.decode(vin) }

        // счётчики наработки — их не стирает сброс ошибок
        let diesel = r.readiness?.compressionIgnition ?? false
        let iptPID: UInt8 = diesel ? 0x0B : 0x08
        if let d = try? await elm.payload(mode: 0x09, pid: iptPID, timeout: 8) {
            r.performance = PerformanceTracking.parse(payload: d, diesel: diesel)
        }
        if r.performance == nil {
            // часть блоков отвечает на «чужой» PID — пробуем второй вариант
            let alt: UInt8 = diesel ? 0x08 : 0x0B
            if let d = try? await elm.payload(mode: 0x09, pid: alt, timeout: 8) {
                r.performance = PerformanceTracking.parse(payload: d, diesel: !diesel)
            }
        }
        if r.performance == nil {
            r.notes.append(Loc.t("Счётчики наработки (Mode 09 PID 08/0B) не поддерживаются.",
                                 "In-use performance counters (Mode 09 PID 08/0B) not supported."))
        }

        // 6. Стоп-кадр
        step(0.40, "Читаем стоп-кадр неисправности…", "Reading freeze frame…")
        r.freezeFrame = await readFreezeFrame(elm, supported: supported)

        // 7. Бортовые тесты
        step(0.48, "Читаем результаты бортовых тестов…", "Reading on-board test results…")
        r.monitorTests = await readMonitorTests(elm, into: &r)

        // 8. Все текущие значения
        let total = max(supported.count, 1)
        for (i, pid) in supported.enumerated() {
            if Task.isCancelled { break }
            guard let def = PIDTable.def(for: pid) else { continue }
            step(0.55 + 0.42 * Double(i) / Double(total),
                 "Опрос датчиков: \(def.ru)", "Reading sensors: \(def.en)")
            if let bytes = try? await elm.payload(mode: 0x01, pid: pid),
               let reading = def.decode(bytes) {
                r.readings.append(PIDResult(pid: pid, name: def.name, category: def.category,
                                            display: reading.display, value: reading.value,
                                            rawBytes: bytes))
            }
        }

        // 9. Оценка относительно нормы.
        // Делается после опроса: норма зависит от условий замера, а они
        // становятся известны только когда прочитаны обороты и температура.
        step(0.98, "Сверяем показания с нормой…", "Comparing readings against normal ranges…")
        let ctx = EngineContext.from(r)
        for i in r.readings.indices {
            guard let v = r.readings[i].value else { continue }
            r.readings[i].assessment = Norms.assess(pid: r.readings[i].pid, value: v, context: ctx)
        }

        step(1.0, "Готово", "Done")
        r.finishedAt = Date()
        r.trafficLog = await elm.trafficLog()

        report = r
        findings = Verdict.build(from: r)
        traffic = r.trafficLog
        state = .connected
        stageText = Loc.t("Проверка завершена", "Scan complete")
    }

    // MARK: Отдельные шаги

    private func discoverSupportedPIDs(_ elm: ELM327) async -> [UInt8] {
        var result: [UInt8] = []
        var base: UInt8 = 0x00
        while true {
            guard let d = try? await elm.payload(mode: 0x01, pid: base), d.count >= 4 else { break }
            let mask = (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
            for bit in 0..<32 {
                if mask & (0x8000_0000 >> UInt32(bit)) != 0 {
                    let pid = base + UInt8(bit + 1)
                    if PIDTable.def(for: pid) != nil { result.append(pid) }
                }
            }
            // последний бит означает «поддерживается следующая группа»
            guard mask & 1 != 0, base <= 0xA0 else { break }
            base += 0x20
        }
        return result.sorted()
    }

    private func readDTCs(_ elm: ELM327, mode: UInt8, kind: DTCKind,
                          into r: inout ScanReport) async -> [DTCInfo] {
        do {
            let payload = try await elm.payload(mode: mode, timeout: 8)
            return DTCDecoder.codes(fromPayload: payload).map {
                DTCDecoder.info(for: $0, kind: kind)
            }
        } catch {
            if mode == 0x0A {
                r.notes.append(Loc.t("Постоянные коды (Mode 0A) не поддерживаются этой машиной.",
                                     "Permanent codes (Mode 0A) are not supported by this vehicle."))
            } else if mode == 0x07 {
                r.notes.append(Loc.t("Ожидающие коды (Mode 07) недоступны.",
                                     "Pending codes (Mode 07) unavailable."))
            }
            return []
        }
    }

    private func readIdentity(_ elm: ELM327, into r: inout ScanReport) async -> VehicleIdentity {
        var id = VehicleIdentity()

        func ascii(_ bytes: [UInt8]) -> String {
            String(bytes: bytes.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? ""
        }

        if let d = try? await elm.payload(mode: 0x09, pid: 0x02, timeout: 8) {
            let text = ascii(Array(d.dropFirst()))     // первый байт — число сообщений
            let cleaned = text.filter { $0.isLetter || $0.isNumber }
            if cleaned.count >= 11 { id.vin = String(cleaned.suffix(17)) }
        } else {
            r.notes.append(Loc.t("VIN (Mode 0902) не читается.", "VIN (Mode 0902) unavailable."))
        }

        if let d = try? await elm.payload(mode: 0x09, pid: 0x04, timeout: 8) {
            let body = Array(d.dropFirst())
            for chunk in stride(from: 0, to: body.count, by: 16) {
                let piece = Array(body[chunk..<min(chunk + 16, body.count)])
                let s = ascii(piece)
                if !s.isEmpty { id.calibrationIDs.append(s) }
            }
        }

        if let d = try? await elm.payload(mode: 0x09, pid: 0x06, timeout: 8) {
            let body = Array(d.dropFirst())
            for chunk in stride(from: 0, to: body.count, by: 4) where chunk + 4 <= body.count {
                let piece = body[chunk..<chunk + 4]
                id.calibrationVerification.append(piece.map { String(format: "%02X", $0) }.joined())
            }
        }

        if let d = try? await elm.payload(mode: 0x09, pid: 0x0A, timeout: 8) {
            let s = ascii(Array(d.dropFirst()))
            if !s.isEmpty { id.ecuName = s }
        }

        return id
    }

    private func readFreezeFrame(_ elm: ELM327, supported: [UInt8]) async -> FreezeFrame {
        var ff = FreezeFrame()

        // PID 02 в стоп-кадре — код, из-за которого кадр сохранён
        if let d = try? await elm.freezeFrame(pid: 0x02), d.count >= 2 {
            ff.triggerCode = DTCDecoder.code(from: d[0], d[1])
        }
        guard ff.triggerCode != nil else { return ff }

        for pid in supported where pid != 0x01 && pid != 0x02 {
            guard let def = PIDTable.def(for: pid) else { continue }
            if let bytes = try? await elm.freezeFrame(pid: pid),
               let reading = def.decode(bytes) {
                ff.entries.append(FreezeFrameEntry(pid: pid, name: def.name,
                                                   display: reading.display))
            }
        }
        return ff
    }

    private func readMonitorTests(_ elm: ELM327, into r: inout ScanReport) async -> [MonitorTest] {
        var mids: [UInt8] = []
        var base: UInt8 = 0x00
        while true {
            guard let full = try? await elm.request(mode: 0x06, pid: base),
                  full.count >= 6 else { break }
            let d = Array(full[2...])
            guard d.count >= 4 else { break }
            let mask = (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
            for bit in 0..<32 where mask & (0x8000_0000 >> UInt32(bit)) != 0 {
                mids.append(base + UInt8(bit + 1))
            }
            guard mask & 1 != 0, base <= 0xA0 else { break }
            base += 0x20
        }

        if mids.isEmpty {
            r.notes.append(Loc.t("Бортовые тесты (Mode 06) недоступны — машина их не отдаёт.",
                                 "On-board test results (Mode 06) unavailable on this vehicle."))
            return []
        }

        var tests: [MonitorTest] = []
        for mid in mids where mid != 0x00 && mid % 0x20 != 0 {
            if let full = try? await elm.request(mode: 0x06, pid: mid), full.count > 1 {
                tests.append(contentsOf: MonitorTest.parse(payloadAfter46: Array(full.dropFirst())))
            }
        }
        return tests
    }

    // MARK: Уточнение модели по VIN

    @Published private(set) var isLookingUpVIN = false
    @Published var vinLookupError: String?

    /// Запрашивает модель, двигатель и тип коробки в открытой базе NHTSA.
    /// Нужен интернет — при подключении к Wi-Fi-донглу его не будет,
    /// поэтому запускается отдельной кнопкой, а не в ходе проверки.
    func lookupVehicleModel() async {
        guard let vin = report?.identity.vin else { return }
        isLookingUpVIN = true
        vinLookupError = nil
        defer { isLookingUpVIN = false }

        do {
            let info = try await NHTSALookup.decode(vin: vin)
            if info.isEmpty {
                vinLookupError = Loc.t(
                    "База не знает этот VIN. Обычно так с машинами, которые официально не продавались в США — внутренний рынок Кореи, Японии или Китая.",
                    "The database does not recognise this VIN. Typical for cars never sold officially in the USA — Korean, Japanese or Chinese domestic market.")
            }
            report?.nhtsa = info
        } catch {
            vinLookupError = error.localizedDescription
        }
    }

    // MARK: Стирание ошибок

    func clearFaultCodes() async -> Bool {
        guard let elm, state == .connected else { return false }
        do {
            try await elm.clearDTCs()
            await runFullScan()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Мониторинг в реальном времени

    func startMonitoring(interval: TimeInterval = 0.2) {
        guard let elm, state == .connected, !monitoredPIDs.isEmpty else { return }
        state = .monitoring
        history = [:]
        liveValues = []

        monitorTask = Task { [weak self] in
            var sampleTimes: [Date] = []

            while !Task.isCancelled {
                guard let self else { return }
                let pids = await MainActor.run { self.monitoredPIDs.sorted() }
                if pids.isEmpty { try? await Task.sleep(nanoseconds: 200_000_000); continue }

                for pid in pids {
                    if Task.isCancelled { break }
                    guard let def = PIDTable.def(for: pid) else { continue }
                    guard let bytes = try? await elm.payload(mode: 0x01, pid: pid, timeout: 2),
                          let reading = def.decode(bytes) else { continue }

                    await MainActor.run {
                        self.applyLive(def: def, reading: reading)
                    }
                }

                let now = Date()
                sampleTimes.append(now)
                sampleTimes.removeAll { now.timeIntervalSince($0) > 5 }
                let rate = Double(sampleTimes.count) / 5.0
                await MainActor.run { self.samplesPerSecond = rate }

                if interval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
    }

    private func applyLive(def: PIDDef, reading: PIDReading) {
        let now = Date()
        if let idx = liveValues.firstIndex(where: { $0.pid == def.pid }) {
            liveValues[idx].display = reading.display
            liveValues[idx].value = reading.value
            liveValues[idx].updated = now
        } else {
            liveValues.append(LiveValue(pid: def.pid, name: def.name, category: def.category,
                                        display: reading.display, value: reading.value,
                                        updated: now))
            liveValues.sort { $0.pid < $1.pid }
        }

        if let v = reading.value {
            var points = history[def.pid] ?? []
            points.append(ChartPoint(time: now, value: v))
            if points.count > historyLimit { points.removeFirst(points.count - historyLimit) }
            history[def.pid] = points
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        samplesPerSecond = 0
        if state == .monitoring { state = .connected }
    }

    /// Данные графика в виде CSV — для выгрузки.
    func historyCSV() -> String {
        var rows = ["timestamp,pid,parameter,value"]
        let fmt = ISO8601DateFormatter()
        for (pid, points) in history.sorted(by: { $0.key < $1.key }) {
            let name = PIDTable.def(for: pid)?.name ?? String(format: "PID %02X", pid)
            for p in points {
                rows.append("\(fmt.string(from: p.time)),\(String(format: "%02X", pid)),\"\(name)\",\(p.value)")
            }
        }
        return rows.joined(separator: "\n")
    }
}
