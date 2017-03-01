//
//  BTree2.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//

public struct BTree2<Element: Comparable> {
    fileprivate typealias Node = BTreeNode2<Element>
    fileprivate var root: Node
    var mutationCount: Int = 0

    public init() {
        self.init(order: 1024)
    }
    
    public init(order: Int) {
        self.root = Node(order: order)
    }

    public var order: Int { return root.order }
    public var depth: Int {
        var depth = 1
        var node = root
        while !node.isLeaf {
            depth += 1
            node = node.children![0]
        }
        return depth
    }
}

fileprivate class BTreeNode2<Element: Comparable> {
    let order: Int
    var elementCount: Int
    var elements: UnsafeMutablePointer<Element>
    var children: UnsafeMutablePointer<BTreeNode2>?

    init(order: Int, leaf: Bool = true) {
        self.order = order
        self.elementCount = 0
        self.elements = .allocate(capacity: order)
        self.children = leaf ? nil : .allocate(capacity: order + 1)
    }

    deinit {
        elements.deinitialize(count: elementCount)
        elements.deallocate(capacity: order)
        if let children = self.children {
            children.deinitialize(count: elementCount + 1)
            children.deallocate(capacity: order + 1)
        }
    }
}

private struct Unowned<Wrapped: AnyObject> {
    unowned(unsafe) let value: Wrapped

    init(_ value: Wrapped) {
        self.value = value
    }
}

public struct BTreeIndex2<Element: Comparable>: Comparable {
    fileprivate typealias Node = BTreeNode2<Element>

    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int

    fileprivate var path: [(ref: Unowned<Node>, slot: Int)]
    fileprivate unowned var node: Node
    fileprivate var slot: Int

    init(startOf tree: BTree2<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.node = tree.root
        self.slot = 0
        _descend()
    }

    init(endOf tree: BTree2<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.node = tree.root
        self.slot = tree.root.elementCount
    }

    private mutating func _push(_ slot: Int) {
        let n = self.node
        path.append((Unowned(n), self.slot))
        self.node = n.children![self.slot]
        self.slot = slot
    }

    private mutating func _pop() {
        let last = self.path.removeLast()
        self.node = last.ref.value
        self.slot = last.slot
    }

    private mutating func _descend() {
        if self.node.isLeaf { return }
        _push(0)
        while !self.node.isLeaf {
            _push(0)
        }
    }

    fileprivate mutating func _advance() {
        slot += 1
        if _fastPath(node.isLeaf && slot < node.elementCount) {
            return
        }
        if !node.isLeaf, slot <= node.elementCount {
            _descend()
            return
        }
        if node === root {
            precondition(slot <= node.elementCount, "Cannot advance beyond endIndex")
        }
        else {
            _pop()
            while node !== root, slot == node.elementCount {
                _pop()
            }
        }
    }

    var current: Element? {
        guard let n = path.last else { return nil }
        return n.ref.value.elements[n.slot]
    }

    public static func ==(left: BTreeIndex2, right: BTreeIndex2) -> Bool {
        precondition(left.root != nil && left.root === right.root && left.mutationCount == right.mutationCount)
        return left.node === right.node && left.slot == right.slot
    }

    public static func <(left: BTreeIndex2, right: BTreeIndex2) -> Bool {
        precondition(left.root != nil && left.root === right.root && left.mutationCount == right.mutationCount)
        switch (left.current, right.current) {
        case let (.some(a), .some(b)):
            return a < b
        case (.none, _):
            return false
        default:
            return true
        }
    }
}

extension BTree2: Collection {
    public typealias Index = BTreeIndex2<Element>

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

        func _validate(_ index: Index) {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
    }

    public subscript(index: Index) -> Element {
        get {
            _validate(index)
            return index.node.elements[index.slot]
        }
    }

    public func formIndex(after i: inout Index) {
        _validate(i)
        i._advance()
    }

    public func index(after i: Index) -> Index {
        _validate(i)
        var i = i
        i._advance()
        return i
    }
}

extension BTreeNode2 {
    internal func slot(of element: Element) -> (match: Bool, index: Int) {
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

extension BTree2 {
    public func contains(_ element: Element) -> Bool {
        return root.contains(element)
    }

    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root.forEach(body)
    }
}

extension BTreeNode2 {
    func contains(_ element: Element) -> Bool {
        let slot = self.slot(of: element)
        if slot.match { return true }
        return children?[slot.index].contains(element) ?? false
    }

    func forEach(_ body: (Element) throws -> Void) rethrows {
        for i in 0 ..< elementCount {
            try children?[i].forEach(body)
            try body(elements[i])
        }
        try children?[elementCount].forEach(body)
    }
}

extension BTree2 {
    fileprivate mutating func makeRootUnique() -> Node {
        mutationCount += 1
        if isKnownUniquelyReferenced(&root) { return root }
        let r = root.clone()
        root = r
        return r
    }
}
extension BTreeNode2 {
    func clone() -> BTreeNode2 {
        let clone = BTreeNode2(order: order, leaf: self.isLeaf)
        clone.elements.initialize(from: self.elements, count: self.elementCount)
        if let children = children {
            clone.children!.initialize(from: children, count: self.elementCount + 1)
        }
        clone.elementCount = self.elementCount
        return clone
    }

