import Tracing
import Synchronization

public final class Span: Tracing.Span {

    public let id: SpanIdentifier
    public let kind: SpanKind
    public let context: ServiceContext

    public var operationName: String {
        get {
            _operationName.withLock { $0 }
        }
        set {
            _operationName.withLock { $0 = newValue }
        }
    }
    private let _operationName: Mutex<String>

    public var attributes: SpanAttributes {
        get {
            _attributes.withLock { $0 }
        }
        set {
            _attributes.withLock { $0 = newValue }
        }
    }
    private let _attributes = Mutex<SpanAttributes>([:])

    var status: SpanStatus? { _status.withLock { $0 } }
    private let _status = Mutex<SpanStatus?>(nil)

    var events: [SpanEvent] { _events.withLock { $0 } }
    private let _events = Mutex([SpanEvent]())

    let startTimeNanosecondsSinceEpoch: UInt64

    var endTimeNanosecondsSinceEpoch: UInt64? { _endTimeNanosecondsSinceEpoch.withLock { $0 } }
    private let _endTimeNanosecondsSinceEpoch = Mutex<UInt64?>(nil)

    private let onEnd: @Sendable (GoogleCloudTracer.Span, _ endTimeNanosecondsSinceEpoch: UInt64) -> Void

    public var isRecording: Bool { endTimeNanosecondsSinceEpoch == nil }

    init(
        id: SpanIdentifier,
        operationName: String,
        kind: SpanKind,
        context: ServiceContext,
        startTimeNanosecondsSinceEpoch: UInt64,
        onEnd: @escaping @Sendable (GoogleCloudTracer.Span, _ endTimeNanosecondsSinceEpoch: UInt64) -> Void
    ) {
        self.id = id
        self._operationName = Mutex(operationName)
        self.kind = kind
        self.context = context
        self.startTimeNanosecondsSinceEpoch = startTimeNanosecondsSinceEpoch
        self.onEnd = onEnd
    }

    public func setStatus(_ status: Tracing.SpanStatus) {
        _status.withLock { $0 = status }
    }

    public func addEvent(_ event: Tracing.SpanEvent) {
        _events.withLock { $0.append(event) }
    }

    public func addLink(_ link: SpanLink) {
        // Links not yet supported
    }

    public func recordError<Instant>(
        _ error: any Error,
        attributes: SpanAttributes,
        at instant: @autoclosure () -> Instant
    ) where Instant: TracerInstant {
        var eventAttributes: SpanAttributes = [
            "exception.type": .string(String(describing: type(of: error))),
            "exception.message": .string(String(describing: error)),
        ]
        eventAttributes.merge(attributes)

        let event = SpanEvent(
            name: "exception",
            at: instant(),
            attributes: eventAttributes
        )
        addEvent(event)

        _status.withLock { $0 = .init(code: .error, message: String(describing: error)) }
    }

    public func end<Instant>(at instant: @autoclosure () -> Instant) where Instant : TracerInstant {
        let endTimeNanosecondsSinceEpoch = instant().nanosecondsSinceEpoch
        _endTimeNanosecondsSinceEpoch.withLock { $0 = endTimeNanosecondsSinceEpoch }
        onEnd(self, endTimeNanosecondsSinceEpoch)
    }
}
