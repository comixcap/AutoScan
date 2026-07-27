import Foundation

/// Разбор VIN по стандарту ISO 3779.
///
/// Работает без интернета: производитель, страна и завод определяются
/// по таблице WMI (первые три знака), год — по десятому знаку.
/// Модель, двигатель и тип коробки в самом VIN не закодированы единообразно —
/// их даёт только база производителя, см. `NHTSALookup`.
struct VINDetails {
    var vin: String
    var wmi: String                 // первые 3 знака — кто и где выпустил
    var manufacturer: String?
    var country: String?
    var region: String?
    var year: Int?
    var plantCode: Character?
    var serial: String              // последние 6 знаков — порядковый номер
    var checkDigit: Character?
    var checksumValid: Bool?
    var checksumMandatory: Bool

    static func decode(_ raw: String) -> VINDetails? {
        let vin = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard vin.count == 17 else { return nil }
        let ch = Array(vin)

        var d = VINDetails(
            vin: vin,
            wmi: String(ch[0...2]),
            manufacturer: nil,
            country: nil,
            region: nil,
            year: nil,
            plantCode: ch[10],
            serial: String(ch[11...16]),
            checkDigit: ch[8],
            checksumValid: nil,
            checksumMandatory: "12345".contains(ch[0])
        )

        // производитель: сначала пробуем 3 знака, потом 2 (у мелких серий WMI длиннее)
        if let m = wmiTable[String(ch[0...2])] {
            d.manufacturer = m.0
            d.country = m.1
        } else if let m = wmiTable[String(ch[0...1])] {
            d.manufacturer = m.0
            d.country = m.1
        }

        d.region = region(for: ch[0])
        d.year = modelYear(code: ch[9])
        d.checksumValid = checksum(vin)
        return d
    }

    // MARK: Год

    private static func modelYear(code: Character) -> Int? {
        let table: [Character: Int] = [
            "A": 1980, "B": 1981, "C": 1982, "D": 1983, "E": 1984, "F": 1985,
            "G": 1986, "H": 1987, "J": 1988, "K": 1989, "L": 1990, "M": 1991,
            "N": 1992, "P": 1993, "R": 1994, "S": 1995, "T": 1996, "V": 1997,
            "W": 1998, "X": 1999, "Y": 2000, "1": 2001, "2": 2002, "3": 2003,
            "4": 2004, "5": 2005, "6": 2006, "7": 2007, "8": 2008, "9": 2009
        ]
        guard var year = table[code] else { return nil }
        // буквы повторяются через 30 лет: 1980-2009 -> 2010-2039
        if code.isLetter && year < 2010 { year += 30 }
        return year
    }

    /// Год неоднозначен: буква может значить и старый, и новый цикл.
    var yearAlternative: Int? {
        guard let y = year, y >= 2010 else { return nil }
        return y - 30
    }

    // MARK: Контрольный разряд

    private static func checksum(_ vin: String) -> Bool? {
        let translit: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (i, c) in vin.enumerated() {
            let v: Int
            if c.isNumber, let n = c.wholeNumberValue { v = n }
            else if let t = translit[c] { v = t }
            else { return nil }
            sum += v * weights[i]
        }
        let r = sum % 11
        let expected: Character = (r == 10) ? "X" : Character(String(r))
        return Array(vin)[8] == expected
    }

    // MARK: Регион по первому знаку

    private static func region(for c: Character) -> String? {
        switch c {
        case "A"..."C": return Loc.t("Африка", "Africa")
        case "J"..."R": return Loc.t("Азия", "Asia")
        case "S"..."Z": return Loc.t("Европа", "Europe")
        case "1"..."5": return Loc.t("Северная Америка", "North America")
        case "6"..."7": return Loc.t("Океания", "Oceania")
        case "8"..."9": return Loc.t("Южная Америка", "South America")
        default: return nil
        }
    }

    // MARK: Таблица WMI

