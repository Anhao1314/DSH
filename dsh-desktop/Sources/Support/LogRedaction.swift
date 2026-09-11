import Foundation

/// 日志与错误文本的出口过滤器：任何进入 UI / 日志 / 通知的字符串都要先过这里。
/// 规则：`token=<值>` 一律替换为 `token=***`，另外屏蔽 `dsh-auth-...` cookie 值。
enum LogRedaction {
    private static let patterns: [NSRegularExpression] = {
        let sources = [
            "token=[A-Za-z0-9_\\-]+",
            "dsh-auth-[A-Za-z0-9]+=[A-Za-z0-9._\\-]+",
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func redact(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "token=***")
        }
        return result
    }

    /// 取末尾 n 行（用于失败面板的日志尾部）。
    static func tail(_ text: String, lines: Int) -> String {
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard all.count > lines else { return text }
        return all.suffix(lines).joined(separator: "\n")
    }

    static func isRedacted(_ text: String) -> Bool {
        redact(text) == text
    }
}
