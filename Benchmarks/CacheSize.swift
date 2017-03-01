//
//  CacheSize.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017 Károly Lőrentey.
//

import Darwin

let cacheSize: Int = {
    var result: Int = 0
    var size = MemoryLayout<Int>.size
    if sysctlbyname("hw.l1dcachesize", &result, &size, nil, 0) == -1 {
        return 32768
    }
    return result
}()
