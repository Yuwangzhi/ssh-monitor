import Foundation

public enum RemoteProbe {
    // One read-only SSH call collects all values. SSH uses the user's existing alias and key.
    public static let script = """
    set -eu
    cpu_line() { awk '/^cpu / { idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; printf "%.0f %.0f\\n", idle, total; exit }' /proc/stat; }
    set -- $(cpu_line)
    idle1=$1
    total1=$2
    sleep 0.25
    set -- $(cpu_line)
    awk -v i1="$idle1" -v t1="$total1" -v i2="$1" -v t2="$2" 'BEGIN { d=t2-t1; if (d<=0) print "CPU 0"; else printf "CPU %.0f\\n", 100*(1-(i2-i1)/d) }'
    awk '/^MemTotal:/ { total=$2 } /^MemAvailable:/ { available=$2 } END { if (total>0) printf "MEM %.0f %.0f\\n", total-available,total }' /proc/meminfo
    if gpu_data=$(nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null); then
      if [ -n "$gpu_data" ]; then
        printf '%s\\n' "$gpu_data" | awk -F, '{ for (i=1;i<=NF;i++) gsub(/^[ \\t]+|[ \\t]+$/, "", $i); printf "GPU %s %s %s %s %s\\n", $1,$2,$3,$4,$5 }'
      else
        echo GPU_UNAVAILABLE
      fi
    else
      echo GPU_UNAVAILABLE
    fi
    """

    public static func fetch(host: String, timeout: TimeInterval = 12) throws -> ServerSnapshot {
        guard HostValidation.isValid(host) else { throw SnapshotError.invalidHost }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                             "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
                             "-o", "StrictHostKeyChecking=yes", host, "sh", "-s"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() }
        catch { throw SnapshotError.ssh(error.localizedDescription) }
        input.fileHandleForWriting.write(Data(script.utf8))
        try? input.fileHandleForWriting.close()

        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            throw SnapshotError.timeout
        }
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SnapshotError.ssh(message.isEmpty ? "退出码 \(process.terminationStatus)" : message)
        }
        return try ServerSnapshot.parse(stdout)
    }
}
