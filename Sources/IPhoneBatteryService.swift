import Foundation
import Combine
import Darwin

enum IPhoneTransport: Int32, CaseIterable {
    case usb = 1, wifi = 2
    var label: String { self == .usb ? "USB" : "Wi-Fi" }
    var symbol: String { self == .usb ? "cable.connector" : "wifi" }
}

struct IPhoneConnectionKey: Hashable {
    let deviceID: String
    let transport: IPhoneTransport
}

/// A phone can advertise two independent connections. Removal applies only to that exact connection.
struct IPhoneConnections<Value> {
    private var entries: [IPhoneConnectionKey: (token: UInt, value: Value)] = [:]
    var deviceIDs: Set<String> { Set(entries.keys.map(\.deviceID)) }

    mutating func insert(_ value: Value, id: String, transport: IPhoneTransport, token: UInt) {
        entries[IPhoneConnectionKey(deviceID: id, transport: transport)] = (token, value)
    }

    @discardableResult mutating func remove(token: UInt) -> Set<String> {
        let removed = entries.filter { $0.value.token == token }.map(\.key)
        for key in removed { entries.removeValue(forKey: key) }
        return Set(removed.map(\.deviceID))
    }

    func candidates(for id: String) -> [(IPhoneConnectionKey, Value)] {
        IPhoneTransport.allCases.compactMap { transport in
            let key = IPhoneConnectionKey(deviceID: id, transport: transport)
            return entries[key].map { (key, $0.value) }
        }
    }
}

struct IPhoneReading: Identifiable, Equatable {
    enum State: Equatable { case ready, needsTrust, unavailable }
    let id: String
    var name: String
    var battery: BatteryReading?
    var state: State
    var sampledAt = Date()
    var transport: IPhoneTransport = .usb

    var status: String {
        switch state {
        case .ready: return battery?.status ?? "Sin lectura"
        case .needsTrust: return transport == .wifi ? "Conecta por USB y autoriza" : "Desbloquea y confía en el Mac"
        case .unavailable: return transport == .wifi ? "Sin respuesta por Wi-Fi" : "Desbloquea para actualizar"
        }
    }

    static func battery(from values: [String: Any]) -> BatteryReading? {
        guard let number = values["BatteryCurrentCapacity"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (0...100).contains(number.doubleValue) else { return nil }
        return BatteryReading(percent: Int(number.doubleValue.rounded()),
                              charging: values["BatteryIsCharging"] as? Bool ?? false,
                              pluggedIn: values["ExternalConnected"] as? Bool ?? false)
    }
}

@MainActor
final class IPhoneBatteryService: ObservableObject {
    @Published private(set) var devices: [IPhoneReading] = []
    @Published private(set) var available = true
    private var worker: IPhoneBatteryWorker?
    private var generation = 0

    func start() {
        guard worker == nil else { return }
        generation += 1
        let currentGeneration = generation
        let worker = IPhoneBatteryWorker { [weak self] readings, available in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.apply(readings, available: available)
            }
        }
        self.worker = worker
        worker.start()
    }

    func refresh() { worker?.refreshSoon() }
    func stop() { generation += 1; worker?.stop(); worker = nil }

    // A failed sample never inherits the previous percentage. Disconnects remove the device.
    func apply(_ readings: [IPhoneReading], available: Bool = true) {
        self.available = available
        devices = readings.sorted { $0.id < $1.id }
    }

    func expire(at now: Date = Date()) {
        devices = devices.map { reading in
            guard reading.state == .ready, now.timeIntervalSince(reading.sampledAt) > 45 else { return reading }
            var expired = reading
            expired.battery = nil
            expired.state = .unavailable
            return expired
        }
    }
}

/// Only name/class and battery values are read. Pairing is handled by Finder/iOS, never initiated here.
/// MobileDevice is a system-private framework; optional symbol loading keeps the rest of ISLA usable if it changes.
private final class MobileDeviceAPI {
    typealias Action = @convention(c) (UnsafeRawPointer?) -> Int32
    typealias CopyValue = @convention(c) (UnsafeRawPointer?, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    typealias CopyID = @convention(c) (UnsafeRawPointer?) -> Unmanaged<CFString>?
    typealias Callback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Subscribe = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias SubscribeOptions = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>, CFDictionary?) -> Int32
    typealias Unsubscribe = @convention(c) (UnsafeMutableRawPointer?) -> Int32

