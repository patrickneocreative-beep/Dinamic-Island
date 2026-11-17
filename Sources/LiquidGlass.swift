import AppKit
import SwiftUI

enum GlassPalette {
    static let edge = LinearGradient(stops: [
        .init(color: .white.opacity(0.72), location: 0),
        .init(color: .white.opacity(0.15), location: 0.28),
        .init(color: .white.opacity(0.045), location: 0.53),
        .init(color: .white.opacity(0.34), location: 0.80),
        .init(color: .white.opacity(0.13), location: 1)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let reflection = LinearGradient(stops: [
        .init(color: .white.opacity(0.18), location: 0),
        .init(color: .white.opacity(0.055), location: 0.24),
        .init(color: .white.opacity(0.01), location: 0.58),
        .init(color: .white.opacity(0.07), location: 1)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Refraction is restricted to a fine edge; the glass and its content stay neutral.
    static let refraction = AngularGradient(stops: [
        .init(color: .white.opacity(0.75), location: 0),
        .init(color: Color(red: 1, green: 0.73, blue: 0.87), location: 0.12),
        .init(color: .white.opacity(0.8), location: 0.24),
        .init(color: Color(red: 0.76, green: 0.71, blue: 1), location: 0.36),
        .init(color: Color(red: 0.49, green: 0.86, blue: 1), location: 0.49),
        .init(color: Color(red: 0.59, green: 1, blue: 0.79), location: 0.65),
        .init(color: .white, location: 0.79),
        .init(color: Color(red: 1, green: 0.9, blue: 0.73), location: 0.9),
        .init(color: .white.opacity(0.75), location: 1)
    ], center: .center, angle: .degrees(-110))
}

struct RefractiveRim<S: Shape>: View {
    let shape: S
    var strength: Double = 1
    var lineWidth: CGFloat = 1.2
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                shape.stroke(GlassPalette.refraction, lineWidth: lineWidth * 3)
                    .blur(radius: 2.7)
                    .opacity(0.30 * strength)
            }
            shape.stroke(GlassPalette.refraction, lineWidth: lineWidth)
                .opacity(0.85 * strength)
            shape.stroke(GlassPalette.edge, lineWidth: 0.35)
                .opacity(0.6 * strength)
        }
        .padding(lineWidth / 2 + 0.35)
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sample the desktop behind this borderless window instead of an opaque app background.
struct DesktopBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The floating panel uses a standard material; interactive elements use Liquid Glass.
struct IslandSurface<S: Shape>: View {
    let shape: S
    let snapshot: Bool
    var expanded = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        shape.fill(.black)
        .allowsHitTesting(false)
    }
}

private struct GlassControl<S: Shape>: ViewModifier {
    let snapshot: Bool
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        material(content: content)
            .overlay(RefractiveRim(shape: shape, strength: 0.16, lineWidth: 0.5))
    }

    @ViewBuilder private func material(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color(white: 0.28)))
                .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 0.75))
        } else if !snapshot {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(GlassPalette.edge, lineWidth: 0.75))
            }
        } else {
            content.background {
                shape.fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08), .white.opacity(0.15)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(shape.stroke(GlassPalette.edge, lineWidth: 0.85))
            .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
        }
    }
}

extension View {
    func glassControl<S: Shape>(snapshot: Bool, shape: S) -> some View {
        modifier(GlassControl(snapshot: snapshot, shape: shape))
    }
}

/// A neutral presentation background for static previews, never shown by the app.
struct LiquidGlassPreview: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.26), Color(white: 0.54), Color(white: 0.31)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Ellipse().fill(.white.opacity(0.22)).frame(width: 600, height: 220)
                .rotationEffect(.degrees(-32)).blur(radius: 32).offset(x: 100, y: -150)
            Ellipse().fill(.black.opacity(0.24)).frame(width: 700, height: 260)
                .rotationEffect(.degrees(-32)).blur(radius: 38).offset(x: -100, y: 150)
            Ellipse().stroke(.white.opacity(0.18), lineWidth: 30).frame(width: 850, height: 340)
                .rotationEffect(.degrees(-32)).blur(radius: 30).offset(x: 45, y: -20)
            IslandView(model: model, media: model.media, snapshot: true)
                .shadow(color: .black.opacity(0.25), radius: 23, x: 0, y: 20)
        }
        .frame(width: max(548, model.width + 100), height: model.expanded ? model.height + 100 : 100)
        .clipped()
    }
}
