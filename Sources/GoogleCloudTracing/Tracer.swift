import Tracing
import GoogleCloudServiceContext
import NIO
import GoogleCloudAuth
import GRPC
import Foundation
import Synchronization
import Logging

public final class GoogleCloudTracer: Tracer {

    public typealias Span = GoogleCloudTracing.Span

    let logger = Logger(label: "trace.write")

    let authorization: Authorization
    let client: Google_Devtools_Cloudtrace_V2_TraceServiceAsyncClient

    public let writeInterval: TimeInterval?
    public let maximumBatchSize: Int

    let writeTimer = Mutex<Timer?>(nil)

    let lastWriteTask: Mutex<Task<(), Error>?> = Mutex(nil)
    let buffer = Mutex<[Span]>([]) // TODO: Should we reserve capacity from `maximumBatchSize`?

    public init(
        writeInterval: TimeInterval? = 10,
        maximumBatchSize: Int = 500,
        eventLoopGroup: EventLoopGroup
    ) {
        self.writeInterval = writeInterval
        self.maximumBatchSize = maximumBatchSize

        self.authorization = Authorization(scopes: [
            "https://www.googleapis.com/auth/trace.append",
            "https://www.googleapis.com/auth/cloud-platform",
        ], eventLoopGroup: eventLoopGroup)

        let channel = ClientConnection
            .usingTLSBackedByNIOSSL(on: eventLoopGroup)
            .connect(host: "cloudtrace.googleapis.com", port: 443)
        self.client = Google_Devtools_Cloudtrace_V2_TraceServiceAsyncClient(channel: channel)

        scheduleRepeatingWriteTimer()
    }

    public func shutdown() async throws {
        writeTimer.withLock {
            $0?.invalidate()
            $0 = nil
        }

        writeIfNeeded()
        await waitForWrite()
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
