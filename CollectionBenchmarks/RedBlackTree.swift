//
//  RedBlackTree.swift
//  dotSwift
//
//  Copyright © 2017 Károly Lőrentey.
//


public struct RedBlackTree<Element: Comparable>: CustomStringConvertible {
    typealias Node = RedBlackTreeNode<Element>

    var root: Node?
    var mutationCount: Int

    public init() {
        self.root = nil
        self.mutationCount = 0
    }

    var depth: (min: Int, max: Int) {
        if let root = self.root {
            return root.depth
        }
        else {
            return (0, 0)
        }
    }
    public func contains(_ element: Element) -> Bool {
        var node = root
        while let n = node {
            if n.element < element {
                node = n.right
            }
            else if n.element == element {
                return true
            }
            else {
                node = n.left
            }
        }
        return false
    }

    var isUniquelyReferenced: Bool {
        mutating get {
            if root == nil { return true }
            return isKnownUniquelyReferenced(&root!)
        }
    }

    mutating func makeUnique() -> Node? {
        if isUniquelyReferenced { return root }
        let node = root!.clone()
        root = node
        return node
    }

    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        self.mutationCount += 1
        guard let root = makeUnique() else {
            self.root = Node(.black, element)
            return (true, element)
        }
        defer { root.color = .black }
        return root.insert(element)
    }

    public var description: String {
        return root?.description ?? "()"
    }
}

private struct Weak<Wrapped: AnyObject> {
    weak var value: Wrapped?

    init(_ value: Wrapped) {
        self.value = value
    }
}

public struct RedBlackTreeIndex<Element: Comparable>: Comparable {
    typealias Node = RedBlackTreeNode<Element>
    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int

    private var path: [Weak<Node>]
    private var offset: Int

    init(endOf tree: RedBlackTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.offset = -1
    }

    init(startOf tree: RedBlackTree<Element>) {
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

    var current: Node? {
        guard let ref = path.last else { return nil }
        return ref.value!
    }

    public static func ==(left: RedBlackTreeIndex, right: RedBlackTreeIndex) -> Bool {
        precondition(left.root === right.root && left.mutationCount == right.mutationCount)
        if left.root == nil && right.root == nil { return true } // Empty trees
        if left.path.isEmpty && right.path.isEmpty { return true } // Both at end of tree
        return left.offset == right.offset
    }

    public static func <(left: RedBlackTreeIndex, right: RedBlackTreeIndex) -> Bool {
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

extension RedBlackTree: Collection {
    public typealias Index = RedBlackTreeIndex<Element>

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    public subscript(_ index: Index) -> Element {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
        return index.current!.element
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

enum RedBlackColor {
    case red
    case black
}

final class RedBlackTreeNode<Element: Comparable>: CustomStringConvertible {
    var left: RedBlackTreeNode<Element>? = nil
    var element: Element
    var right: RedBlackTreeNode<Element>? = nil
    var color: RedBlackColor

    init(_ color: RedBlackColor, _ element: Element) {
        self.element = element
        self.color = color
    }

    init(color: RedBlackColor, left: RedBlackTreeNode?, element: Element, right: RedBlackTreeNode?) {
        self.left = left
        self.element = element
        self.right = right
        self.color = color
    }

    func clone() -> RedBlackTreeNode {
        return RedBlackTreeNode(color: color, left: left, element: element, right: right)
    }

    var description: String {
        var result = "("
        if let l = left {
            result += l.description
            result += " "
        }
        result += color == .red ? "🔴" : "⚫️"
        result += "\(element)"
        if let r = right {
            result += " "
            result += r.description
        }
        result += ")"
        return result
    }
}

extension RedBlackTreeNode {
    func leftMostSubnode() -> RedBlackTreeNode {
        var node = self
        while let next = node.left {
            node = next
        }
        return node
    }

    var depth: (min: Int, max: Int) {
        let l: (min: Int, max: Int) = left?.depth ?? (0, 0)
        let r: (min: Int, max: Int) = right?.depth ?? (0, 0)
        return (1 + min(l.min, r.min), 1 + max(l.max, r.max))
    }
}

extension RedBlackTreeNode {
    func makeLeftUnique() -> RedBlackTreeNode? {
        if left == nil { return nil }
        if isKnownUniquelyReferenced(&left!) {
            return left!
        }
        let child = left!.clone()
        left = child
        return child
    }

    func makeRightUnique() -> RedBlackTreeNode? {
        if right == nil { return nil }
        if isKnownUniquelyReferenced(&right!) {
            return right!
        }
        let child = right!.clone()
        right = child
        return child
    }
}

extension RedBlackTreeNode {
    func balance() {
        if self.color == .red  { return }
        if left?.color == .red {
            if left?.left?.color == .red {
                let l = left!
                let ll = l.left!
                swap(&self.element, &l.element)
                (self.left, l.left, l.right, self.right) = (ll, l.right, self.right, l)
                self.color = .red
                l.color = .black
                ll.color = .black
                return
            }
            if left?.right?.color == .red {
                let l = left!
                let lr = l.right!
                swap(&self.element, &lr.element)
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
                swap(&self.element, &rl.element)
                (self.left, rl.left, rl.right, r.left) = (rl, self.left, rl.left, rl.right)
                self.color = .red
                r.color = .black
                rl.color = .black
                return
            }
            if right?.right?.color == .red {
                let r = right!
                let rr = r.right!
                swap(&self.element, &r.element)
                (self.left, r.left, r.right, self.right) = (r, self.left, r.left, rr)
                self.color = .red
                r.color = .black
                rr.color = .black
                return
            }
        }
    }

    func insert(_ element: Element)  -> (inserted: Bool, memberAfterInsert: Element) {
        if element < self.element {
            if let next = makeLeftUnique() {
                let result = next.insert(element)
                self.balance()
                return result
            }
            else {
                self.left = RedBlackTreeNode(.red, element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        if element > self.element {
            if let next = makeRightUnique() {
                let result = next.insert(element)
                self.balance()
                return result
            }
            else {
                self.right = RedBlackTreeNode(.red, element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        return (inserted: false, memberAfterInsert: self.element)
    }
}

extension RedBlackTree {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root?.forEach(body)
    }
}

extension RedBlackTreeNode {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        try left?.forEach(body)
        try body(element)
        try right?.forEach(body)
    }
}

extension RedBlackTree {
    func validate() {
        _ = root?.validate(parentColor: .red, min: nil, max: nil)
    }
}

extension RedBlackTreeNode {
    func validate(parentColor: RedBlackColor, min: Element?, max: Element?) -> Int {
        precondition(parentColor == .black || color == .black)
        if let min = min { precondition(min < element) }
        if let max = max { precondition(element < max) }
        let lb = left?.validate(parentColor: color, min: min, max: self.element) ?? 0
        let rb = right?.validate(parentColor: color, min: self.element, max: max) ?? 0
        precondition(lb == rb)
        return color == .black ? lb + 1 : lb
    }
}
