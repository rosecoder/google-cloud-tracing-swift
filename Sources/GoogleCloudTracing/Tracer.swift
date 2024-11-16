import Tracing
import GoogleCloudServiceContext
import NIO
import GoogleCloudAuth
import GRPCCore
import GRPCProtobuf
import GRPCNIOTransportHTTP2
import Foundation
import Synchronization
import Logging

public final class GoogleCloudTracer: Tracer {

    public typealias Span = GoogleCloudTracing.Span

    let logger = Logger(label: "trace.write")

    let authorization: Authorization
    let client: Google_Devtools_Cloudtrace_V2_TraceService_Client

    private let grpcClient: GRPCClient
    private let grpcClientRunTask: Task<Void, Error>

    public let writeInterval: TimeInterval?
    public let maximumBatchSize: Int

    let writeTimer = Mutex<Timer?>(nil)

    let lastWriteTask: Mutex<Task<(), Error>?> = Mutex(nil)
    let buffer = Mutex<[Span]>([]) // TODO: Should we reserve capacity from `maximumBatchSize`?

    public init(
        writeInterval: TimeInterval? = 10,
        maximumBatchSize: Int = 500,
        eventLoopGroup: EventLoopGroup
    ) async throws {
        self.writeInterval = writeInterval
        self.maximumBatchSize = maximumBatchSize

        self.authorization = Authorization(scopes: [
            "https://www.googleapis.com/auth/trace.append",
            "https://www.googleapis.com/auth/cloud-platform",
        ], eventLoopGroup: eventLoopGroup)

        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: "cloudtrace.googleapis.com", port: 443),
            config: .defaults(transportSecurity: .tls(.defaults(configure: { config in
                config.serverHostname = "cloudtrace.googleapis.com"
            }))),
            eventLoopGroup: eventLoopGroup
        )
        let grpcClient = GRPCClient(transport: transport)
        self.grpcClient = grpcClient
        self.grpcClientRunTask = Task.detached {
            try await grpcClient.run()
        }

        self.client = Google_Devtools_Cloudtrace_V2_TraceService_Client(wrapping: grpcClient)

        scheduleRepeatingWriteTimer()
    }

    public func shutdown() async throws {
        writeTimer.withLock {
            $0?.invalidate()
            $0 = nil
        }

        writeIfNeeded()
        await waitForWrite()
        grpcClient.beginGracefulShutdown()
        try await grpcClientRunTask.value
        try await authorization.shutdown()
    }

    public func forceFlush() {
        writeIfNeeded()
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
