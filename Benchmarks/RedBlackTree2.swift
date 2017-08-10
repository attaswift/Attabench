//
//  RedBlackTree2.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//

public struct RedBlackTree2<Element: Comparable>: SortedSet {
    fileprivate var root: Node<Element>? = nil

    public init() {}
}

private final class Node<Element: Comparable> {
    var color: Color
    var value: Element
    var left: Node<Element>? = nil
    var right: Node<Element>? = nil
    var mutationCount: Int64 = 0

    init(_ color: Color, _ value: Element, _ left: Node?, _ right: Node?) {
        self.color = color
        self.value = value
        self.left = left
        self.right = right
    }
}

extension RedBlackTree2 {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root?.forEach(body)
    }
}

extension Node {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        try left?.forEach(body)
        try body(value)
        try right?.forEach(body)
    }
}

extension RedBlackTree2 {
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

private func diagram<Element>(for node: Node<Element>?, _ top: String = "", _ root: String = "", _ bottom: String = "") -> String {
    guard let node = node else {
        return root + "•\n"
    }
    if node.left == nil && node.right == nil {
        return root + "\(node.color.symbol) \(node.value)\n"
    }
    return diagram(for: node.right, top + "    ", top + "┌───", top + "│   ")
        + root + "\(node.color.symbol) \(node.value)\n"
        + diagram(for: node.left, bottom + "│   ", bottom + "└───", bottom + "    ")
}

extension RedBlackTree2: CustomStringConvertible {
    public var description: String {
        return diagram(for: root)
    }
}

extension Node {
    func clone() -> Node {
        return Node(color, value, left, right)
    }
}

extension RedBlackTree2 {
    fileprivate mutating func makeRootUnique() -> Node<Element>? {
        if root != nil, !isKnownUniquelyReferenced(&root) {
            root = root!.clone()
        }
        return root
    }
}

extension Node {
    func makeLeftUnique() -> Node? {
        if left != nil, !isKnownUniquelyReferenced(&left) {
            left = left!.clone()
        }
        return left
    }

    func makeRightUnique() -> Node? {
        if right != nil, !isKnownUniquelyReferenced(&right) {
            right = right!.clone()
        }
        return right
    }
}

extension RedBlackTree2 {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        guard let root = makeRootUnique() else {
            self.root = Node(.black, element, nil, nil)
            return (true, element)
        }
        defer { root.color = .black }
        return root.insert(element)
    }
}

extension Node {
    func insert(_ element: Element)  -> (inserted: Bool, memberAfterInsert: Element) {
        mutationCount += 1
        if element < self.value {
            if let next = makeLeftUnique() {
                let result = next.insert(element)
                if result.inserted { self.balance() }
                return result
            }
            else {
                self.left = Node(.red, element, nil, nil)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        if element > self.value {
            if let next = makeRightUnique() {
                let result = next.insert(element)
                if result.inserted { self.balance() }
                return result
            }
            else {
                self.right = Node(.red, element, nil, nil)
                return (inserted: true, memberAfterInsert: element)
            }
        }
        return (inserted: false, memberAfterInsert: self.value)
    }
}

extension Node {
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

private struct Weak<Wrapped: AnyObject> {
    weak var value: Wrapped?

    init(_ value: Wrapped) {
        self.value = value
    }
}

public struct RedBlackTree2Index<Element: Comparable> {
    fileprivate weak var root: Node<Element>?
    fileprivate let mutationCount: Int64

    fileprivate var path: [Weak<Node<Element>>]

    fileprivate init(root: Node<Element>?, path: [Weak<Node<Element>>]) {
        self.root = root
        self.mutationCount = root?.mutationCount ?? -1
        self.path = path
    }
}

extension RedBlackTree2: BidirectionalCollection {
    public typealias Index = RedBlackTree2Index<Element>

    public var endIndex: Index {
        return Index(root: root, path: [])
    }

    public var startIndex: Index {
        var path: [Weak<Node<Element>>] = []
        var node = root
        while let n = node {
            path.append(Weak(n))
            node = n.left
        }
        return Index(root: root, path: path)
    }
}

extension RedBlackTree2Index {
    fileprivate func validate(for root: Node<Element>?) {
        precondition(self.root === root)
        precondition(self.mutationCount == root?.mutationCount ?? -1)
    }
}

extension RedBlackTree2Index {
    fileprivate static func validate(_ left: RedBlackTree2Index, _ right: RedBlackTree2Index) {
        precondition(left.root === right.root)
        precondition(left.mutationCount == right.mutationCount)
        precondition(left.mutationCount == left.root?.mutationCount ?? -1)
    }
}

extension RedBlackTree2 {
    public subscript(_ index: Index) -> Element {
        index.validate(for: root)
        return index.path.last!.value!.value
    }
}

extension RedBlackTree2Index {
    fileprivate var current: Node<Element>? {
        guard let ref = path.last else { return nil }
        return ref.value!
    }
}

extension RedBlackTree2Index: Comparable {
    public static func ==(left: RedBlackTree2Index, right: RedBlackTree2Index) -> Bool {
        RedBlackTree2Index.validate(left, right)
        return left.current === right.current
    }

    public static func <(left: RedBlackTree2Index, right: RedBlackTree2Index) -> Bool {
        RedBlackTree2Index.validate(left, right)
        switch (left.current, right.current) {
        case let (.some(a), .some(b)):
            return a.value < b.value
        case (.none, _):
            return false
        default:
            return true
        }
    }
}

extension RedBlackTree2 {
    public func formIndex(after index: inout Index) {
        index.validate(for: root)
        index.formSuccessor()
    }

    public func index(after index: Index) -> Index {
        var result = index
        self.formIndex(after: &result)
        return result
    }
}

extension RedBlackTree2Index {
    mutating func formSuccessor() {
        guard let node = current else { preconditionFailure() }
        if var n = node.right {
            path.append(Weak(n))
            while let next = n.left {
                path.append(Weak(next))
                n = next
            }
        }
        else {
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

extension RedBlackTree2 {
    public func formIndex(before index: inout Index) {
        index.validate(for: root)
        index.formPredecessor()
    }

    public func index(before index: Index) -> Index {
        var result = index
        self.formIndex(before: &result)
        return result
    }
}

extension RedBlackTree2Index {
    mutating func formPredecessor() {
        guard let node = current else { preconditionFailure() }
        if var n = node.left {
            path.append(Weak(n))
            while let next = n.right {
                path.append(Weak(next))
                n = next
            }
        }
        else {
            path.removeLast()
            var n = node
            while let parent = self.current {
                if parent.right === n { return }
                n = parent
                path.removeLast()
            }
        }
    }
}

public struct RedBlackTree2Iterator<Element: Comparable>: IteratorProtocol {
    let tree: RedBlackTree2<Element>
    var index: RedBlackTree2Index<Element>

    init(_ tree: RedBlackTree2<Element>) {
        self.tree = tree
        self.index = tree.startIndex
    }

    public mutating func next() -> Element? {
        if index.path.isEmpty { return nil }
        defer { index.formSuccessor() }
        return index.path.last!.value!.value
    }
}

extension RedBlackTree2 {
    public func makeIterator() -> RedBlackTree2Iterator<Element> {
        return RedBlackTree2Iterator(self)
    }
}

//MARK: validate()

extension RedBlackTree2 {
    public func validate() {
        _ = root?.validate(parentColor: .red, min: nil, max: nil)
    }
}

extension Node {
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
