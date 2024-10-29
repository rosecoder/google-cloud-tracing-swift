import Testing
import Tracing
import GoogleCloudServiceContext
@testable import GoogleCloudTracing
import NIO
import Foundation

@Suite struct IntegrationTests {

    let tracer = GoogleCloudTracer(eventLoopGroup: MultiThreadedEventLoopGroup(numberOfThreads: 1))

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"] != nil))
    func createSpan() async throws {
        InstrumentationSystem.bootstrap(tracer)

        var context = ServiceContext.current ?? .topLevel
        context.serviceName = "test-api"
        context.serviceVersion = "1.0.1"

        try await ServiceContext.withValue(context) {
            do {
                try await withSpan("root-span") { span in
                    span.attributes["test-attribute"] = "test-value"

                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for number in 1...3 {
                            group.addTask {
                                try await withSpan("child-span-\(number)") { span in
                                    try await Task.sleep(for: .milliseconds(50))
                                    if number == 2 {
                                        throw SomeError()
                                    }
                                }
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            } catch {
                if !(error is SomeError) {
                    throw error
                }
            }
        }

        tracer.forceFlush()

        let lastWriteTask = tracer.lastWriteTask.withLock { $0 }
        try await lastWriteTask?.value

        // Manual validation
    }

    struct SomeError: Error {}
}
