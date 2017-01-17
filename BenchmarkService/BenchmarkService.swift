//
//  BenchmarkService.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-19.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools
import CollectionBenchmarks

@objc class BenchmarkService: NSObject, BenchmarkServiceProtocol {

    let suites: [BenchmarkSuiteProtocol]
    let suitesByTitle: [String: BenchmarkSuiteProtocol]

    override init() {
        self.suites = CollectionBenchmarks.generateBenchmarks()
        var map: [String: BenchmarkSuiteProtocol] = [:]
        for suite in suites {
            map[suite.title] = suite
        }
        self.suitesByTitle = map
    }

    func suites(_ reply: @convention(block) ([String]) -> Void) {
        reply(suites.map { $0.title })
    }

    func benchmarks(for suite: String, reply: @convention(block) ([String]) -> Void) {
        guard let suite = suitesByTitle[suite] else { reply([]); return }

        reply(suite.benchmarkTitles)
    }

    func run(_ suite: String, _ benchmark: String, _ size: Int, reply: @convention(block) (TimeInterval) -> Void) {
        guard let suite = suitesByTitle[suite] else { reply(.nan); return }
        let elapsed = suite.run(benchmark, size)
        reply(elapsed)
    }
}
