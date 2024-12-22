import Instrumentation
import GoogleCloudServiceContext

extension GoogleCloudTracer {

    public func inject<Carrier, Inject>(
        _ context: ServiceContextModule.ServiceContext,
        into carrier: inout Carrier,
        using injector: Inject
    ) where Carrier == Inject.Carrier, Inject: Instrumentation.Injector {
        guard let trace = context.trace, let spanID = trace.spanIDs.last else {
            return
        }
        let value = encodeTraceParent(trace: trace, spanID: spanID)
        injector.inject(value, forKey: "traceparent", into: &carrier)
    }

    private func encodeTraceParent(trace: Trace, spanID: UInt64) -> String {
        // Version is always 00
        let version = "00"
        let traceIDHex = trace.id.prefixedHexRepresentation
        let parentIDHex = spanID.prefixedHexRepresentation
        // Flags: for now we only use the sampling bit
        let flags = trace.isSampled ? "01" : "00"
        
        return "\(version)-\(traceIDHex)-\(parentIDHex)-\(flags)"
    }
}
