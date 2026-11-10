import SwiftUI

/// The parts of the panel's look that belong to a visual style rather than to its layout.
///
/// Panel views call these instead of styling themselves, so the layout is written once.
/// There are two looks: Liquid Glass on macOS 26 and later, and the older look before that.
/// Following Apple's guidance, glass is used only for the controls in the top bar; the list
/// and detail pane stay on the panel's blur material.
enum PanelSkin {
    /// Whether the panel uses the Liquid Glass look.
    ///
    /// Launch with `-PanelLegacySkin YES` to get the older look on macOS 26 or later.
    /// Without an older Mac that is the only way to check it.
    static let usesGlass: Bool = {
        guard #available(macOS 26.0, *) else { return false }
        return !UserDefaults.standard.bool(forKey: "PanelLegacySkin")
    }()

    /// Corner radius of the selected row's highlight.
    static var selectionCornerRadius: CGFloat { usesGlass ? 10 : 6 }
}

extension View {
    /// Places the search field and filter row above the list and detail pane.
    ///
    /// With Liquid Glass the bar floats: the list scrolls underneath it and the system blurs
    /// the rows as they pass. Otherwise the bar sits above the list. Either way the bar and
    /// the content below it occupy the same space.
    @ViewBuilder
    func panelTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26.0, *), PanelSkin.usesGlass {
            safeAreaBar(edge: .top, spacing: 0) {
                // The bar's glass shapes share one container so the system renders them together.
                GlassEffectContainer(spacing: 0) {
                    VStack(spacing: 0) { bar() }
                }
            }
        } else {
            VStack(spacing: 0) {
                bar()
                self
            }
        }
    }

    /// Sizes and decorates the row that holds the search field. In both looks the row is
    /// 40pt tall and its contents start 12pt from the panel's edges, vertically centered.
    @ViewBuilder
    func panelSearchFieldChrome() -> some View {
        if #available(macOS 26.0, *), PanelSkin.usesGlass {
            self
                .padding(.horizontal, 8)
                .frame(height: 32)
                .glassEffect(.regular, in: .capsule)
                .padding(4)
        } else {
            self
                .padding(.horizontal, 12)
                .frame(height: 40)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .bottom)
        }
    }

    /// Decorates the filter row.
    @ViewBuilder
    func panelFilterRowChrome() -> some View {
        if PanelSkin.usesGlass {
            // No divider: the blur under the floating bar separates it from the list.
            self
        } else {
            overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .bottom)
        }
    }

    /// Decorates the group of filter pills without changing its size or position.
    /// With Liquid Glass the group's capsule swells a little while one of its pills is pressed.
    @ViewBuilder
    func panelFilterGroupChrome(isPressed: Bool) -> some View {
        if #available(macOS 26.0, *), PanelSkin.usesGlass {
            self
                .padding(.horizontal, 4).padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .panelPressScale(PanelMotion.glassPressScale, isPressed: isPressed)
                .padding(.horizontal, -4).padding(.vertical, -3)
        } else {
            self
        }
    }

    /// Shape and outline of one filter pill. The active pill's fill is not drawn here: the
    /// filter row draws one fill and moves it from pill to pill.
    func panelFilterPillChrome() -> some View {
        self
            // On glass the group's capsule frames the pills, so they need no outline of their own.
            .overlay(Capsule().stroke(Color(.borderPill), lineWidth: 1).opacity(PanelSkin.usesGlass ? 0 : 1))
            // A pill has no fill of its own, so make the whole capsule clickable, not just the text.
            .contentShape(Capsule())
    }
}

/// The Paste, Copy Path and Delete buttons in the detail pane.
struct PanelActionButtonStyle: ButtonStyle {
    enum Kind {
        /// The main action. The only one that is tinted in the Liquid Glass look.
        case primary
        /// Another way to use the item.
        case secondary
        /// Everything else.
        case plain
    }

    var kind: Kind = .plain

    func makeBody(configuration: Configuration) -> some View {
        PanelActionButtonBody(kind: kind, configuration: configuration)
    }
}

private struct PanelActionButtonBody: View {
    let kind: PanelActionButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if PanelSkin.usesGlass {
                // These sit in the content, so they are plain capsules rather than glass.
                label
                    .foregroundColor(kind == .primary ? (colorScheme == .dark ? .black : .white) : .primary)
                    .background(kind == .primary ? Color(.accentPurple) : Color.primary.opacity(0.1))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            } else {
                label
                    .foregroundColor(Color(.accentPurple))
                    .background(kind == .plain ? Color.clear : Color(.backgroundPill))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.borderButton), lineWidth: 1))
                    .contentShape(Rectangle())
            }
        }
        // Pressing shrinks the button. With Reduce Motion on it dims instead.
        .panelPressScale(PanelMotion.controlPressScale, isPressed: configuration.isPressed)
        .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
    }

    private var label: some View {
        configuration.label
            .font(.system(size: 11))
            .padding(.horizontal, 10).padding(.vertical, 4)
    }
}
