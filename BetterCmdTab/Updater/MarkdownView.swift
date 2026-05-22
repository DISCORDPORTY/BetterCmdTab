import SwiftUI

struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(for: level))
                .padding(.top, level == 1 ? 4 : 2)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(inline(text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(item))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(inline(item))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(inline(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .rule:
            Divider()
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        case 4: return .subheadline.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        if let parsed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            return parsed
        }
        return AttributedString(text)
    }

    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case codeBlock(String)
        case blockquote(String)
        case rule
    }

    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = source.components(separatedBy: "\n")
        var index = 0

        var paragraphBuffer: [String] = []
        var unorderedBuffer: [String] = []
        var orderedBuffer: [String] = []
        var quoteBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(paragraphBuffer.joined(separator: " ")))
            paragraphBuffer.removeAll()
        }
        func flushUnordered() {
            guard !unorderedBuffer.isEmpty else { return }
            blocks.append(.unorderedList(unorderedBuffer))
            unorderedBuffer.removeAll()
        }
        func flushOrdered() {
            guard !orderedBuffer.isEmpty else { return }
            blocks.append(.orderedList(orderedBuffer))
            orderedBuffer.removeAll()
        }
        func flushQuote() {
            guard !quoteBuffer.isEmpty else { return }
            blocks.append(.blockquote(quoteBuffer.joined(separator: " ")))
            quoteBuffer.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushUnordered()
            flushOrdered()
            flushQuote()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if line == "---" || line == "***" || line == "___" {
                flushAll()
                blocks.append(.rule)
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                flushAll()
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let inner = lines[index]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    code.append(inner)
                    index += 1
                }
                blocks.append(.codeBlock(code.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(line) {
                flushAll()
                blocks.append(.heading(level: heading.0, text: heading.1))
                index += 1
                continue
            }

            if let item = parseUnordered(line) {
                flushParagraph()
                flushOrdered()
                flushQuote()
                unorderedBuffer.append(item)
                index += 1
                continue
            }

            if let item = parseOrdered(line) {
                flushParagraph()
                flushUnordered()
                flushQuote()
                orderedBuffer.append(item)
                index += 1
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                flushUnordered()
                flushOrdered()
                let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces)
                quoteBuffer.append(String(stripped))
                index += 1
                continue
            }

            flushUnordered()
            flushOrdered()
            flushQuote()
            paragraphBuffer.append(line)
            index += 1
        }

        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        let chars = Array(line)
        while level < chars.count && chars[level] == "#" {
            level += 1
        }
        guard level > 0, level <= 6, level < chars.count, chars[level] == " " else {
            return nil
        }
        let text = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseUnordered(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let first = line.first!
        let second = line.index(after: line.startIndex)
        guard first == "-" || first == "*" || first == "+", line[second] == " " else {
            return nil
        }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseOrdered(_ line: String) -> String? {
        var idx = line.startIndex
        var digits = ""
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        idx = line.index(after: idx)
        return String(line[idx...]).trimmingCharacters(in: .whitespaces)
    }
}
