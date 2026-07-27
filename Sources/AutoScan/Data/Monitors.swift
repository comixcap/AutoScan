import Foundation

// MARK: - Готовность мониторов (Mode 01 PID 01 / PID 41)

struct MonitorState: Identifiable {
    let name: String
    let supported: Bool
    let complete: Bool
    var id: String { name }
}

struct ReadinessReport {
    var milOn: Bool = false
    var dtcCount: Int = 0
    var compressionIgnition: Bool = false      // дизель
    var monitors: [MonitorState] = []

    var supportedMonitors: [MonitorState] { monitors.filter(\.supported) }
    var incomplete: [MonitorState] { supportedMonitors.filter { !$0.complete } }
    var allComplete: Bool { incomplete.isEmpty && !supportedMonitors.isEmpty }

    /// Разбор 4 байт статуса.
    static func parse(_ d: [UInt8]) -> ReadinessReport? {
        guard d.count >= 4 else { return nil }
        var r = ReadinessReport()
        r.milOn = (d[0] & 0x80) != 0
        r.dtcCount = Int(d[0] & 0x7F)

        let b = d[1], c = d[2], e = d[3]
        r.compressionIgnition = (b & 0x08) != 0

        // Непрерывные мониторы
        r.monitors.append(MonitorState(name: Loc.t("Пропуски воспламенения", "Misfire"),
                                       supported: (b & 0x01) != 0, complete: (b & 0x10) == 0))
        r.monitors.append(MonitorState(name: Loc.t("Топливная система", "Fuel system"),
                                       supported: (b & 0x02) != 0, complete: (b & 0x20) == 0))
        r.monitors.append(MonitorState(name: Loc.t("Компоненты", "Components"),
                                       supported: (b & 0x04) != 0, complete: (b & 0x40) == 0))

        // Периодические мониторы: набор зависит от типа двигателя
        let names: [(String, String)]
        if r.compressionIgnition {
            names = [("Катализатор NMHC", "NMHC catalyst"),
                     ("Система NOx / SCR", "NOx / SCR system"),
                     ("—", "—"),
                     ("Давление наддува", "Boost pressure"),
                     ("—", "—"),
                     ("Датчик отработавших газов", "Exhaust gas sensor"),
                     ("Сажевый фильтр", "PM filter"),
                     ("EGR / VVT", "EGR / VVT")]
        } else {
            names = [("Катализатор", "Catalyst"),
                     ("Прогрев катализатора", "Heated catalyst"),
                     ("Система паров топлива", "Evaporative system"),
                     ("Вторичный воздух", "Secondary air system"),
                     ("—", "—"),
                     ("Кислородные датчики", "Oxygen sensors"),
                     ("Подогрев кислородных датчиков", "Oxygen sensor heater"),
                     ("Система EGR", "EGR system")]
        }

        for bit in 0..<8 {
            let (ru, en) = names[bit]
            if ru == "—" { continue }
            let supported = (c & (1 << UInt8(bit))) != 0
            let incomplete = (e & (1 << UInt8(bit))) != 0
            r.monitors.append(MonitorState(name: Loc.t(ru, en),
                                           supported: supported, complete: !incomplete))
        }
        return r
    }
}

// MARK: - Результаты бортовых тестов (Mode 06)

struct MonitorTest: Identifiable {
    let mid: UInt8
    let tid: UInt8
    let name: String
    let value: Int
    let minLimit: Int
    let maxLimit: Int

    var id: String { String(format: "%02X-%02X", mid, tid) }
    var passed: Bool { value >= minLimit && value <= maxLimit }

    /// Счётчик пропусков воспламенения по цилиндру (MID 0x01…0x0A).
    var misfireCylinder: Int? {
        (mid >= 0x01 && mid <= 0x0A) ? Int(mid) : nil
    }

    enum Outcome { case pass, fail, counter }

    /// Для счётчиков пропусков «допуск» блока бессмысленен — важна сама величина.
    var outcome: Outcome {
        if misfireCylinder != nil { return .counter }
        return passed ? .pass : .fail
    }

    /// Текстовая оценка для отчёта.
    var outcomeText: String {
        switch outcome {
        case .pass: return Loc.t("в допуске", "in range")
        case .fail: return Loc.t("ВНЕ ДОПУСКА", "OUT OF RANGE")
        case .counter:
            if value >= 20 { return Loc.t("много", "high") }
            if value >= 5 { return Loc.t("заметно", "noticeable") }
            if value > 0 { return Loc.t("единично", "few") }
            return Loc.t("нет", "none")
        }
    }

    /// Насколько это тревожно (для окраски в интерфейсе).
    var isConcerning: Bool {
        switch outcome {
        case .pass: return false
        case .fail: return true
        case .counter: return value >= 5
        }
    }

