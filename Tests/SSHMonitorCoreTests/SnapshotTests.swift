import Testing
@testable import SSHMonitorCore

@Test func parsesMultipleGPUReadingsAndSummary() throws {
        let raw = """
        CPU 59
        MEM 22020096 104857600
        GPU 0 0 307 10240 32
        GPU 1 50 1126 24576 87
        """
        let snapshot = try ServerSnapshot.parse(raw)
        #expect(snapshot.cpuPercent == 59)
        #expect(snapshot.memoryPercent == 21)
        #expect(snapshot.memoryText == "21.0/100.0 GB")
        #expect(snapshot.gpus.count == 2)
        #expect(snapshot.maxGPUPercent == 50)
        #expect(snapshot.gpus[1].memoryText == "1.1/24 GB")
}

@Test func rejectsIncompleteResponseAndUnsafeHost() {
        #expect(throws: SnapshotError.self) { try ServerSnapshot.parse("CPU 10\nMEM 20") }
        #expect(!HostValidation.isValid("-oProxyCommand=bad"))
        #expect(!HostValidation.isValid("my-server; echo bad"))
        #expect(HostValidation.isValid("my-server"))
}
