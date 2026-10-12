import SwiftUI
import UIKit

struct GroupMentionToken: Identifiable, Equatable {
    enum Target: Equatable {
        case everyone
        case bot(id: Int)
    }

    let id: UUID
    let text: String
    var range: NSRange
    let target: Target

    init(text: String, range: NSRange, target: Target) {
        id = UUID()
        self.text = text
        self.range = range
        self.target = target
    }
    func adjustedForTrimmedDraft(_ text: String, leading: Int) -> Self? {
        var adjusted = self
        adjusted.range.location -= leading
        let source = text as NSString
        guard adjusted.range.location >= 0, NSMaxRange(adjusted.range) <= source.length,
              source.substring(with: adjusted.range) == adjusted.text else { return nil }
        return adjusted
    }

    static func activeRange(in text: String, selection: NSRange, mentions: [GroupMentionToken]) -> Range<String.Index>? {
        guard selection.length == 0, selection.location >= 0 else { return nil }
        let source = text as NSString
        guard selection.location <= source.length,
              let prefixRange = Range(NSRange(location: 0, length: selection.location), in: text) else { return nil }
        let prefix = text[prefixRange]
        guard let at = prefix.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let previous = text[text.index(before: at)]
            guard previous.isWhitespace || previous.isPunctuation else { return nil }
        }
        let range = at..<prefixRange.upperBound
        let query = text[text.index(after: at)..<range.upperBound]
        guard !query.contains(where: \.isWhitespace) else { return nil }
        let candidate = NSRange(range, in: text)
        guard !mentions.contains(where: { NSIntersectionRange($0.range, candidate).length > 0 }) else { return nil }
        return range
    }

}

struct MentionTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var mentions: [GroupMentionToken]
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    @Binding var isComposing: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.text = text
        view.accessibilityLabel = "群聊消息输入框"
        view.delegate = context.coordinator
        view.textStorage.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 13, left: 0, bottom: 13, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = false
        view.adjustsFontForContentSizeCategory = true
        view.tintColor = UIColor(Color.brandAccent)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.lastText = text
        context.coordinator.lastMentions = mentions
        context.coordinator.applyStyles(to: view, mentions: mentions)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // UIKit owns selection and marked text while the user is editing.
        // Only synchronize changes initiated outside the editor.
        coordinator.isUpdatingView = true
        defer { coordinator.isUpdatingView = false }
        if view.markedTextRange == nil {
            if view.text != text {
                coordinator.pendingEdit = nil
                view.text = text
                coordinator.lastText = text
                coordinator.applyStyles(to: view, mentions: mentions)
                view.selectedRange = clamped(selection, to: text)
            } else if coordinator.lastMentions != mentions {
                coordinator.applyStyles(to: view, mentions: mentions)
            }
            coordinator.lastMentions = mentions
        }
        // Responder changes can call delegates synchronously. Run them after
        // SwiftUI's update, using the latest request rather than a captured value.
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, view.window != nil else { return }
            if coordinator.parent.isFocused, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !coordinator.parent.isFocused, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 240)
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let maxHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight * 5 + 26
        let height = min(maxHeight, max(48, measured.height))
        let needsScrolling = measured.height > maxHeight
        if uiView.isScrollEnabled != needsScrolling { uiView.isScrollEnabled = needsScrolling }
        return CGSize(width: width, height: height)
    }

    private func clamped(_ range: NSRange, to text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let count = min(max(0, range.length), length - location)
        return NSRange(location: location, length: count)
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: MentionTextEditor
        var pendingEdit: (range: NSRange, replacement: String)?
        var isUpdatingView = false
        var lastText = ""
        var lastMentions: [GroupMentionToken] = []

        init(_ parent: MentionTextEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", textView.markedTextRange == nil {
                parent.onSubmit()
                return false
            }
            pendingEdit = (range, text)
            return true
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard !isUpdatingView, editedMask.contains(.editedCharacters),
                  editedRange.length - delta >= 0, NSMaxRange(editedRange) <= textStorage.length else { return }
            pendingEdit = (NSRange(location: editedRange.location, length: editedRange.length - delta),
                           (textStorage.string as NSString).substring(with: editedRange))
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            let updatedText = textView.text ?? ""
            if let edit = pendingEdit, NSMaxRange(edit.range) <= (lastText as NSString).length,
               (lastText as NSString).replacingCharacters(in: edit.range, with: edit.replacement) == updatedText {
                parent.mentions = adjustedMentions(replacing: edit.range,
                                                  withLength: (edit.replacement as NSString).length,
                                                  mentions: parent.mentions)
            } else {
                parent.mentions = adjustedMentions(from: lastText, to: updatedText, mentions: parent.mentions)
            }
            pendingEdit = nil
            lastText = updatedText
            lastMentions = parent.mentions
            parent.text = updatedText
            parent.selection = textView.selectedRange
            parent.isComposing = textView.markedTextRange != nil
            guard textView.markedTextRange == nil else { return }
            applyStyles(to: textView, mentions: parent.mentions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            if parent.selection != textView.selectedRange { parent.selection = textView.selectedRange }
            let composing = textView.markedTextRange != nil
            if parent.isComposing != composing { parent.isComposing = composing }
        }

        func applyStyles(to textView: UITextView, mentions: [GroupMentionToken]) {
            let previousUpdating = isUpdatingView
            isUpdatingView = true
            let savedSelection = textView.selectedRange
            defer {
                textView.selectedRange = savedSelection
                isUpdatingView = previousUpdating
            }
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else {
                textView.typingAttributes = baseAttributes
                return
            }
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)
            for mention in mentions where mention.range.location >= 0 && NSMaxRange(mention.range) <= storage.length {
                guard (storage.string as NSString).substring(with: mention.range) == mention.text else { continue }
                storage.addAttributes([
                    .foregroundColor: UIColor(Color.brandAccent),
                    .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
                ], range: mention.range)
            }
            storage.endEditing()
            textView.typingAttributes = baseAttributes
        }

        private var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        }

        func adjustedMentions(from old: String, to new: String, mentions: [GroupMentionToken]) -> [GroupMentionToken] {
            let before = old as NSString
            let after = new as NSString
            var prefix = 0
            while prefix < before.length && prefix < after.length && before.character(at: prefix) == after.character(at: prefix) {
                prefix += 1
            }
            var suffix = 0
            while suffix < before.length - prefix && suffix < after.length - prefix &&
                    before.character(at: before.length - suffix - 1) == after.character(at: after.length - suffix - 1) {
                suffix += 1
            }
            let replacedLength = before.length - prefix - suffix
            let insertedLength = after.length - prefix - suffix
            return adjustedMentions(replacing: NSRange(location: prefix, length: replacedLength),
                                    withLength: insertedLength, mentions: mentions)
        }

        private func adjustedMentions(replacing range: NSRange, withLength insertedLength: Int,
                                      mentions: [GroupMentionToken]) -> [GroupMentionToken] {
            let delta = insertedLength - range.length
            let editEnd = NSMaxRange(range)
            return mentions.compactMap { mention in
                var updated = mention
                let mentionEnd = NSMaxRange(mention.range)
                if editEnd <= mention.range.location {
                    updated.range.location += delta
                    return updated
                }
                if range.location >= mentionEnd { return updated }
                return nil
            }
        }
    }
}
