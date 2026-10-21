import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    let model = PopoverModel()
    private let panel: PopoverPanel
    private var autoCloseTask: Task<Void, Never>?

    var onReturn: (() -> Void)? {
        get { panel.onReturn } set { panel.onReturn = newValue }
    }
    var onCopy: (() -> Void)? {
        get { panel.onCopy } set { panel.onCopy = newValue }
    }

    init() {
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        panel = PopoverPanel(contentView: hosting)
        panel.onEscape = { [weak self] in self?.hide() }
    }

    func show(_ state: PopoverState) {
        autoCloseTask?.cancel()
        model.state = state
        panel.setContentSize(panel.contentView!.fittingSize)
        if !panel.isVisible { positionNearMouse() }
        panel.makeKeyAndOrderFront(nil)
    }

    func show(_ state: PopoverState, autoCloseAfter seconds: Double) {
        show(state)
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        autoCloseTask?.cancel()
        panel.orderOut(nil)
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }
}
