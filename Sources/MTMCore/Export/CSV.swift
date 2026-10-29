import Foundation

/// RFC 4180 CSV (쉼표·따옴표·줄바꿈이 든 값은 따옴표로 감싼다)
public enum CSV {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func decode(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text).makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let c = pending { pending = nil; return c }
            return iterator.next()
        }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { inQuotes = false; pending = following }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r\n", "\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