    func makeChildUnique(_ slot: Int) -> BTreeNode2 {
        guard !isKnownUniquelyReferenced(&children![slot]) else { return children![slot] }
        let clone = children![slot].clone()
        children![slot] = clone
        return clone
    }

    var maxChildren: Int { return order }
    var minChildren: Int { return (maxChildren + 1) / 2 }
    var maxElements: Int { return maxChildren - 1 }
    var minElements: Int { return minChildren - 1 }

    var isLeaf: Bool { return children == nil }
    var isFull: Bool { return elementCount == maxElements }
    var isTooSmall: Bool { return elementCount < minElements }
    var isTooLarge: Bool { return elementCount > maxElements }
    var isBalanced: Bool { return !isTooLarge && !isTooSmall }
}

extension UnsafeMutablePointer {
    @inline(__always)
    fileprivate mutating func advancingInitialize(to value: Pointee, count: Int = 1) {
        self.initialize(to: value, count: count)
        self += count
    }

    @inline(__always)
    fileprivate mutating func advancingInitialize(from source: UnsafePointer<Pointee>, count: Int) {
        self.initialize(from: source, count: count)
        self += count
    }
}

fileprivate struct Splinter<Element: Comparable> {
    let separator: Element
    let node: BTreeNode2<Element>
}

extension BTreeNode2 {
    func split() -> Splinter<Element> {
        let count = elementCount
        let median = count / 2
        let node = BTreeNode2(order: order, leaf: self.isLeaf)
        let separator = (elements + median).move()
        let c = count - median - 1
        node.elements.moveInitialize(from: self.elements + median + 1, count: c)
        if self.children != nil {
            node.children!.moveInitialize(from: self.children! + median + 1, count: c + 1)
        }
        self.elementCount = median
        node.elementCount = c
        return Splinter(separator: separator, node: node)
    }

    func _insertElement(_ element: Element, at index: Int) {
        assert(index >= 0 && index <= elementCount)
        (elements + index + 1).moveInitialize(from: elements + index, count: elementCount - index)
        (elements + index).initialize(to: element)
        elementCount += 1
    }

    func _insertChild(_ child: BTreeNode2, at index: Int) {
        assert(index >= 0 && index <= elementCount + 1)
        (children! + index + 1).moveInitialize(from: children! + index, count: elementCount + 1 - index)
        (children! + index).initialize(to: child)
    }

    func insert(_ element: Element) -> (old: Element?, splinter: Splinter<Element>?) {
        let slot = self.slot(of: element)
        if slot.match {
            // The element is already in the tree.
            return (self.elements[slot.index], nil)
        }
        if self.isLeaf {
            _insertElement(element, at: slot.index)
            return (nil, self.isTooLarge ? self.split() : nil)
        }
        if isKnownUniquelyReferenced(&children![slot.index]) {
            let (old, splinter) = children![slot.index].insert(element)
            guard let s = splinter else { return (old, nil) }
            assert(old == nil)
            _insertChild(s.node, at: slot.index + 1)
            _insertElement(s.separator, at: slot.index)
            return (nil, self.isTooLarge ? self.split() : nil)
        }
        else {
            let (old, trunk, splinter) = children![slot.index].inserting(element)
            if old != nil { return (old, nil) }
            self.children![slot.index] = trunk
            guard let s = splinter else { return (nil, nil) }
            _insertChild(s.node, at: slot.index + 1)
            _insertElement(s.separator, at: slot.index)
            return (nil, self.isTooLarge ? self.split() : nil)
        }
    }

