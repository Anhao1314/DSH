import Foundation

/// zsh 执行器（降级通道）：GUI App 只继承最小 PATH，所以统一走登录 shell 并显式补 PATH。
/// 所有调用都带超时；输出经过 `LogRedaction` 过滤，token 不会外泄。
enum ProcessShell {
    struct Result {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    static func run(_ command: String, timeout: TimeInterval = 30) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:" + home + "/.orbstack/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: LogRedaction.redact("\(error)"))
        }

        let queue = DispatchQueue.global(qos: .utility)
        var data = Data()
        let workItem = DispatchWorkItem { data = pipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(execute: workItem)

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date().compare(deadline) == .orderedAscending {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            workItem.wait()
            return Result(status: -2, output: LogRedaction.redact(String(data: data, encoding: .utf8) ?? "") + "\n(超时中止)")
        }
        workItem.wait()
        return Result(status: process.terminationStatus, output: LogRedaction.redact(String(data: data, encoding: .utf8) ?? ""))
    }
}
