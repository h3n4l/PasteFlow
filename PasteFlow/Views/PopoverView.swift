import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(searchText: $appState.searchText)
            FilterRowView(activeFilter: Binding(
                get: { appState.activeFilter },
                set: { appState.setFilter($0) }
            ))
            HStack(spacing: 0) {
                ClipListView(appState: appState)
                DetailPanelView(
                    item: appState.selectedItem,
                    onPaste: { item in pasteAndDismiss(item) },
                    onDelete: { item in appState.deleteItem(item) }
                ).frame(width: 220)
            }.frame(maxHeight: .infinity)
            FooterView(
                itemCount: appState.totalItemCount,
                statusMessage: appState.statusMessage,
                isAccessibilityGranted: PasteSimulator.isAccessibilityGranted
            )
        }
        .frame(width: 560, height: 456)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
        .background(
            KeyEventHandler(
                onArrowUp: { appState.selectPrevious() },
                onArrowDown: { appState.selectNext() },
                onEnter: { if let item = appState.selectedItem { pasteAndDismiss(item) } },
                onNumber: { num in
                    let index = num - 1
                    if index >= 0, index < appState.filteredItems.count {
                        pasteAndDismiss(appState.filteredItems[index])
                    }
                },
                onTextInput: { chars in appState.searchText.append(chars) }
            )
        )
        .onExitCommand { onDismiss() }
    }

    private func pasteAndDismiss(_ item: ClipboardItem) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appState.pasteItem(item) }
    }
}

struct KeyEventHandler: NSViewRepresentable {
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: () -> Void
    let onNumber: (Int) -> Void
    let onTextInput: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onEnter = onEnter
        view.onNumber = onNumber
        view.onTextInput = onTextInput
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onEnter = onEnter
        nsView.onNumber = onNumber
        nsView.onTextInput = onTextInput
    }
}

class KeyCaptureView: NSView {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onNumber: ((Int) -> Void)?
    var onTextInput: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers, let num = Int(chars), num >= 1, num <= 9 {
                onNumber?(num)
                return
            }
        }
        switch event.keyCode {
        case 126: onArrowUp?()
        case 125: onArrowDown?()
        case 36: onEnter?()
        default:
            if let chars = event.characters, !chars.isEmpty,
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control) {
                onTextInput?(chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
