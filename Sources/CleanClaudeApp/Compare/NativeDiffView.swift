import AppKit
import CleanCore
import SwiftUI

/// Native TextKit 2, selection and Find support; no per-line SwiftUI hierarchy or interpreted content.
struct NativeDiffView: NSViewRepresentable {
    let document: DiffDocument
    let path: String
    let sideBySide: Bool
    let change: Int
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 1
        for _ in 0..<2 {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true; scroll.borderType = .noBorder
            let text = NSTextView(usingTextLayoutManager: true)
            text.isEditable = false; text.isSelectable = true; text.isRichText = false; text.usesFindBar = true
            text.isAutomaticLinkDetectionEnabled = false; text.isAutomaticDataDetectionEnabled = false
            text.isAutomaticTextReplacementEnabled = false; text.drawsBackground = false
            text.isVerticallyResizable = true; text.isHorizontallyResizable = true
            text.minSize = NSSize(width: 0, height: 0); text.maxSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width: 8, height: 10)
            text.autoresizingMask = [.width]
            scroll.documentView = text
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled(_:)),
                name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            context.coordinator.scrolls.append(scroll)
            stack.addArrangedSubview(scroll)
        }
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        let coordinator = context.coordinator
        coordinator.scrolls[1].isHidden = !sideBySide
        let changed = coordinator.document != document || coordinator.path != path || coordinator.sideBySide != sideBySide || coordinator.dark != (scheme == .dark)
        if changed {
            coordinator.document = document; coordinator.path = path; coordinator.sideBySide = sideBySide; coordinator.dark = scheme == .dark
            for (i, scroll) in coordinator.scrolls.enumerated() where i == 0 || sideBySide {
                guard let text = scroll.documentView as? NSTextView else { continue }
                let rendered = DiffRenderer.text(document, path: path, side: sideBySide ? (i == 0 ? .old : .new) : nil)
                text.textStorage?.setAttributedString(rendered)
                let longest = rendered.string.split(separator: "\n").map(\.utf16.count).max() ?? 0
                text.setFrameSize(NSSize(width: max(scroll.contentSize.width, CGFloat(longest) * 7.3 + 30), height: max(scroll.contentSize.height, CGFloat(document.hunks.reduce(0) { $0 + $1.lines.count + 1 }) * 20 + 30)))
                text.scrollToBeginningOfDocument(nil)
            }
        }
        if coordinator.change != change {
            let direction = change > coordinator.change ? 1 : -1
            coordinator.change = change
            coordinator.hunk = max(0, min(document.hunks.count - 1, coordinator.hunk + direction))
            for scroll in coordinator.scrolls {
                if let text = scroll.documentView as? NSTextView, !document.hunks.isEmpty {
                    let header = document.hunks[coordinator.hunk].header
                    let range = (text.string as NSString).range(of: header)
                    if range.location != NSNotFound { text.scrollRangeToVisible(range) }
                }
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var document: DiffDocument?
        var path = ""
        var sideBySide = false
        var dark = false
        var change = 0
        var hunk = -1
        var scrolls: [NSScrollView] = []
        var syncing = false
        @objc func scrolled(_ notification: Notification) {
            guard sideBySide, !syncing, let source = notification.object as? NSClipView else { return }
            syncing = true; defer { syncing = false }
            for scroll in scrolls where scroll.contentView !== source {
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: source.bounds.origin.y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
}
