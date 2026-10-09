import AppKit
import Carbon.HIToolbox
import Combine
import PCPCore
import SwiftUI

/// A Spotlight-style panel that takes keyboard focus without activating PCP,
/// so the app you were in stays frontmost and receives the paste.
final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class StackViewModel: ObservableObject {
    @Published var query = "" {
        didSet { refresh(); selection = 0 }
    }
    @Published var selection = 0
    @Published private(set) var results: [ClipItem] = []
    @Published private(set) var focusRequest = 0

    let model: HistoryModel
    private var cancellable: AnyCancellable?

    init(model: HistoryModel) {
        self.model = model
        cancellable = model.$history.sink { [weak self] history in
            guard let self else { return }
            self.results = history.search(self.query)
            self.selection = min(self.selection, max(0, self.results.count - 1))
        }
    }

    func reset() {
        query = ""
        selection = 0
        focusRequest += 1
    }

    func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(0, selection + offset), results.count - 1)
    }

    private func refresh() {
        results = model.history.search(query)
    }
}

@MainActor
final class StackPanelController {
    private let panel = FloatingPanel()
    private let viewModel: StackViewModel
    private let model: HistoryModel
    private let onPick: (ClipItem) -> Void
    private var keyMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(model: HistoryModel, onPick: @escaping (ClipItem) -> Void) {
        self.model = model
        self.onPick = onPick
        viewModel = StackViewModel(model: model)
        panel.contentView = NSHostingView(rootView: StackView(viewModel: viewModel, onPick: { [weak self] index in
            self?.pick(index)
        }))
        panel.onResignKey = { [weak self] in self?.close() }
    }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        viewModel.reset()
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func pick(_ index: Int) {
        guard viewModel.results.indices.contains(index) else { NSSound.beep(); return }
        let item = viewModel.results[index]
        close()
        onPick(item)
    }

    /// Centered horizontally, upper third of the screen the mouse is on.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.22 - size.height
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: Keyboard

    private static let digitKeyCodes: [Int: Int] = [
        kVK_ANSI_1: 0, kVK_ANSI_2: 1, kVK_ANSI_3: 2, kVK_ANSI_4: 3, kVK_ANSI_5: 4,
        kVK_ANSI_6: 5, kVK_ANSI_7: 6, kVK_ANSI_8: 7, kVK_ANSI_9: 8,
        kVK_ANSI_Keypad1: 0, kVK_ANSI_Keypad2: 1, kVK_ANSI_Keypad3: 2, kVK_ANSI_Keypad4: 3,
        kVK_ANSI_Keypad5: 4, kVK_ANSI_Keypad6: 5, kVK_ANSI_Keypad7: 6, kVK_ANSI_Keypad8: 7,
        kVK_ANSI_Keypad9: 8,
    ]

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)
        let code = Int(event.keyCode)

        if command, let index = Self.digitKeyCodes[code] {
            pick(index)
            return true
        }
        switch code {
        case kVK_Escape:
            close()
        case kVK_DownArrow:
            viewModel.move(1)
        case kVK_UpArrow:
            viewModel.move(-1)
        case kVK_PageDown:
            viewModel.move(8)
        case kVK_PageUp:
            viewModel.move(-8)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pick(viewModel.selection)
        case kVK_Delete where command, kVK_ForwardDelete where command:
            if viewModel.results.indices.contains(viewModel.selection) {
                model.delete(viewModel.results[viewModel.selection].id)
            }
        case kVK_ANSI_W where command:
            close()
        default:
            return false
        }
        return true
    }
}

// MARK: - View

struct StackView: View {
    @ObservedObject var viewModel: StackViewModel
    let onPick: (Int) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if viewModel.results.isEmpty {
                Spacer()
                Text(viewModel.query.isEmpty ? "Nothing copied yet" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.focusRequest) { searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                        Row(
                            item: item,
                            index: index,
                            isSelected: index == viewModel.selection,
                            isOnStack: viewModel.model.history.isOnStack(item.id)
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onPick(index) }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selection) { _, selection in
                guard viewModel.results.indices.contains(selection) else { return }
                proxy.scrollTo(viewModel.results[selection].id)
            }
            .onChange(of: viewModel.focusRequest) {
                if let first = viewModel.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.results.count) items")
            Spacer()
            Text("↩ paste   ⌘1–9 pick   ⌘⌫ delete   esc close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct Row: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let isOnStack: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOnStack ? Color.accentColor : .clear)
                .frame(width: 6, height: 6)
                .help(isOnStack ? "On the paste stack (⇧⌘V)" : "")
            if item.isSensitive {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.preview())
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.age(item.lastUsedAt))
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .monospacedDigit()
            Text(index < 9 ? "⌘\(index + 1)" : "")
                .font(.caption.monospaced())
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : .clear)
        )
        .help(item.isSensitive ? "" : String(item.text.prefix(600)))
    }

    static func age(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}
