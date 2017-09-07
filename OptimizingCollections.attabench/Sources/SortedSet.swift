//
//  SortedSet.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017 Károly Lőrentey.
//

public protocol SortedSet: Collection, CustomStringConvertible {
    /// Initializes an empty set.
    init()

    /// Returns true iff this set contains `element`.
    func contains(_ element: Iterator.Element) -> Bool

    /// Inserts the given element into the set if it is not already present.
    /// If an element equal to `newMember` is already contained in the set,
    /// this method has no effect.
    ///
    /// - Returns: `(true, newMember)` if `newMember` was not contained in the set.
    ///     If an element equal to `newMember` was already contained in the set,
    ///     the method returns `(false, oldMember)`, where `oldMember` is the element
    ///     that was equal to `newMember`. In some cases, `oldMember` may be
    ///     distinguishable from `newMember` by identity comparison or some
    ///     other means.
    @discardableResult
    mutating func insert(_ newElement: Iterator.Element) -> (inserted: Bool, memberAfterInsert: Iterator.Element)

    func validate()
}

extension SortedSet {
    public func validate() {}
}

extension SortedSet {
    public var description: String {
        return "[" + self.lazy.map { "\($0)" }.joined(separator: ", ") + "]"
    }
}
