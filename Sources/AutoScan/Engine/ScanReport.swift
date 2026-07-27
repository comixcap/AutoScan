import Foundation

struct PIDResult: Identifiable {
    let pid: UInt8
    let name: String
    let category: PIDCategory
    let display: String
    let value: Double?
    let rawBytes: [UInt8]
    /// Оценка относительно нормы — заполняется после того, как известны
    /// условия замера (прогрет ли двигатель, работает ли он вообще).
    var assessment: NormAssessment?
    var id: UInt8 { pid }

    var rawHex: String { rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    /// Пояснение простыми словами, что это за параметр.
    var about: String? { ParameterGuide.about(pid: pid) }
    var isDeviation: Bool { assessment?.status.isDeviation ?? false }
}

/// Что именно приложение выяснило о машине.
struct ScanReport {
    var startedAt = Date()
    var finishedAt: Date?

    var adapter: AdapterInfo?
    var channel: String = "—"

    var identity = VehicleIdentity()
    /// Разбор VIN без интернета.
    var vinDetails: VINDetails?
    /// Уточнение по открытой базе NHTSA — заполняется по кнопке, нужен интернет.
    var nhtsa: NHTSAInfo?
    /// Счётчики наработки — не стираются сбросом ошибок.
    var performance: PerformanceTracking?
    var readiness: ReadinessReport?
    var storedDTCs: [DTCInfo] = []
    var pendingDTCs: [DTCInfo] = []
    var permanentDTCs: [DTCInfo] = []
    var freezeFrame = FreezeFrame()
    var monitorTests: [MonitorTest] = []
    var readings: [PIDResult] = []
    var supportedPIDs: [UInt8] = []
    var batteryVoltage: Double?

    /// Что не удалось прочитать и почему — честно показываем в отчёте.
    var notes: [String] = []
    var trafficLog: [String] = []

    var allDTCs: [DTCInfo] { storedDTCs + pendingDTCs + permanentDTCs }

    /// Параметры, вышедшие за пределы нормы.
    var deviations: [PIDResult] { readings.filter(\.isDeviation) }

    func reading(pid: UInt8) -> PIDResult? { readings.first { $0.pid == pid } }
    func value(pid: UInt8) -> Double? { reading(pid: pid)?.value }

    var engineRunning: Bool {
        if let rpm = value(pid: 0x0C) { return rpm > 300 }
        return false
    }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

// MARK: - Выводы

enum FindingLevel: Int, Comparable {
    case good = 0, neutral = 1, attention = 2, alarm = 3

    static func < (a: FindingLevel, b: FindingLevel) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .good:      return Loc.t("Хорошо", "Good")
        case .neutral:   return Loc.t("Факт", "Note")
        case .attention: return Loc.t("Внимание", "Attention")
        case .alarm:     return Loc.t("Тревога", "Alarm")
        }
    }

    var symbol: String {
        switch self {
        case .good:      return "checkmark.circle.fill"
        case .neutral:   return "info.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .alarm:     return "xmark.octagon.fill"
        }
    }
}

struct Finding: Identifiable {
    let id = UUID()
    let level: FindingLevel
    let title: String
    let detail: String
    /// Что с этим делать — понятным языком.
    let advice: String?
}

enum Verdict {

