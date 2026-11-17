import SwiftUI

struct CalendarPane: View {
    let model: IslandModel
    @ObservedObject var service: CalendarService

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            month.frame(width: 208)
            Rectangle().fill(.white.opacity(0.10)).frame(width: 0.5, height: 140)
            agenda.frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(height: 150, alignment: .top)
    }

    private var month: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Text(service.monthTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { service.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 16, height: 20) }
                    .accessibilityLabel("Mes anterior")
                Button("Hoy") { service.goToToday() }.font(.system(size: 9)).accessibilityIdentifier("calendar-today")
                Button { service.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 16, height: 20) }
                    .accessibilityLabel("Mes siguiente").accessibilityIdentifier("calendar-next")
            }.buttonStyle(.plain).font(.system(size: 8)).frame(height: 20)
            HStack(spacing: 2) {
                ForEach(Array(service.weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity)
                }
            }.frame(height: 11)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(service.days, id: \.self) { date in day(date) }
            }
        }
    }

    private func day(_ date: Date) -> some View {
        let selected = service.systemCalendar.isDate(date, inSameDayAs: service.selectedDate)
        let today = service.systemCalendar.isDate(date, inSameDayAs: service.today)
        let inMonth = service.systemCalendar.isDate(date, equalTo: service.month, toGranularity: .month)
        return Button { service.select(date) } label: {
            ZStack(alignment: .bottom) {
                Text("\(service.systemCalendar.component(.day, from: date))")
                    .font(.system(size: 9, weight: today || selected ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(selected ? .black : .white.opacity(inMonth ? 0.85 : 0.25))
                    .frame(maxWidth: .infinity).frame(height: 16)
                if service.hasEvents(on: date) { Circle().fill(selected ? .black.opacity(0.7) : .white.opacity(0.6)).frame(width: 2, height: 2).offset(y: 1) }
            }
            .background(selected ? .white.opacity(0.9) : .clear, in: Capsule())
            .overlay { if today && !selected { Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(service.label(date, format: "EEEE d 'de' MMMM yyyy"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(service.dayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button { service.openCalendar() } label: { Image(systemName: "arrow.up.right").font(.system(size: 10)).frame(width: 20, height: 20) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45)).help("Abrir Calendario")
            }.frame(height: 20)
            switch service.status {
            case .ready:
                if service.dayEntries.isEmpty {
                    message("Sin eventos para este día", symbol: "calendar")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(service.dayEntries) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(service.timeLabel(entry)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).frame(width: 61, alignment: .leading)
                                    RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: entry.color)).frame(width: 2, height: 25)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).font(.system(size: 11, weight: .medium)).lineLimit(1).help(entry.title)
                                        Text(entry.calendarName).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            case .loading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Conectando Calendario…").font(.system(size: 10)) }
            case .notConnected, .failed:
                VStack(alignment: .leading, spacing: 9) {
                    Text(service.status == .failed ? "No se pudo acceder a Calendario." : "Tus eventos del Mac, junto al calendario.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Button(service.status == .failed ? "Reintentar" : "Conectar Calendario") { model.connectCalendar() }
                        .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.1), in: Capsule()).accessibilityIdentifier("calendar-connect")
                }
            case .denied, .restricted:
                message(service.status == .restricted ? "El acceso está restringido en este Mac." : "Activa el acceso de ISLA en Ajustes del Sistema → Privacidad y seguridad → Calendarios.", symbol: "calendar.badge.exclamationmark")
            }
            Spacer(minLength: 0)
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.white.opacity(0.25))
            Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 12)
    }
}
