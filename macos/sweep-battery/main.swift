// SweepBattery — menu bar battery levels for both halves of the Sweep (ZMK split).
//
// macOS shows only the first Battery Level characteristic of a keyboard (the left,
// central half). With CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY the left half
// also exposes the right half's level as a second characteristic; this app reads both
// over the connection macOS already has (no re-pairing) and shows "L 90% R 85%".

import Cocoa
import CoreBluetooth
import ServiceManagement

let keyboardName = "Sweep"
let batteryService = CBUUID(string: "180F")
let hidService = CBUUID(string: "1812")
let batteryLevelChar = CBUUID(string: "2A19")
let userDescription = CBUUID(string: CBUUIDCharacteristicUserDescriptionString)

final class Battery {
    let characteristic: CBCharacteristic
    var description: String?      // CUD; ZMK sets one on the proxied (peripheral) levels
    var descriptorsRead = false
    var level: Int?
    init(_ c: CBCharacteristic) { characteristic = c }
}

final class App: NSObject, NSApplicationDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    var statusItem: NSStatusItem!
    var central: CBCentralManager!
    var keyboard: CBPeripheral?
    var batteries: [Battery] = []
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        central = CBCentralManager(delegate: self, queue: nil)
        // Re-read every minute (ZMK also notifies on change); reconnect if the keyboard went away.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        render()
    }

    // MARK: Finding the keyboard

    func refresh() {
        guard central.state == .poweredOn else { return }
        if let k = keyboard, k.state == .connected {
            batteries.forEach { k.readValue(for: $0.characteristic) }
            return
        }
        let found = central.retrieveConnectedPeripherals(withServices: [batteryService, hidService])
            .first { $0.name == keyboardName }
        guard let k = found else {
            keyboard = nil
            batteries = []
            render()
            return
        }
        NSLog("SweepBattery: found \(k.identifier), connecting")
        keyboard = k
        k.delegate = self
        central.connect(k)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        NSLog("SweepBattery: Bluetooth state \(c.state.rawValue)")
        refresh()
        render()
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        batteries = []
        p.discoverServices([batteryService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        NSLog("SweepBattery: connect failed: \(String(describing: error))")
        keyboard = nil
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        keyboard = nil
        batteries = []
        render()
        // The keyboard may just be switching profiles; try again shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refresh() }
    }

    // MARK: Reading levels

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == batteryService {
            p.discoverCharacteristics([batteryLevelChar], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] where c.uuid == batteryLevelChar {
            guard !batteries.contains(where: { $0.characteristic === c }) else { continue }
            batteries.append(Battery(c))
            p.discoverDescriptors(for: c)
            p.readValue(for: c)
            if c.properties.contains(.notify) { p.setNotifyValue(true, for: c) }
        }
        render()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor c: CBCharacteristic, error: Error?) {
        guard let b = battery(for: c) else { return }
        let cud = c.descriptors?.first { $0.uuid == userDescription }
        if let d = cud { p.readValue(for: d) } else { b.descriptorsRead = true; render() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor d: CBDescriptor, error: Error?) {
        guard d.uuid == userDescription, let c = d.characteristic, let b = battery(for: c) else { return }
        b.description = (d.value as? String) ?? (d.value as? Data).flatMap { String(data: $0, encoding: .utf8) }
        b.descriptorsRead = true
        NSLog("SweepBattery: characteristic description \(b.description ?? "nil")")
        render()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let b = battery(for: c), let byte = c.value?.first else { return }
        b.level = Int(byte)
        render()
    }

    func battery(for c: CBCharacteristic) -> Battery? { batteries.first { $0.characteristic === c } }

    // MARK: UI

    /// Left = the level without a description (the central's own); right = proxied levels.
    /// Until descriptors are known, fall back to GATT order (central first).
    func labelled() -> [(String, Battery)] {
        let own = batteries.filter { $0.descriptorsRead && $0.description == nil }
        let proxied = batteries.filter { b in !own.contains { $0 === b } }
        let ordered = own.count == 1 ? own + proxied : batteries
        return ordered.enumerated().map { i, b in
            (i == 0 ? "L" : (ordered.count > 2 ? "R\(i)" : "R"), b)
        }
    }

    func render() {
        let pct: (Battery) -> String = { $0.level.map { "\($0)%" } ?? "…" }
        let items = labelled()
        let title: String
        if central?.state == .unauthorized {
            title = "⌨ no BT access"
        } else if keyboard == nil {
            title = "⌨ –"
        } else if items.isEmpty {
            title = "⌨ …"
        } else {
            title = "⌨ " + items.map { "\($0.0) \(pct($0.1))" }.joined(separator: " ")
        }
        statusItem.button?.title = title

        let menu = NSMenu()
        if keyboard == nil {
            menu.addItem(withTitle: "\(keyboardName) not connected", action: nil, keyEquivalent: "")
        }
        for (label, b) in items {
            let name = label == "L" ? "Left" : "Right" + label.dropFirst()
            menu.addItem(withTitle: "\(name): \(pct(b))", action: nil, keyEquivalent: "")
        }
        if keyboard != nil && items.count == 1 {
            menu.addItem(withTitle: "Right half not reported (firmware needs battery proxy)", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r").target = self
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func refreshClicked() { refresh() }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "Add SweepBattery manually in System Settings → General → Login Items."
            alert.runModal()
        }
        render()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
