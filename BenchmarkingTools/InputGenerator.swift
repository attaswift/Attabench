//
//  InputGenerator.swift
//  BenchmarkingTools
//
//  Created by Károly Lőrentey on 2017-8-10.
//  Copyright © 2017 Károly Lőrentey.
//

public protocol InputGeneratorProtocol {
    associatedtype Value
    func generate(_ size: Int) -> Value
}

public struct RandomArrayGenerator: InputGeneratorProtocol {
    public init() {}
    
    public func generate(_ size: Int) -> [Int] {
        var values: [Int] = Array(0 ..< size)
        values.shuffle()
        return values
    }
}

public struct PairGenerator<G1: InputGeneratorProtocol, G2: InputGeneratorProtocol>: InputGeneratorProtocol {
    public typealias Value = (G1.Value, G2.Value)
    
    var g1: G1
    var g2: G2
    public init(_ g1: G1, _ g2: G2) {
        self.g1 = g1
        self.g2 = g2
    }
    
    public func generate(_ size: Int) -> Value {
        return (g1.generate(size), g2.generate(size))
    }
}

public struct ClosureGenerator<Value>: InputGeneratorProtocol {
    private let generator: (Int) -> Value
    
    public init(_ generator: @escaping (Int) -> Value) {
        self.generator = generator
    }
    
    public func generate(_ size: Int) -> Value {
        return generator(size)
    }
}
