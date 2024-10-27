import Foundation

extension GoogleCloudTracer {

    func scheduleRepeatingWriteTimer() {
        guard let writeInterval else {
            return
        }
        writeTimer.withLock {
            let timer = Timer(timeInterval: writeInterval, repeats: true) { _ in
                self.writeIfNeeded()
            }
            $0 = timer
            RunLoop.current.add(timer, forMode: .common)
        }
    }
}
