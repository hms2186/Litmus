import Foundation
import PDFKit
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
var out: [[String: Any]] = []
for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let box = page.bounds(for: .mediaBox)
    guard let sel = page.selection(for: box) else { continue }
    for line in sel.selectionsByLine() {
        let b = line.bounds(for: page)
        out.append(["p": i + 1, "x0": b.minX, "y0": b.minY, "x1": b.maxX, "y1": b.maxY, "t": line.string ?? "", "w": box.width, "h": box.height])
    }
}
let data = try JSONSerialization.data(withJSONObject: out)
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("lines", out.count)
