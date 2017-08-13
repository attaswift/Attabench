//
//  Results.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation


public final class TaskResults: Codable {
    public private(set) var samplesBySize: [Int: TimeSample] = [:]

    public init() {}

    enum Keys: CodingKey {
        case samples
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        self.samplesBySize = try container.decode([Int: TimeSample].self, forKey: .samples)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(samplesBySize, forKey: .samples)
    }

    public func addMeasurement(_ elapsedTime: Time, forSize size: Int) {
        samplesBySize[size, default: TimeSample()].addMeasurement(elapsedTime)
    }
}
