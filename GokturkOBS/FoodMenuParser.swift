import Foundation
import PDFKit

struct FoodMenuDay: Identifiable, Equatable {
    let heading: String
    let items: [String]
    let pageIndex: Int
    var id: String { "\(pageIndex)|\(heading)" }
}

enum FoodMenuParser {
    private static let weekdays = ["pazartesi", "salı", "çarşamba", "perşembe", "cuma"]

    private struct TextCell {
        var bounds: CGRect
        var fragments: [(text: String, bounds: CGRect)]

        var text: String {
            fragments
                .sorted {
                    if abs($0.bounds.midY - $1.bounds.midY) > 1 {
                        return $0.bounds.midY > $1.bounds.midY
                    }
                    return $0.bounds.minX < $1.bounds.minX
                }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    static func parse(_ document: PDFDocument) -> [FoodMenuDay] {
        var result: [FoodMenuDay] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard let selection = page.selection(for: bounds) else { continue }
            let lines = selection.selectionsByLine().compactMap { line -> (String, CGRect)? in
                guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                return (text, line.bounds(for: page))
            }
            let headings = lines.filter { line in
                let normalized = line.0.lowercased(with: Locale(identifier: "tr_TR"))
                return weekdays.contains { normalized.contains($0) }
            }.sorted { $0.1.minX < $1.1.minX }
            guard !headings.isEmpty else { continue }

            for (index, heading) in headings.enumerated() {
                let previousX = index == 0 ? bounds.minX : (headings[index - 1].1.midX + heading.1.midX) / 2
                let nextX = index + 1 == headings.count ? bounds.maxX : (heading.1.midX + headings[index + 1].1.midX) / 2
                let candidates = lines.filter {
                    $0.1.midX >= previousX && $0.1.midX < nextX && $0.1.maxY < heading.1.minY
                }
                let meals = mergeTableCells(candidates)
                if !meals.isEmpty { result.append(FoodMenuDay(heading: heading.0, items: meals, pageIndex: pageIndex)) }
            }
        }
        return result
    }

    private static func mergeTableCells(_ lines: [(String, CGRect)]) -> [String] {
        let fragments = lines.compactMap { text, bounds -> (text: String, bounds: CGRect)? in
            let normalized = text.replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            guard normalized.rangeOfCharacter(from: .letters) != nil else { return nil }
            return (normalized, bounds)
        }
        .sorted { $0.bounds.midY > $1.bounds.midY }

        var cells: [TextCell] = []
        for fragment in fragments {
            if let cellIndex = cells.indices.last,
               verticalRangesOverlap(cells[cellIndex].bounds, fragment.bounds) {
                cells[cellIndex].bounds = cells[cellIndex].bounds.union(fragment.bounds)
                cells[cellIndex].fragments.append(fragment)
            } else {
                cells.append(TextCell(bounds: fragment.bounds, fragments: [fragment]))
            }
        }
        return cells.map(\.text)
    }

    private static func verticalRangesOverlap(_ first: CGRect, _ second: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return second.maxY >= first.minY - tolerance
            && second.minY <= first.maxY + tolerance
    }
}
