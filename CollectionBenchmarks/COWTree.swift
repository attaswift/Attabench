//
//  COWTree.swift
//  dotSwift
//
//  Copyright © 2017 Károly Lőrentey.
//


/// A red-black tree with value semantics and copy-on-write optimization.
public struct COWTree<Element: Comparable> {
    var root: COWNode<Element>?
    var mutationCount: Int

    public init() {
        self.root = nil
        self.mutationCount = 0
    }
}

final class COWNode<Element: Comparable> {
    var left: COWNode<Element>? = nil
    var value: Element
    var right: COWNode<Element>? = nil
    var color: Color

    init(_ color: Color, _ left: COWNode?, _ value: Element, _ right: COWNode?) {
        self.left = left
        self.value = value
        self.right = right
        self.color = color
    }

    convenience init(_ color: Color, _ value: Element) {
        self.init(color, nil, value, nil)
    }
}

//MARK: makeUnique

extension COWTree {
    mutating func makeUnique() -> COWNode<Element>? {
        mutationCount += 1
        guard root != nil else { return nil }
        if isKnownUniquelyReferenced(&root!) { return root }
        let node = root!.clone()
        root = node
        return node
    }
}

extension COWNode {
    func clone() -> COWNode {
        return COWNode(color, left, value, right)
    }

    func makeLeftUnique() -> COWNode? {
        if left == nil { return nil }
        if isKnownUniquelyReferenced(&left!) {
            return left!
        }
        let child = left!.clone()
        left = child
        return child
    }

    func makeRightUnique() -> COWNode? {
        if right == nil { return nil }
        if isKnownUniquelyReferenced(&right!) {
            return right!
        }
        let child = right!.clone()
        right = child
        return child
    }
}

//MARK: Depth 

extension COWTree {
    var depth: (min: Int, max: Int) {
        if let root = self.root {
            return root.depth
        }
        else {
            return (0, 0)
        }
    }
}

extension COWNode {
    var depth: (min: Int, max: Int) {
        let l: (min: Int, max: Int) = left?.depth ?? (0, 0)
        let r: (min: Int, max: Int) = right?.depth ?? (0, 0)
        return (1 + min(l.min, r.min), 1 + max(l.max, r.max))
    }
}

//MARK: Contains

extension COWTree {
    public func contains(_ element: Element) -> Bool {
        var node = root
        while let n = node {
            if n.value < element {
                node = n.right
            }
            else if n.value > element {
                node = n.left
            }
            else {
                return true
            }
        }
        return false
    }
}

//MARK: forEach

extension COWTree {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root?.forEach(body)
    }
}

extension COWNode {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        try left?.forEach(body)
        try body(value)
        try right?.forEach(body)
    }
}


//MARK: insert

extension COWTree {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        guard let root = makeUnique() else {
            self.root = COWNode(.black, element)
            return (true, element)
        }
        defer { root.color = .black }
        return root.insert(element)
    }
}

