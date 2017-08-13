//
//  BinaryTree.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//


public struct BinaryTree<Element: Comparable>: CustomStringConvertible {
    typealias Node = BinaryTreeNode<Element>

    var root: Node?
    var mutationCount: Int

    public init() {
        self.root = nil
        self.mutationCount = 0
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
            self.root = Node(element)
            return (true, element)
        }
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

public struct BinaryTreeIndex<Element: Comparable>: Comparable {
    typealias Node = BinaryTreeNode<Element>
    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int

    private var path: [Weak<Node>]
    private var offset: Int

    init(endOf tree: BinaryTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.offset = -1
    }

    init(startOf tree: BinaryTree<Element>) {
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

    public static func ==(left: BinaryTreeIndex, right: BinaryTreeIndex) -> Bool {
        precondition(left.root === right.root && left.mutationCount == right.mutationCount)
        if left.root == nil && right.root == nil { return true } // Empty trees
        if left.path.isEmpty && right.path.isEmpty { return true } // Both at end of tree
        return left.offset == right.offset
    }

    public static func <(left: BinaryTreeIndex, right: BinaryTreeIndex) -> Bool {
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

extension BinaryTree: Collection {
    public typealias Index = BinaryTreeIndex<Element>

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

extension BinaryTree {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root?.forEach(body)
    }
}

extension BinaryTreeNode {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        try left?.forEach(body)
        try body(element)
        try right?.forEach(body)
    }
}

final class BinaryTreeNode<Element: Comparable>: CustomStringConvertible {
    var left: BinaryTreeNode<Element>? = nil
    var right: BinaryTreeNode<Element>? = nil
    var element: Element

    init(_ element: Element) {
        self.element = element
    }

    init(element: Element, left: BinaryTreeNode?, right: BinaryTreeNode?) {
        self.left = left
        self.right = right
        self.element = element
    }

    func clone() -> BinaryTreeNode {
        return BinaryTreeNode(element: element, left: left, right: right)
    }


    var description: String {
        var result = "("
        if let l = left {
            result += l.description
            result += " "
        }
        result += "\(element)"
        if let r = right {
            result += " "
            result += r.description
        }
        result += ")"
        return result
    }
}

extension BinaryTreeNode {
    func makeLeftUnique() -> BinaryTreeNode? {
        if left == nil { return nil }
        if isKnownUniquelyReferenced(&left!) {
            return left!
        }
        let child = left!.clone()
        left = child
        return child
    }

    func makeRightUnique() -> BinaryTreeNode? {
        if right == nil { return nil }
        if isKnownUniquelyReferenced(&right!) {
            return right!
        }
        let child = right!.clone()
        right = child
        return child
    }
}

extension BinaryTreeNode {
    func insert(_ element: Element)  -> (inserted: Bool, memberAfterInsert: Element) {
        if element < self.element {
            if let next = makeLeftUnique() {
                return next.insert(element)
            }
            else {
                self.left = BinaryTreeNode(element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        if element > self.element {
            if let next = makeRightUnique() {
                return next.insert(element)
            }
            else {
                self.right = BinaryTreeNode(element)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        return (inserted: false, memberAfterInsert: self.element)
    }
}

extension BinaryTree {
    func validate() {
        _ = root?.validate(min: nil, max: nil)
    }
}

extension BinaryTreeNode {
    func validate(min: Element?, max: Element?) -> (depthMin: Int, depthMax: Int) {
        if let min = min { precondition(min < element) }
        if let max = max { precondition(element < max) }
        let ldepth: (depthMin: Int, depthMax: Int) = left?.validate(min: min, max: self.element) ?? (0, 0)
        let rdepth: (depthMin: Int, depthMax: Int) = right?.validate(min: self.element, max: max) ?? (0, 0)
        return (Swift.min(ldepth.depthMin, rdepth.depthMin) + 1, Swift.max(ldepth.depthMax, rdepth.depthMax) + 1)
    }
}