    static func name(mid: UInt8) -> String {
        switch mid {
        case 0x01...0x0A:
            return Loc.t("Пропуски воспламенения, цилиндр \(mid)",
                         "Misfire, cylinder \(mid)")
        case 0x21...0x24:
            return Loc.t("Кислородный датчик B1S\(mid - 0x20)",
                         "Oxygen sensor B1S\(mid - 0x20)")
        case 0x25...0x28:
            return Loc.t("Кислородный датчик B2S\(mid - 0x24)",
                         "Oxygen sensor B2S\(mid - 0x24)")
        case 0x31...0x34:
            return Loc.t("Подогрев лямбды B1S\(mid - 0x30)",
                         "O2 heater B1S\(mid - 0x30)")
        case 0x35...0x38:
            return Loc.t("Подогрев лямбды B2S\(mid - 0x34)",
                         "O2 heater B2S\(mid - 0x34)")
        case 0x41:
            return Loc.t("Катализатор, банк 1", "Catalyst, bank 1")
        case 0x42:
            return Loc.t("Катализатор, банк 2", "Catalyst, bank 2")
        default:
            return Loc.t("Тест MID 0x\(String(format: "%02X", mid))",
                         "Test MID 0x\(String(format: "%02X", mid))")
        }
    }

    /// Разбор ответа Mode 06 (может содержать несколько блоков по 9 байт после 0x46).
    static func parse(payloadAfter46 data: [UInt8]) -> [MonitorTest] {
        var out: [MonitorTest] = []
        var i = 0
        // формат записи: MID, TID, UASID, val(2), min(2), max(2)
        while i + 8 < data.count {
            let mid = data[i]
            let tid = data[i + 1]
            let val = Int(data[i + 3]) << 8 | Int(data[i + 4])
            let lo  = Int(data[i + 5]) << 8 | Int(data[i + 6])
            let hi  = Int(data[i + 7]) << 8 | Int(data[i + 8])
            if mid != 0 {
                out.append(MonitorTest(mid: mid, tid: tid, name: name(mid: mid),
                                       value: val, minLimit: lo, maxLimit: hi))
            }
            i += 9
        }
        return out
    }
}

// MARK: - Паспорт машины (Mode 09)

struct VehicleIdentity {
    var vin: String?
    var calibrationIDs: [String] = []
    var calibrationVerification: [String] = []
    var ecuName: String?

    var isEmpty: Bool {
        vin == nil && calibrationIDs.isEmpty && calibrationVerification.isEmpty && ecuName == nil
    }

    /// Год выпуска по 10-му знаку VIN (стандарт ISO 3779).
    var modelYearFromVIN: Int? {
        guard let vin, vin.count == 17 else { return nil }
        let ch = Array(vin)[9]
        let table: [Character: Int] = [
            "A": 1980, "B": 1981, "C": 1982, "D": 1983, "E": 1984, "F": 1985,
            "G": 1986, "H": 1987, "J": 1988, "K": 1989, "L": 1990, "M": 1991,
            "N": 1992, "P": 1993, "R": 1994, "S": 1995, "T": 1996, "V": 1997,
            "W": 1998, "X": 1999, "Y": 2000, "1": 2001, "2": 2002, "3": 2003,
            "4": 2004, "5": 2005, "6": 2006, "7": 2007, "8": 2008, "9": 2009
        ]
        guard var year = table[ch] else { return nil }
        // буквенный цикл повторяется через 30 лет
        if year < 2010 && ch.isLetter { year += 30 }
        return year
    }

    /// Контрольный разряд обязателен только для Северной Америки (WMI начинается с 1–5).
    /// Для корейских, японских и европейских VIN несовпадение — норма, а не признак подделки.
    var vinChecksumIsMandatory: Bool {
        guard let vin, let first = vin.first else { return false }
        return "12345".contains(first)
    }

    /// Проверка контрольного разряда VIN (для североамериканских VIN).
    var vinChecksumValid: Bool? {
        guard let vin, vin.count == 17 else { return nil }
        let transliteration: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (i, ch) in vin.enumerated() {
            let v: Int
            if let digit = ch.wholeNumberValue, ch.isNumber { v = digit }
            else if let t = transliteration[ch] { v = t }
            else { return nil }
            sum += v * weights[i]
        }
        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return Array(vin)[8] == expected
    }
}

// MARK: - Стоп-кадр (Mode 02)

struct FreezeFrameEntry: Identifiable {
    let pid: UInt8
    let name: String
    let display: String
    var id: UInt8 { pid }
}

struct FreezeFrame {
    var triggerCode: String?
    var entries: [FreezeFrameEntry] = []
    var isEmpty: Bool { triggerCode == nil && entries.isEmpty }
}
