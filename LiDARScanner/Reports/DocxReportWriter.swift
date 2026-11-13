import Foundation

enum DocxReportWriter {
    // A4 printable width ~ 9070 twips (~16 cm); 1 inch = 914400 EMU = 1440 twips -> 1 twip = 635 EMU
    private static let pageWidthTwips = 11_906
    private static let pageHeightTwips = 16_838
    private static let marginTwips = 1_134 // 2.0 cm
    private static let contentWidthTwips = pageWidthTwips - 2 * marginTwips // 9,638 twips

    static func write(_ doc: ReportDocument, to url: URL) throws {
        var entries: [(path: String, data: Data)] = []

        var mediaEntries: [(relID: String, filename: String, fig: ReportFigure)] = []
        for (idx, fig) in doc.figures.enumerated() {
            let relID = "rId\(idx + 2)"
            let filename = "media/figure_\(idx + 1).png"
            mediaEntries.append((relID, filename, fig))
            entries.append((path: "word/\(filename)", data: fig.pngData))
        }

        entries.append((path: "[Content_Types].xml", data: Data(contentTypesXML(hasImages: !mediaEntries.isEmpty).utf8)))
        entries.append((path: "_rels/.rels", data: Data(rootRelsXML().utf8)))
        entries.append((path: "word/_rels/document.xml.rels", data: Data(documentRelsXML(mediaEntries).utf8)))
        entries.append((path: "word/styles.xml", data: Data(stylesXML().utf8)))
        entries.append((path: "word/document.xml", data: Data(documentXML(doc, mediaEntries: mediaEntries).utf8)))

        try ZipArchive.createArchive(entries: entries, to: url)
    }

    // MARK: - OOXML Parts

