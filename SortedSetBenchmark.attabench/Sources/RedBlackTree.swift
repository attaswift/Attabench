//
//  RedBlackTree.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-22.
//  Copyright © 2017 Károly Lőrentey.
//

public enum Color {
    case black
    case red
}

public enum RedBlackTree<Element: Comparable> {
    case empty
    indirect case node(Color, Element, RedBlackTree, RedBlackTree)
}

public extension RedBlackTree {
    func contains(_ element: Element) -> Bool {
        switch self {
        case .empty:
            return false
        case .node(_, element, _, _):
            return true
        case let .node(_, value, left, _) where value > element:
            return left.contains(element)
        case let .node(_, _, _, right):
            return right.contains(element)
        }
    }
}

public extension RedBlackTree {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        switch self {
        case .empty:
            break
        case let .node(_, value, left, right):
            try left.forEach(body)
            try body(value)
            try right.forEach(body)
        }
    }
}

extension Color {
    var symbol: String {
        switch self {
        case .black: return "■"
        case .red:   return "□"
        }
    }
}

extension RedBlackTree: CustomStringConvertible {
    func diagram(_ top: String, _ root: String, _ bottom: String) -> String {
        switch self {
        case .empty:
            return root + "•\n"
        case let .node(color, value, .empty, .empty):
            return root + "\(color.symbol) \(value)\n"
        case let .node(color, value, left, right):
            return right.diagram(top + "    ", top + "┌───", top + "│   ")
                + root + "\(color.symbol) \(value)\n"
                + left.diagram(bottom + "│   ", bottom + "└───", bottom + "    ")
        }
    }

    public var description: String {
        return self.diagram("", "", "")
    }
}

extension RedBlackTree {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element)
    {
        let (tree, old) = inserting(element)
        self = tree
        return (old == nil, old ?? element)
    }
}

extension RedBlackTree {
    public func inserting(_ element: Element) -> (tree: RedBlackTree, existingMember: Element?) {
        let (tree, old) = _inserting(element)
        switch tree {
        case let .node(.red, value, left, right):
            return (.node(.black, value, left, right), old)
        default:
            return (tree, old)
        }
    }
}

extension RedBlackTree {
    func _inserting(_ element: Element) -> (tree: RedBlackTree, old: Element?)
    {
        switch self {

        case .empty:
            return (.node(.red, element, .empty, .empty), nil)

        case let .node(_, value, _, _) where value == element:
            return (self, value)

        case let .node(color, value, left, right) where value > element:
            let (l, old) = left._inserting(element)
            if let old = old { return (self, old) }
            return (balanced(color, value, l, right), nil)

        case let .node(color, value, left, right):
            let (r, old) = right._inserting(element)
            if let old = old { return (self, old) }
            return (balanced(color, value, left, r), nil)
        }
    }
}

extension RedBlackTree {
    func balanced(_ color: Color, _ value: Element, _ left: RedBlackTree, _ right: RedBlackTree) -> RedBlackTree {
        switch (color, value, left, right) {
        case let (.black, z, .node(.red, y, .node(.red, x, a, b), c), d):
            return .node(.red, y, .node(.black, x, a, b), .node(.black, z, c, d))
        case let (.black, z, .node(.red, x, a, .node(.red, y, b, c)), d):
            return .node(.red, y, .node(.black, x, a, b), .node(.black, z, c, d))
        case let (.black, x, a, .node(.red, z, .node(.red, y, b, c), d)):
            return .node(.red, y, .node(.black, x, a, b), .node(.black, z, c, d))
        case let (.black, x, a, .node(.red, y, b, .node(.red, z, c, d))):
            return .node(.red, y, .node(.black, x, a, b), .node(.black, z, c, d))
        default:
            return .node(color, value, left, right)
        }
    }
}

public struct AlgebraicIndex<Element: Comparable> {
    fileprivate var value: Element?
}

extension AlgebraicIndex: Comparable {
    public static func ==(left: AlgebraicIndex, right: AlgebraicIndex) -> Bool {
        return left.value == right.value
    }

    public static func <(left: AlgebraicIndex, right: AlgebraicIndex) -> Bool {
        if let lv = left.value, let rv = right.value {
            return lv < rv
        }
        return left.value != nil
    }
}

extension RedBlackTree {
    var minimum: Element? {
        switch self {
        case .empty:
            return nil
        case let .node(_, value, left, _):
            return left.minimum ?? value
        }
    }
}

extension RedBlackTree {
    var maximum: Element? {
        var node = self
        var maximum: Element? = nil
        while case let .node(_, value, _, right) = node {
            maximum = value
            node = right
        }
        return maximum
    }
}

extension RedBlackTree: Collection {
    public typealias Index = AlgebraicIndex<Element>

    public var startIndex: Index { return Index(value: self.minimum) }
    public var endIndex: Index { return Index(value: nil) }

    public subscript(i: Index) -> Element {
        return i.value!
    }
}

extension RedBlackTree {
    public var count: Int {
        switch self {
        case .empty:
            return 0
        case let .node(_, _, left, right):
            return left.count + 1 + right.count
        }
    }
}

extension RedBlackTree: BidirectionalCollection {
    public func formIndex(after i: inout Index) {
        let v = self.value(following: i.value!)
        precondition(v.found)
        i.value = v.next
    }

    public func index(after i: Index) -> Index {
        let v = self.value(following: i.value!)
        precondition(v.found)
        return Index(value: v.next)
    }
}

extension RedBlackTree {
    func value(following element: Element) -> (found: Bool, next: Element?) {
        switch self {
        case .empty:
            return (false, nil)
        case .node(_, element, _, let right):
            return (true, right.minimum)
        case let .node(_, value, left, _) where value > element:
            let v = left.value(following: element)
            return (v.found, v.next ?? value)
        case let .node(_, _, _, right):
            return right.value(following: element)
        }
    }
}

extension RedBlackTree {
    func value(preceding element: Element) -> (found: Bool, next: Element?) {
        var node = self
        var previous: Element? = nil
        while case let .node(_, value, left, right) = node {
            if value > element {
                node = left
            }
            else if value < element {
                previous = value
                node = right
            }
            else {
                return (true, left.maximum)
            }
        }
        return (false, previous)
    }
}

extension RedBlackTree {
    public func formIndex(before i: inout Index) {
        let v = self.value(preceding: i.value!)
        precondition(v.found)
        i.value = v.next
    }

    public func index(before i: Index) -> Index {
        let v = self.value(preceding: i.value!)
        precondition(v.found)
        return Index(value: v.next)
    }
}

extension RedBlackTree: SortedSet {
    public init() {
        self = .empty
    }
}

extension RedBlackTree {
    private func _validate(parentColor: Color) -> (min: Element, max: Element)? {
        switch self {
        case .empty:
            return nil
        case let .node(color, value, left, right):
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
    public func validate() {
        _ = _validate(parentColor: .red)
    }
}