    let handle: UnsafeMutableRawPointer
    let connect, disconnect, isPaired, validate, startSession, stopSession, interface: Action
    let copyValue: CopyValue
    let copyID: CopyID
    let subscribe: Subscribe
    let subscribeOptions: SubscribeOptions?
    let unsubscribe: Unsubscribe

    init?() {
        let paths = ["/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
                     "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"]
        guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }).first else { return nil }
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let connect = load("AMDeviceConnect", Action.self), let disconnect = load("AMDeviceDisconnect", Action.self),
              let paired = load("AMDeviceIsPaired", Action.self), let validate = load("AMDeviceValidatePairing", Action.self),
              let start = load("AMDeviceStartSession", Action.self), let stop = load("AMDeviceStopSession", Action.self),
              let interface = load("AMDeviceGetInterfaceType", Action.self), let value = load("AMDeviceCopyValue", CopyValue.self),
              let identifier = load("AMDeviceCopyDeviceIdentifier", CopyID.self),
              let subscribe = load("AMDeviceNotificationSubscribe", Subscribe.self),
              let unsubscribe = load("AMDeviceNotificationUnsubscribe", Unsubscribe.self) else {
            dlclose(handle); return nil
        }
        self.handle = handle
        self.connect = connect; self.disconnect = disconnect; self.isPaired = paired; self.validate = validate
        self.startSession = start; self.stopSession = stop; self.interface = interface
        self.copyValue = value; self.copyID = identifier; self.subscribe = subscribe; self.unsubscribe = unsubscribe
        self.subscribeOptions = load("AMDeviceNotificationSubscribeWithOptions", SubscribeOptions.self)
    }

    // Kept loaded while the process is alive: framework callbacks may outlive unsubscription.
    func value(_ device: UnsafeRawPointer, domain: String? = nil, key: String) -> CFTypeRef? {
        copyValue(device, domain.map { $0 as CFString }, key as CFString)?.takeRetainedValue()
    }
}

/// All device/session operations run serially on a dedicated run loop, never on the UI thread.
private final class IPhoneBatteryWorker {
    private let publish: ([IPhoneReading], Bool) -> Void
    private let lock = NSLock()
    private var loop: CFRunLoop?
    private var stopping = false
    private var api: MobileDeviceAPI?
    private var subscription: UnsafeMutableRawPointer?
    private var devices = IPhoneConnections<CFTypeRef>()
    private var readings: [String: IPhoneReading] = [:]
    private var lastPoll = Date.distantPast

    init(publish: @escaping ([IPhoneReading], Bool) -> Void) { self.publish = publish }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "ISLA iPhone battery"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func run() {
        guard let api = MobileDeviceAPI() else { publish([], false); return }
        self.api = api
        let currentLoop = CFRunLoopGetCurrent()!
        lock.lock(); loop = currentLoop; let alreadyStopped = stopping; lock.unlock()
        guard !alreadyStopped else { return }
        let callback: MobileDeviceAPI.Callback = { info, context in
            guard let info, let context, let device = info.load(as: UnsafeRawPointer?.self) else { return }
            let message = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
            Unmanaged<IPhoneBatteryWorker>.fromOpaque(context).takeUnretainedValue().event(device, message: message)
        }
        publish([], true)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let options = ["NotificationOptionSearchForPairedDevices": true,
                       "NotificationOptionSearchForPairedDevicesViaDirectConnectionsOnly": false,
                       "NotificationOptionEnableUSBMux": true,
                       "NotificationOptionSearchForWiFiPairableDevices": false] as CFDictionary
        let result = api.subscribeOptions?(callback, 0, 0, context, &subscription, options)
            ?? api.subscribe(callback, 0, 0, context, &subscription)
        guard result == 0 else {
            publish([], false); return
        }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.current.add(timer, forMode: .default)
        lock.lock(); let shouldRun = !stopping; lock.unlock()
        if shouldRun { CFRunLoopRun() }
        timer.invalidate()
        _ = api.unsubscribe(subscription)
        devices = IPhoneConnections()
        lock.lock(); loop = nil; lock.unlock()
    }

