//
//  Noop.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017 Károly Lőrentey.
//

@_semantics("optimize.sil.never")
@inline(never)
public func noop<T>(_ value: T) {
    _fixLifetime(value)
}
