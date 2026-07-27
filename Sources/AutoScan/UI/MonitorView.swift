import SwiftUI
import Charts
import UniformTypeIdentifiers

struct MonitorView: View {
    @Binding var screen: RootView.Screen
    @EnvironmentObject private var session: VehicleSession

    @State private var interval: Double = 0.2
    @State private var windowSeconds: Double = 60
    @State private var showPicker = true
    @State private var exportError: String?

    var body: some View {
        HSplitView {
            picker
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            charts
                .frame(minWidth: 520, maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                if session.state == .monitoring {
                    Button {
                        session.stopMonitoring()
                    } label: {
                        Label(Loc.t("Стоп", "Stop"), systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        session.startMonitoring(interval: interval)
                    } label: {
                        Label(Loc.t("Старт", "Start"), systemImage: "play.fill")
                    }
                    .disabled(session.monitoredPIDs.isEmpty || session.state != .connected)
                }
                Button {
                    exportCSV()
                } label: {
                    Label(Loc.t("Выгрузить CSV", "Export CSV"), systemImage: "square.and.arrow.down")
                }
                .disabled(session.history.isEmpty)
            }
        }
    }

    // MARK: Выбор параметров

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Loc.t("Параметры", "Parameters"))
                    .font(.system(size: 13, weight: .semibold))

                if session.supportedPIDs.isEmpty {
                    Text(Loc.t("Список параметров появится после первой проверки автомобиля — приложение узнаёт, что именно поддерживает эта машина.",
                               "The parameter list appears after the first vehicle check — that is how the app learns what this car supports."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        Button(Loc.t("Основные", "Essentials")) { selectEssentials() }
                            .font(.system(size: 11))
                        Button(Loc.t("Снять всё", "Clear")) { session.monitoredPIDs = [] }
                            .font(.system(size: 11))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Loc.t("Интервал опроса", "Poll interval"))
                            .font(.system(size: 11))
                        Spacer()
                        Text(interval == 0 ? Loc.t("максимум", "max")
                                           : String(format: "%.0f мс", interval * 1000))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $interval, in: 0...1, step: 0.05)
                        .disabled(session.state == .monitoring)

                    HStack {
                        Text(Loc.t("Окно графика", "Chart window"))
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(windowSeconds)) \(Loc.t("с", "s"))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $windowSeconds, in: 10...300, step: 10)

                    if session.state == .monitoring {
                        Text(String(format: Loc.t("частота: %.1f выборок/с", "rate: %.1f samples/s"),
                                    session.samplesPerSecond))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(14)

            Divider()

            List {
                ForEach(PIDCategory.allCases, id: \.self) { cat in
                    let items = session.supportedPIDs
                        .compactMap { PIDTable.def(for: $0) }
                        .filter { $0.category == cat }
                    if !items.isEmpty {
                        Section(cat.title) {
                            ForEach(items) { def in
                                Toggle(isOn: Binding(
                                    get: { session.monitoredPIDs.contains(def.pid) },
                                    set: { on in
                                        if on { session.monitoredPIDs.insert(def.pid) }
                                        else { session.monitoredPIDs.remove(def.pid) }
                                    })) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(def.name).font(.system(size: 12))
                                            Text(def.code)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func selectEssentials() {
        let wanted: [UInt8] = [0x0C, 0x0D, 0x05, 0x0F, 0x04, 0x11, 0x10, 0x06, 0x07, 0x0B, 0x42, 0x0E]
        session.monitoredPIDs = Set(wanted.filter { session.supportedPIDs.contains($0) })
    }

    // MARK: Графики

    private var charts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if session.liveValues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text(Loc.t("Отметьте параметры слева и нажмите «Старт»",
                                   "Select parameters on the left and press Start"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    gauges
                    ForEach(session.liveValues) { lv in
                        if let points = session.history[lv.pid], points.count > 1 {
                            chartCard(for: lv, points: points)
                        }
                    }
                }

                if let e = exportError {
                    Text(e).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gauges: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            ForEach(session.liveValues) { lv in
                VStack(alignment: .leading, spacing: 3) {
                    Text(lv.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lv.display)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    private func chartCard(for lv: LiveValue, points: [ChartPoint]) -> some View {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        let visible = points.filter { $0.time >= cutoff }
        let def = PIDTable.def(for: lv.pid)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lv.name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(lv.display).font(.system(size: 12, design: .monospaced))
            }
            Chart(visible) { p in
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: yDomain(visible: visible, def: def))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            .frame(height: 140)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .controlBackgroundColor)))
    }

    /// Диапазон по фактическим данным, а не по теоретическому пределу PID —
    /// иначе график обортов в 0…8000 превращается в прямую линию.
    private func yDomain(visible: [ChartPoint], def: PIDDef?) -> ClosedRange<Double> {
        guard let lo = visible.map(\.value).min(),
              let hi = visible.map(\.value).max() else { return 0...1 }
        if lo == hi {
            let pad = max(abs(lo) * 0.1, 1)
            return (lo - pad)...(hi + pad)
        }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    // MARK: Экспорт

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "autoscan-log-\(Self.fileStamp.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.historyCSV().write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}
