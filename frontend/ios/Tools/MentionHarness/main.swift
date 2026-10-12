import SwiftUI
import UIKit

@MainActor @Observable final class DraftState {
    var text = ""
    var mentions: [GroupMentionToken] = []
    var selection = NSRange(location: 0, length: 0)
    var focused = false
    var composing = false
    var submitted = 0
}

struct EditorProbe: View {
    @Bindable var state: DraftState
    var body: some View {
        MentionTextEditor(text: $state.text, mentions: $state.mentions, selection: $state.selection,
                          isFocused: $state.focused, isComposing: $state.composing,
                          onSubmit: { state.submitted += 1 })
            .frame(width: 300).padding()
    }
}

@main @MainActor final class ProbeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let state = DraftState()
    var results: [String] = []
    var failures = 0
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: EditorProbe(state: state))
        window.makeKeyAndVisible()
        self.window = window
        Task { await run() }
        return true
    }
    func check(_ passed: Bool, _ name: String) {
        results.append("\(passed ? "PASS" : "FAIL") \(name)")
        if !passed { failures += 1 }
    }
    func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
    func findEditor(_ view: UIView) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        for child in view.subviews { if let editor = findEditor(child) { return editor } }
        return nil
    }
    func query(_ text: String, _ caret: Int, tokens: [GroupMentionToken] = []) -> String? {
        guard let range = GroupMentionToken.activeRange(in: text, selection: NSRange(location: caret, length: 0), mentions: tokens) else { return nil }
        return String(text[range])
    }
    func run() async {
        await settle()
        guard let editor = window.flatMap({ findEditor($0) }),
              let coordinator = editor.delegate as? MentionTextEditor.Coordinator else {
            check(false, "editor is mounted")
            finish(); return
        }
        check(!editor.isFirstResponder, "opening chat does not force keyboard")
        state.focused = true
        await settle()
        check(editor.isFirstResponder && state.focused, "focus request opens keyboard")
        editor.text = "你好 @Bo 后面的正文"
        editor.selectedRange = NSRange(location: 6, length: 0)
        coordinator.textViewDidChange(editor)
        await settle()
        check(editor.isFirstResponder, "draft update keeps keyboard open")
        check(editor.selectedRange.location == 6 && state.selection.location == 6, "draft update preserves middle caret")
        check(query(state.text, 6) == "@Bo", "mention query stops at caret and preserves suffix")
        check(query("a@b.com", 3) == nil, "email is not a mention")
        check(query("你好 @Bot 正文", 10) == nil, "whitespace closes picker query")
        check(query("🙂 @", 4) == "@", "UTF16 caret works after emoji")
        check(GroupMentionToken.activeRange(in: "@Bot", selection: NSRange(location: 1, length: 2), mentions: []) == nil, "selection does not open picker")
        let token = GroupMentionToken(text: "@Bot", range: NSRange(location: 0, length: 4), target: .bot(id: 1))
        check(query("@Bot ", 3, tokens: [token]) == nil, "completed mention does not reopen picker")
        let spacedToken = GroupMentionToken(text: "@Bot", range: NSRange(location: 2, length: 4), target: .bot(id: 1))
        let trimmedToken = spacedToken.adjustedForTrimmedDraft("@Bot 正文", leading: 2)
        check(trimmedToken?.range.location == 0 && trimmedToken?.target == .bot(id: 1), "trimming a pending send preserves mention identity and routing")
        check(token.adjustedForTrimmedDraft("", leading: 0) == nil, "accepted empty draft has no mention identity")
        state.mentions = [token]
        state.text = "@Bot 正文"
        state.selection = NSRange(location: 5, length: 0)
        await settle()
        check(editor.selectedRange.location == 5 && editor.isFirstResponder, "candidate insertion keeps caret and keyboard")
        check((editor.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) == UIColor(Color.brandAccent), "mention uses accent color")
        check((editor.typingAttributes[.foregroundColor] as? UIColor) == UIColor.label, "following text uses normal color")
        editor.selectedRange = NSRange(location: 1, length: 0)
        editor.insertText("x")
        await settle()
        check(state.mentions.isEmpty, "editing inside mention removes routing token")
        state.text = "@Bot "
        state.mentions = [token]
        state.selection = NSRange(location: 0, length: 0)
        await settle()
        editor.insertText("@Bot ")
        await settle()
        check(state.mentions.first?.range.location == 5, "identical prefix insertion shifts the original mention, not the pasted copy")
        state.focused = false
        await settle()
        check(!editor.isFirstResponder && !state.focused, "dismiss request closes keyboard")
        state.focused = true
        await settle()
        check(editor.isFirstResponder, "keyboard can reopen after dismissal")
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        coordinator.textViewDidChange(editor)
        await settle()
        check(editor.markedTextRange != nil && state.composing, "SwiftUI updates preserve marked Chinese input")
        check(coordinator.textView(editor, shouldChangeTextIn: editor.selectedRange, replacementText: "\n"), "return during composition does not send")
        editor.unmarkText()
        coordinator.textViewDidChange(editor)
        await settle()
        check(!state.composing, "committing composition clears composing state")
        check(!coordinator.textView(editor, shouldChangeTextIn: editor.selectedRange, replacementText: "\n") && state.submitted == 1, "send key submits exactly once")
        check(coordinator.textView(editor, shouldChangeTextIn: editor.selectedRange, replacementText: "第一行\n第二行"), "pasting multiline text does not send")
        state.text = String(repeating: "长文字 ", count: 100)
        state.selection = NSRange(location: (state.text as NSString).length, length: 0)
        await settle()
        check(editor.isScrollEnabled && editor.bounds.height < 170, "long draft scrolls within five-line editor")
        finish()
    }
    func finish() {
        results.append("checks=\(results.count) failures=\(failures)")
        try? results.joined(separator: "\n").write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }
}
