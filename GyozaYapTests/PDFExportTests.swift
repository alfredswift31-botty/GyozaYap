import Foundation
import PDFKit
import Testing
@testable import GyozaYap

@MainActor
struct PDFExportTests {

    @Test func longTranscriptsFlowOntoMultiplePages() throws {
        var meeting = Meeting(title: "Long call", startedAt: Date())
        meeting.segments = (0..<400).map { index in
            TranscriptSegment(
                speaker: index.isMultiple(of: 2) ? .me : .others,
                start: TimeInterval(index * 10),
                end: TimeInterval(index * 10 + 5),
                text: "Sentence number \(index) about the roadmap and the budget."
            )
        }

        let data = PDFExport.pdfData(for: meeting)
        let document = try #require(PDFDocument(data: data))

        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(document.pageCount > 1)
        #expect(document.string?.contains("Sentence number 399") == true)
    }

    @Test func styledTextDropsMarkdownSyntax() {
        let styled = PDFExport.styled(fromMarkdown: "## Decisions\n- [ ] **Sam:** Ship it\n- Point")

        #expect(styled.string == "\nDecisions\n☐ Sam: Ship it\n•  Point\n")
    }
}
