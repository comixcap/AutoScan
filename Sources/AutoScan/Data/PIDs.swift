import Foundation

enum PIDCategory: String, CaseIterable {
    case engine, fuel, air, temperature, oxygen, electrical, emissions, hybrid, other

    var ru: String {
        switch self {
        case .engine:      return "Двигатель"
        case .fuel:        return "Топливная система"
        case .air:         return "Впуск и воздух"
        case .temperature: return "Температуры"
        case .oxygen:      return "Кислородные датчики"
        case .electrical:  return "Электрика"
        case .emissions:   return "Экология"
        case .hybrid:      return "Гибрид"
        case .other:       return "Прочее"
        }
    }

    var en: String {
        switch self {
        case .engine:      return "Engine"
        case .fuel:        return "Fuel system"
        case .air:         return "Air intake"
        case .temperature: return "Temperatures"
        case .oxygen:      return "Oxygen sensors"
        case .electrical:  return "Electrical"
        case .emissions:   return "Emissions"
        case .hybrid:      return "Hybrid"
        case .other:       return "Other"
        }
    }

    var title: String { Loc.t(ru, en) }
}

/// Результат расшифровки одного параметра.
struct PIDReading {
    /// Числовое значение (для графиков). nil — если параметр текстовый.
    var value: Double?
    /// Готовая к показу строка.
    var display: String
}

struct PIDDef: Identifiable {
    let pid: UInt8
    let byteCount: Int
    let ru: String
    let en: String
    let unit: String
    let range: ClosedRange<Double>?
    let category: PIDCategory
    let decode: @Sendable ([UInt8]) -> PIDReading?

    var id: UInt8 { pid }
    var name: String { Loc.t(ru, en) }
    var code: String { String(format: "01%02X", pid) }

    /// Числовой параметр пригоден для графика.
    var isPlottable: Bool { range != nil }
}

// MARK: - Помощники расшифровки

private func num(_ v: Double, _ unit: String, digits: Int = 1) -> PIDReading {
    let s = digits == 0 ? String(format: "%.0f", v) : String(format: "%.\(digits)f", v)
    return PIDReading(value: v, display: unit.isEmpty ? s : "\(s) \(unit)")
}

private func text(_ s: String) -> PIDReading { PIDReading(value: nil, display: s) }

/// Процент коррекции: (A-128)*100/128
private func trimPercent(_ a: UInt8) -> Double { (Double(a) - 128) * 100 / 128 }

/// Процент 0..100 из байта: A*100/255
private func pct(_ a: UInt8) -> Double { Double(a) * 100 / 255 }

private let fuelSystemStatus: [UInt8: (String, String)] = [
    0x00: ("Не поддерживается", "Not supported"),
    0x01: ("Открытый контур — прогрев", "Open loop — warming up"),
    0x02: ("Замкнутый контур — по лямбде", "Closed loop — using O2"),
    0x04: ("Открытый контур — нагрузка/торможение", "Open loop — load or decel"),
    0x08: ("Открытый контур — неисправность", "Open loop — system fault"),
    0x10: ("Замкнутый контур с ошибкой лямбды", "Closed loop with O2 fault")
]

private let secondaryAirStatus: [UInt8: (String, String)] = [
    0x01: ("Наверх (перед катализатором)", "Upstream"),
    0x02: ("Вниз (в катализатор)", "Downstream of catalyst"),
    0x04: ("В атмосферу / отключён", "From outside or off"),
    0x08: ("Работает по диагностике", "Pump commanded on for diagnostics")
]

private let obdStandards: [UInt8: (String, String)] = [
    1: ("OBD-II (Калифорния ARB)", "OBD-II (CARB)"),
    2: ("OBD (федеральный EPA)", "OBD (EPA)"),
    3: ("OBD и OBD-II", "OBD and OBD-II"),
    4: ("OBD-I", "OBD-I"),
    5: ("Без бортовой диагностики", "Not OBD compliant"),
    6: ("EOBD (Европа)", "EOBD"),
    7: ("EOBD и OBD-II", "EOBD and OBD-II"),
    8: ("EOBD и OBD", "EOBD and OBD"),
    9: ("EOBD, OBD и OBD-II", "EOBD, OBD and OBD-II"),
    10: ("JOBD (Япония)", "JOBD"),
    11: ("JOBD и OBD-II", "JOBD and OBD-II"),
    12: ("JOBD и EOBD", "JOBD and EOBD"),
    13: ("JOBD, EOBD и OBD-II", "JOBD, EOBD and OBD-II"),
    17: ("EMD", "EMD"),
    18: ("EMD+", "EMD+"),
    19: ("HD OBD-C", "HD OBD-C"),
    20: ("HD OBD", "HD OBD"),
    21: ("WWH OBD", "WWH OBD"),
    23: ("HD EOBD-I", "HD EOBD-I"),
    28: ("OBDBr-1 (Бразилия)", "OBDBr-1"),
    33: ("Тяжёлый транспорт EURO IV B1", "HD EURO IV B1"),
    34: ("Тяжёлый транспорт EURO VI", "HD EURO VI")
]

