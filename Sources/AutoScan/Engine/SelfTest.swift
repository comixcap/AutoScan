import Foundation

/// Прогон полного цикла без интерфейса — для проверки разбора протокола.
///
///     AutoScan --selftest tcp:127.0.0.1:35000
///     AutoScan --selftest /dev/cu.usbserial-1420
///
/// Использует ровно тот же код, что и приложение, поэтому если здесь всё
/// прочиталось — прочитается и в интерфейсе.
enum SelfTest {

    static func run(target: String) -> Never {
        let kind: AdapterKind
        if target.hasPrefix("tcp:") {
            let parts = target.dropFirst(4).split(separator: ":")
            let host = String(parts.first ?? "127.0.0.1")
            let port = Int(parts.count > 1 ? parts[1] : "35000") ?? 35000
            kind = .wifi(host: host, port: port)
        } else if target.hasPrefix("ble") {
            kind = .ble(uuid: nil)
        } else {
            kind = .serial(path: target)
        }

        var finished = false
        var exitCode: Int32 = 0

        Task { @MainActor in
            let session = VehicleSession()

            print("== AutoScan self-test ==")
            print("цель: \(target)\n")

            await session.connect(to: kind)
            guard session.isConnected else {
                print("ОШИБКА подключения: \(session.lastError ?? "неизвестно")")
                exitCode = 1
                finished = true
                return
            }

            if let a = session.adapterInfo {
                print("адаптер:  \(a.identity)")
                print("протокол: \(a.protocolName) (\(a.protocolNumber))")
                if let v = a.voltage { print("питание:  \(v) В") }
            }
            print("")

            await session.runFullScan()

            guard let r = session.report else {
                print("ОШИБКА: отчёт не сформирован")
                exitCode = 1
                finished = true
                return
            }

            printReport(r, findings: session.findings)

            // проверяем, что PDF реально собирается
            let pdfURL = URL(fileURLWithPath: "/tmp/autoscan-selftest.pdf")
            do {
                try PDFReport.write(report: r, findings: session.findings, to: pdfURL)
                let size = (try? FileManager.default
                    .attributesOfItem(atPath: pdfURL.path)[.size] as? Int) ?? 0
                print("\nPDF: \(pdfURL.path) (\(size) байт)")
            } catch {
                print("\nОШИБКА PDF: \(error.localizedDescription)")
                exitCode = 3
            }

            // критерий успеха: что-то реально прочитано
            if r.readings.isEmpty && r.allDTCs.isEmpty && r.identity.isEmpty {
                print("\nПРОВАЛ: не прочитано ничего.")
                exitCode = 2
            } else {
                print("\nOK: цикл отработал полностью.")
            }

            session.disconnect()
            finished = true
        }

        // прокачиваем главный цикл, чтобы работали задачи на MainActor
        while !finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    private static func printReport(_ r: ScanReport, findings: [Finding]) {
        print("--- Идентификация ---")
        print("VIN:        \(r.identity.vin ?? "—")")
        if let d = r.vinDetails {
            print("WMI:        \(d.wmi)")
            print("завод:      \(d.manufacturer ?? "не определён") / \(d.countryLocalized ?? "—")")
            print("регион:     \(d.region ?? "—")")
            print("год:        \(d.year.map(String.init) ?? "—")"
                  + (d.yearAlternative.map { " (или \($0))" } ?? ""))
            print("код завода: \(d.plantCode.map(String.init) ?? "—")")
            print("серийный:   \(d.serial)")
            if d.checksumMandatory {
                print("контр.разряд: \(d.checksumValid == true ? "сходится" : "НЕ сходится")")
            } else {
                print("контр.разряд: не проверяется (не Северная Америка)")
            }
        }
        print("прошивка:   \(r.identity.calibrationIDs.joined(separator: ", "))")
        print("CVN:        \(r.identity.calibrationVerification.joined(separator: ", "))")

        print("\n--- Самодиагностика ---")
        if let m = r.readiness {
            print("Check Engine: \(m.milOn ? "ГОРИТ" : "не горит"), счётчик ошибок: \(m.dtcCount)")
            for mon in m.supportedMonitors {
                print("  [\(mon.complete ? "v" : " ")] \(mon.name)")
            }
        } else {
            print("недоступна")
        }

        print("\n--- Коды ошибок ---")
        if r.allDTCs.isEmpty {
            print("нет")
        } else {
            for d in r.allDTCs {
                print("  \(d.code)  [\(d.kind.title)]  \(d.title)")
            }
        }

        if !r.freezeFrame.isEmpty {
            print("\n--- Стоп-кадр (код \(r.freezeFrame.triggerCode ?? "—")) ---")
            for e in r.freezeFrame.entries.prefix(8) {
                print("  \(e.name): \(e.display)")
            }
        }

        if !r.monitorTests.isEmpty {
            print("\n--- Бортовые тесты ---")
            for t in r.monitorTests {
                print("  \(t.name): \(t.value) — \(t.outcomeText)")
            }
        }

        print("\n--- Отклонения от нормы (\(r.deviations.count)) ---")
        if r.deviations.isEmpty {
            print("нет")
        } else {
            for d in r.deviations {
                guard let a = d.assessment else { continue }
                print("  \(d.name): \(d.display) — \(a.status.title)")
                print("      норма: \(a.rangeText)")
                if let m = a.meaning { print("      \(m)") }
                if let c = a.whatToCheck { print("      проверять: \(c)") }
            }
        }

        print("\n--- Показания (\(r.readings.count)) ---")
        for i in r.readings {
            let mark: String
            switch i.assessment?.status {
            case .normal: mark = " [норма]"
            case .low: mark = " [НИЖЕ НОРМЫ]"
            case .high: mark = " [ВЫШЕ НОРМЫ]"
            default: mark = ""
            }
            print("  \(String(format: "01%02X", i.pid))  \(i.name): \(i.display)\(mark)")
        }

        print("\n--- Выводы ---")
        for f in findings {
            print("  [\(f.level.title)] \(f.title)")
            print("      \(f.detail)")
        }

        if !r.notes.isEmpty {
            print("\n--- Не прочитано ---")
            for n in r.notes { print("  - \(n)") }
        }
    }
}