    func _inserting(_ element: Element, _ spawn: (left: BTreeNode2, right: BTreeNode2)?, at index: Int)
        -> (trunk: BTreeNode2, splinter: Splinter<Element>?) {
        if elementCount < maxElements {
            let tree = BTreeNode2(order: order, leaf: isLeaf)
            var p = tree.elements
            p.advancingInitialize(from: elements, count: index)
            p.advancingInitialize(to: element)
            p.advancingInitialize(from: elements + index, count: elementCount - index)

            if let spawn = spawn {
                var q = tree.children!
                q.advancingInitialize(from: children!, count: index)
                q.advancingInitialize(to: spawn.left)
                q.advancingInitialize(to: spawn.right)
                q.advancingInitialize(from: children! + index + 1, count: elementCount - index)
            }
            tree.elementCount = self.elementCount + 1
            return (tree, nil)
        }
        // Split
        let median = (elementCount + 1) / 2
        if median < index {
            let separator = elements[median]

            let left = BTreeNode2(order: order, leaf: isLeaf)
            left.elements.initialize(from: elements, count: median)
            left.elementCount = median

            let right = BTreeNode2(order: order, leaf: isLeaf)
            var p = right.elements
            p.advancingInitialize(from: elements + median + 1, count: index - median - 1)
            p.advancingInitialize(to: element)
            p.advancingInitialize(from: elements + index, count: elementCount - index)
            right.elementCount = elementCount - median

            if let spawn = spawn {
                left.children!.initialize(from: children!, count: median + 1)
                var q = right.children!
                q.advancingInitialize(from: children! + median + 1, count: index - median - 1)
                q.advancingInitialize(to: spawn.left)
                q.advancingInitialize(to: spawn.right)
                q.advancingInitialize(from: children! + (index + 1), count: elementCount - index)
            }
            return (left, Splinter(separator: separator, node: right))
        }
        if median > index {
            let separator = elements[median - 1]

            let left = BTreeNode2(order: order, leaf: isLeaf)
            var p = left.elements
            p.advancingInitialize(from: elements, count: index)
            p.advancingInitialize(to: element)
            p.advancingInitialize(from: elements + index, count: median - index - 1)
            left.elementCount = median

            let right = BTreeNode2(order: order, leaf: isLeaf)
            right.elements.initialize(from: elements + median, count: elementCount - median)
            right.elementCount = elementCount - median

            if let spawn = spawn {
                var q = left.children!
                q.advancingInitialize(from: children!, count: index)
                q.advancingInitialize(to: spawn.left)
                q.advancingInitialize(to: spawn.right)
                q.advancingInitialize(from: children! + index + 1, count: median - index - 1)

                right.children!.initialize(from: children! + median, count: elementCount - median + 1)
            }

            return (left, Splinter(separator: separator, node: right))
        }
        // median == slot.index
        let separator = element

        let left = BTreeNode2(order: order, leaf: isLeaf)
        left.elements.initialize(from: elements, count: median)
        left.elementCount = median

        let right = BTreeNode2(order: order, leaf: isLeaf)
        right.elements.initialize(from: elements + median, count: elementCount - median)
        right.elementCount = elementCount - median

        if let spawn = spawn {
            left.children!.initialize(from: children!, count: index)
            (left.children! + index).initialize(to: spawn.left)

            right.children!.initialize(to: spawn.right)
            (right.children! + 1).initialize(from: children! + index + 1, count: elementCount - median)
        }

        return (left, Splinter(separator: separator, node: right))
    }

    func inserting(_ element: Element) -> (old: Element?, trunk: BTreeNode2, splinter: Splinter<Element>?) {
        let slot = self.slot(of: element)
        if slot.match {
            // The element is already in the tree.
            return (self.elements[slot.index], self, nil)
        }
        if self.isLeaf {
            let t = self._inserting(element, nil, at: slot.index)
            return (nil, t.trunk, t.splinter)
        }
        let (old, trunk, splinter) = self.children![slot.index].inserting(element)
        if let old = old {
            assert(splinter == nil && trunk === self.children![slot.index])
            return (old, self, nil)
        }
        if let splinter = splinter {
            let t = self._inserting(splinter.separator, (trunk, splinter.node), at: slot.index)
            return (nil, t.trunk, t.splinter)
        }
        let clone = self.clone()
        clone.children![slot.index] = trunk
        return (nil, clone, nil)
    }
}

extension BTreeNode2 {
    fileprivate convenience init(order: Int, left: BTreeNode2, element: Element, right: BTreeNode2) {
        self.init(order: order, leaf: false)
        elements.initialize(to: element)
        children!.initialize(to: left)
        (children! + 1).initialize(to: right)
        elementCount = 1
    }
}
extension BTree2 {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        mutationCount += 1
        if isKnownUniquelyReferenced(&root) {
            let (old, splinter) = root.insert(element)
            if let splinter = splinter {
                self.root = Node(order: root.order, left: root, element: splinter.separator, right: splinter.node)
            }
            return (inserted: old == nil, memberAfterInsert: old ?? element)
        }
        let (old, trunk, splinter) = root.inserting(element)
        if let old = old { return (false, old) }
        if let splinter = splinter {
            self.root = Node(order: trunk.order, left: trunk, element: splinter.separator, right: splinter.node)
        }
        else {
            self.root = trunk
        }
        return (true, element)
    }
}

extension BTree2: OrderedSet {
    public func validate() {
        _ = root.validate(level: 0)
    }
}

extension BTreeNode2 {
    func validate(level: Int, min: Element? = nil, max: Element? = nil) -> Int {
        // Check balance.
        precondition(!isTooLarge)
        precondition(level == 0 || !isTooSmall)

        if elementCount == 0 {
            precondition(children == nil)
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
        let depth = children![0].validate(level: level + 1, min: min, max: elements[0])
        for i in 1 ..< elementCount {
            let d = children![i].validate(level: level + 1, min: elements[i - 1], max: elements[i])
            precondition(depth == d)
        }
        let d = children![elementCount].validate(level: level + 1, min: elements[elementCount - 1], max: max)
        precondition(depth == d)
        return depth + 1
    }
}