    /// Производитель и страна выпуска. Покрыты массовые марки;
    /// для остальных приложение честно покажет «не определён».
    private static let wmiTable: [String: (String, String)] = [
        // --- Корея ---
        "KMH": ("Hyundai", "Корея"), "KM8": ("Hyundai", "Корея"),
        "KMF": ("Hyundai", "Корея"), "KMJ": ("Hyundai", "Корея"),
        "KNA": ("Kia", "Корея"), "KND": ("Kia", "Корея"),
        "KNE": ("Kia", "Корея"), "KNM": ("Kia", "Корея"),
        "KL1": ("Daewoo / Chevrolet", "Корея"), "KLA": ("Daewoo", "Корея"),
        "KPT": ("SsangYong", "Корея"),
        "Z94": ("Hyundai", "Россия"), "XWE": ("Hyundai", "Россия"),
        "XWK": ("Kia", "Россия"),

        // --- Япония ---
        "JF1": ("Subaru", "Япония"), "JF2": ("Subaru", "Япония"),
        "4S3": ("Subaru", "США"), "4S4": ("Subaru", "США"),
        "JA3": ("Mitsubishi", "Япония"), "JA4": ("Mitsubishi", "Япония"),
        "JMB": ("Mitsubishi", "Япония"), "JMY": ("Mitsubishi", "Япония"),
        "4A3": ("Mitsubishi", "США"), "4A4": ("Mitsubishi", "США"),
        "JT2": ("Toyota", "Япония"), "JT3": ("Toyota", "Япония"),
        "JTD": ("Toyota", "Япония"), "JTE": ("Toyota", "Япония"),
        "JTM": ("Toyota", "Япония"), "JTN": ("Toyota", "Япония"),
        "JTH": ("Lexus", "Япония"),
        "JHM": ("Honda", "Япония"), "JHL": ("Honda", "Япония"),
        "SHH": ("Honda", "Великобритания"),
        "JN1": ("Nissan", "Япония"), "JN6": ("Nissan", "Япония"),
        "JN8": ("Nissan", "Япония"), "SJN": ("Nissan", "Великобритания"),
        "JM1": ("Mazda", "Япония"), "JM3": ("Mazda", "Япония"),
        "JS1": ("Suzuki", "Япония"), "JS2": ("Suzuki", "Япония"),
        "JL5": ("Isuzu", "Япония"), "JAA": ("Isuzu", "Япония"),

        // --- Европа ---
        "WBA": ("BMW", "Германия"), "WBS": ("BMW M", "Германия"),
        "WBY": ("BMW", "Германия"),
        "WDB": ("Mercedes-Benz", "Германия"), "WDD": ("Mercedes-Benz", "Германия"),
        "WDC": ("Mercedes-Benz", "Германия"), "W1K": ("Mercedes-Benz", "Германия"),
        "WVW": ("Volkswagen", "Германия"), "WV1": ("Volkswagen", "Германия"),
        "WV2": ("Volkswagen", "Германия"), "XW8": ("Volkswagen", "Россия"),
        "WAU": ("Audi", "Германия"), "WA1": ("Audi", "Германия"),
        "WP0": ("Porsche", "Германия"), "WP1": ("Porsche", "Германия"),
        "WF0": ("Ford", "Германия"), "WMW": ("MINI", "Германия"),
        "VF1": ("Renault", "Франция"), "X7L": ("Renault", "Россия"),
        "VF3": ("Peugeot", "Франция"), "VF7": ("Citroen", "Франция"),
        "VSS": ("SEAT", "Испания"), "TMB": ("Skoda", "Чехия"),
        "ZFA": ("Fiat", "Италия"), "ZAR": ("Alfa Romeo", "Италия"),
        "YV1": ("Volvo", "Швеция"), "YS3": ("Saab", "Швеция"),
        "SAL": ("Land Rover", "Великобритания"), "SAJ": ("Jaguar", "Великобритания"),

        // --- Россия ---
        "XTA": ("Lada / ВАЗ", "Россия"), "XTT": ("UAZ", "Россия"),
        "X4X": ("BMW", "Россия"), "XUF": ("GM-АвтоВАЗ", "Россия"),
        "XTC": ("КамАЗ", "Россия"), "XW7": ("Toyota", "Россия"),

        // --- Китай ---
        "LVS": ("Ford", "Китай"), "LFV": ("Volkswagen", "Китай"),
        "LGW": ("Haval / Great Wall", "Китай"), "LB3": ("Geely", "Китай"),
        "L6T": ("Geely", "Китай"), "LVV": ("Chery", "Китай"),
        "LJ1": ("JAC", "Китай"), "LZW": ("Wuling", "Китай"),
        "LDC": ("Dongfeng", "Китай"), "LS5": ("Changan", "Китай"),
        "LNB": ("Exeed", "Китай"), "LMG": ("GAC", "Китай"),

        // --- США ---
        "1FA": ("Ford", "США"), "1FT": ("Ford", "США"), "1FM": ("Ford", "США"),
        "1G1": ("Chevrolet", "США"), "1GC": ("Chevrolet", "США"),
        "1GY": ("Cadillac", "США"), "1C3": ("Chrysler", "США"),
        "1C4": ("Jeep", "США"), "1J4": ("Jeep", "США"),
        "2T1": ("Toyota", "Канада"), "3VW": ("Volkswagen", "Мексика"),
        "5YJ": ("Tesla", "США"), "7SA": ("Tesla", "США")
    ]

