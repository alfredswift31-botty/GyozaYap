import AppKit
import CoreText
import Foundation

/// Paginated PDF rendering with Core Text, so long transcripts flow across
/// pages instead of being clipped to one image.
enum PDFExport {
    static func pdfData(for meeting: Meeting, includeTranscript: Bool = true) -> Data {
        let markdown = MeetingExport.markdown(meeting, includeTranscript: includeTranscript)
        return render(styled(fromMarkdown: stripFrontMatter(markdown)))
    }

    /// Converts the subset of Markdown that `MeetingExport` produces into
    /// styled text: headings, bullets, checkboxes and bold speaker names.
    static func styled(fromMarkdown markdown: String) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 11)
        let bold = NSFont.boldSystemFont(ofSize: 11)
        let result = NSMutableAttributedString()

        func append(_ text: String, font: NSFont) {
            result.append(NSAttributedString(string: text, attributes: [.font: font]))
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            var line = rawLine
            if line.hasPrefix("# ") {
                append(String(line.dropFirst(2)) + "\n", font: .boldSystemFont(ofSize: 20))
                continue
            }
            if line.hasPrefix("## ") {
                append("\n" + String(line.dropFirst(3)) + "\n", font: .boldSystemFont(ofSize: 15))
                continue
            }
            if line.hasPrefix("### ") {
                append(String(line.dropFirst(4)) + "\n", font: .boldSystemFont(ofSize: 12))
                continue
            }
            if line == "---" {
                append("\n", font: body)
                continue
            }
            if line.hasPrefix("- [ ] ") {
                line = "☐ " + line.dropFirst(6)
            } else if line.hasPrefix("- [x] ") {
                line = "☑ " + line.dropFirst(6)
            } else if line.hasPrefix("- ") {
                line = "•  " + line.dropFirst(2)
            }
            if line.hasPrefix("*"), line.hasSuffix("*"), !line.hasPrefix("**"), line.count > 1 {
                line = String(line.dropFirst().dropLast())
            }
            // "**Bold**" runs become bold; everything else is body text.
            let parts = line.components(separatedBy: "**")
            for (index, part) in parts.enumerated() where !part.isEmpty {
                append(part, font: index.isMultiple(of: 2) ? body : bold)
            }
            append("\n", font: body)
        }
        return result
    }

    /// Lays text out on US Letter pages with 0.75" margins.
    static func render(_ text: NSAttributedString) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let textRect = mediaBox.insetBy(dx: 54, dy: 54)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            // A zero-length page would loop forever; stop instead.
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < text.length
        context.closePDF()
        return data as Data
    }

    private static func stripFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n"),
              let end = markdown.range(of: "\n---\n", range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex) else {
            return markdown
        }
        return String(markdown[end.upperBound...])
    }
}
