import ServiceContextModule
import Instrumentation
import GoogleCloudServiceContext

extension GoogleCloudTracer {

    public func extract<Carrier, Extract>(
        _ carrier: Carrier,
        into context: inout ServiceContextModule.ServiceContext,
        using extractor: Extract
    ) where Carrier == Extract.Carrier, Extract: Instrumentation.Extractor {
        if 
            let headerValue = extractor.extract(key: "X-Cloud-Trace-Context", from: carrier),
            let trace = decodeXCloudTraceContext(headerValue: headerValue)
        {
            context.trace = trace
        }
    }

    private func decodeXCloudTraceContext(headerValue: String) -> Trace? {
        guard let firstSeparatorIndex = headerValue.firstIndex(of: "/") else {
            return nil
        }
        guard let traceID = TraceIdentifier(stringValue: headerValue[..<firstSeparatorIndex]) else {
            return nil
        }
        let afterFirstSeparator = headerValue.index(after: firstSeparatorIndex)
        guard let secondSeparatorIndex = headerValue[afterFirstSeparator...].firstIndex(of: ";") else {
            guard let spanID = UInt64(headerValue[afterFirstSeparator...], radix: 16) else {
                return nil
            }
            return Trace(id: traceID.rawValue, spanIDs: [spanID], isSampled: false)
        }
        let spanIDString = String(headerValue[afterFirstSeparator..<secondSeparatorIndex])
        guard let spanID = UInt64(spanIDString, radix: 16) else {
            return nil
        }
        let afterSecondSeparator = headerValue.index(after: secondSeparatorIndex)
        let isSampled = headerValue[afterSecondSeparator...].contains("1")
        
        return Trace(id: traceID.rawValue, spanIDs: [spanID], isSampled: isSampled)
    }
}
