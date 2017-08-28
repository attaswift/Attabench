// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

@_semantics("optimize.sil.never")
@inline(never)
public func noop<T>(_ value: T) {
    _fixLifetime(value)
}
