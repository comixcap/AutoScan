import Foundation

/// Счётчики наработки (In-Use Performance Tracking, Mode 09 PID 08 / 0B).
///
/// Почему это важно при покупке: в отличие от кодов ошибок, эти счётчики
/// сканером не стираются. Они копятся всю жизнь машины и показывают,
/// сколько раз двигатель запускали и сколько раз каждый бортовой тест
/// реально успел отработать.
///
/// Число запусков нельзя «скрутить» вместе с одометром, поэтому оно даёт
/// независимую оценку того, сколько машина проехала на самом деле.
struct PerformanceCounter: Identifiable {
    let key: String
    let name: String
    /// Сколько раз тест завершился полностью.
    let completed: Int
    /// Сколько раз возникли условия для его проведения.
    let conditions: Int

    var id: String { key }

    /// Доля успешных прогонов. Низкая — тест почти никогда не доходит до конца.
    var ratio: Double? {
        guard conditions > 0 else { return nil }
        return Double(completed) / Double(conditions)
    }
}

struct PerformanceTracking {
    /// Сколько раз возникали условия для бортовой диагностики.
    var obdConditions: Int?
    /// Число циклов зажигания — фактически число запусков двигателя.
    var ignitionCycles: Int?
    var counters: [PerformanceCounter] = []

    var isEmpty: Bool {
        obdConditions == nil && ignitionCycles == nil && counters.isEmpty
    }

    /// Названия пар счётчиков по порядку следования в ответе (SAE J1979).
    private static let sparkOrder: [(String, String, String)] = [
        ("CAT1",  "Катализатор, банк 1", "Catalyst bank 1"),
        ("CAT2",  "Катализатор, банк 2", "Catalyst bank 2"),
        ("O2S1",  "Кислородные датчики, банк 1", "Oxygen sensors bank 1"),
        ("O2S2",  "Кислородные датчики, банк 2", "Oxygen sensors bank 2"),
        ("EGR",   "Система EGR", "EGR system"),
        ("AIR",   "Вторичный воздух", "Secondary air"),
        ("EVAP",  "Система паров топлива", "Evaporative system"),
        ("SO2S1", "Доп. кислородный датчик, банк 1", "Secondary O2 bank 1"),
        ("SO2S2", "Доп. кислородный датчик, банк 2", "Secondary O2 bank 2")
    ]

    private static let dieselOrder: [(String, String, String)] = [
        ("HCCAT", "Катализатор HC", "HC catalyst"),
        ("NCAT",  "Катализатор NOx", "NOx catalyst"),
        ("NADS",  "Адсорбер NOx", "NOx adsorber"),
        ("PM",    "Сажевый фильтр", "PM filter"),
        ("EGS",   "Датчик отработавших газов", "Exhaust gas sensor"),
        ("EGR",   "Система EGR", "EGR system"),
        ("BP",    "Давление наддува", "Boost pressure"),
        ("FUEL",  "Топливная система", "Fuel system")
    ]

    /// Разбирает полезную нагрузку Mode 09 PID 08 (бензин) или 0B (дизель).
    ///
    /// Формат: первый байт — количество 16-битных значений, далее пары байт.
    /// Первые два значения всегда OBDCOND и IGNCNTR, дальше идут пары
    /// «завершено / условий» по каждому монитору.
    static func parse(payload: [UInt8], diesel: Bool) -> PerformanceTracking? {
        guard payload.count >= 5 else { return nil }

        // некоторые блоки не присылают байт количества — определяем по длине
        var body = payload
        let declared = Int(payload[0])
        if declared > 0, declared * 2 == payload.count - 1 {
            body = Array(payload.dropFirst())
        }
        guard body.count >= 4, body.count % 2 == 0 else { return nil }

        var values: [Int] = []
        var i = 0
        while i + 1 < body.count {
            values.append(Int(body[i]) << 8 | Int(body[i + 1]))
            i += 2
        }
        guard values.count >= 2 else { return nil }

        var t = PerformanceTracking()
        t.obdConditions = values[0]
        t.ignitionCycles = values[1]

        let order = diesel ? dieselOrder : sparkOrder
        var idx = 2
        var slot = 0
        while idx + 1 < values.count && slot < order.count {
            let (key, ru, en) = order[slot]
            let completed = values[idx]
            let conditions = values[idx + 1]
            // пропускаем незанятые слоты, чтобы не показывать пустые строки
            if completed != 0 || conditions != 0 {
                t.counters.append(PerformanceCounter(key: key, name: Loc.t(ru, en),
                                                     completed: completed,
                                                     conditions: conditions))
            }
            idx += 2
            slot += 1
        }
        return t
    }

    /// Средний пробег за одну поездку, если одометр доступен.
    /// Малое значение = машина ходила короткими поездками, это тяжёлый режим:
    /// нагар, масло, катализатор, аккумулятор.
    func averageTripDistance(odometerKm: Double?) -> Double? {
        guard let odo = odometerKm, let cycles = ignitionCycles, cycles > 50 else { return nil }
        return odo / Double(cycles)
    }
}