    func refreshSoon() {
        lock.lock(); let target = loop; let stopped = stopping; lock.unlock()
        guard let target, !stopped else { return }
        CFRunLoopPerformBlock(target, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.poll() }
        CFRunLoopWakeUp(target)
    }

    func stop() {
        lock.lock(); stopping = true; let target = loop; lock.unlock()
        if let target { CFRunLoopStop(target); CFRunLoopWakeUp(target) }
    }

    private func event(_ device: UnsafeRawPointer, message: UInt32) {
        guard let api else { return }
        let token = UInt(bitPattern: device)
        if message == 2 {
            let affected = devices.remove(token: token)
            for identifier in affected {
                // Clear the old sample immediately; the surviving connection must supply its own reading.
                readings.removeValue(forKey: identifier)
                if let first = devices.candidates(for: identifier).first {
                    readings[identifier] = IPhoneReading(id: identifier, name: "iPhone", battery: nil,
                                                        state: .unavailable, transport: first.0.transport)
                }
            }
            guard !affected.isEmpty else { return }
            publish(Array(readings.values), true)
            lastPoll = .distantPast
            poll()
        } else if message == 1, let transport = IPhoneTransport(rawValue: api.interface(device)),
                  let identifier = api.copyID(device)?.takeRetainedValue() as String? {
            let retained = Unmanaged<CFTypeRef>.fromOpaque(device).retain().takeRetainedValue()
            devices.insert(retained, id: identifier, transport: transport, token: token)
            lastPoll = .distantPast
            poll()
        }
    }

    private func poll() {
        guard let api, Date().timeIntervalSince(lastPoll) >= 1 else { return }
        lastPoll = Date()
        for id in devices.deviceIDs {
            var result: IPhoneReading?
            // Prefer USB; if it fails, try the authorized Wi-Fi connection for the same phone.
            for (key, retained) in devices.candidates(for: id) {
                let device = UnsafeRawPointer(Unmanaged.passUnretained(retained).toOpaque())
                let candidate = read(device, id: id, transport: key.transport, api: api)
                if result == nil { result = candidate }
                if candidate?.state == .ready { result = candidate; break }
            }
            readings[id] = result
        }
        publish(Array(readings.values), true)
    }

    private func read(_ device: UnsafeRawPointer, id: String, transport: IPhoneTransport, api: MobileDeviceAPI) -> IPhoneReading? {
        let previousName = readings[id]?.name ?? "Dispositivo iOS"
        var reading = IPhoneReading(id: id, name: previousName, battery: nil, state: .unavailable, transport: transport)
        guard api.connect(device) == 0 else { return reading }
        defer { _ = api.disconnect(device) }
        if let deviceClass = api.value(device, key: "DeviceClass") as? String, deviceClass != "iPhone" { return nil }
        if let name = api.value(device, key: "DeviceName") as? String, !name.isEmpty { reading.name = name }
        guard api.isPaired(device) == 1, api.validate(device) == 0 else { reading.state = .needsTrust; return reading }
        guard api.startSession(device) == 0 else { return reading }
        defer { _ = api.stopSession(device) }
        guard let deviceClass = api.value(device, key: "DeviceClass") as? String, deviceClass == "iPhone" else { return nil }
        var values: [String: Any] = [:]
        for key in ["BatteryCurrentCapacity", "BatteryIsCharging", "ExternalConnected"] {
            values[key] = api.value(device, domain: "com.apple.mobile.battery", key: key)
        }
        guard let battery = IPhoneReading.battery(from: values) else { return reading }
        reading.battery = battery
        reading.state = .ready
        reading.sampledAt = Date()
        return reading
    }
}
