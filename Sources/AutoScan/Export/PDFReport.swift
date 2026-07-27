import AppKit
import Foundation

/// Сборка PDF-отчёта постранично средствами CoreGraphics.
/// Ничего не «рисуется красиво» — задача документа быть читаемым и полным.
enum PDFReport {

    private static let pageSize = CGSize(width: 595, height: 842)   // A4
    private static let margin: CGFloat = 46
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // MARK: Публичный вход

    static func write(report: ScanReport, findings: [Finding], to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "AutoScan", code: 1, userInfo: [
                NSLocalizedDescriptionKey: Loc.t("Не удалось создать PDF-файл",
                                                 "Could not create the PDF file")])
        }

        var renderer = Renderer(ctx: ctx)
        renderer.beginPage()

        compose(report: report, findings: findings, into: &renderer)

        renderer.endPage()
        ctx.closePDF()
    }

    // MARK: Содержимое

    private static func compose(report r: ScanReport, findings: [Finding],
                                into p: inout Renderer) {

        p.title("AutoScan — " + Loc.t("отчёт о диагностике", "diagnostic report"))

        let dateLabel: String = Loc.t("Дата проверки: ", "Scan date: ")
        let dateValue: String = Self.stamp.string(from: r.startedAt)
        let durLabel: String = Loc.t("длительность ", "duration ")
        let durValue: String = "\(Int(r.duration)) " + Loc.t("с", "s")
        p.small(dateLabel + dateValue + " · " + durLabel + durValue)
        p.gap(6)

        // --- Итог ---
        let summary = Verdict.summary(findings)
        p.heading(Loc.t("Общий вывод", "Overall verdict"))
        p.body(summary.text, bold: true)
        p.small(Loc.t("Подтверждённых ошибок: \(r.storedDTCs.count) · ожидающих: \(r.pendingDTCs.count) · постоянных: \(r.permanentDTCs.count) · параметров прочитано: \(r.readings.count)",
                      "Confirmed faults: \(r.storedDTCs.count) · pending: \(r.pendingDTCs.count) · permanent: \(r.permanentDTCs.count) · parameters read: \(r.readings.count)"))
        p.gap(8)

        // --- Идентификация ---
        p.heading(Loc.t("Идентификация", "Identity"))
        if let vin = r.identity.vin {
            p.kv("VIN", vin)
            if let y = r.identity.modelYearFromVIN {
                p.kv(Loc.t("Модельный год по VIN", "Model year from VIN"), String(y))
            }
            if let ok = r.identity.vinChecksumValid {
                p.kv(Loc.t("Контрольный разряд VIN", "VIN check digit"),
                     ok ? Loc.t("сходится", "valid") : Loc.t("не сходится", "invalid"))
            }
        } else {
            p.kv("VIN", Loc.t("не читается", "not available"))
        }
        if let d = r.vinDetails {
            if let m = d.manufacturer { p.kv(Loc.t("Производитель", "Manufacturer"), m) }
            if let c = d.countryLocalized { p.kv(Loc.t("Страна выпуска", "Country"), c) }
            if let pc = d.plantCode { p.kv(Loc.t("Код завода", "Plant code"), String(pc)) }
            p.kv(Loc.t("Серийный номер кузова", "Serial number"), d.serial)
        }
        if let n = r.nhtsa, !n.isEmpty {
            if let v = n.make { p.kv(Loc.t("Марка", "Make"), v) }
            if let v = n.model { p.kv(Loc.t("Модель", "Model"), v) }
            if let v = n.series { p.kv(Loc.t("Серия", "Series"), v) }
            if let v = n.trim { p.kv(Loc.t("Комплектация", "Trim"), v) }
            if let v = n.bodyClass { p.kv(Loc.t("Тип кузова", "Body class"), v) }
            if let v = n.transmissionHuman { p.kv(Loc.t("Коробка передач", "Transmission"), v) }
            if let v = n.driveType { p.kv(Loc.t("Привод", "Drive type"), v) }
            if let v = n.displacementL { p.kv(Loc.t("Объём двигателя", "Displacement"), v + " l") }
            if let v = n.engineCylinders { p.kv(Loc.t("Цилиндров", "Cylinders"), v) }
            if let v = n.engineModel { p.kv(Loc.t("Модель двигателя", "Engine model"), v) }
            if let v = n.fuelType { p.kv(Loc.t("Топливо", "Fuel"), v) }
            if let v = n.plantCountry { p.kv(Loc.t("Завод", "Plant"), v) }
        }
        for (i, cal) in r.identity.calibrationIDs.enumerated() {
            p.kv(Loc.t("Версия прошивки \(i + 1)", "Calibration ID \(i + 1)"), cal)
        }
        for (i, cvn) in r.identity.calibrationVerification.enumerated() {
            p.kv(Loc.t("Контрольная сумма \(i + 1)", "Calibration verification \(i + 1)"), cvn)
        }
        if let ecu = r.identity.ecuName { p.kv(Loc.t("Блок управления", "ECU"), ecu) }
        if let a = r.adapter {
            p.kv(Loc.t("Адаптер", "Adapter"), a.identity)
            p.kv(Loc.t("Протокол", "Protocol"), a.protocolName)
        }
        p.kv(Loc.t("Канал связи", "Channel"), r.channel)
        if let v = r.batteryVoltage {
            p.kv(Loc.t("Напряжение бортсети", "System voltage"),
                 String(format: "%.2f %@", v, Loc.t("В", "V")))
        }
        p.gap(8)

        // --- Отклонения от нормы ---
        if !r.deviations.isEmpty {
            p.heading(Loc.t("Отклонения от нормы", "Out-of-range readings"))
            for item in r.deviations {
                guard let a = item.assessment else { continue }
                p.body("\(item.name): \(item.display) — \(a.status.title)", bold: true)
                p.small(Loc.t("Норма: ", "Normal: ") + a.rangeText)
                if let m = a.meaning { p.body(m) }
                if let c = a.whatToCheck {
                    p.small(Loc.t("Что проверять: ", "What to check: ") + c)
                }
                p.gap(4)
            }
            p.gap(4)
        }

        // --- Выводы ---
        p.heading(Loc.t("Выводы", "Findings"))
        for f in findings {
            p.body("[\(f.level.title)] \(f.title)", bold: true)
            p.body(f.detail)
            if let a = f.advice { p.small(a) }
            p.gap(4)
        }
        p.gap(4)

        // --- Ошибки ---
        if !r.allDTCs.isEmpty {
            p.heading(Loc.t("Коды ошибок", "Fault codes"))
            for d in r.allDTCs {
                p.body("\(d.code) — \(d.title)  (\(d.kind.title), \(d.severity.title))", bold: true)
                p.body(d.explanation)
                p.gap(3)
            }
            p.gap(4)
        }

        // --- Счётчики наработки ---
        if let perf = r.performance, !perf.isEmpty {
            p.heading(Loc.t("Счётчики наработки", "In-use performance counters"))
            p.small(Loc.t("Не стираются сканером, копятся всю жизнь машины.",
                          "Cannot be cleared with a scanner; accumulate over the vehicle's life."))
            if let c = perf.ignitionCycles {
                p.kv(Loc.t("Запусков двигателя", "Engine starts"), "\(c)")
            }
            if let c = perf.obdConditions {
                p.kv(Loc.t("Циклов бортовой диагностики", "OBD monitoring cycles"), "\(c)")
            }
            if let odo = r.value(pid: 0xA6) {
                p.kv(Loc.t("Одометр (из блока)", "Odometer (from ECU)"), "\(Int(odo)) km")
                if let avg = perf.averageTripDistance(odometerKm: odo) {
                    p.kv(Loc.t("Средняя длина поездки", "Average trip length"),
                         String(format: "%.1f km", avg))
                }
            }
            for c in perf.counters {
                p.kv(c.name, "\(c.completed) / \(c.conditions)")
            }
            p.gap(8)
        }

        // --- Мониторы ---
        if let m = r.readiness {
            p.heading(Loc.t("Готовность самодиагностики", "Readiness monitors"))
            p.kv(Loc.t("Лампа Check Engine", "Check Engine lamp"),
                 m.milOn ? Loc.t("горит", "on") : Loc.t("не горит", "off"))
            p.kv(Loc.t("Тип двигателя", "Engine type"),
                 m.compressionIgnition ? Loc.t("дизель", "diesel") : Loc.t("бензин", "petrol"))
            for mon in m.supportedMonitors {
                p.kv(mon.name, mon.complete ? Loc.t("пройден", "complete")
                                            : Loc.t("НЕ ЗАВЕРШЁН", "INCOMPLETE"))
            }
            p.gap(8)
        }

        // --- Стоп-кадр ---
        if !r.freezeFrame.isEmpty {
            p.heading(Loc.t("Стоп-кадр неисправности", "Freeze frame"))
            if let c = r.freezeFrame.triggerCode {
                p.kv(Loc.t("Сохранён по коду", "Stored for code"), c)
            }
            for e in r.freezeFrame.entries { p.kv(e.name, e.display) }
            p.gap(8)
        }

        // --- Бортовые тесты ---
        if !r.monitorTests.isEmpty {
            p.heading(Loc.t("Бортовые тесты (Mode 06)", "On-board tests (Mode 06)"))
            for t in r.monitorTests {
                let limits: String = t.outcome == .counter ? "" : "  [\(t.minLimit)…\(t.maxLimit)]"
                p.kv(t.name, "\(t.value)\(limits)  \(t.outcomeText)")
            }
            p.gap(8)
        }

        // --- Показания ---
        if !r.readings.isEmpty {
            p.heading(Loc.t("Показания датчиков", "Sensor readings"))
            for cat in PIDCategory.allCases {
                let items = r.readings.filter { $0.category == cat }
                guard !items.isEmpty else { continue }
                p.subheading(cat.title)
                for i in items {
                    p.kv(i.name, i.display + "   (" + String(format: "01%02X", i.pid) + ")")
                }
                p.gap(4)
            }
        }

        // --- Что не прочиталось ---
        if !r.notes.isEmpty {
            p.gap(4)
            p.heading(Loc.t("Что прочитать не удалось", "What could not be read"))
            for n in r.notes { p.body("— " + n) }
        }

        p.gap(10)
        p.small(Loc.t("Отчёт содержит только данные стандарта OBD-II (двигатель и система снижения выбросов). Блоки ABS, подушек безопасности и коробки передач по этому протоколу недоступны.",
                      "This report covers OBD-II standard data only (engine and emissions). ABS, airbag and transmission modules are not accessible over this protocol."))
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f
    }()

    // MARK: Постраничная отрисовка

    private struct Renderer {
        let ctx: CGContext
        var y: CGFloat = 0
        private var pageStarted = false

        init(ctx: CGContext) { self.ctx = ctx }

        mutating func beginPage() {
            ctx.beginPDFPage(nil)
            pageStarted = true
            y = pageSize.height - margin
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        }

        mutating func endPage() {
            guard pageStarted else { return }
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
            pageStarted = false
        }

        mutating func newPageIfNeeded(_ height: CGFloat) {
            if y - height < margin {
                endPage()
                beginPage()
            }
        }

        mutating func gap(_ h: CGFloat) { y -= h }

        mutating func draw(_ s: String, font: NSFont, color: NSColor = .black,
                           indent: CGFloat = 0) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let width = contentWidth - indent
            let bounding = (s as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs)
            let h = ceil(bounding.height)
            newPageIfNeeded(h + 2)
            (s as NSString).draw(
                with: CGRect(x: margin + indent, y: y - h, width: width, height: h),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs)
            y -= h + 2
        }

        mutating func title(_ s: String) {
            draw(s, font: .systemFont(ofSize: 17, weight: .semibold))
            gap(2)
        }

        mutating func heading(_ s: String) {
            gap(4)
            draw(s, font: .systemFont(ofSize: 12, weight: .semibold))
            gap(1)
        }

        mutating func subheading(_ s: String) {
            draw(s, font: .systemFont(ofSize: 10, weight: .semibold), color: .darkGray)
        }

        mutating func body(_ s: String, bold: Bool = false) {
            draw(s, font: .systemFont(ofSize: 10, weight: bold ? .medium : .regular))
        }

        mutating func small(_ s: String) {
            draw(s, font: .systemFont(ofSize: 9), color: .darkGray)
        }

        /// Строка «параметр — значение» с выравниванием значения вправо.
        mutating func kv(_ key: String, _ value: String) {
            let keyFont = NSFont.systemFont(ofSize: 10)
            let valFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont,
                                                           .foregroundColor: NSColor.black]
            let valAttrs: [NSAttributedString.Key: Any] = [.font: valFont,
                                                           .foregroundColor: NSColor.black]

            let valWidth = min(contentWidth * 0.5,
                               ceil((value as NSString).size(withAttributes: valAttrs).width) + 2)
            let keyWidth = contentWidth - valWidth - 8

            let keyRect = (key as NSString).boundingRect(
                with: CGSize(width: keyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: keyAttrs)
            let valRect = (value as NSString).boundingRect(
                with: CGSize(width: valWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: valAttrs)

            let h = ceil(max(keyRect.height, valRect.height))
            newPageIfNeeded(h + 2)

            (key as NSString).draw(
                with: CGRect(x: margin, y: y - h, width: keyWidth, height: h),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: keyAttrs)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            var rightAttrs = valAttrs
            rightAttrs[.paragraphStyle] = paragraph
            (value as NSString).draw(
                with: CGRect(x: margin + keyWidth + 8, y: y - h, width: valWidth, height: h),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: rightAttrs)

            y -= h + 2
        }
    }
}
