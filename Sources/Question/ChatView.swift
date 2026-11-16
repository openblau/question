import AppKit
import SwiftUI

struct ChatView: View {
    let session: ChatSession
    let onEndSession: () -> Void
    let onExpandedChange: (Bool) -> Void

    @State private var input = ""
    @State private var keyError: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            if !session.turns.isEmpty {
                Divider()
                transcript
                Divider()
                footer
            }
        }
        .frame(width: PanelController.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .onExitCommand(perform: onEndSession)
        .onChange(of: session.turns.isEmpty) { _, empty in onExpandedChange(!empty) }
        .onChange(of: session.focusTick) { focused = true }
        .onAppear { focused = true }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 12) {
            Image(systemName: session.needsKey ? "key.fill" : "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            Group {
                if session.needsKey {
                    SecureField("Paste your Anthropic API key and press Return", text: $input)
                } else {
                    TextField(session.turns.isEmpty ? "Ask anything…" : "Follow up…", text: $input)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 22))
            .focused($focused)
            .onSubmit(submit)

            if session.needsKey, let keyError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(keyError)
            }

            if session.isBusy {
                Button(action: session.stop) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Stop")
            }

            Label("Incognito", systemImage: "eye.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .help("Nothing is saved. Esc ends the session and erases it from memory.")
        }
        .padding(.horizontal, 20)
        .frame(height: PanelController.compactHeight)
    }

    private func submit() {
        let text = input
        input = ""
        if session.needsKey {
            do { try session.saveKey(text); keyError = nil } catch { keyError = error.localizedDescription }
        } else {
            session.ask(text)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(session.turns) { TurnView(turn: $0) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
            }
            .onChange(of: session.turns.last?.answer) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: session.turns.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("esc  end session")
            Text("⌥space  hide")
            Spacer()
            Button("New chat") { session.end(); onExpandedChange(false) }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.plain)
            Text("Nothing is saved")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct TurnView: View {
    let turn: ChatSession.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(turn.question)
                .font(.system(size: 15, weight: .semibold))
                .textSelection(.enabled)

            if !turn.answer.isEmpty {
                Text(markdown(turn.answer))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = turn.status, !turn.done {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !turn.sources.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(turn.sources.prefix(6).enumerated()), id: \.offset) { index, source in
                        if let url = URL(string: source.url) {
                            Link("\(index + 1). \(source.title)", destination: url)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
