# Google Cloud Tracing for Swift

This package provides a Swift implementation for tracing with the Google Cloud Platform. It's built to integrate with the official [Swift Distributed Tracing](https://github.com/apple/swift-distributed-tracing).

## Example usage

```swift
import Tracing
import GoogleCloudTracing

let tracer = GoogleCloudTracer(eventLoopGroup: <#eventLoopGroup#>)
InstrumentationSystem.bootstrap(tracer)
```

This will automatically authenticate with Google Cloud and send traces to [Cloud Trace)(https://cloud.google.com/trace/docs).

See [Google Cloud Auth for Swift](https://github.com/rosecoder/google-cloud-auth-swift) for supported authentication methods.
