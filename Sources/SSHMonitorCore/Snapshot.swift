import Foundation

public struct GPUReading: Equatable, Identifiable {
    public let index: Int
    public let utilization: Int
    public let memoryUsedMiB: Int
    public let memoryTotalMiB: Int
    public let temperatureC: Int

    public var id: Int { index }

    public var memoryText: String {
        String(format: "%.1f/%.0f GB", Double(memoryUsedMiB) / 1024, Double(memoryTotalMiB) / 1024)
    }
}

public struct ServerSnapshot: Equatable {
    public let cpuPercent: Int
    public let memoryUsedKiB: Int
    public let memoryTotalKiB: Int
    public let gpus: [GPUReading]

    public var maxGPUPercent: Int { gpus.map(\.utilization).max() ?? 0 }
    public var memoryPercent: Int { Int((100.0 * Double(memoryUsedKiB) / Double(memoryTotalKiB)).rounded()) }
    public var memoryText: String {
        String(format: "%.1f/%.1f GB", Double(memoryUsedKiB) / 1_048_576,
               Double(memoryTotalKiB) / 1_048_576)
    }

    public static func parse(_ output: String) throws -> ServerSnapshot {
        var cpu: Int?
        var memoryUsed: Int?
        var memoryTotal: Int?
        var gpus: [GPUReading] = []
        var gpuUnavailable = false

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: " ").map(String.init)
            guard let kind = parts.first else { continue }
            switch kind {
            case "CPU" where parts.count == 2:
                cpu = Int(parts[1])
            case "MEM" where parts.count == 3:
                memoryUsed = Int(parts[1])
                memoryTotal = Int(parts[2])
            case "GPU" where parts.count == 6:
                guard let index = Int(parts[1]), let utilization = Int(parts[2]),
                      let used = Int(parts[3]), let total = Int(parts[4]),
                      let temperature = Int(parts[5]), total > 0,
                      (0...100).contains(utilization), used >= 0 else {
                    throw SnapshotError.invalidData
                }
                gpus.append(GPUReading(index: index, utilization: utilization,
                                       memoryUsedMiB: used, memoryTotalMiB: total,
                                       temperatureC: temperature))
            case "GPU_UNAVAILABLE":
                gpuUnavailable = true
            default:
                continue
            }
        }
        guard let cpu, let memoryUsed, let memoryTotal, (0...100).contains(cpu),
              memoryTotal > 0, (0...memoryTotal).contains(memoryUsed),
              (!gpus.isEmpty || gpuUnavailable) else {
            throw SnapshotError.invalidData
        }
        return ServerSnapshot(cpuPercent: cpu, memoryUsedKiB: memoryUsed, memoryTotalKiB: memoryTotal,
                              gpus: gpus.sorted { $0.index < $1.index })
    }
}

public enum SnapshotError: LocalizedError {
    case invalidData
    case invalidHost
    case timeout
    case ssh(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData: "服务器返回的数据不完整"
        case .invalidHost: "SSH 主机名无效"
        case .timeout: "SSH 连接或采集超时"
        case .ssh: "SSH 连接失败，请检查网络、主机别名与密钥。"
        }
    }
}

public enum HostValidation {
    public static func isValid(_ host: String) -> Bool {
        !host.isEmpty && host.first != "-" &&
        host.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }
}
