import SwiftUI

/// The parts of the panel's look that belong to a visual style rather than to its layout.
///
/// Panel views call these instead of styling themselves. The layout is then written once,
/// and a second look can be added here without touching the views.
enum PanelSkin {
    /// Corner radius of the selected row's highlight.
    static let selectionCornerRadius: CGFloat = 6
}

extension View {
    /// Places the search field and filter row above the list and detail pane.
    func panelTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            bar()
            self
        }
    }

    /// Sizes and decorates the row that holds the search field.
    func panelSearchFieldChrome() -> some View {
        self
            .padding(.horizontal, 12)
            .frame(height: 40)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .bottom)
    }

    /// Decorates the filter row.
    func panelFilterRowChrome() -> some View {
        overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .bottom)
    }

    /// Fill, shape and outline of one filter pill.
    func panelFilterPillChrome(isActive: Bool) -> some View {
        self
            .background(isActive ? Color(.backgroundPill) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.borderPill), lineWidth: 1))
            // An inactive pill has no fill, so make the whole capsule clickable, not just the text.
            .contentShape(Capsule())
    }
}

/// The Paste, Copy Path and Delete buttons in the detail pane.
struct PanelActionButtonStyle: ButtonStyle {
    /// Filled, for the actions that put the item to use.
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(Color(.accentPurple))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isProminent ? Color(.backgroundPill) : Color.clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.borderButton), lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