    /// Главная логика интерпретации: превращает сырые данные в понятные выводы.
    static func build(from r: ScanReport) -> [Finding] {
        var f: [Finding] = []

        // --- Check Engine и коды ---
        let milOn = r.readiness?.milOn ?? false
        if milOn {
            f.append(Finding(
                level: .alarm,
                title: Loc.t("Горит Check Engine", "Check Engine light is on"),
                detail: Loc.t("Блок управления зафиксировал подтверждённую неисправность.",
                              "The ECU has a confirmed fault stored."),
                advice: Loc.t("Смотрите список подтверждённых ошибок ниже — там причина.",
                              "See the confirmed fault list below for the cause.")))
        }

        if r.storedDTCs.isEmpty && r.pendingDTCs.isEmpty && !milOn {
            f.append(Finding(
                level: .good,
                title: Loc.t("Активных ошибок двигателя нет", "No active engine faults"),
                detail: Loc.t("Память подтверждённых и ожидающих ошибок пуста.",
                              "Confirmed and pending fault memory is empty."),
                advice: nil))
        }

        for dtc in r.storedDTCs {
            f.append(Finding(
                level: dtc.severity >= .serious ? .alarm : .attention,
                title: "\(dtc.code) — \(dtc.title)",
                detail: dtc.explanation,
                advice: Loc.t("Тип: подтверждённая ошибка. \(DTCKind.stored.explanation)",
                              "Type: confirmed. \(DTCKind.stored.explanation)")))
        }

        for dtc in r.pendingDTCs where !r.storedDTCs.contains(where: { $0.code == dtc.code }) {
            f.append(Finding(
                level: .attention,
                title: "\(dtc.code) — \(dtc.title)",
                detail: dtc.explanation,
                advice: DTCKind.pending.explanation))
        }

        // --- Признаки того, что ошибки стёрли перед показом ---
        f.append(contentsOf: clearedRecentlyFindings(r))

        // --- Пропуски воспламенения ---
        let misfires = r.monitorTests.compactMap { t -> (Int, Int)? in
            guard let cyl = t.misfireCylinder, t.value > 0 else { return nil }
            return (cyl, t.value)
        }
        if !misfires.isEmpty {
            let worst = misfires.map(\.1).max() ?? 0
            let list = misfires.sorted { $0.1 > $1.1 }
                .map { Loc.t("цилиндр \($0.0): \($0.1)", "cyl \($0.0): \($0.1)") }
                .joined(separator: ", ")
            f.append(Finding(
                level: worst >= 20 ? .alarm : (worst >= 5 ? .attention : .neutral),
                title: Loc.t("Счётчики пропусков воспламенения", "Misfire counters"),
                detail: list,
                advice: worst >= 5
                    ? Loc.t("Пропуски в одном цилиндре проверяют по цепочке: свеча → катушка → форсунка → компрессия. Разброс по всем цилиндрам говорит об общей причине (топливо, подсос, зажигание).",
                            "For a single cylinder check in order: spark plug → coil → injector → compression. Misfires spread across all cylinders point to a shared cause (fuel, air leak, ignition).")
                    : Loc.t("Единичные пропуски в пределах нормы.", "A few counts are normal.")))
        }

        // --- Топливные коррекции ---
        f.append(contentsOf: fuelTrimFindings(r))

        // --- Температура двигателя ---
        if let ect = r.value(pid: 0x05) {
            if ect > 105 {
                f.append(Finding(
                    level: .alarm,
                    title: Loc.t("Высокая температура двигателя", "High engine temperature"),
                    detail: Loc.t("Охлаждающая жидкость: \(Int(ect)) °C.",
                                  "Coolant: \(Int(ect)) °C."),
                    advice: Loc.t("Заглушить и разбираться: термостат, вентилятор, помпа, уровень ОЖ.",
                                  "Shut down and investigate: thermostat, fan, water pump, coolant level.")))
            } else if r.engineRunning && ect < 70 {
                f.append(Finding(
                    level: .neutral,
                    title: Loc.t("Двигатель не прогрет", "Engine not warmed up"),
                    detail: Loc.t("Охлаждающая жидкость: \(Int(ect)) °C. Часть параметров ещё не показательна.",
                                  "Coolant: \(Int(ect)) °C. Some readings are not meaningful yet."),
                    advice: Loc.t("Для честной картины прогрейте мотор до рабочей температуры и повторите проверку.",
                                  "For a fair picture warm the engine to operating temperature and scan again.")))
            }
        }

        // --- Напряжение бортсети ---
        if let v = r.batteryVoltage ?? r.value(pid: 0x42) {
            if r.engineRunning {
                if v < 13.0 {
                    f.append(Finding(
                        level: .attention,
                        title: Loc.t("Низкое напряжение при работающем двигателе", "Low charging voltage"),
                        detail: String(format: "%.2f %@", v, Loc.t("В", "V")),
                        advice: Loc.t("На заведённой машине норма 13.5–14.8 В. Ниже — генератор, ремень или реле-регулятор.",
                                      "With the engine running 13.5–14.8 V is normal. Below that: alternator, belt or regulator.")))
                } else if v > 15.0 {
                    f.append(Finding(
                        level: .attention,
                        title: Loc.t("Перезаряд", "Overcharging"),
                        detail: String(format: "%.2f %@", v, Loc.t("В", "V")),
                        advice: Loc.t("Неисправен реле-регулятор. Опасно для электроники.",
                                      "Faulty voltage regulator. Harmful to electronics.")))
                } else {
                    f.append(Finding(
                        level: .good,
                        title: Loc.t("Зарядка в норме", "Charging system OK"),
                        detail: String(format: "%.2f %@", v, Loc.t("В", "V")), advice: nil))
                }
            } else if v < 12.0 {
                f.append(Finding(
                    level: .attention,
                    title: Loc.t("Низкое напряжение аккумулятора", "Low battery voltage"),
                    detail: String(format: "%.2f %@", v, Loc.t("В", "V")),
                    advice: Loc.t("На заглушенной машине норма 12.4–12.7 В. Ниже 12.0 — аккумулятор разряжен или изношен.",
                                  "With the engine off 12.4–12.7 V is normal. Below 12.0 the battery is flat or worn.")))
            }
        }

        // --- Пробег с горящим Check ---
        if let dist = r.value(pid: 0x21), dist > 0 {
            f.append(Finding(
                level: dist > 100 ? .attention : .neutral,
                title: Loc.t("Ездили с горящим Check", "Driven with the Check light on"),
                detail: Loc.t("\(Int(dist)) км с активной неисправностью.",
                              "\(Int(dist)) km with an active fault."),
                advice: Loc.t("Долгая езда с ошибкой часто означает, что проблему игнорировали.",
                              "Long distances with a fault usually means the problem was ignored.")))
        }

        // --- Счётчики наработки ---
        if let p = r.performance, let cycles = p.ignitionCycles, cycles > 0 {
            var detail = Loc.t("Запусков двигателя за всю жизнь: \(cycles)",
                               "Engine starts over the vehicle's life: \(cycles)")
            var advice = Loc.t("Этот счётчик не стирается сканером и не связан с одометром — им нельзя управлять при скрутке пробега. Прикиньте: пробег из объявления, делённый на число запусков, даёт среднюю длину поездки. Если получается неправдоподобно много (больше 60–70 км на запуск для городской машины) — пробег, скорее всего, скручен.",
                               "This counter cannot be cleared with a scanner and is independent of the odometer — it is not touched when mileage is rolled back. Divide the advertised mileage by the number of starts to get the average trip length. An implausibly high figure (over 60–70 km per start for a city car) suggests the odometer was wound back.")

            if let odo = r.value(pid: 0xA6), let avg = p.averageTripDistance(odometerKm: odo) {
                detail += Loc.t(" · одометр \(Int(odo)) км · в среднем \(String(format: "%.1f", avg)) км на поездку",
                                " · odometer \(Int(odo)) km · average \(String(format: "%.1f", avg)) km per trip")
                if avg < 5 {
                    advice = Loc.t("Средняя поездка меньше 5 км — машина ходила почти исключительно короткими маршрутами. Это самый тяжёлый режим для двигателя: масло не прогревается, копится нагар, страдают катализатор и аккумулятор. Смотрите на состояние внимательнее, чем на цифру пробега.",
                                   "The average trip is under 5 km — the car was used almost entirely for short runs. That is the hardest regime for an engine: oil never warms up, carbon builds up, the catalyst and battery suffer. Judge condition rather than the mileage figure.")
                }
            }

            f.append(Finding(level: .neutral,
                             title: Loc.t("Счётчики наработки", "In-use performance counters"),
                             detail: detail, advice: advice))
        }

        // --- Стоп-кадр ---
        if let trigger = r.freezeFrame.triggerCode {
            f.append(Finding(
                level: .neutral,
                title: Loc.t("Есть стоп-кадр неисправности", "Freeze frame data present"),
                detail: Loc.t("Сохранены условия в момент ошибки \(trigger).",
                              "Conditions recorded when \(trigger) occurred."),
                advice: Loc.t("Стоп-кадр — лучшая улика по плавающей неисправности. Не стирайте ошибки, пока не разобрались.",
                              "A freeze frame is the best evidence for an intermittent fault. Don't clear codes before you understand it.")))
        }

        // --- VIN ---
        if let vin = r.identity.vin {
            var detail = "VIN: \(vin)"
            if let year = r.identity.modelYearFromVIN {
                detail += Loc.t(" · модельный год \(year)", " · model year \(year)")
            }
            var level = FindingLevel.neutral
            var advice: String? = nil
            if r.identity.vinChecksumValid == false && r.identity.vinChecksumIsMandatory {
                level = .attention
                advice = Loc.t("Контрольный разряд VIN не сходится, а для североамериканского VIN он обязателен. Это либо ошибка чтения, либо несоответствие — сверьте VIN с табличкой на кузове и документами.",
                               "The VIN check digit does not match, and it is mandatory for a North American VIN. Either a read error or a mismatch — compare the VIN with the body plate and the papers.")
            }
            if !r.identity.vinChecksumIsMandatory {
                advice = Loc.t("Контрольный разряд проверяется только для VIN североамериканского рынка; у корейских, японских и европейских машин его несовпадение — норма.",
                               "The check digit is only validated for North American VINs; for Korean, Japanese and European cars a mismatch is normal.")
            }
            f.append(Finding(level: level,
                             title: Loc.t("Идентификация", "Vehicle identity"),
                             detail: detail, advice: advice))
        } else {
            f.append(Finding(
                level: .neutral,
                title: Loc.t("VIN не читается", "VIN not available"),
                detail: Loc.t("Блок не отдаёт VIN по стандартному запросу.",
                              "The ECU does not report a VIN over the standard request."),
                advice: Loc.t("Нормально для машин до ~2008 года и части азиатского рынка.",
                              "Normal for pre-2008 cars and some Asian-market vehicles.")))
        }

        return f.sorted { $0.level > $1.level }
    }

