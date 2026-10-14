//
//  Glass.swift
//  Tether
//
//  Tether's surface language: Liquid Glass on macOS 26, the system's
//  translucent materials on macOS 15, same shapes and spacing on both.
//  Glass is used for things that float over content (panels, round buttons,
//  status pills), never as a fill for whole screens.
//

import SwiftUI

enum GlassMetrics {
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 40
}

extension View {
    /// A floating panel: Liquid Glass, or a thick material with a hairline edge.
    @ViewBuilder
    func glassPanel(radius: CGFloat = GlassMetrics.panelRadius) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: .rect(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }

    /// Glass over imagery (the phone card), where the material should stay clear.
    @ViewBuilder
    func clearGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// A round glass button with a symbol, and optionally a caption under it.
struct GlassCircleButton: View {
    let title: String
    let systemImage: String
    var showsTitle = true
    var size: CGFloat = 44
    var isProminent = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            button
            if showsTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .help(title)
    }

    @ViewBuilder
    private var button: some View {
        let label = Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.38, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(.circle)
            .accessibilityLabel(title)

        if #available(macOS 26.0, *) {
            if isProminent {
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        } else {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.regularMaterial), in: .circle)
                .overlay(Circle().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}

/// A small capsule saying how a device is connected.
struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .green

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassPanel(radius: 100)
    }
}

/// A section heading over a glass panel.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Entrance

private struct StaggeredEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(MotionPreference.key) private var tetherReduceMotion = false
    @State private var isShown = false

    private var reduceMotion: Bool { systemReduceMotion || tetherReduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : -8)
            .onAppear {
                guard !isShown else { return }
                if reduceMotion {
                    isShown = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(Double(index) * 0.045)) {
                        isShown = true
                    }
                }
            }
    }
}

extension View {
    /// Fades and settles in after the ones before it, e.g. the popover's panels.
    func staggeredEntrance(_ index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }
}

enum DeviceSymbols {
    /// A battery symbol for a level, with a bolt while charging.
    static func battery(_ percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
