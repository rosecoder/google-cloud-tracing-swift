import Testing
import Tracing
import GoogleCloudServiceContext
@testable import GoogleCloudTracing
import NIO

@Suite struct ExtractAndInjectTests {

    let tracer: GoogleCloudTracer

    init() throws {
        tracer = try GoogleCloudTracer()
    }

    @Test func extractValidTraceContext() {
        var context = ServiceContext.topLevel
        let carrier = ["traceparent": "00-105445aa7843bc8bf206b12000100000-0000000000000001-01"]
        
        tracer.extract(carrier, into: &context, using: DictionaryExtractor())
        
        #expect(context.trace != nil)
        #expect(context.trace?.id == 0x105445aa7843bc8bf206b12000100000)
        #expect(context.trace?.spanIDs.last == 1)
        #expect(context.trace?.isSampled == true)
    }
    
    @Test func extractInvalidTraceContext() {
        var context = ServiceContext.topLevel
        let carrier = ["traceparent": "invalid-trace-context"]
        
        tracer.extract(carrier, into: &context, using: DictionaryExtractor())
        
        #expect(context.trace == nil)
    }
    
    @Test func injectTraceContext() {
        var context = ServiceContext.topLevel
        context.trace = Trace(id: 0x105445aa7843bc8bf206b12000100000, spanIDs: [1], isSampled: true)
        var carrier: [String: String] = [:]
        
        tracer.inject(context, into: &carrier, using: DictionaryInjector())
        
        #expect(carrier["traceparent"] == "00-105445aa7843bc8bf206b12000100000-0000000000000001-01")
    }
    
    @Test func extractTraceContextWithoutSampling() {
        var context = ServiceContext.topLevel
        let carrier = ["traceparent": "00-105445aa7843bc8bf206b12000100000-0000000000000001-00"]
        
        tracer.extract(carrier, into: &context, using: DictionaryExtractor())
        
        #expect(context.trace != nil)
        #expect(context.trace?.id == 0x105445aa7843bc8bf206b12000100000)
        #expect(context.trace?.spanIDs.last == 1)
        #expect(context.trace?.isSampled == false)
    }
}

private struct DictionaryExtractor: Extractor {

    func extract(key: String, from carrier: [String: String]) -> String? {
        return carrier[key]
    }
}

private struct DictionaryInjector: Injector {

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}
