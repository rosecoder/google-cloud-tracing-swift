import Tracing
import GoogleCloudServiceContext
import NIO
import GoogleCloudAuth
import GRPCCore
import GRPCProtobuf
import GRPCNIOTransportHTTP2
import Synchronization
import Logging
import ServiceLifecycle

public final class GoogleCloudTracer: Tracer, Service {

    public typealias Span = GoogleCloudTracing.Span

    let logger = Logger(label: "trace.write")

    let authorization: Authorization
    let client: Google_Devtools_Cloudtrace_V2_TraceService.ClientProtocol

    private let grpcClient: GRPCClient

    public let writeInterval: Duration?
    public let maximumBatchSize: Int

    let lastWriteTask: Mutex<Task<Void, Never>?> = Mutex(nil)
    let buffer = Mutex<[Span]>([]) // TODO: Should we reserve capacity from `maximumBatchSize`?

    public init(
        writeInterval: Duration? = .seconds(10),
        maximumBatchSize: Int = 500
    ) throws {
        self.writeInterval = writeInterval
        self.maximumBatchSize = maximumBatchSize

        self.authorization = Authorization(scopes: [
            "https://www.googleapis.com/auth/trace.append",
            "https://www.googleapis.com/auth/cloud-platform",
        ], eventLoopGroup: .singletonMultiThreadedEventLoopGroup)

        self.grpcClient = GRPCClient(transport: try .http2NIOPosix(
            target: .dns(host: "cloudtrace.googleapis.com"),
            transportSecurity: .tls
        ))
        self.client = Google_Devtools_Cloudtrace_V2_TraceService.Client(wrapping: grpcClient)
    }

    public func run() async throws {
        let writeTimerTask = startWriteTimerTask()

        try await withGracefulShutdownHandler {
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask(priority: .background) {
                    try await self.grpcClient.run()
                }
                if let writeTimerTask {
                    group.addTask(priority: .background) {
                        do {
                            try await writeTimerTask.value
                        } catch {
                            if !(error is CancellationError) {
                                self.logger.error("Timer task failed: \(error)") // TODO: Remove this when typed throws in concurrency module has been implemented: https://forums.swift.org/t/pitch-typed-throws-in-the-concurrency-module/68210
                            }
                        }
                    }
                }
            }
        } onGracefulShutdown: {
            // Cancel write timer
            writeTimerTask?.cancel()

            // Force a last flush
            self.forceFlush()

            // Wait for last write task before shutting down gRPC client
            self.lastWriteTask.withLock {
                let task = $0
                Task(priority: .userInitiated) {
                    await task?.value
                    self.grpcClient.beginGracefulShutdown()
                }
            }
        }

        await lastWriteTask.withLock { $0 }?.value

        try await authorization.shutdown()
    }

    public func forceFlush() {
        lastWriteTask.withLock {
            $0 = Task(priority: .userInitiated) {
                await writeIfNeeded()
            }
        }
    }

    public func startSpan<Instant: TracerInstant>(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> Instant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> Span {
        let id = SpanIdentifier()
        var context = context()
        if context.trace != nil {
            context.trace!.spanIDs.append(id.rawValue)
        } else {
            context.trace = Trace(
                id: TraceIdentifier().rawValue,
                spanIDs: [id.rawValue],
                isSampled: true // TODO: Make this configurable
            )
        }
        return Span(
            id: id,
            operationName: operationName,
            kind: kind,
            context: context,
            startTimeNanosecondsSinceEpoch: instant().nanosecondsSinceEpoch,
            onEnd: { [weak self] span, endTimeNanosecondsSinceEpoch in
                self?.bufferWrite(span: span)
            }
        )
    }
}
