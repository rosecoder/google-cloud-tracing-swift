import ServiceContextModule
import Instrumentation
import GoogleCloudServiceContext
import RetryableTask
import GRPC
import Tracing
import Foundation

extension GoogleCloudTracer {

    func bufferWrite(span: Span) {
        precondition(span.endTimeNanosecondsSinceEpoch != nil, "Scheduled span has not ended.")

        buffer.withLock { buffer in
            buffer.append(span)
            if buffer.count > maximumBatchSize {
                write(buffer: &buffer)
            }
        }
    }

    public func writeIfNeeded() {
        buffer.withLock { buffer in
            guard !buffer.isEmpty else {
                return
            }
            write(buffer: &buffer)
        }
    }

    public func waitForWrite() async {
        let task = lastWriteTask.withLock {
            $0
        }
        try? await task?.value // TODO: Not guaranteed to be the last write. But this may be good enough?
    }

    private func write(buffer: inout [Span]) {
        let spans = buffer
        buffer.removeAll(keepingCapacity: true)

        logger.debug("Writing \(spans.count) trace span(s)...")

        let task: Task<(), Error> = Task {
            do {
                try await withRetryableTask(logger: logger) {
                    try await self._write(spans: spans)
                }
                logger.debug("Successfully wrote spans.")
            } catch {
                logger.error("Error writing trace spans: \(error)")
                throw error
            }
        }
        lastWriteTask.withLock { $0 = task }
    }

    enum WriteError: Error {
        case missingProjectID
    }

    private func _write(spans: [Span]) async throws {
        let context = ServiceContext.current ?? .topLevel
        guard let projectID = context.projectID else {
            throw WriteError.missingProjectID
        }
        let encodedSpans = spans.compactMap {
            encode(span: $0, projectID: projectID)
        }
        guard !encodedSpans.isEmpty else {
            return
        }
        _ = try await client.batchWriteSpans(.with {
            $0.name = "projects/" + projectID
            $0.spans = encodedSpans
        }, callOptions: CallOptions(customMetadata: [
            "authorization": "Bearer " + authorization.accessToken(),
        ]))
    }

    private func encode(span: Span, projectID: String) -> Google_Devtools_Cloudtrace_V2_Span? {
        let spanIDString = span.id.stringValue
        guard let trace = span.context.trace else {
            return nil
        }
        guard let endTimeNanosecondsSinceEpoch = span.endTimeNanosecondsSinceEpoch else {
            return nil
        }
        return .with {
            $0.name = "projects/\(projectID)/traces/\(trace.id.prefixedHexRepresentation)/spans/\(spanIDString)"
            $0.spanID = spanIDString
            if trace.spanIDs.count > 1 {
                $0.parentSpanID = trace.spanIDs[trace.spanIDs.count - 2].prefixedHexRepresentation
            }
            $0.displayName = Google_Devtools_Cloudtrace_V2_TruncatableString(span.operationName, limit: 128)
            $0.startTime = .init(nanosecondsSinceEpoch: span.startTimeNanosecondsSinceEpoch)
            $0.endTime = .init(nanosecondsSinceEpoch: endTimeNanosecondsSinceEpoch)
            $0.attributes = encode(attributes: span.attributes, context: span.context)
            if let status = span.status {
                $0.status = .with {
                    switch status.code {
                    case .ok:
                        $0.code = 200
                    case .error:
                        $0.code = 500
                    }
                    $0.message = status.message ?? ""
                }
            }
//            $0.sameProcessAsParentSpan
//            $0.links
            $0.timeEvents = .with {
                $0.timeEvent = span.events.map { encode(event: $0, context: span.context) }
            }
//            $0.stackTrace
//            $0.childSpanCount
            $0.spanKind = encode(kind: span.kind)
        }
    }

    private func encode(attributes: SpanAttributes, context: ServiceContext) -> Google_Devtools_Cloudtrace_V2_Span.Attributes {

        // Well-known labels can be found here: https://github.com/googleapis/cloud-trace-nodejs/blob/c57a0b100d00fe0002544400c3958a17cc9751fb/src/trace-labels.ts

        var attributes = attributes
        if let serviceName = context.serviceName {
            attributes["g.co/gae/app/module"] = serviceName
        }
        if let version = context.serviceVersion {
            attributes["g.co/gae/app/version"] = version
        }

        let limit: UInt8 = 32

        var encoded = Google_Devtools_Cloudtrace_V2_Span.Attributes.with {
            $0.droppedAttributesCount = 0
        }
        var count: UInt8 = 0
        attributes.forEach { key, value in
            count += 1
            if count >= limit {
                encoded.droppedAttributesCount = Int32(attributes.count - Int(limit))
                return
            }
            let encodedValue: Google_Devtools_Cloudtrace_V2_AttributeValue
            switch value {
            case .bool(let value):
                encodedValue = .with {
                    $0.boolValue = value
                }
            case .int32(let value): 
                encodedValue = .with {
                    $0.intValue = Int64(value)
                }
            case .int64(let value): 
                encodedValue = .with {
                    $0.intValue = value
                }
            case .string(let value): 
                encodedValue = .with {
                    $0.stringValue = Google_Devtools_Cloudtrace_V2_TruncatableString(value, limit: 256)
                }
            case .stringConvertible(let value): 
                encodedValue = .with {
                    $0.stringValue = Google_Devtools_Cloudtrace_V2_TruncatableString(value.description, limit: 256)
                }
            default:
                logger.warning("Unsupported attribute value: \(value)")
                return
            }
            encoded.attributeMap[key] = encodedValue
        }
        return encoded
    }

    private func encode(event: SpanEvent, context: ServiceContext) -> Google_Devtools_Cloudtrace_V2_Span.TimeEvent {
        return .with {
            $0.time = .init(nanosecondsSinceEpoch: event.nanosecondsSinceEpoch)
            $0.value = .annotation(.with {
                $0.description_p = .with {
                    $0.value = event.name
                }
                $0.attributes = encode(attributes: event.attributes, context: context)
            })
        }
    }

    private func encode(kind: SpanKind) -> Google_Devtools_Cloudtrace_V2_Span.SpanKind {
        switch kind {
        case .internal:
            return .internal
        case .server:
            return .server
        case .client:
            return .client
        case .producer:
            return .producer
        case .consumer:
            return .consumer
        }
    }
}
