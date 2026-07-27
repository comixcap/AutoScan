import SwiftUI

@main
struct Entry {
    static func main() {
        // headless-режим: AutoScan --selftest tcp:127.0.0.1:35000
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest") {
            let target = (i + 1 < args.count) ? args[i + 1] : "tcp:127.0.0.1:35000"
            SelfTest.run(target: target)
        }
        AutoScanApp.main()
    }
}

struct AutoScanApp: App {
    @StateObject private var session = VehicleSession()
    @StateObject private var l10n = LocalizationStore()

    var body: some Scene {
        WindowGroup("AutoScan") {
            RootView()
                .environmentObject(session)
                .environmentObject(l10n)
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: VehicleSession
    @EnvironmentObject private var l10n: LocalizationStore
    @State private var screen: Screen = .menu

    enum Screen: Hashable {
        case menu, connection, scan, monitor, report
    }

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .menu:       MainMenuView(screen: $screen)
                case .connection: ConnectionView(screen: $screen)
                case .scan:       ScanView(screen: $screen)
                case .monitor:    MonitorView(screen: $screen)
                case .report:     ReportView(screen: $screen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if screen != .menu {
                        Button {
                            if session.state == .monitoring { session.stopMonitoring() }
                            screen = .menu
                        } label: {
                            Label(Loc.t("Меню", "Menu"), systemImage: "chevron.left")
                        }
                        .disabled(session.isBusy)
                    }
                }
                ToolbarItem(placement: .principal) {
                    ConnectionBadge()
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("", selection: $l10n.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang == .ru ? "RU" : "EN").tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 96)
                }
            }
        }
        // смена языка перерисовывает всё дерево
        .id(l10n.language)
    }
}

/// Компактный индикатор состояния связи в тулбаре.
struct ConnectionBadge: View {
    @EnvironmentObject private var session: VehicleSession

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .help(session.channelDescription)
    }

    private var color: Color {
        switch session.state {
        case .disconnected: return .secondary
        case .connecting:   return .orange
        case .connected:    return .green
        case .scanning:     return .blue
        case .monitoring:   return .blue
        }
    }

    private var label: String {
        switch session.state {
        case .disconnected: return Loc.t("Нет связи", "Disconnected")
        case .connecting:   return Loc.t("Подключение…", "Connecting…")
        case .connected:    return session.channelDescription
        case .scanning:     return Loc.t("Проверка…", "Scanning…")
        case .monitoring:   return Loc.t("Мониторинг", "Monitoring")
        }
    }
}
