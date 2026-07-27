import SwiftUI

struct ScanView: View {
    @Binding var screen: RootView.Screen
    @EnvironmentObject private var session: VehicleSession
    @State private var showClearConfirm = false
    @State private var showRawLog = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if session.state == .scanning {
                progressPane
            } else if let report = session.report {
                ResultsPane(report: report, findings: session.findings,
                            showRawLog: $showRawLog, session: session)
            } else {
                emptyPane
            }
        }
        .confirmationDialog(Loc.t("Стереть коды ошибок?", "Clear fault codes?"),
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(Loc.t("Стереть", "Clear"), role: .destructive) {
                Task { _ = await session.clearFaultCodes() }
            }
            Button(Loc.t("Отмена", "Cancel"), role: .cancel) { }
        } message: {
            Text(Loc.t("""
                Вместе с кодами сотрётся стоп-кадр — данные о том, что происходило с двигателем в момент неисправности. Это самая ценная улика при поиске плавающей проблемы.
                Мониторы готовности обнулятся, и до накатки нескольких циклов машина не пройдёт проверку по выхлопу.
                Постоянные коды (Mode 0A) не стираются — они погаснут сами.
                """, """
                Clearing also erases the freeze frame — the record of what the engine was doing when the fault occurred. That is the most valuable evidence for an intermittent problem.
                Readiness monitors will reset, and the car will fail an emissions test until several drive cycles complete.
                Permanent codes (Mode 0A) are not cleared — they fade on their own.
                """))
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Проверка автомобиля", "Vehicle check"))
                    .font(.system(size: 17, weight: .semibold))
                if let r = session.report, r.finishedAt != nil {
                    Text(Loc.t("Выполнена \(Self.stamp.string(from: r.startedAt)) · \(Int(r.duration)) с",
                               "Completed \(Self.stamp.string(from: r.startedAt)) · \(Int(r.duration))s"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if session.report != nil && session.state != .scanning {
                Button(Loc.t("Стереть ошибки", "Clear codes")) { showClearConfirm = true }
                Button(Loc.t("Отчёт", "Report")) { screen = .report }
            }
            Button {
                Task { await session.runFullScan() }
            } label: {
                Label(session.report == nil
                      ? Loc.t("Начать проверку", "Start check")
                      : Loc.t("Проверить снова", "Scan again"),
                      systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.state != .connected)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var progressPane: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: session.progress)
                .frame(maxWidth: 460)
            Text(session.stageText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(Int(session.progress * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPane: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "car.side")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(Loc.t("Проверка ещё не выполнялась", "No check has been run yet"))
                .font(.system(size: 14, weight: .medium))
            Text(Loc.t("Приложение опросит блок управления по всем поддерживаемым запросам стандарта OBD-II и объяснит результат.",
                       "The app will query the ECU with every supported OBD-II request and explain the result."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f
    }()
}

// MARK: - Результаты

struct ResultsPane: View {
    let report: ScanReport
    let findings: [Finding]
    @Binding var showRawLog: Bool
    @ObservedObject var session: VehicleSession
    @State private var showExplanations = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                deviationsSection
                findingsSection
                identitySection
                performanceSection
                dtcSection
                readinessSection
                freezeFrameSection
                testsSection
                readingsSection
                notesSection
                logSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: (level: FindingLevel, text: String) { Verdict.summary(findings) }

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.level.symbol)
                .font(.system(size: 26))
                .foregroundStyle(color(summary.level))
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.text)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(countsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color(summary.level).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color(summary.level).opacity(0.35)))
    }

    private var countsLine: String {
        var parts: [String] = []
        parts.append(Loc.t("подтверждённых ошибок: \(report.storedDTCs.count)",
                           "confirmed faults: \(report.storedDTCs.count)"))
        parts.append(Loc.t("ожидающих: \(report.pendingDTCs.count)",
                           "pending: \(report.pendingDTCs.count)"))
        parts.append(Loc.t("постоянных: \(report.permanentDTCs.count)",
                           "permanent: \(report.permanentDTCs.count)"))
        parts.append(Loc.t("параметров прочитано: \(report.readings.count)",
                           "parameters read: \(report.readings.count)"))
        return parts.joined(separator: " · ")
    }

    private func color(_ l: FindingLevel) -> Color {
        switch l {
        case .good: return .green
        case .neutral: return .secondary
        case .attention: return .orange
        case .alarm: return .red
        }
    }

    // MARK: Выводы

    private var findingsSection: some View {
        Section2(Loc.t("Выводы", "Findings")) {
            VStack(spacing: 8) {
                ForEach(findings) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: f.level.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(color(f.level))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.title)
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(f.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let advice = f.advice {
                                Text(advice)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 1)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
        }
    }

    // MARK: Паспорт

    @ViewBuilder private var identitySection: some View {
        if !report.identity.isEmpty || report.adapter != nil {
            Section2(Loc.t("Идентификация и связь", "Identity and link")) {
                VStack(alignment: .leading, spacing: 5) {
                    if let vin = report.identity.vin {
                        Row(Loc.t("VIN", "VIN"), vin, mono: true)
                    }
                    if let d = report.vinDetails {
                        if let m = d.manufacturer {
                            Row(Loc.t("Производитель", "Manufacturer"), m)
                        }
                        if let c = d.countryLocalized {
                            Row(Loc.t("Страна выпуска", "Country of manufacture"), c)
                        }
                        if d.year != nil {
                            Row(Loc.t("Модельный год", "Model year"), yearText(d))
                        }
                        Row(Loc.t("Код завода-изготовителя", "Plant code"),
                            String(d.plantCode.map(String.init) ?? "—"), mono: true)
                        Row(Loc.t("Серийный номер кузова", "Serial number"), d.serial, mono: true)
                        if let valid = d.checksumValid, d.checksumMandatory {
                            Row(Loc.t("Контрольный разряд VIN", "VIN check digit"),
                                valid ? Loc.t("сходится", "valid") : Loc.t("не сходится", "invalid"))
                        }
                    }

                    modelLookup

                    ForEach(Array(report.identity.calibrationIDs.enumerated()), id: \.offset) { i, cal in
                        Row(Loc.t("Версия прошивки \(i + 1)", "Calibration ID \(i + 1)"), cal, mono: true)
                    }
                    ForEach(Array(report.identity.calibrationVerification.enumerated()), id: \.offset) { i, cvn in
                        Row(Loc.t("Контрольная сумма прошивки \(i + 1)", "Calibration verification \(i + 1)"),
                            cvn, mono: true)
                    }
                    if let ecu = report.identity.ecuName {
                        Row(Loc.t("Блок управления", "ECU name"), ecu)
                    }
                    if let a = report.adapter {
                        Row(Loc.t("Адаптер", "Adapter"), a.identity)
                        Row(Loc.t("Протокол", "Protocol"), a.protocolName)
                    }
                    Row(Loc.t("Канал", "Channel"), report.channel)
                    if let v = report.batteryVoltage {
                        Row(Loc.t("Напряжение бортсети", "System voltage"),
                            String(format: "%.2f %@", v, Loc.t("В", "V")))
                    }
                }
            }
        }
    }

    private func yearText(_ d: VINDetails) -> String {
        guard let y = d.year else { return "—" }
        if let alt = d.yearAlternative {
            return "\(y) (\(Loc.t("или", "or")) \(alt))"
        }
        return String(y)
    }

    /// Модель, двигатель и коробка — только из внешней базы, нужен интернет.
    @ViewBuilder private var modelLookup: some View {
        if report.identity.vin != nil {
            Divider().padding(.vertical, 3)

            if let n = report.nhtsa, !n.isEmpty {
                if let v = n.make { Row(Loc.t("Марка", "Make"), v) }
                if let v = n.model { Row(Loc.t("Модель", "Model"), v) }
                if let v = n.series { Row(Loc.t("Серия / поколение", "Series"), v) }
                if let v = n.trim { Row(Loc.t("Комплектация", "Trim"), v) }
                if let v = n.bodyClass { Row(Loc.t("Тип кузова", "Body class"), v) }
                if let v = n.transmissionHuman {
                    Row(Loc.t("Коробка передач", "Transmission"), v)
                }
                if let v = n.driveType { Row(Loc.t("Привод", "Drive type"), v) }
                if let v = n.displacementL { Row(Loc.t("Объём двигателя", "Displacement"), v + " л") }
                if let v = n.engineCylinders { Row(Loc.t("Цилиндров", "Cylinders"), v) }
                if let v = n.engineModel { Row(Loc.t("Модель двигателя", "Engine model"), v) }
                if let v = n.fuelType { Row(Loc.t("Топливо", "Fuel"), v) }
                if let v = n.plantCity, let c = n.plantCountry {
                    Row(Loc.t("Завод", "Plant"), "\(v), \(c)")
                } else if let c = n.plantCountry {
                    Row(Loc.t("Завод", "Plant"), c)
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await session.lookupVehicleModel() }
                    } label: {
                        if session.isLookingUpVIN {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.small)
                                Text(Loc.t("Запрашиваем…", "Looking up…"))
                            }
                        } else {
                            Label(Loc.t("Определить модель, двигатель и коробку",
                                        "Look up model, engine and transmission"),
                                  systemImage: "globe")
                        }
                    }
                    .disabled(session.isLookingUpVIN)
                    Spacer()
                }
                Text(Loc.t("Марки, модели и типа коробки в протоколе OBD-II нет — блок двигателя их не знает. Эти данные запрашиваются по VIN в открытой базе NHTSA, поэтому нужен интернет. При подключении к Wi-Fi-адаптеру интернета нет: нажмите кнопку после того, как отключитесь от сети адаптера.",
                           "Make, model and transmission type do not exist in the OBD-II protocol — the engine ECU has no idea about them. They are looked up by VIN in the open NHTSA database, so internet access is required. While connected to a Wi-Fi adapter there is no internet: press the button after leaving the adapter's network."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let e = session.vinLookupError {
                Text(e)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 3)
        }
    }

    // MARK: Ошибки

    @ViewBuilder private var dtcSection: some View {
        if !report.allDTCs.isEmpty {
            Section2(Loc.t("Коды ошибок", "Fault codes")) {
                VStack(spacing: 6) {
                    ForEach(report.allDTCs) { dtc in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(dtc.code)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Text(dtc.kind.title)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                Text(dtc.severity.title)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(dtc.title)
                                .font(.system(size: 12, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(dtc.explanation)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
        }
    }

    // MARK: Счётчики наработки

    @ViewBuilder private var performanceSection: some View {
        if let p = report.performance, !p.isEmpty {
            Section2(Loc.t("Счётчики наработки", "In-use performance counters")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Loc.t("Эти счётчики не стираются сканером и копятся всю жизнь машины.",
                               "These counters cannot be cleared with a scanner and accumulate over the vehicle's life."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let c = p.ignitionCycles {
                        Row(Loc.t("Запусков двигателя", "Engine starts"), "\(c)")
                    }
                    if let c = p.obdConditions {
                        Row(Loc.t("Циклов бортовой диагностики", "OBD monitoring cycles"), "\(c)")
                    }
                    if let odo = report.value(pid: 0xA6) {
                        Row(Loc.t("Одометр (из блока)", "Odometer (from ECU)"),
                            "\(Int(odo)) " + Loc.t("км", "km"))
                        if let avg = p.averageTripDistance(odometerKm: odo) {
                            Row(Loc.t("Средняя длина поездки", "Average trip length"),
                                String(format: "%.1f ", avg) + Loc.t("км", "km"))
                        }
                    }

                    if !p.counters.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text(Loc.t("Сколько раз каждый тест успел отработать / сколько раз были условия:",
                                   "How many times each test completed / how many times conditions occurred:"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(p.counters) { c in
                            HStack(alignment: .firstTextBaseline) {
                                Text(c.name).font(.system(size: 12))
                                Spacer(minLength: 12)
                                Text("\(c.completed) / \(c.conditions)")
                                    .font(.system(size: 12, design: .monospaced))
                                if let r = c.ratio {
                                    Text(String(format: "%.0f%%", r * 100))
                                        .font(.system(size: 10))
                                        .foregroundStyle(r < 0.1 ? Color.orange : Color.secondary)
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Мониторы

    @ViewBuilder private var readinessSection: some View {
        if let r = report.readiness {
            Section2(Loc.t("Готовность самодиагностики", "Readiness monitors")) {
                VStack(alignment: .leading, spacing: 6) {
                    Row(Loc.t("Лампа Check Engine", "Check Engine lamp"),
                        r.milOn ? Loc.t("горит", "on") : Loc.t("не горит", "off"))
                    Row(Loc.t("Ошибок в памяти по счётчику", "Fault count reported"), String(r.dtcCount))
                    Row(Loc.t("Тип двигателя", "Engine type"),
                        r.compressionIgnition ? Loc.t("дизель", "compression (diesel)")
                                              : Loc.t("бензин", "spark ignition"))
                    Divider().padding(.vertical, 2)
                    ForEach(r.supportedMonitors) { m in
                        HStack {
                            Image(systemName: m.complete ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                                .font(.system(size: 11))
                                .foregroundStyle(m.complete ? Color.green : Color.orange)
                            Text(m.name).font(.system(size: 12))
                            Spacer()
                            Text(m.complete ? Loc.t("пройден", "complete")
                                            : Loc.t("не завершён", "incomplete"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Стоп-кадр

    @ViewBuilder private var freezeFrameSection: some View {
        if !report.freezeFrame.isEmpty {
            Section2(Loc.t("Стоп-кадр неисправности", "Freeze frame")) {
                VStack(alignment: .leading, spacing: 5) {
                    if let code = report.freezeFrame.triggerCode {
                        Row(Loc.t("Сохранён по коду", "Stored for code"), code, mono: true)
                    }
                    Text(Loc.t("Условия работы двигателя в момент возникновения ошибки:",
                               "Engine conditions at the moment the fault occurred:"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(report.freezeFrame.entries) { e in
                        Row(e.name, e.display)
                    }
                }
            }
        }
    }

    // MARK: Бортовые тесты

    @ViewBuilder private var testsSection: some View {
        if !report.monitorTests.isEmpty {
            Section2(Loc.t("Результаты бортовых тестов (Mode 06)", "On-board test results (Mode 06)")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.t("Значения приводятся в единицах блока управления. Важен факт попадания в допуск и счётчики пропусков воспламенения.",
                               "Values are in ECU units. What matters is whether they fall within limits, plus the misfire counters."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    ForEach(report.monitorTests) { t in
                        HStack(spacing: 8) {
                            Image(systemName: t.isConcerning ? "exclamationmark.circle.fill"
                                                             : "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(t.isConcerning ? Color.orange : Color.green)
                            Text(t.name).font(.system(size: 12))
                            Spacer()
                            Text("\(t.value)")
                                .font(.system(size: 12, design: .monospaced))
                            Text(t.outcomeText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if t.outcome != .counter {
                                Text("[\(t.minLimit)…\(t.maxLimit)]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Отклонения от нормы

    @ViewBuilder private var deviationsSection: some View {
        if !report.deviations.isEmpty {
            Section2(Loc.t("Отклонения от нормы", "Out-of-range readings")) {
                VStack(spacing: 8) {
                    ForEach(report.deviations) { item in
                        deviationCard(item)
                    }
                }
            }
        }
    }

    private func deviationCard(_ item: PIDResult) -> some View {
        let a = item.assessment
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: a?.status.symbol ?? "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(item.display)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(a?.status.title ?? "")
                    .font(.system(size: 10))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
            }
            if let range = a?.rangeText {
                Text(Loc.t("Норма: \(range)", "Normal: \(range)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let meaning = a?.meaning {
                Text(meaning)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let check = a?.whatToCheck {
                Text(Loc.t("Что проверять: ", "What to check: ") + check)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.30)))
    }

    // MARK: Все параметры

    @ViewBuilder private var readingsSection: some View {
        if !report.readings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Loc.t("Показания датчиков", "Sensor readings"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle(isOn: $showExplanations) {
                        Text(Loc.t("Пояснения", "Explanations"))
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                Text(Loc.t("Включите «Пояснения», чтобы к каждому параметру появилось описание простыми словами и его нормальный диапазон.",
                           "Turn on Explanations to see a plain-language description and the normal range for every parameter."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PIDCategory.allCases, id: \.self) { cat in
                        let items = report.readings.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: showExplanations ? 8 : 4) {
                                Text(cat.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(items) { item in
                                    readingRow(item)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readingRow(_ item: PIDResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name).font(.system(size: 12))
                if let s = item.assessment?.status, s != .notApplicable {
                    Image(systemName: s.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(s.isDeviation ? Color.orange : Color.green.opacity(0.8))
                }
                Spacer(minLength: 12)
                Text(item.display)
                    .font(.system(size: 12, design: .monospaced))
                Text(String(format: "01%02X", item.pid))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }

            if showExplanations {
                if let about = item.about {
                    Text(about)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let a = item.assessment {
                    Text(Loc.t("Норма: \(a.rangeText) — сейчас \(a.status.title)",
                               "Normal: \(a.rangeText) — currently \(a.status.title)"))
                        .font(.system(size: 10))
                        .foregroundStyle(a.status.isDeviation ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let m = a.meaning, a.status.isDeviation {
                        Text(m)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        if !report.notes.isEmpty {
            Section2(Loc.t("Что прочитать не удалось", "What could not be read")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var logSection: some View {
        if !report.trafficLog.isEmpty {
            Section2(Loc.t("Журнал обмена с адаптером", "Adapter traffic log")) {
                DisclosureGroup(isExpanded: $showRawLog) {
                    ScrollView {
                        Text(report.trafficLog.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 260)
                } label: {
                    Text(Loc.t("Показать \(report.trafficLog.count) строк",
                               "Show \(report.trafficLog.count) lines"))
                        .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: - Мелкие переиспользуемые элементы

struct Section2<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Row: View {
    let label: String
    let value: String
    var mono: Bool = false

    init(_ label: String, _ value: String, mono: Bool = false) {
        self.label = label
        self.value = value
        self.mono = mono
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
