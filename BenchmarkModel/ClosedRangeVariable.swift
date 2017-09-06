// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import GlueKit

public class ClosedRangeVariable<Bounds: Comparable> : Variable<ClosedRange<Bounds>> {
    let limits: Value?
    init(_ value: Value, limits: Value? = nil) {
        self.limits = limits
        super.init(value)
    }

    public var lowerBound: AnyUpdatableValue<Bounds> {
        return AnyUpdatableValue<Bounds>(
            getter: { () -> Bounds in self.value.lowerBound },
            apply: self.applyLowerBoundUpdate,
            updates: self.updates.map { update in update.map { change in change.map { $0.lowerBound } } })
    }

    func applyLowerBoundUpdate(_ update: ValueUpdate<Bounds>) {
        switch update {
        case .beginTransaction:
            self.apply(.beginTransaction)
        case .change(let change):
            let upper = Swift.max(change.new, self.value.upperBound)
            var new = (change.new ... upper)
            if let limits = limits { new = new.clamped(to: limits) }
            self.apply(.change(.init(from: self.value, to: new)))
        case .endTransaction:
            self.apply(.endTransaction)
        }
    }

    public var upperBound: AnyUpdatableValue<Bounds> {
        return AnyUpdatableValue<Bounds>(
            getter: { () -> Bounds in self.value.upperBound },
            apply: self.applyUpperBoundUpdate,
            updates: self.updates.map { update in update.map { change in change.map { $0.upperBound } } })
    }

    func applyUpperBoundUpdate(_ update: ValueUpdate<Bounds>) {
        switch update {
        case .beginTransaction:
            self.apply(.beginTransaction)
        case .change(let change):
            let lower = Swift.min(self.value.lowerBound, change.new)
            var new = lower ... change.new
            if let limits = limits { new = new.clamped(to: limits) }
            self.apply(.change(.init(from: self.value, to: new)))
        case .endTransaction:
            self.apply(.endTransaction)
        }
    }
}