private let fuelTypes: [UInt8: (String, String)] = [
    0: ("Не указан", "Not available"),
    1: ("Бензин", "Gasoline"),
    2: ("Метанол", "Methanol"),
    3: ("Этанол", "Ethanol"),
    4: ("Дизель", "Diesel"),
    5: ("СНГ (пропан)", "LPG"),
    6: ("СПГ (метан)", "CNG"),
    7: ("Пропан", "Propane"),
    8: ("Электро", "Electric"),
    9: ("Бензин + battery", "Bifuel gasoline"),
    10: ("Метанол гибрид", "Bifuel methanol"),
    11: ("Этанол гибрид", "Bifuel ethanol"),
    12: ("СНГ гибрид", "Bifuel LPG"),
    13: ("СПГ гибрид", "Bifuel CNG"),
    14: ("Пропан гибрид", "Bifuel propane"),
    15: ("Электро гибрид", "Bifuel electric"),
    17: ("Гибрид бензин", "Hybrid gasoline"),
    18: ("Гибрид этанол", "Hybrid ethanol"),
    19: ("Гибрид дизель", "Hybrid diesel"),
    20: ("Гибрид электро", "Hybrid electric"),
    23: ("Гибрид на регенерации", "Hybrid regenerative")
]

// MARK: - Таблица Mode 01

enum PIDTable {

    static let all: [PIDDef] = build()

    static func def(for pid: UInt8) -> PIDDef? { map[pid] }

