//
//  AlgebraicTree.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-22.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

enum Color {
    case black
    case red
}

enum AlgebraicTree<Element: Comparable> {
    case empty
    indirect case node(Color, AlgebraicTree, Element, AlgebraicTree)

    var color: Color {
        switch self {
        case .empty: return .black
        case let .node(color, _, _, _): return color
        }
    }
}

extension AlgebraicTree {
    init() {
        self = .empty
    }
}

extension AlgebraicTree {
    func contains(_ element: Element) -> Bool {
        switch self {
        case .empty:
            return false
        case let .node(_, left, value, right):
            if element < value {
                return left.contains(element)
            }
            if element > value {
                return right.contains(element)
            }
            return true
        }
    }
}

extension AlgebraicTree {
    // The insert algorithm below is a simple transliteration of the 
    // algorithm in Chris Okasaki's 1999 paper, "Red-black trees in a functional setting".
    // doi:10.1017/S0956796899003494

    @discardableResult
    mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        let new = inserting(element)
        self = new.0
        return (new.old == nil, new.old ?? element)
    }

    func inserting(_ element: Element) -> (AlgebraicTree, old: Element?) {
        let n = _inserting(element)
        guard case let (.node(_, left, value, right), old) = n else { fatalError() }
        return (.node(.black, left, value, right), old)
    }

    private func _inserting(_ element: Element) -> (node: AlgebraicTree, old: Element?) {
        switch self {
        case .empty:
            return (.node(.red, .empty, element, .empty), nil)

        case let .node(color, left, value, right):
            if element < value {
                let n = left._inserting(element)
                return (n.old == nil ? balanced(color, n.0, value, right) : self, n.old)
            }
            if element > value {
                let n = right._inserting(element)
                return (n.old == nil ? balanced(color, left, value, n.0) : self, n.old)
            }
            return (self, value)
        }
    }

    private func balanced(_ color: Color, _ left: AlgebraicTree, _ value: Element, _ right: AlgebraicTree) -> AlgebraicTree {
        #if false // This should work but it is miscompiled in Swift 3.0.1:
            switch (color, left, value, right) {
            case let (.black, .node(.red, .node(.red, a, x, b), y, c), z, d),
                 let (.black, .node(.red, a, x, .node(.red, b, y, c)), z, d),
                 let (.black, a, x, .node(.red, .node(.red, b, y, c), z, d)),
                 let (.black, a, x, .node(.red, b, y, .node(.red, c, z, d))):
                return .node(.red, .node(.black, a, x, b), y, .node(.black, c, z, d))
            default:
                return .node(color, left, value, right)
            }
        #else
            switch (color, left, value, right) {
            case let (.black, .node(.red, .node(.red, a, x, b), y, c), z, d):
                return .node(.red, .node(.black, a, x, b), y, .node(.black, c, z, d))
            case let (.black, .node(.red, a, x, .node(.red, b, y, c)), z, d):
                return .node(.red, .node(.black, a, x, b), y, .node(.black, c, z, d))
            case let (.black, a, x, .node(.red, .node(.red, b, y, c), z, d)):
                return .node(.red, .node(.black, a, x, b), y, .node(.black, c, z, d))
            case let (.black, a, x, .node(.red, b, y, .node(.red, c, z, d))):
                return .node(.red, .node(.black, a, x, b), y, .node(.black, c, z, d))
            default:
                return .node(color, left, value, right)
            }
        #endif
    }
}

extension AlgebraicTree {
    private func _validate(parentColor: Color) -> (min: Element, max: Element)? {
        switch self {
        case .empty:
            return nil
        case let .node(color, left, value, right):
            precondition(parentColor == .black || color == .black)
            let leftBounds = left._validate(parentColor: color)
            let rightBounds = right._validate(parentColor: color)
            if let l = leftBounds {
                precondition(l.max < value)
            }
            if let r = rightBounds {
                precondition(value < r.min)
            }
            return (leftBounds?.min ?? value, rightBounds?.max ?? value)
        }
    }
    func validate() {
        _ = _validate(parentColor: .red)
    }

}
extension AlgebraicTree: CustomStringConvertible {
    var description: String {
        switch self {
        case .empty:
            return ""
        case let .node(color, left, value, right):
            var result = "("
            if case .node(_, _, _, _) = left {
                result += "\(left) "
            }
            result += color == .red ? "🔴" : "⚫️"
            result += "\(value)"
            if case .node(_, _, _, _) = right {
                result += " \(right)"
            }
            result += ")"
            return result
        }
    }
}

extension AlgebraicTree {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        guard case let .node(_, left, value, right) = self else { return }
        try left.forEach(body)
        try body(value)
        try right.forEach(body)
    }
}

struct AlgebraicTreeIndex<Element: Comparable>: Comparable {
    typealias Tree = AlgebraicTree<Element>
    fileprivate var value: Element?

    static func ==(left: AlgebraicTreeIndex, right: AlgebraicTreeIndex) -> Bool {
        return left.value == right.value
    }

    static func <(left: AlgebraicTreeIndex, right: AlgebraicTreeIndex) -> Bool {
        if let lv = left.value, let rv = right.value { return lv < rv }
        return left.value != nil
    }
}

extension AlgebraicTree: Collection {
    typealias Index = AlgebraicTreeIndex<Element>

    var startIndex: Index { return Index(value: self.minimum) }
    var endIndex: Index { return Index(value: nil) }

    subscript(i: Index) -> Element {
        // Note that the index isn't validated at all here.
        return i.value!
    }

    var count: Int {
        switch self {
        case .empty:
            return 0
        case let .node(_, left, _, right):
            return left.count + 1 + right.count
        }
    }

    var minimum: Element? {
        var node = self
        var minimum: Element? = nil
        while case let .node(_, left, value, _) = node {
            minimum = value
            node = left
        }
        return minimum
    }

    private func value(following element: Element) -> (found: Bool, next: Element?) {
        guard case let .node(_, left, value, right) = self else { return (false, nil) }
        if element < value {
            let v = left.value(following: element)
            return (v.found, v.next ?? value)
        }
        if element > value {
            return right.value(following: element)
        }
        return (true, right.minimum)
    }

    func formIndex(after i: inout Index) {
        let v = self.value(following: i.value!)
        precondition(v.found)
        i.value = v.next
    }

    func index(after i: Index) -> Index {
        let v = self.value(following: i.value!)
        precondition(v.found)
        return Index(value: v.next)
    }
}
