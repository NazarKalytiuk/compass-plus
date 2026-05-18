import AppKit
import SwiftUI

// MARK: - Key events the autocomplete cares about

/// Keystrokes the filter-bar autocomplete intercepts. The coordinator hands
/// them to SwiftUI; SwiftUI returns `true` if it consumed the event (e.g. the
/// dropdown moved its selection), `false` otherwise (e.g. the text view
/// should perform its default action — like a plain Enter submitting Find).
enum MQLKey {
    case up, down, returnKey, tab, escape
}

// MARK: - Single-line MQL text field

/// NSTextField wrapped for the filter bar. Exposes:
///   - `text`: two-way bound to `stringValue`.
///   - `cursor`: UTF-16 caret location, two-way bound. Settable from SwiftUI
///     to programmatically place the caret (e.g. after inserting a snippet).
///   - `isFocused`: two-way bound focus state. Setting it `true` from
///     SwiftUI re-routes first responder to this field — used to restore
///     focus after clicking a suggestion row in the dropdown.
///   - `onKey`: returns `true` if SwiftUI handled the key (dropdown nav /
///     accept / dismiss); the field falls back to its native behavior
///     otherwise.
///   - `onSubmit`: fires when plain Enter is *not* consumed by `onKey`.
struct MQLTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursor: Int
    @Binding var isFocused: Bool
    var placeholder: String
    var onKey: (MQLKey) -> Bool
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = MQLBackingTextField()
        tf.delegate = context.coordinator
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.placeholderString = placeholder
        tf.lineBreakMode = .byClipping
        tf.cell?.usesSingleLineMode = true
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.stringValue = text

        context.coordinator.field = tf
        context.coordinator.startObservingSelection()

        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        // Text sync — avoid clobbering during editing if value hasn't changed.
        if tf.stringValue != text {
            coord.suppressNextChange = true
            tf.stringValue = text
            coord.suppressNextChange = false
        }

        // Focus sync — but only when SwiftUI's `isFocused` disagrees with
        // AppKit's first-responder state. Spurious makeFirstResponder calls
        // cause the field to re-select all on every body pass.
        let isFR = (tf.window?.firstResponder === tf.currentEditor()) ||
                   (tf.window?.firstResponder === tf)
        if isFocused && !isFR {
            DispatchQueue.main.async { tf.window?.makeFirstResponder(tf) }
        } else if !isFocused && isFR {
            DispatchQueue.main.async {
                if tf.window?.firstResponder === tf.currentEditor() ||
                   tf.window?.firstResponder === tf {
                    tf.window?.makeFirstResponder(nil)
                }
            }
        }

        // Cursor sync — only when we have a field editor (i.e. focused) and
        // the bound value diverges from the live selection. This is what
        // lets SwiftUI place the caret inside an inserted snippet.
        if let editor = tf.currentEditor() {
            let length = (tf.stringValue as NSString).length
            let safe = min(max(cursor, 0), length)
            if editor.selectedRange.location != safe || editor.selectedRange.length != 0 {
                editor.selectedRange = NSRange(location: safe, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MQLTextField
        weak var field: NSTextField?
        var suppressNextChange = false
        private var selectionObserver: NSObjectProtocol?

        init(_ parent: MQLTextField) { self.parent = parent }

        deinit {
            if let obs = selectionObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        /// Cursor moves *without* text edits (arrow keys, click) don't fire
        /// `controlTextDidChange`. We catch them via the field editor's
        /// selection-change notification.
        func startObservingSelection() {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self = self,
                      let tf = self.field,
                      let editor = note.object as? NSTextView,
                      editor === tf.currentEditor() else { return }
                let loc = editor.selectedRange.location
                if self.parent.cursor != loc {
                    self.parent.cursor = loc
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !suppressNextChange,
                  let tf = notification.object as? NSTextField else { return }
            parent.text = tf.stringValue
            if let editor = tf.currentEditor() {
                parent.cursor = editor.selectedRange.location
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return parent.onKey(.down)
            case #selector(NSResponder.moveUp(_:)):
                return parent.onKey(.up)
            case #selector(NSResponder.insertNewline(_:)):
                if parent.onKey(.returnKey) { return true }
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertTab(_:)):
                return parent.onKey(.tab)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onKey(.escape)
            default:
                return false
            }
        }
    }
}

/// Subclass marker so future tweaks (custom drawing, layout) have a single
/// landing spot.
private final class MQLBackingTextField: NSTextField {}

// MARK: - Multi-line MQL text editor

/// NSTextView (in NSScrollView) wrapped for the expand-mode editor. Same
/// surface as `MQLTextField` so the dropdown logic in DocumentListView
/// doesn't care which one is on screen.
struct MQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursor: Int
    @Binding var isFocused: Bool
    var placeholder: String
    var onKey: (MQLKey) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let tv = MQLBackingTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFontPanel = false
        tv.string = text
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.coordinator = context.coordinator

        scroll.documentView = tv
        context.coordinator.textView = tv

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }

        if tv.string != text {
            coord.suppressNextChange = true
            tv.string = text
            coord.suppressNextChange = false
        }

        // Update placeholder layer
        coord.refreshPlaceholder(placeholder: placeholder)

        let length = (tv.string as NSString).length
        let safe = min(max(cursor, 0), length)
        if tv.selectedRange().location != safe || tv.selectedRange().length != 0 {
            tv.setSelectedRange(NSRange(location: safe, length: 0))
        }

        let isFR = tv.window?.firstResponder === tv
        if isFocused && !isFR {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        } else if !isFocused && isFR {
            DispatchQueue.main.async {
                if tv.window?.firstResponder === tv {
                    tv.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MQLTextEditor
        weak var textView: NSTextView?
        var suppressNextChange = false

        init(_ parent: MQLTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !suppressNextChange,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.cursor = tv.selectedRange().location
            refreshPlaceholder(placeholder: parent.placeholder)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            if parent.cursor != loc { parent.cursor = loc }
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused { parent.isFocused = true }
        }
        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return parent.onKey(.down)
            case #selector(NSResponder.moveUp(_:)):
                return parent.onKey(.up)
            case #selector(NSResponder.insertNewline(_:)):
                // Multi-line editor: Enter inserts a newline. We only consume
                // it when the dropdown wants to accept a suggestion.
                return parent.onKey(.returnKey)
            case #selector(NSResponder.insertTab(_:)):
                return parent.onKey(.tab)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onKey(.escape)
            default:
                return false
            }
        }

        // Placeholder management (NSTextView has no native placeholder).
        func refreshPlaceholder(placeholder: String) {
            guard let tv = textView as? MQLBackingTextView else { return }
            tv.placeholderString = placeholder
            tv.needsDisplay = true
        }
    }
}

/// NSTextView with a built-in placeholder so the multi-line editor can show
/// hint text identical to a single-line NSTextField.
private final class MQLBackingTextView: NSTextView {
    weak var coordinator: MQLTextEditor.Coordinator?
    var placeholderString: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let inset = textContainerInset
        let point = NSPoint(x: inset.width + 1, y: inset.height)
        (placeholderString as NSString).draw(at: point, withAttributes: attrs)
    }
}
