import SwiftUI

struct CompactBatteryState {
    let name: String
    let symbol: String
    let reading: BatteryReading?
    let status: String
    let isPhone: Bool

    init(mac: BatteryReading, phones: [IPhoneReading]) {
        if let phone = phones.first(where: { $0.state == .ready && $0.battery?.percent != nil }) ?? phones.first {
            name = phone.name
            symbol = "iphone.gen3"
            reading = phone.state == .ready ? phone.battery : nil
            status = phone.status
            isPhone = true
        } else {
            name = "Mac"
            symbol = "laptopcomputer"
            reading = mac
            status = mac.status
            isPhone = false
        }
    }

    var percentage: String { reading?.percent.map { "\($0)%" } ?? "—" }
    var charging: Bool { reading?.charging == true }
    var label: String { "\(name), \(percentage), \(status)" }
}

struct CompactStatus: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaService
    @ObservedObject var phones: IPhoneBatteryService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var power: CompactBatteryState { CompactBatteryState(mac: model.battery, phones: phones.devices) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if media.track.exists {
                    Group {
                        if let image = media.artwork {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(width: 19, height: 19).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                    if media.track.playing {
                        PlaybackBars(animate: !reduceMotion).frame(width: 15, height: 16)
                    } else {
                        Image(systemName: "pause.fill").font(.system(size: 9)).frame(width: 15)
                    }
                }
            }
            .opacity(media.track.playing ? 0.9 : 0.4)
            .frame(width: model.compactSideWidth)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(media.track.exists ? "\(media.track.playing ? "Reproduciendo" : "En pausa"): \(media.track.title), \(media.track.artist)" : "Sin reproducción")
            .help(media.track.exists ? "\(media.track.title) · \(media.track.artist)" : "Sin reproducción")

            Color.clear.frame(width: model.hasNotch ? model.notchWidth : 12).accessibilityHidden(true)

            HStack(spacing: 4) {
                Image(systemName: power.symbol).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(power.percentage).font(.system(size: 11, weight: .medium)).monospacedDigit().fixedSize()
                    .foregroundStyle(.white.opacity(0.85))
                if power.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                }
            }.frame(width: model.compactSideWidth)
                .accessibilityElement(children: .ignore).accessibilityLabel(power.label)
                .accessibilityIdentifier("compact-battery").help(power.label)
        }
        .padding(.horizontal, model.hasNotch ? 9 : 8)
        .frame(width: model.compactWidth, height: model.compactHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.setExpanded(true) }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Mostrar ISLA") { model.setExpanded(true) }
    }
}

/// A playback indicator, not microphone input or a measurement of the song's volume.
private struct PlaybackBars: View {
    let animate: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animate)) { context in
            let time = animate ? context.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let phase = time * (3.4 + Double(index) * 0.35) + Double(index) * 1.3
                    Capsule().fill(.white.opacity(0.75))
                        .frame(width: 2, height: 4 + 10 * (0.5 + 0.5 * sin(phase)))
                }
            }.frame(height: 16)
        }.accessibilityHidden(true)
    }
}
