// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "google-cloud-tracing",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "GoogleCloudTracing", targets: ["GoogleCloudTracing"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", branch: "main"),
        .package(url: "https://github.com/rosecoder/grpc-swift-nio-transport.git", branch: "authority-header"),
        .package(url: "https://github.com/rosecoder/google-cloud-auth-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/rosecoder/retryable-task.git", from: "1.1.2"),
        .package(url: "https://github.com/rosecoder/google-cloud-service-context.git", revision: "5464a8beb9b4d4d93cc219313b207bd82cc128bb"),
    ],
    targets: [
        .target(
            name: "GoogleCloudTracing",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "RetryableTask", package: "retryable-task"),
                .product(name: "GoogleCloudAuth", package: "google-cloud-auth-swift"),
                .product(name: "GoogleCloudServiceContext", package: "google-cloud-service-context"),
            ]
        ),
        .testTarget(name: "GoogleCloudTracingTests", dependencies: ["GoogleCloudTracing"]),
    ]
)
