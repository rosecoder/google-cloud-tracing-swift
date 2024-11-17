extension GoogleCloudTracer {

    func startWriteTimerTask() -> Task<Void, Error>? {
        guard let writeInterval else {
            return nil
        }
        return Task(priority: .background) {
            try await self.startWriteTimer(writeInterval: writeInterval)
        }
    }

    private func startWriteTimer(writeInterval: Duration) async throws {
        while true {
            try await Task.sleep(for: writeInterval, tolerance: .seconds(1))

            await self.writeIfNeeded()
        }
    }
}
