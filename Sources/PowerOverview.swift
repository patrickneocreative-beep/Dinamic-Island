import SwiftUI

private typealias PowerState<Value> = SwiftUI.State<Value>

struct BatteryGlyph: View {
    let reading: BatteryReading

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).stroke(.white.opacity(0.55), lineWidth: 1)
                if reading.percent != nil {
                    RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.85))
                        .frame(width: max(0, 19 * reading.fraction), height: 8).padding(.leading, 2)
                }
            }.frame(width: 23, height: 12)
            Capsule().fill(.white.opacity(0.55)).frame(width: 1.5, height: 5)
        }.frame(width: 26, height: 14).accessibilityHidden(true)
    }
}

struct PowerOverview: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var phones: IPhoneBatteryService
    @PowerState private var selectedPhone = ""

    private var phone: IPhoneReading? { phones.devices.first(where: { $0.id == selectedPhone }) ?? phones.devices.first }
    private var divider: some View { Rectangle().fill(.white.opacity(0.10)).frame(width: 0.5, height: 57) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mac").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                HStack(spacing: 8) {
                    BatteryGlyph(reading: model.battery)
                    percentage(model.battery)
                    if model.battery.charging { Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)) }
                }
                status(model.battery.status)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine).accessibilityIdentifier("battery-mac")
            divider
            if let phone {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if phones.devices.count > 1 {
                            Menu {
                                ForEach(phones.devices) { entry in Button(entry.name) { selectedPhone = entry.id } }
                            } label: { Text(phone.name).lineLimit(1) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.mini)
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        } else {
                            Text(phone.name).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).help(phone.name)
                        }
                        Spacer(minLength: 0)
                        Label(phone.transport.label, systemImage: phone.transport.symbol)
                            .font(.system(size: 7)).foregroundStyle(.white.opacity(0.45)).fixedSize()
                            .help("Conexión utilizada: " + phone.transport.label)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.gen3").font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.8))
                        percentage(phone.battery)
                        if phone.battery?.charging == true { Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)) }
                    }
                    HStack {
                        status(phone.status)
                        Spacer(minLength: 0)
                        Button(action: model.showIPhoneWiFiHelp) {
                            Image(systemName: "info.circle").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                        }.buttonStyle(.plain).help("Conectar el iPhone por Wi-Fi")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("battery-iphone")
                divider
            } else {
                Button(action: model.showIPhoneWiFiHelp) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("iPhone").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.gen3").font(.system(size: 22, weight: .light))
                            Image(systemName: "wifi").font(.system(size: 12))
                        }.foregroundStyle(.white.opacity(0.35)).frame(height: 29)
                        status(phones.available ? "Conectar por Wi-Fi" : "Detección no disponible")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help("Configurar la conexión inalámbrica del iPhone")
                divider
            }
            Button { model.select(.focus) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foco").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    HStack(spacing: 8) {
                        Image(systemName: "timer").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                        Text(model.focus.label).font(.system(size: 24, weight: .medium)).monospacedDigit()
                    }
                    status(model.focus.running ? "En curso" : "Temporizador")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.frame(height: 68)
    }

    private func percentage(_ reading: BatteryReading?) -> some View {
        Text(reading?.percent.map { "\($0)%" } ?? "—")
            .font(.system(size: 24, weight: .medium)).monospacedDigit().lineLimit(1).fixedSize()
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).help(text)
    }
}
