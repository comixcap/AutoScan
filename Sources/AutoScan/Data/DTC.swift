import Foundation

enum DTCSeverity: Int, Comparable {
    case info = 0, warning = 1, serious = 2, critical = 3

    static func < (a: DTCSeverity, b: DTCSeverity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .info:     return Loc.t("Информация", "Info")
        case .warning:  return Loc.t("Обратить внимание", "Worth checking")
        case .serious:  return Loc.t("Серьёзно", "Serious")
        case .critical: return Loc.t("Критично", "Critical")
        }
    }
}

/// Откуда получен код.
enum DTCKind {
    case stored      // Mode 03 — подтверждённые, Check горит
    case pending     // Mode 07 — замечены в текущем цикле, ещё не подтверждены
    case permanent   // Mode 0A — нельзя стереть сканером, гаснут сами

    var title: String {
        switch self {
        case .stored:    return Loc.t("Подтверждённые", "Confirmed")
        case .pending:   return Loc.t("Ожидающие", "Pending")
        case .permanent: return Loc.t("Постоянные", "Permanent")
        }
    }

    var explanation: String {
        switch self {
        case .stored:
            return Loc.t("Неисправность подтверждена, обычно горит Check.",
                         "Fault confirmed, usually the Check Engine light is on.")
        case .pending:
            return Loc.t("Замечено в текущем цикле. Если повторится — станет подтверждённой.",
                         "Seen in the current drive cycle. Will confirm if it repeats.")
        case .permanent:
            return Loc.t("Не стирается сканером — гаснет сама после нескольких исправных поездок. "
                         + "Наличие таких кодов при пустой памяти означает, что ошибки стирали недавно.",
                         "Cannot be cleared by a scanner — clears itself after several good drive cycles. "
                         + "Present while stored memory is empty means codes were cleared recently.")
        }
    }
}

struct DTCInfo: Identifiable, Hashable {
    let code: String
    let title: String
    let explanation: String
    let severity: DTCSeverity
    let kind: DTCKind

    var id: String { code + String(describing: kind) }

    static func == (a: DTCInfo, b: DTCInfo) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Расшифровка байтов в код

enum DTCDecoder {

    /// Два байта -> строка вида "P0301". Возвращает nil для пустого кода (0x0000).
    static func code(from hi: UInt8, _ lo: UInt8) -> String? {
        if hi == 0 && lo == 0 { return nil }
        let letters: [Character] = ["P", "C", "B", "U"]
        let letter = letters[Int((hi >> 6) & 0x03)]
        let d1 = (hi >> 4) & 0x03
        let d2 = hi & 0x0F
        let d3 = (lo >> 4) & 0x0F
        let d4 = lo & 0x0F
        return "\(letter)\(d1)\(hexDigit(d2))\(hexDigit(d3))\(hexDigit(d4))"
    }

    private static func hexDigit(_ v: UInt8) -> Character {
        Character(String(v, radix: 16, uppercase: true))
    }

    /// Разбирает полезную нагрузку ответа Mode 03/07/0A в список кодов.
    ///
    /// На CAN первый байт обычно содержит количество кодов, но не все блоки
    /// его присылают. Поэтому пробуем оба варианта и выбираем осмысленный.
    static func codes(fromPayload payload: [UInt8]) -> [String] {
        func parse(_ bytes: [UInt8]) -> [String] {
            var out: [String] = []
            var i = 0
            while i + 1 < bytes.count {
                if let c = code(from: bytes[i], bytes[i + 1]) { out.append(c) }
                i += 2
            }
            return out
        }

        guard !payload.isEmpty else { return [] }

        // Вариант «первый байт — счётчик»
        let count = Int(payload[0])
        let rest = Array(payload.dropFirst())
        let withCounter = parse(rest)
        if count > 0, count <= 16, withCounter.count >= min(count, 1),
           rest.count >= count * 2 {
            return Array(withCounter.prefix(count))
        }
        if count == 0 { return [] }

        // Вариант «сразу коды»
        let direct = parse(payload)
        return direct.isEmpty ? withCounter : direct
    }

    // MARK: - Описание кода

    static func info(for code: String, kind: DTCKind) -> DTCInfo {
        if let e = DTCDatabase.entries[code] {
            return DTCInfo(code: code,
                           title: Loc.t(e.ru, e.en),
                           explanation: Loc.t(e.ruWhy, e.enWhy),
                           severity: e.severity,
                           kind: kind)
        }
        let g = structural(code)
        return DTCInfo(code: code, title: g.title, explanation: g.explanation,
                       severity: g.severity, kind: kind)
    }

    /// Осмысленное описание для кода, которого нет в таблице —
    /// по структуре самого кода (SAE J2012).
    private static func structural(_ code: String) -> (title: String, explanation: String,
                                                       severity: DTCSeverity) {
        guard code.count >= 3 else {
            return (code, Loc.t("Неизвестный код.", "Unknown code."), .warning)
        }
        let chars = Array(code)
        let system = chars[0]
        let isGeneric = chars[1] == "0" || chars[1] == "2"
        let group = chars[2]

        let systemName: String
        let systemSeverity: DTCSeverity
        switch system {
        case "P": systemName = Loc.t("двигатель и трансмиссия", "powertrain"); systemSeverity = .serious
        case "C": systemName = Loc.t("шасси (тормоза, ABS, подвеска)", "chassis (brakes, ABS, suspension)"); systemSeverity = .serious
        case "B": systemName = Loc.t("кузовная электроника", "body electronics"); systemSeverity = .warning
        case "U": systemName = Loc.t("сеть и связь между блоками", "network / module communication"); systemSeverity = .warning
        default:  systemName = Loc.t("неизвестная система", "unknown system"); systemSeverity = .warning
        }

        var groupName = ""
        if system == "P" {
            switch group {
            case "1": groupName = Loc.t("подача топлива и воздуха", "fuel and air metering")
            case "2": groupName = Loc.t("топливные форсунки", "fuel injector circuit")
            case "3": groupName = Loc.t("зажигание или пропуски воспламенения", "ignition or misfire")
            case "4": groupName = Loc.t("система снижения выбросов", "emission controls")
            case "5": groupName = Loc.t("холостой ход и управление скоростью", "idle and speed control")
            case "6": groupName = Loc.t("выходные цепи блока управления", "ECU output circuits")
            case "7", "8": groupName = Loc.t("коробка передач", "transmission")
            case "9": groupName = Loc.t("коробка передач и её электроника", "transmission electronics")
            case "A", "B", "C": groupName = Loc.t("гибридная установка", "hybrid propulsion")
            default: break
            }
        }

        let origin = isGeneric
            ? Loc.t("Общий код стандарта OBD-II.", "Generic OBD-II code.")
            : Loc.t("Код производителя — точное значение зависит от марки.",
                    "Manufacturer-specific code — exact meaning depends on the brand.")

        var title = Loc.t("Ошибка: \(systemName)", "Fault: \(systemName)")
        if !groupName.isEmpty {
            title = Loc.t("Ошибка: \(groupName)", "Fault: \(groupName)")
        }

        let explanation = origin + " " + Loc.t(
            "Точного описания этого кода нет в базе. Область — \(systemName)"
            + (groupName.isEmpty ? "" : ", раздел: \(groupName)")
            + ". Расшифровку под конкретную марку смотрите в сервисной документации.",
            "No exact description for this code in the database. Area — \(systemName)"
            + (groupName.isEmpty ? "" : ", section: \(groupName)")
            + ". Check brand service documentation for the precise meaning.")

        return (title, explanation, isGeneric ? systemSeverity : .warning)
    }
}
