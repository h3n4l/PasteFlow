import SwiftUI

struct FilterRowView: View {
    @Binding var activeFilter: ContentType?
    /// Where each pill is within the group, by label.
    @State private var pillFrames: [String: CGRect] = [:]
    @State private var isPillPressed = false

    private let filters: [(label: String, type: ContentType?)] = [
        ("All", nil), ("Text", .text), ("Link", .link), ("Code", .code), ("Image", .image), ("File", .file),
    ]
    private static let groupSpace = "filterPills"

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.label) { filter in
                    FilterPill(label: filter.label) { activeFilter = filter.type }
                        .background(GeometryReader { pill in
                            Color.clear.preference(key: PillFramesKey.self, value: [filter.label: pill.frame(in: .named(Self.groupSpace))])
                        })
                }
            }
            .coordinateSpace(name: Self.groupSpace)
            // One fill for the whole group, placed behind the active pill, so it can travel between pills.
            .background(FilterSelectionFill(target: activePillFrame))
            .onPreferenceChange(PillFramesKey.self) { pillFrames = $0 }
            .onPreferenceChange(PillPressedKey.self) { isPillPressed = $0 }
            .panelFilterGroupChrome(isPressed: isPillPressed)
            Spacer()
            KeyCapHint(key: "Tab", label: "Filter")
        }
        .padding(.horizontal, 12).padding(.vertical, 6).frame(height: 32)
        .panelFilterRowChrome()
    }

    private var activePillFrame: CGRect? {
        filters.first { $0.type == activeFilter }.flatMap { pillFrames[$0.label] }
    }
}

private struct FilterPill: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11)).foregroundColor(Color(.accentPurple))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .panelFilterPillChrome()
        }.buttonStyle(FilterPillButtonStyle())
    }
}

private struct FilterPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .panelPressScale(PanelMotion.controlPressScale, isPressed: configuration.isPressed)
            .preference(key: PillPressedKey.self, value: configuration.isPressed)
    }
}

/// The fill behind the active filter pill.
///
/// When another pill is chosen, the edge nearer to it gets there first and the other edge
/// follows, so the fill stretches toward the new pill and then closes up behind it.
private struct FilterSelectionFill: View {
    /// The active pill's frame within the group, once the group has been laid out.
    let target: CGRect?
    @State private var span: Span?

    private struct Span: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
        /// Whether the fill last moved toward the trailing end of the group.
        var movesTowardTrailing = false
    }

    var body: some View {
        ZStack {
            if let span {
                // Two bars that each run off one end of the group; where they overlap is the fill.
                // Each bar owns one of the fill's edges, which lets the two edges move at different paces.
                HalfBar(edge: span.leading, runsToTrailing: true)
                    .fill(Color(.backgroundPill))
                    .panelAnimation(span.movesTowardTrailing ? PanelMotion.filterFollowingEdge : PanelMotion.filterLeadingEdge, value: span.leading)
                    .mask(
                        HalfBar(edge: span.trailing, runsToTrailing: false)
                            .panelAnimation(span.movesTowardTrailing ? PanelMotion.filterLeadingEdge : PanelMotion.filterFollowingEdge, value: span.trailing)
                    )
            }
        }
        .onAppear { move(to: target) }
        .onChange(of: target) { move(to: $0) }
    }

    private func move(to target: CGRect?) {
        guard let target else { return }
        span = Span(leading: target.minX, trailing: target.maxX, movesTowardTrailing: target.minX > (span?.leading ?? target.minX))
    }
}

/// A bar with a capsule end at `edge` that runs off one end of the group.
private struct HalfBar: Shape {
    var edge: CGFloat
    /// Whether the bar runs from `edge` off the trailing end, or from off the leading end up to `edge`.
    let runsToTrailing: Bool

    var animatableData: CGFloat {
        get { edge }
        set { edge = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Far enough past the group that the bar's other end stays out of view.
        let reach = rect.width + rect.height
        let minX = runsToTrailing ? edge : rect.minX - reach
        let maxX = runsToTrailing ? rect.maxX + reach : edge
        return Path(roundedRect: CGRect(x: minX, y: rect.minY, width: max(maxX - minX, 0), height: rect.height),
                    cornerRadius: rect.height / 2)
    }
}

private struct PillFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Whether any filter pill is being pressed.
private struct PillPressedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
