import Foundation

/// Karty drogowe jako dokument Word (.docx), do dowolnej edycji w Word / Pages / Google Docs.
/// Układ jak w PDF: jedna strona A4 na kartę (15 wierszy + suma).
extension KartaExport {
    static func docx(rows: [KartaRow], header: KartaHeader, month: Date) throws -> URL {
        var body = ""
        for (i, card) in rows.chunked(tripsPerCard).enumerated() {
            if i > 0 { body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            body += Docx.card(card, header: header)
        }
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/>\
        <w:pgMar w:top="1000" w:right="1000" w:bottom="850" w:left="1000" w:header="0" w:footer="0" w:gutter="0"/>\
        </w:sectPr></w:body></w:document>
        """
        let files: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(Docx.contentTypes.utf8)),
            ("_rels/.rels", Data(Docx.rels.utf8)),
            ("word/document.xml", Data(document.utf8)),
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karta_drogowa_\(fileMonth(month)).docx")
        try Zip.store(files).write(to: url, options: .atomic)
        return url
    }
}

private enum Docx {
    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    </Types>
    """

    static let rels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="word/document.xml"/></Relationships>
    """

    /// Szerokość tekstu na stronie A4 (11906 − 2 × 1000), w twipach.
    static let width = 9906

    static func card(_ card: [KartaRow], header: KartaHeader) -> String {
        var x = ""
        let title = "KARTA DROGOWA od \(Fmt.full(card.first!.date)) r. do \(Fmt.full(card.last!.date)) r."
        x += para(title, size: 13, bold: true, align: "center", after: 360)

        let half = width / 2
        x += table(cols: [half, half], rows: [
            ("Nazwa przewoźnika", header.carrier),
            ("Marka pojazdu", header.car),
            ("Numer Rejestracyjny", header.registration),
        ].map { label, value in
            row(height: 520, cell(label, width: half, size: 11, align: "left")
                + cell(value, width: half, size: 11, bold: true, align: "left"))
        })
        x += para("", size: 9, after: 240)

        let cols = [640, 960, width - 640 - 960 - 1200, 1200]
        var rows = [row(height: 480, header: true,
                        cell("LP", width: cols[0], size: 9, bold: true)
                        + cell("DATA", width: cols[1], size: 9, bold: true)
                        + cell("Opis trasy + nazwa firmy", width: cols[2], size: 9, bold: true)
                        + cell("KM", width: cols[3], size: 9, bold: true))]
        for i in 0..<KartaExport.tripsPerCard {
            let t = i < card.count ? card[i] : nil
            rows.append(row(height: 600,
                            cell("\(i + 1)", width: cols[0], size: 9)
                            + cell(t.map { Fmt.dayMonth($0.date) } ?? "", width: cols[1], size: 9)
                            + cell(t?.description ?? "", width: cols[2], size: 9, align: "left")
                            + cell(t.map { Fmt.km($0.km) } ?? "", width: cols[3], size: 9)))
        }
        let sum = card.reduce(0) { $0 + $1.km }
        rows.append(row(height: 520,
                        cell("", width: cols[0] + cols[1], size: 9, span: 2)
                        + cell("SUMA", width: cols[2], size: 10, bold: true, align: "right")
                        + cell("\(Fmt.km(sum)) km", width: cols[3], size: 10, bold: true)))
        x += table(cols: cols, rows: rows)

        x += para("", size: 9, after: 0)
        x += para("", size: 9, after: 600)
        x += para("…………………………………………….", size: 9, align: "right", after: 0)
        x += para("Podpis sporządzającego kartę drogową", size: 8, align: "right", after: 0)
        return x
    }

    static func table(cols: [Int], rows: [String]) -> String {
        let b = #"w:val="single" w:sz="4" w:space="0" w:color="000000""#
        let total = cols.reduce(0, +)
        let grid = cols.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        let borders = "<w:tblBorders><w:top \(b)/><w:left \(b)/><w:bottom \(b)/><w:right \(b)/><w:insideH \(b)/><w:insideV \(b)/></w:tblBorders>"
        let margins = #"<w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>"#
        let props = "<w:tblPr><w:tblW w:w=\"\(total)\" w:type=\"dxa\"/>\(borders)<w:tblLayout w:type=\"fixed\"/>\(margins)</w:tblPr>"
        return "<w:tbl>\(props)<w:tblGrid>\(grid)</w:tblGrid>\(rows.joined())</w:tbl>"
    }

    static func row(height: Int, header: Bool = false, _ cells: String) -> String {
        "<w:tr><w:trPr><w:cantSplit/>\(header ? "<w:tblHeader/>" : "")<w:trHeight w:val=\"\(height)\" w:hRule=\"atLeast\"/></w:trPr>\(cells)</w:tr>"
    }

    static func cell(_ text: String, width: Int, size: Int, bold: Bool = false,
                     align: String = "center", span: Int = 1) -> String {
        let spanXML = span > 1 ? "<w:gridSpan w:val=\"\(span)\"/>" : ""
        let p = para(text, size: size, bold: bold, align: align, after: 0)
        return "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>\(spanXML)<w:vAlign w:val=\"center\"/></w:tcPr>\(p)</w:tc>"
    }

    static func para(_ text: String, size: Int, bold: Bool = false, align: String = "left", after: Int) -> String {
        let fonts = #"<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>"#
        let rPr = "<w:rPr>\(fonts)\(bold ? "<w:b/>" : "")<w:sz w:val=\"\(size * 2)\"/></w:rPr>"
        // Każda linia osobno, rozdzielone <w:br/>, żeby enter z edycji w aplikacji przeszedł do Worda.
        let runs = text.components(separatedBy: "\n").map {
            "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r>"
        }.joined(separator: "<w:r>\(rPr)<w:br/></w:r>")
        return "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"\(after)\"/><w:jc w:val=\"\(align)\"/>\(rPr)</w:pPr>\(runs)</w:p>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Minimalny zapis ZIP bez kompresji (metoda „store”) – wystarcza na plik .docx.
enum Zip {
    static func store(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(out.count)
            let size = UInt32(file.data.count)

            out.le32(0x0403_4b50)
            out.le16(20); out.le16(0x0800); out.le16(0)      // wersja, flagi (UTF-8), metoda: store
            out.le16(0); out.le16(0x21)                        // czas, data (1980-01-01)
            out.le32(crc); out.le32(size); out.le32(size)
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(file.data)

            central.le32(0x0201_4b50)
            central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(0); central.le16(0x21)
            central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0)
            central.le32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4b50)
        out.le16(0); out.le16(0)
        out.le16(UInt16(files.count)); out.le16(UInt16(files.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset)
        out.le16(0)
        return out
    }

    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
