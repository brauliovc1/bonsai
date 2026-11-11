import AppKit
import CleanCore
import SwiftUI

/// Native TextKit 2, selection and Find support; no per-line SwiftUI hierarchy or interpreted content.
struct NativeDiffView: NSViewRepresentable {
    let document: DiffDocument
    let path: String
    let sideBySide: Bool
    let change: Int
    var fileStep: @MainActor (Int) -> Void = { _ in }
    var toggleViewed: @MainActor () -> Void = {}
    var moreContext: @MainActor () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 1
        for _ in 0..<2 {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true; scroll.borderType = .noBorder
            let text = ReviewTextView(usingTextLayoutManager: true)
            text.delegate = context.coordinator
            text.reviewKey = { [weak coordinator = context.coordinator] key in coordinator?.key(key) }
            text.isEditable = false; text.isSelectable = true; text.isRichText = false; text.usesFindBar = true
            text.isAutomaticLinkDetectionEnabled = false; text.isAutomaticDataDetectionEnabled = false
            text.isAutomaticTextReplacementEnabled = false; text.drawsBackground = false
            text.isVerticallyResizable = true; text.isHorizontallyResizable = true
            text.minSize = NSSize(width: 0, height: 0); text.maxSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width: 8, height: 10)
            text.autoresizingMask = []
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
        coordinator.fileStep = fileStep; coordinator.toggleViewed = toggleViewed; coordinator.moreContext = moreContext
        coordinator.scrolls[1].isHidden = !sideBySide
        let changed = coordinator.document != document || coordinator.path != path || coordinator.sideBySide != sideBySide || coordinator.dark != (scheme == .dark)
        if changed {
            let sameFile = coordinator.path == path
            if !sameFile { coordinator.hunk = -1 }
            coordinator.document = document; coordinator.path = path; coordinator.sideBySide = sideBySide; coordinator.dark = scheme == .dark
            for (i, scroll) in coordinator.scrolls.enumerated() where i == 0 || sideBySide {
                guard let text = scroll.documentView as? NSTextView else { continue }
                let origin = scroll.contentView.bounds.origin
                let rendered = DiffRenderer.text(document, path: path, side: sideBySide ? (i == 0 ? .old : .new) : nil)
                text.textStorage?.setAttributedString(rendered)
                // Font fallback changes glyph advances (CJK, emoji). Measure the actual attributed
                // layout once; TextKit still draws and scrolls only the visible part of the document.
                let width = ceil(rendered.size().width) + text.textContainerInset.width * 2 + 16
                text.setFrameSize(NSSize(width: max(scroll.contentSize.width, width), height: max(scroll.contentSize.height, CGFloat(document.hunks.reduce(0) { $0 + $1.lines.count + 1 }) * 20 + 30)))
                if sameFile {
                    scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
                } else { text.scrollToBeginningOfDocument(nil) }
            }
        }
        if coordinator.change != change {
            let direction = change > coordinator.change ? 1 : -1
            coordinator.change = change
            coordinator.moveHunk(direction)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var document: DiffDocument?
        var path = ""
        var sideBySide = false
        var dark = false
        var change = 0
        var hunk = -1
        var scrolls: [NSScrollView] = []
        var syncing = false
        var fileStep: @MainActor (Int) -> Void = { _ in }
        var toggleViewed: @MainActor () -> Void = {}
        var moreContext: @MainActor () -> Void = {}

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if ((link as? String) ?? (link as? URL)?.absoluteString) == "bonsai-compare-context" { moreContext() }
            return true
        }
        func key(_ key: String) {
            switch key {
            case "down": fileStep(1)
            case "up": fileStep(-1)
            case " ": toggleViewed()
            case "n": moveHunk(1)
            case "p": moveHunk(-1)
            default: break
            }
        }
        func moveHunk(_ delta: Int) {
            guard let document, !document.hunks.isEmpty else { return }
            hunk = max(0, min(document.hunks.count - 1, hunk + delta))
            for scroll in scrolls {
                if let text = scroll.documentView as? NSTextView {
                    let range = (text.string as NSString).range(of: document.hunks[hunk].header)
                    if range.location != NSNotFound { text.scrollRangeToVisible(range) }
                }
            }
        }
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

/// Review shortcuts still work when the native text view owns keyboard focus.
@MainActor private final class ReviewTextView: NSTextView {
    var reviewKey: ((String) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            let key = event.keyCode == 125 ? "down" : event.keyCode == 126 ? "up" : event.charactersIgnoringModifiers ?? ""
            if ["down", "up", "n", "p", " "].contains(key) { reviewKey?(key); return }
        }
        super.keyDown(with: event)
    }
}
