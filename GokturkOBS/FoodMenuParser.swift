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
                }.sorted {
                    abs($0.1.midY - $1.1.midY) > max($0.1.height, $1.1.height) * 0.55
                        ? $0.1.midY > $1.1.midY
                        : $0.1.minX < $1.1.minX
                }
                var meals: [String] = []
                for candidate in candidates {
                    let text = candidate.0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    guard text.rangeOfCharacter(from: .letters) != nil else { continue }
                    if let last = meals.last, candidate.1.height < heading.1.height * 0.9,
                       candidate.1.minY.distance(to: heading.1.minY) < bounds.height * 0.65 {
                        meals[meals.count - 1] = last + " " + text
                    } else {
                        meals.append(text)
                    }
                }
                if !meals.isEmpty { result.append(FoodMenuDay(heading: heading.0, items: meals, pageIndex: pageIndex)) }
            }
        }
        return result
    }
}

private extension CGFloat {
    func distance(to other: CGFloat) -> CGFloat { abs(self - other) }
}
