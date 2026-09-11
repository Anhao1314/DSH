import Foundation

/// `/console-api/v1/*` 的响应模型。
///
/// 全部字段都走 `decodeIfPresent` + 安全默认值：中继少给一个字段时界面必须照常渲染，
/// 不能因为上游改了投影结构就崩在解码上（红线：绝不抛崩）。

struct RelayHealth: Decodable {
    let ok: Bool
    let upstream: String
    let serverTime: Double

    var upstreamUp: Bool { upstream == "up" }
}

struct SessionTokens: Decodable, Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int

    init(input: Int, output: Int, cacheRead: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? box.decodeIfPresent(Int.self, forKey: .input)) ?? 0
        output = (try? box.decodeIfPresent(Int.self, forKey: .output)) ?? 0
        cacheRead = (try? box.decodeIfPresent(Int.self, forKey: .cacheRead)) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case input, output, cacheRead }
}

struct SessionChild: Decodable, Identifiable, Equatable {
    let id: String
    let role: String
    let label: String
    let running: Bool
    let updatedAt: Double
    let settledMs: Int
    let verdict: String

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decode(String.self, forKey: .id)) ?? ""
        role = (try? box.decode(String.self, forKey: .role)) ?? "sub"
        label = (try? box.decode(String.self, forKey: .label)) ?? ""
        running = (try? box.decode(Bool.self, forKey: .running)) ?? false
        updatedAt = (try? box.decode(Double.self, forKey: .updatedAt)) ?? 0
        settledMs = (try? box.decode(Int.self, forKey: .settledMs)) ?? 0
        verdict = (try? box.decode(String.self, forKey: .verdict)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, role, label, running, updatedAt, settledMs, verdict }
}

struct SessionRoot: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let running: Bool
    let updatedAt: Double
    let turns: Int
    let verdict: String
    let tokens: SessionTokens
    let children: [SessionChild]

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decode(String.self, forKey: .id)) ?? ""
        title = (try? box.decode(String.self, forKey: .title)) ?? ""
        running = (try? box.decode(Bool.self, forKey: .running)) ?? false
        updatedAt = (try? box.decode(Double.self, forKey: .updatedAt)) ?? 0
        turns = (try? box.decode(Int.self, forKey: .turns)) ?? 0
        verdict = (try? box.decode(String.self, forKey: .verdict)) ?? ""
        tokens = (try? box.decode(SessionTokens.self, forKey: .tokens)) ?? SessionTokens(input: 0, output: 0, cacheRead: 0)
        children = (try? box.decode([SessionChild].self, forKey: .children)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, title, running, updatedAt, turns, verdict, tokens, children }

    /// 侧边栏/Inspector 用的状态文案（与 Web 控制台同一套判定）。
    var statusText: String { SessionStatus.text(running: running, verdict: verdict) }
}

struct SessionsResponse: Decodable {
    let ok: Bool
    let roots: [SessionRoot]

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? box.decode(Bool.self, forKey: .ok)) ?? false
        roots = (try? box.decode([SessionRoot].self, forKey: .roots)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case ok, roots }
}

struct TimelineEvent: Decodable, Identifiable, Equatable {
    let seq: Int
    let ts: Double
    let kind: String
    let role: String
    let status: String
    let title: String
    let detail: String

    var id: String { "\(seq)-\(kind)-\(role)-\(status)-\(title)" }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        seq = (try? box.decode(Int.self, forKey: .seq)) ?? 0
        ts = (try? box.decode(Double.self, forKey: .ts)) ?? 0
        kind = (try? box.decode(String.self, forKey: .kind)) ?? ""
        role = (try? box.decode(String.self, forKey: .role)) ?? "lead"
        status = (try? box.decode(String.self, forKey: .status)) ?? ""
        title = (try? box.decode(String.self, forKey: .title)) ?? ""
        detail = (try? box.decode(String.self, forKey: .detail)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case seq, ts, kind, role, status, title, detail }
}

struct TimelineResponse: Decodable {
    let ok: Bool
    let events: [TimelineEvent]

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? box.decode(Bool.self, forKey: .ok)) ?? false
        events = (try? box.decode([TimelineEvent].self, forKey: .events)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case ok, events }
}

/// 角色 / 状态 / 结论的统一文案与配色键（颜色在视图层解析，模型层只给语义）。
enum SessionStatus {
    static func text(running: Bool, verdict: String) -> String {
        if running { return Copy.sidebarRunning }
        switch verdict {
        case "pass": return Copy.sidebarPassed
        case "fail": return Copy.sidebarFailed
        default: return Copy.sidebarDone
        }
    }
}

enum RoleDisplay {
    static func text(_ role: String) -> String {
        switch role {
        case "coder": return "Coder"
        case "reviewer": return "Reviewer"
        case "sub": return Copy.roleSub
        default: return "Lead"
        }
    }
}
