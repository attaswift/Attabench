//
//  IntBTree3.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//

private let internalOrder = 16

public struct IntBTree3 {
    fileprivate var root: Node

    public init(order: Int) {
        self.root = Node(order: order)
    }
}

extension IntBTree3 {
    public init() {
        self.init(order: Swift.max(16, cacheSize / (MemoryLayout<Int>.stride << 2)))
    }
}

fileprivate class Node {
    let order: Int
    var mutationCount: Int64 = 0
    var elementCount: Int = 0
    let elements: UnsafeMutablePointer<Int>
    var children: ContiguousArray<Node> = []

    init(order: Int) {
        self.order = order
        self.elements = .allocate(capacity: order)
    }

    deinit {
        elements.deinitialize(count: elementCount)
        elements.deallocate(capacity: order)
    }
}

extension IntBTree3 {
    public func forEach(_ body: (Int) throws -> Void) rethrows {
        try root.forEach(body)
    }
}

extension Node {
    func forEach(_ body: (Int) throws -> Void) rethrows {
        if isLeaf {
            for i in 0 ..< elementCount {
                try body(elements[i])
            }
        }
        else {
            for i in 0 ..< elementCount {
                try children[i].forEach(body)
                try body(elements[i])
            }
            try children[elementCount].forEach(body)
        }
    }
}

extension Node {
    internal func slot(of element: Int) -> (match: Bool, index: Int) {
        var start = 0
        var end = elementCount
        while start < end {
            let mid = start + (end - start) / 2
            if elements[mid] < element {
                start = mid + 1
            }
            else {
                end = mid
            }
        }
        let match = start < elementCount && elements[start] == element
        return (match, start)
    }
}

extension IntBTree3 {
    public func contains(_ element: Int) -> Bool {
        return root.contains(element)
    }
}

extension Node {
    func contains(_ element: Int) -> Bool {
        let slot = self.slot(of: element)
        if slot.match { return true }
        guard !children.isEmpty else { return false }
        return children[slot.index].contains(element)
    }
}

extension IntBTree3 {
    fileprivate mutating func makeRootUnique() -> Node {
        if isKnownUniquelyReferenced(&root) { return root }
        root = root.clone()
        return root
    }
}

extension Node {
    func clone() -> Node {
        let node = Node(order: order)
        node.elementCount = self.elementCount
        node.elements.initialize(from: self.elements, count: self.elementCount)
        if !isLeaf {
            node.children.reserveCapacity(order + 1)
            node.children += self.children
        }
        return node
    }
}

extension Node {
    func makeChildUnique(_ slot: Int) -> Node {
        guard !isKnownUniquelyReferenced(&children[slot]) else {
            return children[slot]
        }
        let clone = children[slot].clone()
        children[slot] = clone
        return clone
    }
}

extension Node {
    var maxChildren: Int { return order }
    var minChildren: Int { return (maxChildren + 1) / 2 }
    var maxInts: Int { return maxChildren - 1 }
    var minInts: Int { return minChildren - 1 }

    var isLeaf: Bool { return children.isEmpty }
    var isTooLarge: Bool { return elementCount > maxInts }
}

private struct Splinter {
    let separator: Int
    let node: Node
}

extension Node {
    func split() -> Splinter {
        let count = self.elementCount
        let middle = count / 2

        let separator = elements[middle]
        let node = Node(order: self.order)

        let c = count - middle - 1
        node.elements.moveInitialize(from: self.elements + middle + 1, count: c)
        node.elementCount = c
        self.elementCount = middle

        if !isLeaf {
            node.children.reserveCapacity(self.order + 1)
            node.children += self.children[middle + 1 ... count]
            self.children.removeSubrange(middle + 1 ... count)
        }
        return Splinter(separator: separator, node: node)
    }
}

extension Node {
    fileprivate func _insertInt(_ element: Int, at slot: Int) {
        assert(slot >= 0 && slot <= elementCount)
        (elements + slot + 1).moveInitialize(from: elements + slot, count: elementCount - slot)
        (elements + slot).initialize(to: element)
        elementCount += 1
    }
}

extension Node {
    func insert(_ element: Int) -> (old: Int?, splinter: Splinter?) {
        let slot = self.slot(of: element)
        if slot.match {
            // The element is already in the tree.
            return (self.elements[slot.index], nil)
        }
        mutationCount += 1
        if self.isLeaf {
            _insertInt(element, at: slot.index)
            return (nil, self.isTooLarge ? self.split() : nil)
        }
        let (old, splinter) = makeChildUnique(slot.index).insert(element)
        guard let s = splinter else { return (old, nil) }
        _insertInt(s.separator, at: slot.index)
        self.children.insert(s.node, at: slot.index + 1)
        return (old, self.isTooLarge ? self.split() : nil)
    }
}

extension IntBTree3 {
    @discardableResult
    public mutating func insert(_ element: Int) -> (inserted: Bool, memberAfterInsert: Int) {
        let root = makeRootUnique()
        let (old, splinter) = root.insert(element)
        if let s = splinter {
            let root = Node(order: internalOrder)
            root.elementCount = 1
            root.elements.initialize(to: s.separator)
            root.children = [self.root, s.node]
            self.root = root
        }
        return (inserted: old == nil, memberAfterInsert: old ?? element)
    }
}


private struct PathElement {
    unowned(unsafe) let node: Node
    var slot: Int

    init(_ node: Node, _ slot: Int) {
        self.node = node
        self.slot = slot
    }
}

