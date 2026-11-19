import Foundation

/// LRC 歌词解析，兼容一行多时间标签、[offset:] 与逐字歌词（降级为按行）
enum LyricParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        guard !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var offset: Double = 0
        var lines: [(Double, String)] = []

        let pattern = "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if let offsetMatch = firstMatch(regex: try? NSRegularExpression(pattern: "\\[offset:\\s*(-?\\d+)\\s*\\]", options: []), in: line) {
                offset = (Double(offsetMatch) ?? 0) / 1000
                continue
            }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            let lastEnd = matches.last!.range.location + matches.last!.range.length
            // NSRange 以 UTF-16 计，中文/emoji 歌词必须用 Range(_:in:) 换算，不能按 Character 偏移
            let tailRange = NSRange(location: lastEnd, length: (line as NSString).length - lastEnd)
            let textStart = Range(tailRange, in: line)?.lowerBound ?? line.endIndex
            var text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
            // 逐字歌词 <开始,持续> 标记去掉，保留文字
            if text.contains("<") {
                text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            }
            if text.isEmpty { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line) else { continue }
                let minute = Double(line[minuteRange]) ?? 0
                let second = Double(line[secondRange]) ?? 0
                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let digits = String(line[fractionRange])
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                lines.append((minute * 60 + second + fraction + offset, text))
            }
        }

        let sorted = lines.sorted { $0.0 < $1.0 }
        return sorted.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    static func currentIndex(lines: [LyricLine], time: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var answer = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer >= 0 ? answer : nil
    }

    private static func firstMatch(regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex = regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }
}
