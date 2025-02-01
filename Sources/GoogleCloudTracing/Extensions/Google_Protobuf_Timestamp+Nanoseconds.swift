import SwiftProtobuf

extension Google_Protobuf_Timestamp {

  public init(nanosecondsSinceEpoch: UInt64) {
    self.init(
      seconds: Int64(nanosecondsSinceEpoch / 1_000_000_000),
      nanos: Int32(nanosecondsSinceEpoch % 1_000_000_000)
    )
  }
}
