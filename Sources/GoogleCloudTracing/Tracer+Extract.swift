import Instrumentation
import GoogleCloudServiceContext

extension GoogleCloudTracer {

    public func extract<Carrier, Extract>(
        _ carrier: Carrier,
        into context: inout ServiceContextModule.ServiceContext,
        using extractor: Extract
    ) where Carrier == Extract.Carrier, Extract: Instrumentation.Extractor {
        if let headerValue = extractor.extract(key: "traceparent", from: carrier),
           let trace = decodeTraceParent(headerValue: headerValue)
        {
            context.trace = trace
        }
    }

    private func decodeTraceParent(headerValue: String) -> Trace? {
        // traceparent format: VERSION-TRACEID-PARENTID-FLAGS
        // Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
        
        let components = headerValue.split(separator: "-")
        guard components.count == 4,
              components[0] == "00" else { // Only support version 00 for now
            return nil
        }
        
        guard let traceID = TraceIdentifier(stringValue: String(components[1])),
              let spanID = UInt64(String(components[2]), radix: 16),
              let flags = UInt8(String(components[3]), radix: 16) else {
            return nil
        }
        
        // In traceparent, sampling is determined by the least significant bit of flags
        let isSampled = (flags & 0x01) == 0x01
        
        return Trace(id: traceID.rawValue, spanIDs: [spanID], isSampled: isSampled)
    }
}
