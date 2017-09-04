// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import BenchmarkResults

extension NSValueTransformerName {
    static let timeTransformer = NSValueTransformerName(rawValue: "TimeTransformer")
}

@objc class TimeTransformer: ValueTransformer {
    static let shared = TimeTransformer()

    static func register() {
        ValueTransformer.setValueTransformer(shared, forName: .timeTransformer)
    }

    override class func transformedValueClass() -> Swift.AnyClass {
        return NSString.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let value = value as? Double else { return nil }
        return Time(value).description
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let value = value as? String else { return nil }
        return Time(description: value)?.seconds
    }
}