    private static func contentTypesXML(hasImages: Bool) -> String {
        let pngDefault = hasImages ? "<Default Extension=\"png\" ContentType=\"image/png\"/>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          \(pngDefault)
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private static func documentRelsXML(_ media: [(relID: String, filename: String, fig: ReportFigure)]) -> String {
        var rels = """
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        for item in media {
            rels += "\n  <Relationship Id=\"\(item.relID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(item.filename)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(rels)
        </Relationships>
        """
    }

    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue" w:cs="Helvetica Neue"/>
                <w:color w:val="1F2933"/>
                <w:sz w:val="20"/>
                <w:szCs w:val="20"/>
              </w:rPr>
            </w:rPrDefault>
            <w:pPrDefault>
              <w:pPr>
                <w:spacing w:after="120" w:line="276" w:lineRule="auto"/>
              </w:pPr>
            </w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:pPr>
              <w:keepNext/>
              <w:spacing w:before="240" w:after="100"/>
              <w:pBdr>
                <w:bottom w:val="single" w:sz="8" w:space="4" w:color="14B8A6"/>
              </w:pBdr>
            </w:pPr>
            <w:rPr>
              <w:b/>
              <w:color w:val="0F172A"/>
              <w:sz w:val="26"/>
              <w:szCs w:val="26"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Caption">
            <w:name w:val="caption"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr>
              <w:spacing w:before="60" w:after="180"/>
            </w:pPr>
            <w:rPr>
              <w:i/>
              <w:color w:val="52606D"/>
              <w:sz w:val="18"/>
              <w:szCs w:val="18"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="CodeBlock">
            <w:name w:val="Code"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr>
              <w:spacing w:before="40" w:after="40" w:line="240" w:lineRule="auto"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/>
              <w:color w:val="334E68"/>
              <w:sz w:val="16"/>
              <w:szCs w:val="16"/>
            </w:rPr>
          </w:style>
        </w:styles>
        """
    }

    private static func documentXML(
        _ doc: ReportDocument,
        mediaEntries: [(relID: String, filename: String, fig: ReportFigure)]
    ) -> String {
        var body = ""

        // Banner header card
        body += bannerXML(doc)

        // Metrics cards
        if !doc.metrics.isEmpty {
            body += metricsTableXML(doc.metrics)
        }

        // Result preview figures
        if !mediaEntries.isEmpty {
            body += headingXML(LanguageManager.isGerman ? "Visuelle Ergebnisse" : "Visual Results")
            for (idx, item) in mediaEntries.enumerated() {
                body += imageParagraphXML(relID: item.relID, fig: item.fig, docPrID: idx + 1)
                body += captionParagraphXML("\(item.fig.title) — \(item.fig.caption)")
            }
        }

        // Structured sections
        for section in doc.sections {
            body += headingXML(section.heading)
            for block in section.blocks {
                switch block {
                case .paragraph(let text):
                    body += paragraphXML(text)
                case .keyValues(let pairs):
                    body += keyValueTableXML(pairs)
                case .table(let headers, let rows, let dotHexes):
                    body += dataTableXML(headers: headers, rows: rows, dotHexes: dotHexes)
                case .code(let title, let codeText):
                    body += captionParagraphXML(title)
                    body += codeBoxXML(codeText)
                }
            }
        }

        // Footer line
        body += """
        <w:p>
          <w:pPr>
            <w:spacing w:before="280" w:after="40"/>
            <w:pBdr><w:top w:val="single" w:sz="4" w:space="6" w:color="CBD2D9"/></w:pBdr>
          </w:pPr>
          <w:r>
            <w:rPr><w:color w:val="616E7C"/><w:sz w:val="17"/><w:szCs w:val="17"/></w:rPr>
            <w:t xml:space="preserve">\(xmlEscape(doc.footerText))</w:t>
          </w:r>
        </w:p>
        """

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
            \(body)
            <w:sectPr>
              <w:pgSz w:w="\(pageWidthTwips)" w:h="\(pageHeightTwips)"/>
              <w:pgMar w:top="\(marginTwips)" w:right="\(marginTwips)" w:bottom="\(marginTwips)" w:left="\(marginTwips)"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func bannerXML(_ doc: ReportDocument) -> String {
        """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidthTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="none"/><w:left w:val="single" w:sz="24" w:space="0" w:color="14B8A6"/>
              <w:bottom w:val="none"/><w:right w:val="none"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="180" w:type="dxa"/><w:left w:w="220" w:type="dxa"/>
              <w:bottom w:w="180" w:type="dxa"/><w:right w:w="200" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid><w:gridCol w:w="\(contentWidthTwips)"/></w:tblGrid>
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(contentWidthTwips)" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="0F172A"/>
              </w:tcPr>
              <w:p>
                <w:pPr><w:spacing w:after="60"/></w:pPr>
                <w:r>
                  <w:rPr><w:b/><w:color w:val="5EEAD4"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
                  <w:t xml:space="preserve">\(xmlEscape(doc.badge))</w:t>
                </w:r>
              </w:p>
              <w:p>
                <w:pPr><w:spacing w:after="60"/></w:pPr>
                <w:r>
                  <w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr>
                  <w:t xml:space="preserve">\(xmlEscape(doc.title))</w:t>
                </w:r>
              </w:p>
              <w:p>
                <w:pPr><w:spacing w:after="20"/></w:pPr>
                <w:r>
                  <w:rPr><w:color w:val="CBD5E1"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
                  <w:t xml:space="preserve">\(xmlEscape(doc.subtitle)) · \(xmlEscape(doc.generatedAt))</w:t>
                </w:r>
              </w:p>
            </w:tc>
          </w:tr>
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>
        """
    }

    private static func metricsTableXML(_ metrics: [(label: String, value: String)]) -> String {
        let colCount = max(1, metrics.count)
        let colW = contentWidthTwips / colCount
        let gridCols = (0..<colCount).map { _ in "<w:gridCol w:w=\"\(colW)\"/>" }.joined()
        var cells = ""
        for m in metrics {
            cells += """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colW)" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="F4F7F9"/>
              </w:tcPr>
              <w:p>
                <w:pPr><w:spacing w:after="40"/></w:pPr>
                <w:r>
                  <w:rPr><w:b/><w:color w:val="52606D"/><w:sz w:val="15"/><w:szCs w:val="15"/></w:rPr>
                  <w:t xml:space="preserve">\(xmlEscape(m.label.uppercased()))</w:t>
                </w:r>
              </w:p>
              <w:p>
                <w:pPr><w:spacing w:after="0"/></w:pPr>
                <w:r>
                  <w:rPr><w:b/><w:color w:val="102A43"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>
                  <w:t xml:space="preserve">\(xmlEscape(m.value))</w:t>
                </w:r>
              </w:p>
            </w:tc>
            """
        }
        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidthTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="D9E2EC"/>
              <w:left w:val="single" w:sz="6" w:space="0" w:color="D9E2EC"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="D9E2EC"/>
              <w:right w:val="single" w:sz="6" w:space="0" w:color="D9E2EC"/>
              <w:insideV w:val="single" w:sz="6" w:space="0" w:color="D9E2EC"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="110" w:type="dxa"/><w:left w:w="120" w:type="dxa"/>
              <w:bottom w:w="110" w:type="dxa"/><w:right w:w="120" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>\(gridCols)</w:tblGrid>
          <w:tr>\(cells)</w:tr>
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>
        """
    }

    private static func headingXML(_ text: String) -> String {
        """
        <w:p>
          <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
          <w:r><w:t xml:space="preserve">\(xmlEscape(text))</w:t></w:r>
        </w:p>
        """
    }

    private static func paragraphXML(_ text: String) -> String {
        """
        <w:p>
          <w:r><w:t xml:space="preserve">\(xmlEscape(text))</w:t></w:r>
        </w:p>
        """
    }

    private static func captionParagraphXML(_ text: String) -> String {
        """
        <w:p>
          <w:pPr><w:pStyle w:val="Caption"/></w:pPr>
          <w:r><w:t xml:space="preserve">\(xmlEscape(text))</w:t></w:r>
        </w:p>
        """
    }

    private static func keyValueTableXML(_ pairs: [(label: String, value: String)]) -> String {
        let labelW = 3_200
        let valW = contentWidthTwips - labelW
        var rows = ""
        for (idx, pair) in pairs.enumerated() {
            let fill = idx % 2 == 0 ? "F8FAFC" : "FFFFFF"
            rows += """
            <w:tr>
              <w:tc>
                <w:tcPr><w:tcW w:w="\(labelW)" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(fill)"/></w:tcPr>
                <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="334E68"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr><w:t xml:space="preserve">\(xmlEscape(pair.label))</w:t></w:r></w:p>
              </w:tc>
              <w:tc>
                <w:tcPr><w:tcW w:w="\(valW)" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(fill)"/></w:tcPr>
                <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr><w:t xml:space="preserve">\(xmlEscape(pair.value))</w:t></w:r></w:p>
              </w:tc>
            </w:tr>
            """
        }
        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidthTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="D9E2EC"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="D9E2EC"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
              <w:left w:val="none"/><w:right w:val="none"/><w:insideV w:val="none"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="80" w:type="dxa"/><w:left w:w="100" w:type="dxa"/>
              <w:bottom w:w="80" w:type="dxa"/><w:right w:w="100" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid><w:gridCol w:w="\(labelW)"/><w:gridCol w:w="\(valW)"/></w:tblGrid>
          \(rows)
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>
        """
    }

    private static func dataTableXML(headers: [String], rows: [[String]], dotHexes: [String?]?) -> String {
        let count = max(1, headers.count)
        let colW = contentWidthTwips / count
        let gridCols = (0..<count).map { _ in "<w:gridCol w:w=\"\(colW)\"/>" }.joined()

        var xmlRows = "<w:tr><w:tblHeader/>"
        for h in headers {
            xmlRows += """
            <w:tc>
              <w:tcPr><w:tcW w:w="\(colW)" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="E6F4F1"/></w:tcPr>
              <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="102A43"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve">\(xmlEscape(h))</w:t></w:r></w:p>
            </w:tc>
            """
        }
        xmlRows += "</w:tr>"

        for (rIdx, row) in rows.enumerated() {
            let fill = rIdx % 2 == 0 ? "FFFFFF" : "F8FAFC"
            let dotHex = dotHexes?[safe: rIdx] ?? nil
            xmlRows += "<w:tr>"
            for cIdx in 0..<count {
                let text = row[safe: cIdx] ?? ""
                let dotRun: String
                if cIdx == 0, let dotHex {
                    dotRun = "<w:r><w:rPr><w:b/><w:color w:val=\"\(dotHex)\"/><w:sz w:val=\"18\"/></w:rPr><w:t>● </w:t></w:r>"
                } else {
                    dotRun = ""
                }
                xmlRows += """
                <w:tc>
                  <w:tcPr><w:tcW w:w="\(colW)" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(fill)"/></w:tcPr>
                  <w:p><w:pPr><w:spacing w:after="0"/></w:pPr>\(dotRun)<w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve">\(xmlEscape(text))</w:t></w:r></w:p>
                </w:tc>
                """
            }
            xmlRows += "</w:tr>"
        }

        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidthTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="BCCCDC"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="BCCCDC"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
              <w:left w:val="none"/><w:right w:val="none"/><w:insideV w:val="none"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="75" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>
              <w:bottom w:w="75" w:type="dxa"/><w:right w:w="80" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>\(gridCols)</w:tblGrid>
          \(xmlRows)
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>
        """
    }

    private static func codeBoxXML(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { line in
            """
            <w:p>
              <w:pPr><w:pStyle w:val="CodeBlock"/></w:pPr>
              <w:r><w:t xml:space="preserve">\(xmlEscape(line))</w:t></w:r>
            </w:p>
            """
        }.joined()
        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(contentWidthTwips)" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="D9E2EC"/>
              <w:left w:val="single" w:sz="12" w:space="0" w:color="9FB3C8"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="D9E2EC"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="D9E2EC"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="100" w:type="dxa"/><w:left w:w="140" w:type="dxa"/>
              <w:bottom w:w="100" w:type="dxa"/><w:right w:w="140" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid><w:gridCol w:w="\(contentWidthTwips)"/></w:tblGrid>
          <w:tr>
            <w:tc>
              <w:tcPr><w:tcW w:w="\(contentWidthTwips)" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F4F7F9"/></w:tcPr>
              \(lines)
            </w:tc>
          </w:tr>
        </w:tbl>
        <w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>
        """
    }

    private static func imageParagraphXML(relID: String, fig: ReportFigure, docPrID: Int) -> String {
        // Fit content width (~9200 twips = 5,842,000 EMU -> ~6.38 in) preserving aspect ratio
        let cx = 5_842_000
        let cy = max(600_000, Int(Double(cx) * Double(max(1, fig.pixelHeight)) / Double(max(1, fig.pixelWidth))))
        return """
        <w:p>
          <w:pPr><w:keepNext/><w:spacing w:before="80" w:after="40"/></w:pPr>
          <w:r>
            <w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0">
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:docPr id="\(docPrID)" name="\(xmlEscape(fig.id))"/>
                <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="\(docPrID)" name="\(xmlEscape(fig.id)).png"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relID)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    private static func xmlEscape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            // Strip illegal XML 1.0 control characters
            if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D {
                continue
            }
            switch scalar {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&apos;")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
