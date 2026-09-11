import Foundation

/// 启动失败的细分类型：每种失败都有专属图标、标题、说明与一个主动作。
/// 日志尾部由 StackController 单独发布（`logTail`），此处只描述错误本身。
enum StackError: Error, Equatable {
    case projectMissing
    case orbNotFound
    case orbStartTimeout
    case composeFailed(String)
    case healthTimeout
    case tokenMissing
    case relayUnreachable
    case socketFailed(String)

    enum Action: Equatable {
        case retry
        case downloadOrbStack
        case chooseProject
    }

    var icon: String {
        switch self {
        case .projectMissing: return "folder"
        case .orbNotFound, .orbStartTimeout: return "shippingbox"
        case .composeFailed: return "exclamationmark.triangle"
        case .healthTimeout: return "clock"
        case .tokenMissing: return "lock.shield"
        case .relayUnreachable: return "network"
        case .socketFailed: return "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .projectMissing: return Copy.projectMissingTitle
        case .orbNotFound: return Copy.orbNotFoundTitle
        case .orbStartTimeout: return Copy.orbStartTimeoutTitle
        case .composeFailed: return Copy.composeFailedTitle
        case .healthTimeout: return Copy.healthTimeoutTitle
        case .tokenMissing: return Copy.tokenMissingTitle
        case .relayUnreachable: return Copy.relayUnreachableTitle
        case .socketFailed: return Copy.socketFailedTitle
        }
    }

    var message: String {
        switch self {
        case .projectMissing: return Copy.projectMissingMessage
        case .orbNotFound: return Copy.orbNotFoundMessage
        case .orbStartTimeout: return Copy.orbStartTimeoutMessage
        case .composeFailed(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "容器编排没有启动成功，展开日志可以看到最后一屏输出。" : trimmed
        case .healthTimeout: return Copy.healthTimeoutMessage
        case .tokenMissing: return Copy.tokenMissingMessage
        case .relayUnreachable: return Copy.relayUnreachableMessage
        case .socketFailed(let detail): return detail
        }
    }

    var primaryAction: Action {
        switch self {
        case .projectMissing: return .chooseProject
        case .orbNotFound: return .downloadOrbStack
        case .orbStartTimeout, .composeFailed, .healthTimeout, .tokenMissing, .relayUnreachable, .socketFailed:
            return .retry
        }
    }

    var primaryActionTitle: String {
        switch primaryAction {
        case .retry: return Copy.actionRetry
        case .downloadOrbStack: return Copy.actionDownloadOrbStack
        case .chooseProject: return Copy.actionChooseProject
        }
    }

    static let orbStackDownloadURL = "https://orbstack.dev/download"
}