    // MARK: Признаки недавнего сброса ошибок

    private static func clearedRecentlyFindings(_ r: ScanReport) -> [Finding] {
        var out: [Finding] = []

        let distance = r.value(pid: 0x31)      // км с момента сброса
        let minutes  = r.value(pid: 0x4E)      // минуты с момента сброса
        let warmups  = r.value(pid: 0x30)      // прогревов с момента сброса
        let incompleteCount = r.readiness?.incomplete.count ?? 0

        var clues: [String] = []
        var suspicious = false

        if let d = distance {
            if d < 100 {
                suspicious = true
                clues.append(Loc.t("пробег с момента сброса: \(Int(d)) км", "distance since clear: \(Int(d)) km"))
            } else {
                clues.append(Loc.t("пробег с момента сброса: \(Int(d)) км", "distance since clear: \(Int(d)) km"))
            }
        }
        if let m = minutes {
            if m < 120 {
                suspicious = true
                clues.append(Loc.t("времени с момента сброса: \(formatDuration(seconds: Int(m) * 60))",
                                   "time since clear: \(formatDuration(seconds: Int(m) * 60))"))
            } else {
                clues.append(Loc.t("времени с момента сброса: \(formatDuration(seconds: Int(m) * 60))",
                                   "time since clear: \(formatDuration(seconds: Int(m) * 60))"))
            }
        }
        if let w = warmups, w < 5 {
            suspicious = true
            clues.append(Loc.t("прогревов с момента сброса: \(Int(w))", "warm-ups since clear: \(Int(w))"))
        }

        if incompleteCount >= 2 {
            clues.append(Loc.t("не завершено мониторов: \(incompleteCount)",
                               "incomplete monitors: \(incompleteCount)"))
        }

        let permanentWithoutStored = !r.permanentDTCs.isEmpty && r.storedDTCs.isEmpty

        if suspicious && incompleteCount >= 2 {
            out.append(Finding(
                level: .alarm,
                title: Loc.t("Ошибки стёрли незадолго до проверки", "Fault memory was cleared shortly before this scan"),
                detail: clues.joined(separator: ", "),
                advice: Loc.t("Это главный признак предпродажной подготовки: память очистили, и неисправности ещё не успели проявиться заново. Проедьте на машине 30–50 км и просканируйте повторно — либо считайте, что реальное состояние двигателя вы не видели.",
                              "This is the classic pre-sale trick: memory was wiped and faults have not had time to reappear. Drive 30–50 km and rescan — otherwise assume you have not seen the engine's real condition.")))
        } else if incompleteCount >= 2 {
            out.append(Finding(
                level: .attention,
                title: Loc.t("Мониторы готовности не завершены", "Readiness monitors incomplete"),
                detail: Loc.t("Не завершено: \(r.readiness?.incomplete.map(\.name).joined(separator: ", ") ?? "—")",
                              "Incomplete: \(r.readiness?.incomplete.map(\.name).joined(separator: ", ") ?? "—")"),
                advice: Loc.t("Мониторы обнуляются при сбросе ошибок и при снятии клеммы аккумулятора. Пока они не завершены, скрытые неисправности не видны, и техосмотр по выхлопу не пройти.",
                              "Monitors reset when codes are cleared or the battery is disconnected. Until they complete, hidden faults stay invisible and an emissions test cannot be passed.")))
        } else if let r0 = r.readiness, r0.allComplete {
            out.append(Finding(
                level: .good,
                title: Loc.t("Все мониторы готовности пройдены", "All readiness monitors complete"),
                detail: Loc.t("Бортовая самодиагностика отработала полностью — память не сбрасывали недавно.",
                              "On-board self-diagnostics have fully run — memory was not cleared recently."),
                advice: nil))
        }

        if permanentWithoutStored {
            out.append(Finding(
                level: .alarm,
                title: Loc.t("Постоянные коды при пустой памяти ошибок", "Permanent codes with empty fault memory"),
                detail: r.permanentDTCs.map(\.code).joined(separator: ", "),
                advice: Loc.t("Постоянные коды нельзя стереть сканером — они гаснут сами только после нескольких исправных поездок. Их наличие при пустой основной памяти прямо доказывает, что ошибки стирали, а неисправность была реальной.",
                              "Permanent codes cannot be cleared with a scanner — they only clear themselves after several good drive cycles. Their presence alongside empty stored memory is direct proof that codes were cleared and the fault was real.")))
        }

        return out
    }