    private static let map: [UInt8: PIDDef] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
    }()

    private static func build() -> [PIDDef] {
        var t: [PIDDef] = []

        func add(_ pid: UInt8, _ n: Int, _ ru: String, _ en: String, _ unit: String,
                 _ range: ClosedRange<Double>?, _ cat: PIDCategory,
                 _ decode: @escaping @Sendable ([UInt8]) -> PIDReading?) {
            t.append(PIDDef(pid: pid, byteCount: n, ru: ru, en: en, unit: unit,
                            range: range, category: cat, decode: decode))
        }

        add(0x03, 2, "Состояние топливной системы", "Fuel system status", "", nil, .fuel) { d in
            guard let a = d.first else { return nil }
            var parts: [String] = []
            for (i, byte) in d.prefix(2).enumerated() where byte != 0 {
                if let s = fuelSystemStatus[byte] {
                    parts.append("\(Loc.t("Блок", "Bank")) \(i + 1): \(Loc.t(s.0, s.1))")
                }
            }
            if parts.isEmpty, let s = fuelSystemStatus[a] { parts.append(Loc.t(s.0, s.1)) }
            return text(parts.isEmpty ? "—" : parts.joined(separator: " · "))
        }

        add(0x04, 1, "Расчётная нагрузка", "Calculated engine load", "%", 0...100, .engine) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x05, 1, "Температура ОЖ", "Engine coolant temp", "°C", -40...215, .temperature) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 40, "°C", digits: 0)
        }

        add(0x06, 1, "Краткая коррекция топлива, банк 1", "Short term fuel trim B1", "%", -100...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(trimPercent(a), "%")
        }
        add(0x07, 1, "Долгая коррекция топлива, банк 1", "Long term fuel trim B1", "%", -100...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(trimPercent(a), "%")
        }
        add(0x08, 1, "Краткая коррекция топлива, банк 2", "Short term fuel trim B2", "%", -100...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(trimPercent(a), "%")
        }
        add(0x09, 1, "Долгая коррекция топлива, банк 2", "Long term fuel trim B2", "%", -100...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(trimPercent(a), "%")
        }

        add(0x0A, 1, "Давление топлива", "Fuel pressure", "кПа", 0...765, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) * 3, Loc.t("кПа", "kPa"), digits: 0)
        }

        add(0x0B, 1, "Давление во впуске (MAP)", "Intake manifold pressure", "кПа", 0...255, .air) { d in
            guard let a = d.first else { return nil }
            return num(Double(a), Loc.t("кПа", "kPa"), digits: 0)
        }

        add(0x0C, 2, "Обороты двигателя", "Engine RPM", "об/мин", 0...8000, .engine) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 4, Loc.t("об/мин", "rpm"), digits: 0)
        }

        add(0x0D, 1, "Скорость", "Vehicle speed", "км/ч", 0...255, .engine) { d in
            guard let a = d.first else { return nil }
            return num(Double(a), Loc.t("км/ч", "km/h"), digits: 0)
        }

        add(0x0E, 1, "Угол опережения зажигания", "Timing advance", "°", -64...64, .engine) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) / 2 - 64, "°")
        }

        add(0x0F, 1, "Температура впускного воздуха", "Intake air temp", "°C", -40...215, .temperature) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 40, "°C", digits: 0)
        }

        add(0x10, 2, "Массовый расход воздуха (MAF)", "Mass air flow", "г/с", 0...655, .air) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 100, Loc.t("г/с", "g/s"), digits: 2)
        }

        add(0x11, 1, "Положение дроссельной заслонки", "Throttle position", "%", 0...100, .air) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x12, 1, "Система вторичного воздуха", "Secondary air status", "", nil, .emissions) { d in
            guard let a = d.first, let s = secondaryAirStatus[a] else { return text("—") }
            return text(Loc.t(s.0, s.1))
        }

        add(0x1C, 1, "Стандарт диагностики", "OBD standard", "", nil, .other) { d in
            guard let a = d.first else { return nil }
            if let s = obdStandards[a] { return text(Loc.t(s.0, s.1)) }
            return text("#\(a)")
        }

        add(0x1F, 2, "Время работы двигателя", "Run time since start", "с", 0...65535, .engine) { d in
            guard d.count >= 2 else { return nil }
            let sec = Double(d[0]) * 256 + Double(d[1])
            return PIDReading(value: sec, display: formatDuration(seconds: Int(sec)))
        }

        add(0x21, 2, "Пробег с горящим Check", "Distance with MIL on", "км", 0...65535, .emissions) { d in
            guard d.count >= 2 else { return nil }
            return num(Double(d[0]) * 256 + Double(d[1]), Loc.t("км", "km"), digits: 0)
        }

        add(0x22, 2, "Давление в топливной рампе (отн.)", "Fuel rail pressure (rel)", "кПа", 0...5178, .fuel) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) * 0.079, Loc.t("кПа", "kPa"), digits: 0)
        }

        add(0x23, 2, "Давление в топливной рампе", "Fuel rail gauge pressure", "кПа", 0...655350, .fuel) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) * 10, Loc.t("кПа", "kPa"), digits: 0)
        }

        add(0x2C, 1, "Команда на клапан EGR", "Commanded EGR", "%", 0...100, .emissions) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x2D, 1, "Ошибка EGR", "EGR error", "%", -100...100, .emissions) { d in
            guard let a = d.first else { return nil }
            return num(trimPercent(a), "%")
        }
        add(0x2E, 1, "Продувка адсорбера", "Commanded evap purge", "%", 0...100, .emissions) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x2F, 1, "Уровень топлива", "Fuel tank level", "%", 0...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x30, 1, "Прогревов с момента сброса ошибок", "Warm-ups since codes cleared", "", 0...255, .emissions) { d in
            guard let a = d.first else { return nil }
            return num(Double(a), "", digits: 0)
        }

        add(0x31, 2, "Пробег с момента сброса ошибок", "Distance since codes cleared", "км", 0...65535, .emissions) { d in
            guard d.count >= 2 else { return nil }
            return num(Double(d[0]) * 256 + Double(d[1]), Loc.t("км", "km"), digits: 0)
        }

        add(0x32, 2, "Давление паров топлива", "Evap system vapor pressure", "Па", -8192...8192, .emissions) { d in
            guard d.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(d[0]) << 8 | UInt16(d[1]))
            return num(Double(raw) / 4, Loc.t("Па", "Pa"))
        }

        add(0x33, 1, "Атмосферное давление", "Barometric pressure", "кПа", 0...255, .air) { d in
            guard let a = d.first else { return nil }
            return num(Double(a), Loc.t("кПа", "kPa"), digits: 0)
        }

        add(0x3C, 2, "Температура катализатора, банк 1 датчик 1", "Cat temp B1S1", "°C", -40...6513, .temperature) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 10 - 40, "°C", digits: 0)
        }
        add(0x3D, 2, "Температура катализатора, банк 2 датчик 1", "Cat temp B2S1", "°C", -40...6513, .temperature) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 10 - 40, "°C", digits: 0)
        }
        add(0x3E, 2, "Температура катализатора, банк 1 датчик 2", "Cat temp B1S2", "°C", -40...6513, .temperature) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 10 - 40, "°C", digits: 0)
        }
        add(0x3F, 2, "Температура катализатора, банк 2 датчик 2", "Cat temp B2S2", "°C", -40...6513, .temperature) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 10 - 40, "°C", digits: 0)
        }

        add(0x42, 2, "Напряжение блока управления", "Control module voltage", "В", 0...66, .electrical) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 1000, Loc.t("В", "V"), digits: 2)
        }

        add(0x43, 2, "Абсолютная нагрузка", "Absolute load value", "%", 0...25700, .engine) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) * 100 / 255, "%")
        }

        add(0x44, 2, "Заданный коэффициент избытка воздуха", "Commanded equivalence ratio", "λ", 0...2, .fuel) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 32768, "λ", digits: 3)
        }

        add(0x45, 1, "Относительное положение дросселя", "Relative throttle position", "%", 0...100, .air) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x46, 1, "Температура за бортом", "Ambient air temperature", "°C", -40...215, .temperature) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 40, "°C", digits: 0)
        }

        add(0x47, 1, "Абсолютное положение дросселя B", "Absolute throttle position B", "%", 0...100, .air) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x48, 1, "Абсолютное положение дросселя C", "Absolute throttle position C", "%", 0...100, .air) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x49, 1, "Положение педали D", "Accelerator pedal position D", "%", 0...100, .engine) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x4A, 1, "Положение педали E", "Accelerator pedal position E", "%", 0...100, .engine) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x4B, 1, "Положение педали F", "Accelerator pedal position F", "%", 0...100, .engine) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }
        add(0x4C, 1, "Команда на привод дросселя", "Commanded throttle actuator", "%", 0...100, .air) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x4D, 2, "Время с горящим Check", "Time run with MIL on", "мин", 0...65535, .emissions) { d in
            guard d.count >= 2 else { return nil }
            let m = Double(d[0]) * 256 + Double(d[1])
            return PIDReading(value: m, display: formatDuration(seconds: Int(m) * 60))
        }

        add(0x4E, 2, "Время с момента сброса ошибок", "Time since codes cleared", "мин", 0...65535, .emissions) { d in
            guard d.count >= 2 else { return nil }
            let m = Double(d[0]) * 256 + Double(d[1])
            return PIDReading(value: m, display: formatDuration(seconds: Int(m) * 60))
        }

        add(0x51, 1, "Тип топлива", "Fuel type", "", nil, .fuel) { d in
            guard let a = d.first else { return nil }
            if let s = fuelTypes[a] { return text(Loc.t(s.0, s.1)) }
            return text("#\(a)")
        }

        add(0x52, 1, "Доля этанола", "Ethanol fuel percentage", "%", 0...100, .fuel) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x53, 2, "Абсолютное давление паров", "Absolute evap pressure", "кПа", 0...328, .emissions) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 200, Loc.t("кПа", "kPa"), digits: 2)
        }

        add(0x5A, 1, "Относительное положение педали", "Relative pedal position", "%", 0...100, .engine) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x5B, 1, "Заряд гибридной батареи", "Hybrid battery pack remaining", "%", 0...100, .hybrid) { d in
            guard let a = d.first else { return nil }
            return num(pct(a), "%")
        }

        add(0x5C, 1, "Температура масла", "Engine oil temperature", "°C", -40...215, .temperature) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 40, "°C", digits: 0)
        }

        add(0x5D, 2, "Угол впрыска топлива", "Fuel injection timing", "°", -210...302, .fuel) { d in
            guard d.count >= 2 else { return nil }
            let raw = Double(d[0]) * 256 + Double(d[1])
            return num(raw / 128 - 210, "°")
        }

        add(0x5E, 2, "Расход топлива", "Engine fuel rate", "л/ч", 0...3277, .fuel) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 20, Loc.t("л/ч", "L/h"), digits: 2)
        }

        add(0x61, 1, "Требуемый крутящий момент", "Driver's demand torque", "%", -125...130, .engine) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 125, "%", digits: 0)
        }
        add(0x62, 1, "Фактический крутящий момент", "Actual engine torque", "%", -125...130, .engine) { d in
            guard let a = d.first else { return nil }
            return num(Double(a) - 125, "%", digits: 0)
        }
        add(0x63, 2, "Опорный крутящий момент", "Reference engine torque", "Н·м", 0...65535, .engine) { d in
            guard d.count >= 2 else { return nil }
            return num(Double(d[0]) * 256 + Double(d[1]), Loc.t("Н·м", "N·m"), digits: 0)
        }

        add(0x66, 5, "Расход воздуха (датчик)", "Mass air flow sensor", "г/с", 0...2048, .air) { d in
            guard d.count >= 3 else { return nil }
            return num((Double(d[1]) * 256 + Double(d[2])) / 32, Loc.t("г/с", "g/s"), digits: 2)
        }

        add(0x67, 3, "Температура ОЖ (датчики)", "Engine coolant temp sensors", "°C", -40...215, .temperature) { d in
            guard d.count >= 2 else { return nil }
            return num(Double(d[1]) - 40, "°C", digits: 0)
        }

        add(0x9D, 4, "Расход топлива (двигатель)", "Engine fuel rate", "г/с", 0...3212, .fuel) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 32, Loc.t("г/с", "g/s"), digits: 2)
        }

        add(0x9E, 2, "Расход топлива двигателя", "Engine exhaust flow rate", "кг/ч", 0...16383, .emissions) { d in
            guard d.count >= 2 else { return nil }
            return num((Double(d[0]) * 256 + Double(d[1])) / 4, Loc.t("кг/ч", "kg/h"), digits: 1)
        }

        add(0xA6, 4, "Одометр", "Odometer", "км", 0...429496729, .other) { d in
            guard d.count >= 4 else { return nil }
            let raw = (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
            return num(Double(raw) / 10, Loc.t("км", "km"), digits: 0)
        }

        // Кислородные датчики: напряжение + краткая коррекция (0x14…0x1B)
        for (i, pid) in (UInt8(0x14)...UInt8(0x1B)).enumerated() {
            let bank = i / 4 + 1
            let sensor = i % 4 + 1
            add(pid, 2,
                "Лямбда B\(bank)S\(sensor): напряжение",
                "O2 B\(bank)S\(sensor): voltage",
                "В", 0...1.275, .oxygen) { d in
                guard d.count >= 2 else { return nil }
                let v = Double(d[0]) / 200
                if d[1] == 0xFF { return num(v, Loc.t("В", "V"), digits: 3) }
                let trim = trimPercent(d[1])
                return PIDReading(value: v,
                                  display: String(format: "%.3f %@ · %@ %+.1f%%",
                                                  v, Loc.t("В", "V"),
                                                  Loc.t("коррекция", "trim"), trim))
            }
        }

        // Лямбда-зонды широкополосные: коэффициент + напряжение (0x24…0x2B)
        for (i, pid) in (UInt8(0x24)...UInt8(0x2B)).enumerated() {
            let bank = i / 4 + 1
            let sensor = i % 4 + 1
            add(pid, 4,
                "Лямбда B\(bank)S\(sensor): коэффициент",
                "O2 B\(bank)S\(sensor): lambda",
                "λ", 0...2, .oxygen) { d in
                guard d.count >= 4 else { return nil }
                let ratio = (Double(d[0]) * 256 + Double(d[1])) / 32768
                let volt  = (Double(d[2]) * 256 + Double(d[3])) / 8192
                return PIDReading(value: ratio,
                                  display: String(format: "λ %.3f · %.3f %@", ratio, volt,
                                                  Loc.t("В", "V")))
            }
        }

        // Лямбда-зонды широкополосные: коэффициент + ток (0x34…0x3B)
        for (i, pid) in (UInt8(0x34)...UInt8(0x3B)).enumerated() {
            let bank = i / 4 + 1
            let sensor = i % 4 + 1
            add(pid, 4,
                "Лямбда B\(bank)S\(sensor): ток",
                "O2 B\(bank)S\(sensor): current",
                "мА", 0...2, .oxygen) { d in
                guard d.count >= 4 else { return nil }
                let ratio = (Double(d[0]) * 256 + Double(d[1])) / 32768
                let cur   = (Double(d[2]) * 256 + Double(d[3])) / 256 - 128
                return PIDReading(value: ratio,
                                  display: String(format: "λ %.3f · %+.2f %@", ratio, cur,
                                                  Loc.t("мА", "mA")))
            }
        }

        return t.sorted { $0.pid < $1.pid }
    }
}

func formatDuration(seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return Loc.t("\(h) ч \(m) мин", "\(h)h \(m)m") }
    if m > 0 { return Loc.t("\(m) мин \(s) с", "\(m)m \(s)s") }
    return Loc.t("\(s) с", "\(s)s")
}
