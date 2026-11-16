import AppKit
import SwiftUI
import Textual

/// Renders an answer as rich text: headings, lists, tables, block quotes, links,
/// and syntax-highlighted code blocks with a copy button.
///
/// Top-level code blocks are split out and drawn by `CodeBlockView`. Textual can host them itself,
/// but its text-selection overlay covers the whole document and swallows clicks, so a Copy button
/// placed inside it never fires and the code can't be selected.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.segments(of: text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let markdown): ProseView(markdown: markdown)
                case .code(let language, let code): CodeBlockView(language: language, code: code)
                }
            }
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Segment: Equatable {
        case prose(String)
        case code(language: String?, code: String)
    }

    /// Splits markdown at top-level fenced code blocks. A fence still open at the end (mid-stream) counts as code.
    static func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var fence: (marker: Character, length: Int, language: String?)?

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segments.append(.prose(joined)) }
            prose = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix { $0 == " " }.count
            let body = line.dropFirst(indent)
            let marker = body.first
            let run = body.prefix { $0 == marker }.count
            let rest = body.dropFirst(run).trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if marker == open.marker, run >= open.length, rest.isEmpty {
                    segments.append(.code(language: open.language, code: code.joined(separator: "\n")))
                    code = []
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if indent <= 3, let marker, marker == "`" || marker == "~", run >= 3, !rest.contains("`") {
                flushProse()
                fence = (marker, run, rest.split(separator: " ").first.map(String.init))
            } else {
                prose.append(line)
            }
        }
        if let fence {
            segments.append(.code(language: fence.language, code: code.joined(separator: "\n")))
        } else {
            flushProse()
        }
        return segments
    }
}

private struct ProseView: View {
    let markdown: String

    var body: some View {
        // Environment values set closest to the view win, so the overrides come before the base style.
        StructuredText(markdown: markdown)
            .textual.inlineStyle(.answer)
            .textual.headingStyle(AnswerHeadingStyle())
            .textual.codeBlockStyle(NestedCodeBlockStyle())
            .textual.tableStyle(AnswerTableStyle())
            .textual.structuredTextStyle(.gitHub)
            .textual.overflowMode(.wrap)   // scrolling regions would be dead to the mouse, see MarkdownView
            .textual.textSelection(.enabled)
    }
}

extension InlineStyle {
    fileprivate static var answer: InlineStyle {
        InlineStyle()
            .code(.monospaced, .fontScale(0.9), .backgroundColor(Color.primary.opacity(0.1)))
            .strong(.fontWeight(.semibold))
            .link(.foregroundColor(Color.accentColor))
    }
}

/// A code block with a language label and a copy button above selectable, highlighted code.
private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05))

            ScrollView(.horizontal) {
                // Textual does the highlighting; the whole view scrolls, so its selection overlay scrolls with it.
                StructuredText(markdown: fenced)
                    .textual.codeBlockStyle(BareCodeBlockStyle())
                    .textual.overflowMode(.wrap)
                    .textual.textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    /// The code wrapped in a fence longer than any backtick run inside it.
    private var fenced: String {
        var longest = 0, current = 0
        for character in code {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\(language ?? "")\n\(code)\n\(fence)"
    }
}

/// Just the highlighted code; `CodeBlockView` supplies the chrome.
private struct BareCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.225))
            .textual.fontScale(0.9)
            .monospaced()
    }
}

/// Code nested in a list or quote stays inside Textual: wrapped, selectable, no header.
private struct NestedCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.225))
            .textual.fontScale(0.9)
            .monospaced()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .textual.blockSpacing(.init(top: 0, bottom: 16))
    }
}

/// Headings sized for a pop-up panel rather than a full document.
private struct AnswerHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.4, 1.25, 1.1, 1, 0.9, 0.85]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        configuration.label
            .textual.fontScale(Self.fontScales[level - 1])
            .fontWeight(.semibold)
            .textual.blockSpacing(.fontScaled(top: 1.2, bottom: 0.5))
    }
}

/// GitHub's table layout, with translucent fills that sit well on the panel's vibrancy.
private struct AnswerTableStyle: StructuredText.TableStyle {
    private static let border = Color.primary.opacity(0.15)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: 1, vertical: 1)
            .textual.blockSpacing(.init(top: 0, bottom: 16))
            .textual.tableBackground { layout in
                Canvas { context, _ in
                    // Tint the header row.
                    if layout.numberOfRows > 0 {
                        context.fill(Path(layout.rowBounds(0).integral), with: .color(.primary.opacity(0.06)))
                    }
                }
            }
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(Path(divider), with: .color(Self.border))
                    }
                }
            }
            .padding(1)
            .border(Self.border, width: 1)
    }
}

private struct CopyButton: View {
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