    // MARK: Топливные коррекции

    private static func fuelTrimFindings(_ r: ScanReport) -> [Finding] {
        var out: [Finding] = []
        let banks: [(String, UInt8, UInt8)] = [
            (Loc.t("банк 1", "bank 1"), 0x06, 0x07),
            (Loc.t("банк 2", "bank 2"), 0x08, 0x09)
        ]

        for (name, shortPID, longPID) in banks {
            let short = r.value(pid: shortPID)
            let long = r.value(pid: longPID)
            guard short != nil || long != nil else { continue }

            let total = (short ?? 0) + (long ?? 0)
            var parts: [String] = []
            if let s = short { parts.append(String(format: "%@ %+.1f%%", Loc.t("краткая", "short"), s)) }
            if let l = long { parts.append(String(format: "%@ %+.1f%%", Loc.t("долгая", "long"), l)) }
            let detail = "\(name): " + parts.joined(separator: ", ")

            if abs(total) >= 25 {
                out.append(Finding(
                    level: .alarm,
                    title: Loc.t("Сильный уход топливной коррекции, \(name)",
                                 "Large fuel trim deviation, \(name)"),
                    detail: detail,
                    advice: total > 0
                        ? Loc.t("Блок сильно добавляет топливо — смесь бедная. Ищите подсос воздуха, грязный расходомер, слабый бензонасос или забитый фильтр.",
                                "The ECU is adding a lot of fuel — the mixture is lean. Look for an air leak, dirty MAF, weak fuel pump or clogged filter.")
                        : Loc.t("Блок сильно убавляет топливо — смесь богатая. Ищите льющие форсунки, высокое давление топлива, забитый воздушный фильтр.",
                                "The ECU is cutting fuel — the mixture is rich. Look for leaking injectors, high fuel pressure, clogged air filter.")))
            } else if abs(total) >= 10 {
                out.append(Finding(
                    level: .attention,
                    title: Loc.t("Заметная топливная коррекция, \(name)",
                                 "Noticeable fuel trim, \(name)"),
                    detail: detail,
                    advice: Loc.t("Отклонение более 10% — двигатель уже компенсирует какую-то проблему, хотя ошибки может ещё не быть.",
                                  "Over 10% means the engine is already compensating for something, even if no fault code has set yet.")))
            } else {
                out.append(Finding(
                    level: .good,
                    title: Loc.t("Топливная коррекция в норме, \(name)",
                                 "Fuel trim normal, \(name)"),
                    detail: detail, advice: nil))
            }
        }
        return out
    }

    /// Общая оценка одной строкой.
    static func summary(_ findings: [Finding]) -> (level: FindingLevel, text: String) {
        let worst = findings.map(\.level).max() ?? .neutral
        switch worst {
        case .alarm:
            return (.alarm, Loc.t("Есть серьёзные замечания — читайте список ниже",
                                  "Serious issues found — see the list below"))
        case .attention:
            return (.attention, Loc.t("Есть замечания, требующие проверки",
                                      "Some findings need attention"))
        default:
            return (.good, Loc.t("Явных проблем по двигателю не обнаружено",
                                 "No obvious engine problems found"))
        }
    }
}