    /// Локализованное название страны.
    var countryLocalized: String? {
        guard let country else { return nil }
        guard Loc.lang == .en else { return country }
        let en: [String: String] = [
            "Корея": "South Korea", "Япония": "Japan", "Германия": "Germany",
            "Франция": "France", "Испания": "Spain", "Чехия": "Czechia",
            "Италия": "Italy", "Швеция": "Sweden", "Великобритания": "United Kingdom",
            "Россия": "Russia", "Китай": "China", "США": "USA",
            "Канада": "Canada", "Мексика": "Mexico"
        ]
        return en[country] ?? country
    }
}

// MARK: - Уточнение по базе NHTSA

/// Модель, двигатель и тип коробки в VIN напрямую не закодированы —
/// их знает только производитель. Открытая база NHTSA (США) отдаёт
/// эти данные бесплатно и без ключа.
///
/// Требует интернета. Полнота зависит от рынка: машины, официально
/// продававшиеся в США, разбираются подробно; чисто внутренние
/// корейские и японские версии — частично или никак.
struct NHTSAInfo {
    var make: String?
    var model: String?
    var year: String?
    var series: String?
    var trim: String?
    var bodyClass: String?
    var driveType: String?
    var engineCylinders: String?
    var displacementL: String?
    var engineModel: String?
    var fuelType: String?
    var transmissionStyle: String?
    var transmissionSpeeds: String?
    var plantCountry: String?
    var plantCity: String?
    var errorText: String?

    var isEmpty: Bool {
        make == nil && model == nil && transmissionStyle == nil
            && engineCylinders == nil && bodyClass == nil
    }

    /// Тип коробки понятным языком.
    var transmissionHuman: String? {
        guard let style = transmissionStyle?.lowercased(), !style.isEmpty else { return nil }
        var text: String
        if style.contains("continuously") || style.contains("cvt") {
            text = Loc.t("вариатор (CVT)", "continuously variable (CVT)")
        } else if style.contains("dual") || style.contains("dct") {
            text = Loc.t("робот с двумя сцеплениями (DCT)", "dual-clutch (DCT)")
        } else if style.contains("automated") || style.contains("amt") {
            text = Loc.t("роботизированная (AMT)", "automated manual (AMT)")
        } else if style.contains("manual") {
            text = Loc.t("механическая", "manual")
        } else if style.contains("automatic") {
            text = Loc.t("автоматическая (гидротрансформатор)", "automatic (torque converter)")
        } else {
            text = transmissionStyle ?? ""
        }
        if let speeds = transmissionSpeeds, !speeds.isEmpty {
            text += Loc.t(", \(speeds) ступ.", ", \(speeds)-speed")
        }
        return text
    }
}

enum NHTSALookup {

    /// Запрашивает разбор VIN в открытой базе NHTSA.
    static func decode(vin: String, timeout: TimeInterval = 12) async throws -> NHTSAInfo {
        let clean = vin.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count == 17 else {
            throw NSError(domain: "AutoScan", code: 10, userInfo: [
                NSLocalizedDescriptionKey: Loc.t("VIN должен содержать 17 знаков",
                                                 "A VIN must be 17 characters")])
        }

        var comps = URLComponents(string:
            "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(clean)")!
        comps.queryItems = [URLQueryItem(name: "format", value: "json")]

        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "AutoScan", code: 11, userInfo: [
                NSLocalizedDescriptionKey: Loc.t("База NHTSA не ответила",
                                                 "NHTSA database did not respond")])
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["Results"] as? [[String: Any]],
              let r = results.first else {
            throw NSError(domain: "AutoScan", code: 12, userInfo: [
                NSLocalizedDescriptionKey: Loc.t("Неожиданный ответ базы",
                                                 "Unexpected database response")])
        }

        func s(_ key: String) -> String? {
            guard let v = r[key] as? String else { return nil }
            let t = v.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t == "Not Applicable" ? nil : t
        }

        return NHTSAInfo(
            make: s("Make"),
            model: s("Model"),
            year: s("ModelYear"),
            series: s("Series"),
            trim: s("Trim"),
            bodyClass: s("BodyClass"),
            driveType: s("DriveType"),
            engineCylinders: s("EngineCylinders"),
            displacementL: s("DisplacementL"),
            engineModel: s("EngineModel"),
            fuelType: s("FuelTypePrimary"),
            transmissionStyle: s("TransmissionStyle"),
            transmissionSpeeds: s("TransmissionSpeeds"),
            plantCountry: s("PlantCountry"),
            plantCity: s("PlantCity"),
            errorText: s("ErrorText")
        )
    }
}
