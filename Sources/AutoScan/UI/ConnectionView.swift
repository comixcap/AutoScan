import SwiftUI
import CoreBluetooth

struct ConnectionView: View {
    @Binding var screen: RootView.Screen
    @EnvironmentObject private var session: VehicleSession
    @StateObject private var ble = BLEScanner()

    @State private var wifiHost = UserDefaults.standard.string(forKey: "autoscan_host") ?? "192.168.0.10"
    @State private var wifiPort = UserDefaults.standard.string(forKey: "autoscan_port") ?? "35000"
    @State private var serialPorts: [String] = []
    @State private var selectedPort: String?
    @State private var tab: Tab = .wifi

    enum Tab: String, CaseIterable {
        case wifi, serial, bluetooth

        var title: String {
            switch self {
            case .wifi:      return Loc.t("Wi-Fi", "Wi-Fi")
            case .serial:    return Loc.t("USB / порт", "USB / port")
            case .bluetooth: return Loc.t("Bluetooth LE", "Bluetooth LE")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(Loc.t("Подключение адаптера", "Connect adapter"))
                    .font(.system(size: 20, weight: .semibold))

                Text(Loc.t("Воткните адаптер в разъём OBD-II под рулём и включите зажигание. Затем выберите способ связи.",
                           "Plug the adapter into the OBD-II socket under the dash and switch on the ignition. Then pick a channel."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .wifi:      wifiSection
                case .serial:    serialSection
                case .bluetooth: bluetoothSection
                }

                if let err = session.lastError {
                    GroupBox {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                helpBox
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            serialPorts = SerialTransport.availablePorts()
            selectedPort = serialPorts.first { $0.lowercased().contains("obd") } ?? serialPorts.first
        }
        .onChange(of: session.state) { _, new in
            if new == .connected { screen = .menu }
        }
    }

    // MARK: Wi-Fi

    private var wifiSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.t("Подключитесь к Wi-Fi-сети адаптера в системных настройках, затем нажмите «Подключиться». Стандартный адрес большинства донглов уже подставлен.",
                           "Join the adapter's Wi-Fi network in System Settings, then press Connect. The default address of most dongles is pre-filled."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    TextField(Loc.t("Адрес", "Host"), text: $wifiHost)
                        .frame(width: 180)
                    TextField(Loc.t("Порт", "Port"), text: $wifiPort)
                        .frame(width: 80)
                }
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        Button(preset.0) {
                            wifiHost = preset.1
                            wifiPort = preset.2
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }

                Button {
                    UserDefaults.standard.set(wifiHost, forKey: "autoscan_host")
                    UserDefaults.standard.set(wifiPort, forKey: "autoscan_port")
                    Task {
                        await session.connect(to: .wifi(host: wifiHost,
                                                        port: Int(wifiPort) ?? 35000))
                    }
                } label: {
                    if session.state == .connecting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(Loc.t("Подключение…", "Connecting…"))
                        }
                    } else {
                        Text(Loc.t("Подключиться", "Connect"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.state == .connecting || wifiHost.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var presets: [(String, String, String)] {
        [("192.168.0.10:35000", "192.168.0.10", "35000"),
         ("192.168.4.1:35000", "192.168.4.1", "35000"),
         ("192.168.1.5:35000", "192.168.1.5", "35000"),
         (Loc.t("Эмулятор", "Emulator"), "127.0.0.1", "35000")]
    }

    // MARK: Последовательный порт

    private var serialSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.t("USB-адаптеры и классические Bluetooth-адаптеры, спаренные в системных настройках, появляются здесь как порт.",
                           "USB adapters and classic Bluetooth adapters paired in System Settings appear here as a port."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if serialPorts.isEmpty {
                    Text(Loc.t("Портов не найдено.", "No ports found."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(Loc.t("Порт", "Port"), selection: $selectedPort) {
                        ForEach(serialPorts, id: \.self) { p in
                            Text((p as NSString).lastPathComponent).tag(Optional(p))
                        }
                    }
                    .frame(maxWidth: 420)
                }

                HStack {
                    Button(Loc.t("Обновить список", "Refresh")) {
                        serialPorts = SerialTransport.availablePorts()
                    }
                    Button {
                        if let p = selectedPort {
                            Task { await session.connect(to: .serial(path: p)) }
                        }
                    } label: {
                        if session.state == .connecting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(Loc.t("Подключение…", "Connecting…"))
                            }
                        } else {
                            Text(Loc.t("Подключиться", "Connect"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPort == nil || session.state == .connecting)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: BLE

    private var bluetoothSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ble.stateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if ble.isScanning {
                        ProgressView().controlSize(.small)
                    }
                    Button(Loc.t("Искать", "Scan")) { ble.start() }
                        .font(.system(size: 11))
                }

                if ble.devices.isEmpty {
                    Text(Loc.t("Устройств пока не найдено. Адаптер должен быть запитан — включите зажигание.",
                               "No devices yet. The adapter needs power — switch on the ignition."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(ble.devices) { dev in
                        HStack {
                            Image(systemName: dev.looksLikeOBD
                                  ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                                .foregroundStyle(dev.looksLikeOBD ? Color.accentColor : Color.secondary)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.name).font(.system(size: 12, weight: .medium))
                                Text("RSSI \(dev.rssi) dBm")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(Loc.t("Подключиться", "Connect")) {
                                ble.stop()
                                Task { await session.connect(to: .ble(uuid: dev.id)) }
                            }
                            .font(.system(size: 11))
                            .disabled(session.state == .connecting)
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .onAppear { ble.start() }
        .onDisappear { ble.stop() }
    }

    private var helpBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(Loc.t("Если связи нет", "If it doesn't connect"))
                    .font(.system(size: 12, weight: .semibold))
                ForEach(hints, id: \.self) { hint in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var hints: [String] {
        [Loc.t("Зажигание должно быть включено — без него блоки не отвечают.",
               "The ignition must be on — the modules stay silent otherwise."),
         Loc.t("Wi-Fi-адаптер поднимает собственную сеть: подключитесь к ней в системных настройках, интернет при этом пропадёт.",
               "A Wi-Fi adapter creates its own network: join it in System Settings; internet access will drop while connected."),
         Loc.t("Классический Bluetooth-адаптер сначала нужно спарить в системных настройках, потом он появится во вкладке «USB / порт».",
               "A classic Bluetooth adapter must be paired in System Settings first, then it shows up under 'USB / port'."),
         Loc.t("Дешёвые клоны ELM327 часто теряют кадры и не отвечают на часть запросов — это ограничение железа, а не программы.",
               "Cheap ELM327 clones frequently drop frames and ignore some requests — a hardware limitation, not a software one.")]
    }
}