extension PathElement {
    var isLeaf: Bool { return node.isLeaf }
    var isAtEnd: Bool { return slot == node.elementCount }
    var value: Int? {
        guard slot < node.elementCount else { return nil }
        return node.elements[slot]
    }
    var child: Node {
        return node.children[slot]
    }
}

extension PathElement: Equatable {
    static func ==(left: PathElement, right: PathElement) -> Bool {
        return left.node === right.node && left.slot == right.slot
    }
}

public struct IntBTree3Index: Comparable {
    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int64

    fileprivate var path: [PathElement]
    fileprivate var current: PathElement

    init(startOf tree: IntBTree3) {
        self.root = tree.root
        self.mutationCount = tree.root.mutationCount
        self.path = []
        self.current = PathElement(tree.root, 0)
        while !current.isLeaf { push(0) }
    }

    init(endOf tree: IntBTree3) {
        self.root = tree.root
        self.mutationCount = tree.root.mutationCount
        self.path = []
        self.current = PathElement(tree.root, tree.root.elementCount)
    }
}

extension IntBTree3Index {
    fileprivate func validate(for root: Node) {
        precondition(self.root === root)
        precondition(self.mutationCount == root.mutationCount)
    }

    fileprivate static func validate(_ left: IntBTree3Index, _ right: IntBTree3Index) {
        precondition(left.root === right.root)
        precondition(left.mutationCount == right.mutationCount)
        precondition(left.root != nil)
        precondition(left.mutationCount == left.root!.mutationCount)
    }
}

extension IntBTree3Index {
    fileprivate mutating func push(_ slot: Int) {
        path.append(current)
        current = PathElement(current.node.children[current.slot], slot)
    }

    fileprivate mutating func pop() {
        current = self.path.removeLast()
    }
}

extension IntBTree3Index {
    fileprivate mutating func formSuccessor() {
        precondition(!current.isAtEnd, "Cannot advance beyond endIndex")
        current.slot += 1
        if current.isLeaf {
            while current.isAtEnd, current.node !== root {
                pop()
            }
        }
        else {
            while !current.isLeaf {
                push(0)
            }
        }
    }
}

extension IntBTree3Index {
    fileprivate mutating func formPredecessor() {
        if current.isLeaf {
            while current.slot == 0, current.node !== root {
                pop()
            }
            precondition(current.slot > 0, "Cannot go below startIndex")
            current.slot -= 1
        }
        else {
            while !current.isLeaf {
                let c = current.child
                push(c.isLeaf ? c.elementCount - 1 : c.elementCount)
            }
        }
    }
}

extension IntBTree3Index {
    public static func ==(left: IntBTree3Index, right: IntBTree3Index) -> Bool {
        IntBTree3Index.validate(left, right)
        return left.current == right.current
    }

    public static func <(left: IntBTree3Index, right: IntBTree3Index) -> Bool {
        IntBTree3Index.validate(left, right)
        switch (left.current.value, right.current.value) {
        case let (.some(a), .some(b)): return a < b
        case (.none, _): return false
        default: return true
        }
    }
}

extension IntBTree3: SortedSet {
    public typealias Index = IntBTree3Index

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    public subscript(index: Index) -> Int {
        get {
            index.validate(for: root)
            return index.current.value!
        }
    }

    public func formIndex(after i: inout Index) {
        i.validate(for: root)
        i.formSuccessor()
    }

    public func index(after i: Index) -> Index {
        i.validate(for: root)
        var i = i
        i.formSuccessor()
        return i
    }

    public func formIndex(before i: inout Index) {
        i.validate(for: root)
        i.formPredecessor()
    }

    public func index(before i: Index) -> Index {
        i.validate(for: root)
        var i = i
        i.formPredecessor()
        return i
    }
}

extension IntBTree3 {
    public var count: Int {
        return root.count
    }
}

extension Node {
    var count: Int {
        return children.reduce(elementCount) { $0 + $1.count }
    }
}

public struct IntBTree3Iterator: IteratorProtocol {
    let tree: IntBTree3
    var index: IntBTree3Index

    init(_ tree: IntBTree3) {
        self.tree = tree
        self.index = tree.startIndex
    }

    public mutating func next() -> Int? {
        guard let result = index.current.value else { return nil }
        index.formSuccessor()
        return result
    }
}

extension IntBTree3 {
    public func makeIterator() -> IntBTree3Iterator {
        return IntBTree3Iterator(self)
    }
}

extension IntBTree3 {
    public func validate() {
        _ = root.validate(level: 0)
    }
}

extension Node {
    func validate(level: Int, min: Int? = nil, max: Int? = nil) -> Int {
        // Check balance.
        precondition(!isTooLarge)
        precondition(level == 0 || elementCount >= minInts)

        if elementCount == 0 {
            precondition(children.isEmpty)
            return 0
        }

        // Check element ordering.
        var previous = min
        for i in 0 ..< elementCount {
            let next = elements[i]
            precondition(previous == nil || previous! < next)
            previous = next
        }

        if isLeaf {
            return 0
        }

        // Check children.
        precondition(children.count == elementCount + 1)
        let depth = children[0].validate(level: level + 1, min: min, max: elements[0])
        for i in 1 ..< elementCount {
            let d = children[i].validate(level: level + 1, min: elements[i - 1], max: elements[i])
            precondition(depth == d)
        }
        let d = children[elementCount].validate(level: level + 1, min: elements[elementCount - 1], max: max)
        precondition(depth == d)
        return depth + 1
    }
}

