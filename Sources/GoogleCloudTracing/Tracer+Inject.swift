import ServiceContextModule
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
        let value = encodeXCloudTraceContext(trace: trace, spanID: spanID)
        injector.inject(value, forKey: "X-Cloud-Trace-Context", into: &carrier)
    }

    private func encodeXCloudTraceContext(trace: Trace, spanID: UInt64) -> String {
        trace.id.prefixedHexRepresentation +
        "/" +
        spanID.prefixedHexRepresentation +
        ";o=" +
        (trace.isSampled ? "1" : "0")
    }
}
