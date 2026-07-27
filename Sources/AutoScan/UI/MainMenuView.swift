import SwiftUI

struct MainMenuView: View {
    @Binding var screen: RootView.Screen
    @EnvironmentObject private var session: VehicleSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("AutoScan")
                        .font(.system(size: 26, weight: .semibold))
                    Text(Loc.t("Диагностика автомобиля по OBD-II",
                               "OBD-II vehicle diagnostics"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                connectionCard

                VStack(spacing: 10) {
                    MenuButton(
                        icon: "checklist",
                        title: Loc.t("Проверка автомобиля", "Vehicle check"),
                        subtitle: Loc.t("Полный опрос всех доступных систем с расшифровкой",
                                        "Full sweep of every available system, explained"),
                        enabled: session.isConnected && !session.isBusy
                    ) { screen = .scan }

                    MenuButton(
                        icon: "waveform.path.ecg",
                        title: Loc.t("Мониторинг в реальном времени", "Live monitoring"),
                        subtitle: Loc.t("Графики и показания датчиков на ходу и на стоянке",
                                        "Charts and sensor readings, running or parked"),
                        enabled: session.isConnected && !session.isBusy
                    ) { screen = .monitor }

                    MenuButton(
                        icon: "doc.richtext",
                        title: Loc.t("Отчёт и экспорт", "Report and export"),
                        subtitle: Loc.t("Результаты проверки, PDF и CSV",
                                        "Scan results, PDF and CSV"),
                        enabled: session.report != nil
                    ) { screen = .report }
                }

                if let err = session.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if session.isConnected {
                    LabeledContent(Loc.t("Канал", "Channel"), value: session.channelDescription)
                    if let a = session.adapterInfo {
                        LabeledContent(Loc.t("Адаптер", "Adapter"), value: a.identity)
                        LabeledContent(Loc.t("Протокол", "Protocol"), value: a.protocolName)
                        if let v = a.voltage {
                            LabeledContent(Loc.t("Напряжение", "Voltage"),
                                           value: String(format: "%.1f %@", v, Loc.t("В", "V")))
                        }
                    }
                    HStack {
                        Button(Loc.t("Отключиться", "Disconnect")) { session.disconnect() }
                        Button(Loc.t("Сменить адаптер", "Change adapter")) {
                            session.disconnect()
                            screen = .connection
                        }
                    }
                    .padding(.top, 2)
                } else {
                    Text(Loc.t("Адаптер не подключён. Воткните разъём в машину, включите зажигание и выберите канал связи.",
                               "No adapter connected. Plug the dongle into the car, switch on the ignition and pick a channel."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        screen = .connection
                    } label: {
                        Label(Loc.t("Подключить адаптер", "Connect adapter"),
                              systemImage: "cable.connector")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(Loc.t("Подключение", "Connection"), systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 30)
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
