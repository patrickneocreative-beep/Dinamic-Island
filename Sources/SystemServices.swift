import AppKit
import CoreAudio
import IOKit.ps

struct BatteryReading: Equatable {
    var percent: Int?
    var charging = false
    var pluggedIn = false

    var fraction: Double { Double(percent ?? 0) / 100 }
    var status: String {
        guard let percent else { return "Sin lectura" }
        if charging { return "Cargando" }
        if pluggedIn { return percent >= 100 ? "Carga completa" : "Conectado · sin cargar" }
        return "Con batería"
    }

    static func percentage(current: Double, maximum: Double) -> Int? {
        guard current.isFinite, maximum.isFinite, current >= 0, maximum > 0 else { return nil }
        return Int(min(100, max(0, (current / maximum * 100).rounded())))
    }

    static func decode(_ data: [String: Any]) -> BatteryReading? {
        guard data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              data[kIOPSIsPresentKey] as? Bool != false,
              let current = (data[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
              let maximum = (data[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
              let percent = percentage(current: current, maximum: maximum) else { return nil }
        return BatteryReading(percent: percent, charging: data[kIOPSIsChargingKey] as? Bool ?? false,
                              pluggedIn: data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }

    static func read() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return BatteryReading() }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let reading = decode(data) else { continue }
            return reading
        }
        return BatteryReading()
    }
}

enum SystemAudio {
    static func outputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func channels(_ device: AudioDeviceID) -> [UInt32] {
        let supported = [UInt32(0), 1, 2].filter { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &address)
                && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
        }
        return supported.contains(0) ? [0] : supported
    }

    static func read() -> Double? {
        guard let device = outputDevice(), let channel = channels(device).first else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func set(_ value: Double) {
        guard let device = outputDevice() else { return }
        for channel in channels(device) {
            var level = Float32(min(1, max(0, value)))
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        }
    }
}
