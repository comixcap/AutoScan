import Foundation
import CoreBluetooth

/// Известные сервисы BLE-адаптеров ELM327.
enum BLEIDs {
    static let candidateServices: [CBUUID] = [
        CBUUID(string: "FFF0"),   // самый распространённый (Vgate, Konnwei)
        CBUUID(string: "FFE0"),   // HM-10 и клоны
        CBUUID(string: "18F0"),   // Viecar / некоторые OBDLink
        CBUUID(string: "FFF1"),
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2") // LELink
    ]

    /// Слова в имени устройства, по которым узнаём OBD-адаптер.
    static let nameHints = ["OBD", "ELM", "VGATE", "VEEPEAK", "LELINK",
                            "KONNWEI", "VIECAR", "CARISTA", "OBDLINK", "IOS-VLINK"]
}

/// Найденное в эфире BLE-устройство.
struct BLEDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let looksLikeOBD: Bool
}

// MARK: - Сканер эфира (для списка в UI)

@MainActor
final class BLEScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false

    private var central: CBCentralManager?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    func stop() {
        central?.stopScan()
        isScanning = false
    }

    private func beginScan() {
        devices.removeAll()
        // nil = все устройства: многие клоны не публикуют сервис в рекламе
        central?.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    var stateText: String {
        switch state {
        case .poweredOn:   return Loc.t("Bluetooth включён", "Bluetooth on")
        case .poweredOff:  return Loc.t("Bluetooth выключен", "Bluetooth off")
        case .unauthorized:return Loc.t("Нет разрешения на Bluetooth", "Bluetooth not authorized")
        case .unsupported: return Loc.t("Bluetooth не поддерживается", "Bluetooth unsupported")
        case .resetting:   return Loc.t("Bluetooth перезапускается", "Bluetooth resetting")
        default:           return Loc.t("Состояние Bluetooth неизвестно", "Bluetooth state unknown")
        }
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        Task { @MainActor in
            self.state = s
            if s == .poweredOn { self.beginScan() } else { self.isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "—"
        let upper = name.uppercased()
        let hinted = BLEIDs.nameHints.contains { upper.contains($0) }

        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let serviceMatch = advServices.contains { BLEIDs.candidateServices.contains($0) }

        let dev = BLEDevice(id: peripheral.identifier,
                            name: name,
                            rssi: RSSI.intValue,
                            looksLikeOBD: hinted || serviceMatch)

        Task { @MainActor in
            guard dev.name != "—" || dev.looksLikeOBD else { return }
            if let idx = self.devices.firstIndex(where: { $0.id == dev.id }) {
                self.devices[idx] = dev
            } else {
                self.devices.append(dev)
            }
            self.devices.sort {
                if $0.looksLikeOBD != $1.looksLikeOBD { return $0.looksLikeOBD }
                return $0.rssi > $1.rssi
            }
        }
    }
}

// MARK: - Транспорт поверх BLE

final class BLETransport: NSObject, Transport, @unchecked Sendable {
    private let targetID: UUID?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private let rx = RXBuffer()
    private let queue = DispatchQueue(label: "AutoScan.BLE")

    private var openContinuation: CheckedContinuation<Void, Error>?
    private let contLock = NSLock()
    private var deviceName = "BLE"

    var descriptionText: String { "BLE \(deviceName)" }
    var isOpen: Bool { writeChar != nil && notifyChar != nil }

    /// - Parameter deviceID: конкретное устройство; nil — взять первое похожее на OBD.
    init(deviceID: UUID?) {
        self.targetID = deviceID
        super.init()
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            contLock.lock()
            openContinuation = cont
            contLock.unlock()
            central = CBCentralManager(delegate: self, queue: queue)

            // страховка от зависания: BLE может молчать бесконечно
            queue.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.finishOpen(.failure(TransportError.bleNotFound))
            }
        }
    }

    private func finishOpen(_ result: Result<Void, Error>) {
        contLock.lock()
        let cont = openContinuation
        openContinuation = nil
        contLock.unlock()
        guard let cont else { return }
        switch result {
        case .success:      cont.resume()
        case .failure(let e):
            central?.stopScan()
            cont.resume(throwing: e)
        }
    }

    func write(_ data: Data) throws {
        guard let p = peripheral, let ch = writeChar else { throw TransportError.notConnected }
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        // BLE-пакет ограничен MTU, режем на куски
        let limit = max(20, p.maximumWriteValueLength(for: type))
        var offset = 0
        while offset < data.count {
            let end = min(offset + limit, data.count)
            p.writeValue(data.subdata(in: offset..<end), for: ch, type: type)
            offset = end
        }
    }

    func readAvailable() -> Data { rx.drain() }

    func close() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        rx.clear()
    }
}

extension BLETransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let id = targetID,
               let known = central.retrievePeripherals(withIdentifiers: [id]).first {
                peripheral = known
                known.delegate = self
                deviceName = known.name ?? "BLE"
                central.connect(known)
            } else {
                central.scanForPeripherals(withServices: nil)
            }
        case .poweredOff:
            finishOpen(.failure(TransportError.bleUnavailable("выключен")))
        case .unauthorized:
            finishOpen(.failure(TransportError.bleUnavailable("нет разрешения в системных настройках")))
        case .unsupported:
            finishOpen(.failure(TransportError.bleUnavailable("не поддерживается")))
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let id = targetID {
            guard peripheral.identifier == id else { return }
        } else {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String
                        ?? peripheral.name ?? "").uppercased()
            let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let looksRight = BLEIDs.nameHints.contains { name.contains($0) }
                || advServices.contains { BLEIDs.candidateServices.contains($0) }
            guard looksRight else { return }
        }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        deviceName = peripheral.name ?? "BLE"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        finishOpen(.failure(TransportError.openFailed(error?.localizedDescription ?? "connect failed")))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            finishOpen(.failure(TransportError.bleNoCharacteristics)); return
        }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }

        for ch in chars {
            if writeChar == nil,
               ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                writeChar = ch
            }
            if notifyChar == nil, ch.properties.contains(.notify) {
                notifyChar = ch
                peripheral.setNotifyValue(true, for: ch)
            }
        }

        if writeChar != nil && notifyChar != nil {
            finishOpen(.success(()))
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, !value.isEmpty else { return }
        rx.append(value)
    }
}