extension COWNode {
    func insert(_ element: Element)  -> (inserted: Bool, memberAfterInsert: Element) {
        if element < self.value {
            if let next = makeLeftUnique() {
                let result = next.insert(element)
                self.balance()
                return result
            }
            else {
                self.left = COWNode(.red, element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        if element > self.value {
            if let next = makeRightUnique() {
                let result = next.insert(element)
                self.balance()
                return result
            }
            else {
                self.right = COWNode(.red, element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        return (inserted: false, memberAfterInsert: self.value)
    }
}

extension COWNode {
    func balance() {
        if self.color == .red  { return }
        if left?.color == .red {
            if left?.left?.color == .red {
                let l = left!
                let ll = l.left!
                swap(&self.value, &l.value)
                (self.left, l.left, l.right, self.right) = (ll, l.right, self.right, l)
                self.color = .red
                l.color = .black
                ll.color = .black
                return
            }
            if left?.right?.color == .red {
                let l = left!
                let lr = l.right!
                swap(&self.value, &lr.value)
                (l.right, lr.left, lr.right, self.right) = (lr.left, lr.right, self.right, lr)
                self.color = .red
                l.color = .black
                lr.color = .black
                return
            }
        }
        if right?.color == .red {
            if right?.left?.color == .red {
                let r = right!
                let rl = r.left!
                swap(&self.value, &rl.value)
                (self.left, rl.left, rl.right, r.left) = (rl, self.left, rl.left, rl.right)
                self.color = .red
                r.color = .black
                rl.color = .black
                return
            }
            if right?.right?.color == .red {
                let r = right!
                let rr = r.right!
                swap(&self.value, &r.value)
                (self.left, r.left, r.right, self.right) = (r, self.left, r.left, rr)
                self.color = .red
                r.color = .black
                rr.color = .black
                return
            }
        }
    }
}

//MARK: Collection

private struct Weak<Wrapped: AnyObject> {
    weak var value: Wrapped?

    init(_ value: Wrapped) {
        self.value = value
    }
}

public struct COWTreeIndex<Element: Comparable>: Comparable {
    fileprivate weak var root: COWNode<Element>?
    fileprivate let mutationCount: Int

    private var path: [Weak<COWNode<Element>>]
    private var offset: Int

    init(endOf tree: COWTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.offset = -1
    }

    init(startOf tree: COWTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.offset = 0
        var node = tree.root
        while let n = node {
            self.path.append(Weak(n))
            node = n.left
        }
    }

    var current: COWNode<Element>? {
        guard let ref = path.last else { return nil }
        return ref.value!
    }

    public static func ==(left: COWTreeIndex, right: COWTreeIndex) -> Bool {
        precondition(left.root === right.root && left.mutationCount == right.mutationCount)
        if left.root == nil && right.root == nil { return true } // Empty trees
        if left.path.isEmpty && right.path.isEmpty { return true } // Both at end of tree
        return left.offset == right.offset
    }

    public static func <(left: COWTreeIndex, right: COWTreeIndex) -> Bool {
        precondition(left.root === right.root && left.mutationCount == right.mutationCount)
        if left.path.isEmpty { return false }
        if right.path.isEmpty { return true }
        return left.offset < right.offset
    }

    mutating func _advance() {
        guard let node = current else { preconditionFailure() }
        offset += 1
        if var n = node.right {
            // Descend to leftmost node in the current node's right subtree.
            path.append(Weak(n))
            while let next = n.left {
                path.append(Weak(next))
                n = next
            }
        }
        else {
            // Ascend to nearest ancestor that has the current node in its left subtree.
            path.removeLast()
            var n = node
            while let parent = self.current {
                if parent.left === n { return }
                n = parent
                path.removeLast()
            }
        }
    }
}

extension COWTree: Collection {
    public typealias Index = COWTreeIndex<Element>

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    public subscript(_ index: Index) -> Element {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
        return index.current!.value
    }

    public func formIndex(after index: inout Index) {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
        index._advance()
    }

    public func index(after index: Index) -> Index {
        var result = index
        self.formIndex(after: &result)
        return result
    }
}

//MARK: CustomStringConvertible

extension COWTree: CustomStringConvertible {
    public var description: String {
        return root?.description ?? "()"
    }
}

extension COWNode: CustomStringConvertible {

    var description: String {
        var result = "("
        if let l = left {
            result += l.description
            result += " "
        }
        result += color == .red ? "🔴" : "⚫️"
        result += "\(value)"
        if let r = right {
            result += " "
            result += r.description
        }
        result += ")"
        return result
    }
}

//MARK: validate()

extension COWTree {
    func validate() {
        _ = root?.validate(parentColor: .red, min: nil, max: nil)
    }
}

extension COWNode {
    func validate(parentColor: Color, min: Element?, max: Element?) -> Int {
        precondition(parentColor == .black || color == .black)
        if let min = min { precondition(min < value) }
        if let max = max { precondition(value < max) }
        let lb = left?.validate(parentColor: color, min: min, max: self.value) ?? 0
        let rb = right?.validate(parentColor: color, min: self.value, max: max) ?? 0
        precondition(lb == rb)
        return color == .black ? lb + 1 : lb
    }
}
