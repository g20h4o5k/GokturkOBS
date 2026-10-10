import Foundation

struct StudentProfileHTMLParser {
    func parse(html: String, profilePageURL: URL) -> StudentProfile? {
        let source = html as NSString
        let listPattern = #"<dl\b[^>]*>(.*?)</dl>"#
        let listExpression = try? NSRegularExpression(
            pattern: listPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let listMatches = listExpression?
            .matches(in: html, range: NSRange(location: 0, length: source.length)) ?? []
        print("[Profile Parser] <dl> block count: \(listMatches.count)")

        let allValues = listMatches.compactMap { match -> [String: String]? in
                guard match.numberOfRanges == 2 else {
                    return nil
                }
                return fieldValues(in: source.substring(with: match.range(at: 1)))
            }
        let studentValues = allValues.first { values in
            values["Öğrenci Numara"] != nil &&
                values["Sınıf Kodu"] != nil &&
                values["İsim Soyisim"] != nil
        }
        let parentName = allValues.first { values in
            values["İsim Soyisim"] != nil && values["Öğrenci Numara"] == nil && values["Sınıf Kodu"] == nil
        }?["İsim Soyisim"]

        // Eski veya eksik HTML varyantlarında ilk alanı koruyarak güvenli bir fallback sağla.
        let values = studentValues ?? fieldValues(in: html)
        print("[Profile Parser] Student block matched: \(studentValues != nil)")
        print("[Profile Parser] Field labels: \(values.keys.sorted().joined(separator: ", "))")
        guard let stuNo = values["Öğrenci Numara"], !stuNo.isEmpty,
              let classId = values["Sınıf Kodu"], !classId.isEmpty,
              let name = values["İsim Soyisim"], !name.isEmpty else {
            return nil
        }

        return StudentProfile(
            stuNo: stuNo,
            classId: classId,
            name: name,
            photoURL: photoURL(from: html, source: source, profilePageURL: profilePageURL),
            parentName: parentName
        )
    }

    private func fieldValues(in html: String) -> [String: String] {
        let pattern = #"<dt\b[^>]*>(.*?)</dt>\s*<dd\b[^>]*>(.*?)</dd>"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return [:]
        }

        let source = html as NSString
        var values: [String: String] = [:]
        for match in expression.matches(
            in: html,
            range: NSRange(location: 0, length: source.length)
        ) where match.numberOfRanges == 3 {
            let label = decodeHTMLText(source.substring(with: match.range(at: 1)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard values[label] == nil else {
                continue
            }
            values[label] = decodeHTMLText(source.substring(with: match.range(at: 2)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }

    private func photoURL(from html: String, source: NSString, profilePageURL: URL) -> URL? {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*["']([^"']*studentPhoto\.php[^"']*)["'][^>]*>"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let match = expression.firstMatch(
            in: html,
            range: NSRange(location: 0, length: source.length)
        ), match.numberOfRanges == 2 else {
            print("[Profile Parser] studentPhoto.php image source not found")
            return nil
        }

        let relativePath = decodeHTMLText(source.substring(with: match.range(at: 1)))
        let parsedComponents = URLComponents(string: relativePath)
        let queryNames = parsedComponents?.queryItems?.map(\.name).sorted() ?? []
        print("[Profile Parser] Photo source path: \(parsedComponents?.path ?? "<invalid>")")
        print("[Profile Parser] Photo query keys: \(queryNames.isEmpty ? "<none>" : queryNames.joined(separator: ", "))")
        if relativePath.hasPrefix("images/"),
           var origin = URLComponents(url: profilePageURL, resolvingAgainstBaseURL: false) {
            origin.path = "/"
            origin.query = nil
            origin.fragment = nil
            if let rootURL = origin.url {
                return URL(string: relativePath, relativeTo: rootURL)?.absoluteURL
            }
        }
        return URL(string: relativePath, relativeTo: profilePageURL)?.absoluteURL
    }

    private func decodeHTMLText(_ html: String) -> String {
        let tagPattern = #"<[^>]+>"#
        let stripped = html.replacingOccurrences(
            of: tagPattern,
            with: "",
            options: .regularExpression
        )
        var result = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)

        guard let expression = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else {
            return result
        }

        for match in expression.matches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length)
        ).reversed() {
            let source = result as NSString
            let entity = source.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if entity.lowercased().hasPrefix("x") {
                scalarValue = UInt32(entity.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(entity)
            }
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            result = source.replacingCharacters(in: match.range, with: String(scalar))
        }

        return result
    }
}
