import UIKit

/// Dane nagłówka karty drogowej.
struct KartaHeader {
    var carrier: String
    var car: String
    var registration: String
}

/// Karty drogowe po 15 kursów (PDF A4) i zestawienie CSV do Excela.
enum KartaExport {
    static let tripsPerCard = 15

    static func pdf(trips: [Trip], header: KartaHeader, month: Date) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karta_drogowa_\(fileMonth(month)).pdf")
        try renderer.writePDF(to: url) { ctx in
            for card in trips.chunked(tripsPerCard) {
                ctx.beginPage()
                drawCard(card, header: header, in: page)
            }
        }
        return url
    }

    static func csv(trips: [Trip], month: Date, rate: Double) throws -> URL {
        var rows = ["Karta;LP;Data;Opis trasy;KM"]
        for (i, card) in trips.chunked(tripsPerCard).enumerated() {
            for (j, t) in card.enumerated() {
                rows.append("\(i + 1);\(j + 1);\(Fmt.full(t.date));\(t.routeDescription);\(Fmt.km(t.km))")
            }
            rows.append(";;;SUMA KARTA \(i + 1);\(Fmt.km(card.reduce(0) { $0 + $1.km }))")
        }
        let total = trips.reduce(0) { $0 + $1.km }
        rows.append(";;;SUMA \(Fmt.month(month).uppercased());\(Fmt.km(total))")
        if rate > 0 {
            rows.append(";;;DO ZAPŁATY (\(rate) zł/km);\(Fmt.km((total * rate * 100).rounded() / 100))")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilometry_\(fileMonth(month)).csv")
        // BOM, żeby Excel poprawnie pokazał polskie znaki.
        try ("\u{FEFF}" + rows.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func fileMonth(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return String(format: "%04ld-%02ld", c.year ?? 0, c.month ?? 0)
    }

    // MARK: - Rysowanie

    private static func drawCard(_ card: [Trip], header: KartaHeader, in page: CGRect) {
        let margin: CGFloat = 50
        let width = page.width - 2 * margin
        var y: CGFloat = 50

        let title = "KARTA DROGOWA od \(Fmt.full(card.first!.date)) r. do \(Fmt.full(card.last!.date)) r."
        draw(title, in: CGRect(x: margin, y: y, width: width, height: 20), size: 13, bold: true, align: .center)
        y += 36

        let infoRows = [
            ("Nazwa przewoźnika", header.carrier),
            ("Marka pojazdu", header.car),
            ("Numer Rejestracyjny", header.registration),
        ]
        for (label, value) in infoRows {
            let half = width / 2
            cell(label, CGRect(x: margin, y: y, width: half, height: 26), size: 11)
            cell(value, CGRect(x: margin + half, y: y, width: half, height: 26), size: 11, bold: true)
            y += 26
        }
        y += 18

        let cols: [CGFloat] = [32, 48, width - 32 - 48 - 60, 60]
        func row(_ values: [String], height: CGFloat, bold: Bool = false) {
            var x = margin
            for (i, v) in values.enumerated() {
                cell(v, CGRect(x: x, y: y, width: cols[i], height: height), size: 9, bold: bold,
                     align: i == 2 ? .left : .center)
                x += cols[i]
            }
            y += height
        }
        row(["LP", "DATA", "Opis trasy + nazwa firmy", "KM"], height: 24, bold: true)
        for i in 0..<tripsPerCard {
            if i < card.count {
                let t = card[i]
                row(["\(i + 1)", Fmt.dayMonth(t.date), t.routeDescription, Fmt.km(t.km)], height: 30)
            } else {
                row(["\(i + 1)", "", "", ""], height: 30)
            }
        }
        let sum = card.reduce(0) { $0 + $1.km }
        cell("", CGRect(x: margin, y: y, width: cols[0] + cols[1], height: 26), size: 9)
        cell("SUMA", CGRect(x: margin + cols[0] + cols[1], y: y, width: cols[2], height: 26), size: 10, bold: true, align: .right)
        cell("\(Fmt.km(sum)) km", CGRect(x: margin + width - cols[3], y: y, width: cols[3], height: 26), size: 10, bold: true)
        y += 60

        draw("…………………………………………….", in: CGRect(x: margin, y: y, width: width, height: 14), size: 9, align: .right)
        draw("Podpis sporządzającego kartę drogową", in: CGRect(x: margin, y: y + 14, width: width, height: 14), size: 8, align: .right)
    }

    private static func cell(_ text: String, _ rect: CGRect, size: CGFloat, bold: Bool = false, align: NSTextAlignment = .center) {
        let path = UIBezierPath(rect: rect)
        path.lineWidth = 0.6
        UIColor.black.setStroke()
        path.stroke()
        let inset = rect.insetBy(dx: 4, dy: 3)
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let textHeight = min(inset.height, ceil(font.lineHeight * 2.2))
        let lines = (text as NSString).boundingRect(
            with: CGSize(width: inset.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil
        ).height
        let h = min(textHeight, lines)
        draw(text, in: CGRect(x: inset.minX, y: inset.midY - h / 2, width: inset.width, height: h + 1),
             size: size, bold: bold, align: align)
    }

    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool = false, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
            .paragraphStyle: style,
            .foregroundColor: UIColor.black,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }
}
