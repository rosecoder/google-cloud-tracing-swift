struct TraceIdentifier {

  typealias RawValue = UInt128

  let rawValue: RawValue

  /// Initializes a new identifier with a new unique raw value.
  init() {
    self.rawValue = UInt128.random(in: 1..<UInt128.max)
  }

  init(rawValue: RawValue) {
    precondition(rawValue != 0, "Trace id must not be 0")

    self.rawValue = rawValue
  }

  init?(stringValue: some StringProtocol) {
    guard
      stringValue.count == 32,
      let rawValue = UInt128(stringValue, radix: 16),
      rawValue != 0
    else {
      return nil
    }

    self.rawValue = rawValue
  }
}

extension TraceIdentifier: Sendable {}

extension TraceIdentifier: Equatable {

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue == rhs.rawValue
  }
}

extension TraceIdentifier: CustomStringConvertible {

  var description: String {
    rawValue.prefixedHexRepresentation
  }
}
