import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ReportView: View {
    @Binding var screen: RootView.Screen
    @EnvironmentObject private var session: VehicleSession

    @State private var status: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(Loc.t("Отчёт и экспорт", "Report and export"))
                    .font(.system(size: 20, weight: .semibold))

                if let r = session.report {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Row(Loc.t("Проверка выполнена", "Scan performed"),
                                PDFReport.stamp.string(from: r.startedAt))
                            Row(Loc.t("Длительность", "Duration"),
                                "\(Int(r.duration)) \(Loc.t("с", "s"))")
                            if let vin = r.identity.vin { Row("VIN", vin, mono: true) }
                            Row(Loc.t("Найдено ошибок", "Faults found"),
                                "\(r.allDTCs.count)")
                            Row(Loc.t("Прочитано параметров", "Parameters read"),
                                "\(r.readings.count)")
                            Row(Loc.t("Строк в журнале обмена", "Traffic log lines"),
                                "\(r.trafficLog.count)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        exportButton(
                            icon: "doc.richtext",
                            title: Loc.t("Сохранить PDF-отчёт", "Save PDF report"),
                            subtitle: Loc.t("Полный отчёт со всеми расшифровками — это файл, который можно переслать",
                                            "The full report with all explanations — a file you can send on"),
                            action: exportPDF)

                        exportButton(
                            icon: "tablecells",
                            title: Loc.t("Сохранить показания в CSV", "Save readings as CSV"),
                            subtitle: Loc.t("Таблица всех прочитанных параметров",
                                            "A table of every parameter that was read"),
                            action: exportReadingsCSV)

                        exportButton(
                            icon: "text.alignleft",
                            title: Loc.t("Сохранить журнал обмена", "Save adapter traffic log"),
                            subtitle: Loc.t("Сырой лог всех команд и ответов — для разбора спорных случаев",
                                            "Raw log of every command and reply — for troubleshooting"),
                            action: exportLog)
                    }

                    if let s = status {
                        Label(s, systemImage: isError ? "exclamationmark.triangle.fill"
                                                      : "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isError ? Color.orange : Color.green)
                            .textSelection(.enabled)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Loc.t("Что входит в отчёт", "What the report contains"))
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(contents, id: \.self) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(line)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                } else {
                    Text(Loc.t("Отчёта пока нет — сначала выполните проверку автомобиля.",
                               "No report yet — run a vehicle check first."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contents: [String] {
        [Loc.t("общий вывод и все замечания с объяснением простым языком",
               "the overall verdict and every finding explained in plain language"),
         Loc.t("коды ошибок трёх типов: подтверждённые, ожидающие и постоянные",
               "fault codes of all three kinds: confirmed, pending and permanent"),
         Loc.t("статус мониторов готовности — стирали ли ошибки перед проверкой",
               "readiness monitor status — whether codes were cleared before the scan"),
         Loc.t("стоп-кадр: что происходило с двигателем в момент неисправности",
               "the freeze frame: what the engine was doing when the fault occurred"),
         Loc.t("VIN, версия прошивки блока и её контрольная сумма",
               "VIN, ECU calibration version and its checksum"),
         Loc.t("показания всех датчиков, которые машина отдала",
               "readings from every sensor the car reported")]
    }

    private func exportButton(icon: String, title: String, subtitle: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(width: 26)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Действия

    private func save(suggested: String, type: UTType, write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggested
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(url)
            status = Loc.t("Сохранено: \(url.path)", "Saved: \(url.path)")
            isError = false
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }

    private var baseName: String {
        let vin = session.report?.identity.vin
        let stamp = MonitorView.fileStamp.string(from: session.report?.startedAt ?? Date())
        return "autoscan-\(vin ?? "report")-\(stamp)"
    }

    private func exportPDF() {
        guard let r = session.report else { return }
        save(suggested: baseName + ".pdf", type: .pdf) { url in
            try PDFReport.write(report: r, findings: session.findings, to: url)
        }
    }

    private func exportReadingsCSV() {
        guard let r = session.report else { return }
        save(suggested: baseName + ".csv", type: .commaSeparatedText) { url in
            var rows = ["pid,parameter,category,value,raw"]
            for i in r.readings {
                rows.append("\(String(format: "01%02X", i.pid)),\"\(i.name)\",\"\(i.category.title)\",\"\(i.display)\",\"\(i.rawHex)\"")
            }
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportLog() {
        guard let r = session.report else { return }
        save(suggested: baseName + "-traffic.txt", type: .plainText) { url in
            try r.trafficLog.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
