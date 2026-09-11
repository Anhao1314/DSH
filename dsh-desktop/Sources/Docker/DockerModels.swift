import Foundation

/// Docker Engine REST 的最小模型集合（只覆盖本项目用到的字段）。

struct DockerContainerSummary: Decodable {
    let id: String
    let names: [String]
    let state: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case names = "Names"
        case state = "State"
        case status = "Status"
    }

    var primaryName: String {
        names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? id
    }
}

struct DockerContainerInspect: Decodable {
    struct State: Decodable {
        struct Health: Decodable {
            let status: String?
            enum CodingKeys: String, CodingKey { case status = "Status" }
        }
        let status: String?
        let health: Health?
        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case health = "Health"
        }
    }
    let state: State?
    enum CodingKeys: String, CodingKey { case state = "State" }
}

struct DockerStatsSample: Decodable {
    struct CPUStats: Decodable {
        struct CPUUsage: Decodable {
            let totalUsage: UInt64?
            let percpuUsage: [UInt64]?
            enum CodingKeys: String, CodingKey {
                case totalUsage = "total_usage"
                case percpuUsage = "percpu_usage"
            }
        }
        let cpuUsage: CPUUsage?
        let systemCpuUsage: UInt64?
        let onlineCpus: Int?
        enum CodingKeys: String, CodingKey {
            case cpuUsage = "cpu_usage"
            case systemCpuUsage = "system_cpu_usage"
            case onlineCpus = "online_cpus"
        }
    }

    struct MemoryStats: Decodable {
        let usage: UInt64?
        let limit: UInt64?
        let stats: [String: UInt64]?
    }

    let cpuStats: CPUStats?
    let precpuStats: CPUStats?
    let memoryStats: MemoryStats?

    enum CodingKeys: String, CodingKey {
        case cpuStats = "cpu_stats"
        case precpuStats = "precpu_stats"
        case memoryStats = "memory_stats"
    }
}

/// 归一化后的容器资源采样（UI 只认这个结构）。
struct ContainerMetrics: Equatable {
    let cpuPercent: Double
    let memoryBytes: UInt64
    let memoryLimitBytes: UInt64

    var memoryFraction: Double {
        memoryLimitBytes > 0 ? Double(memoryBytes) / Double(memoryLimitBytes) : 0
    }
}
