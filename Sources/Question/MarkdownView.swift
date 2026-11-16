import SwiftUI
import Textual

/// Renders an answer as rich text: headings, lists, tables, block quotes, links,
/// and syntax-highlighted code blocks with a copy button.
struct MarkdownView: View {
    let text: String

    var body: some View {
        // Environment values set closest to the view win, so the overrides come before the base style.
        StructuredText(markdown: text)
            .textual.inlineStyle(
                InlineStyle()
                    .code(.monospaced, .fontScale(0.9), .backgroundColor(Color.primary.opacity(0.1)))
                    .strong(.fontWeight(.semibold))
                    .link(.foregroundColor(Color.accentColor)))
            .textual.headingStyle(AnswerHeadingStyle())
            .textual.codeBlockStyle(AnswerCodeBlockStyle())
            .textual.tableStyle(AnswerTableStyle())
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// A code block with a language label and a copy button above the code.
private struct AnswerCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.languageHint ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton { configuration.codeBlock.copyToPasteboard() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05))

            Overflow {
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.225))
                    .textual.fontScale(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(12)
            }
        }
        .background(.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .textual.blockSpacing(.init(top: 0, bottom: 16))
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
