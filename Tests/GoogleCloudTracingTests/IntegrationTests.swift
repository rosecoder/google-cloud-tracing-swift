import Foundation
import GoogleCloudServiceContext
import Logging
import ServiceLifecycle
import Testing
import Tracing

@testable import GoogleCloudTracing

@Suite struct IntegrationTests {

  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"] != nil))
  func createSpan() async throws {
    var logger = Logger(label: "test")
    logger.logLevel = .trace

    var context = ServiceContext.current ?? .topLevel
    context.serviceName = "test-api"
    context.serviceVersion = "1.0.1"

    try await ServiceContext.withValue(context) {
      let tracer = try GoogleCloudTracer()
      InstrumentationSystem.bootstrap(tracer)

      let app = AppService()

      let serviceGroup = ServiceGroup(
        configuration: ServiceGroupConfiguration(
          services: [
            .init(service: tracer),
            .init(service: app, successTerminationBehavior: .gracefullyShutdownGroup),
          ],
          logger: logger
        ))

      try await serviceGroup.run()

      // Manually validate that spans has been created i GCP
      // Traces should be written automatically during shutdown
    }
  }

  struct AppService: Service {

    func run() async throws {
      do {
        try await withSpan("root-span") { span in
          span.attributes["test-attribute"] = "test-value"

          try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 1...3 {
              group.addTask {
                try await withSpan("child-span-\(number)") { span in
                  try await Task.sleep(for: .milliseconds(.random(in: 5..<50)))
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
  }

  struct SomeError: Error {}
}
