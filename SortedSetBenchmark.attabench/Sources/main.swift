// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Benchmarking

let benchmark = Benchmark<([Int], [Int])>(title: "SortedSet")
benchmark.descriptiveTitle = "SortedSet operations"
benchmark.descriptiveAmortizedTitle = "SortedSet operations (amortized)"

benchmark.addTask(title: "SortedArray.insert") { input, lookups in
    return { timer in
        var set = SortedArray<Int>()
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "SortedArray.contains") { input, lookups in
    let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "SortedArray.contains2") { input, lookups in
    let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
    return { timer in
        for element in lookups {
            guard set.contains2(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "SortedArray.contains3") { input, lookups in
    let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
    return { timer in
        for element in lookups {
            guard set.contains3(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "SortedArray.forEach") { input, lookups in
    let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "SortedArray.for-in") { input, lookups in
    let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "SortedArray.sharedInsert") { input, lookups in
    return { timer in
        var set = SortedArray<Int>()
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "OrderedSet.insert") { input, lookups in
    return { timer in
        var set = OrderedSet<Int>()
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "OrderedSet.contains") { input, lookups in
    var set = OrderedSet<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "OrderedSet.contains2") { input, lookups in
    var set = OrderedSet<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains2(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "OrderedSet.forEach") { input, lookups in
    var set = OrderedSet<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "OrderedSet.for-in") { input, lookups in
    var set = OrderedSet<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "OrderedSet.sharedInsert") { input, lookups in
    return { timer in
        var set = OrderedSet<Int>()
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "RedBlackTree.insert") { input, lookups in
    return { timer in
        var set = RedBlackTree<Int>()
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "RedBlackTree.contains") { input, lookups in
    var set = RedBlackTree<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "RedBlackTree.forEach") { input, lookups in
    var set = RedBlackTree<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree.for-in") { input, lookups in
    var set = RedBlackTree<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree.sharedInsert") { input, lookups in
    return { timer in
        var set = RedBlackTree<Int>()
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "RedBlackTree2.insert") { input, lookups in
    return { timer in
        var set = RedBlackTree2<Int>()
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "RedBlackTree2.contains") { input, lookups in
    var set = RedBlackTree2<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "RedBlackTree2.forEach") { input, lookups in
    var set = RedBlackTree2<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree2.for-in") { input, lookups in
    var set = RedBlackTree2<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        var index = set.startIndex
        while index != set.endIndex {
            let element = set[index]
            guard element == i else { fatalError() }
            i += 1
            set.formIndex(after: &index)
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree2.for-in2") { input, lookups in
    var set = RedBlackTree2<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree2.for-in3") { input, lookups in
    var set = RedBlackTree2b<Int>()
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "RedBlackTree2.sharedInsert") { input, lookups in
    return { timer in
        var set = RedBlackTree2<Int>()
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "BTree.insert") { input, lookups in
    return { timer in
        var set = BTree<Int>(order: 1024)
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "BTree.contains") { input, lookups in
    var set = BTree<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "BTree.forEach") { input, lookups in
    var set = BTree<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree.for-in") { input, lookups in
    var set = BTree<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree.sharedInsert") { input, lookups in
    return { timer in
        var set = BTree<Int>(order: 1024)
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}


benchmark.addTask(title: "BTree2.insert") { input, lookups in
    return { timer in
        var set = BTree2<Int>(order: 1024)
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "BTree2.contains") { input, lookups in
    var set = BTree2<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "BTree2.forEach") { input, lookups in
    var set = BTree2<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree2.for-in") { input, lookups in
    var set = BTree2<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError("\(i) vs \(input.count)") }
    }
}

benchmark.addTask(title: "BTree2.sharedInsert") { input, lookups in
    return { timer in
        var set = BTree2<Int>(order: 1024)
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "BTree3.insert") { input, lookups in
    return { timer in
        var set = BTree3<Int>(order: 1024)
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "BTree3.contains") { input, lookups in
    var set = BTree3<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "BTree3.forEach") { input, lookups in
    var set = BTree3<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree3.for-in") { input, lookups in
    var set = BTree3<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree3.sharedInsert") { input, lookups in
    return { timer in
        var set = BTree3<Int>(order: 1024)
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

#if false
benchmark.addTask(title: "BTree4.insert") { input, lookups in
    return { timer in
        var set = BTree4<Int>(order: 1024)
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "BTree4.contains") { input, lookups in
    var set = BTree4<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "BTree4.forEach") { input, lookups in
    var set = BTree4<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree4.for-in") { input, lookups in
    var set = BTree4<Int>(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "BTree4.sharedInsert") { input, lookups in
    return { timer in
        var set = BTree4<Int>(order: 1024)
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}

benchmark.addTask(title: "IntBTree3.insert") { input, lookups in
    return { timer in
        var set = IntBTree3(order: 1024)
        timer.measure {
            for value in input {
                set.insert(value)
            }
        }
    }
}

benchmark.addTask(title: "IntBTree3.contains") { input, lookups in
    var set = IntBTree3(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        for element in lookups {
            guard set.contains(element) else { fatalError() }
        }
    }
}

benchmark.addTask(title: "IntBTree3.forEach") { input, lookups in
    var set = IntBTree3(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        set.forEach { element in
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "IntBTree3.for-in") { input, lookups in
    var set = IntBTree3(order: 1024)
    for value in input {
        set.insert(value)
    }
    return { timer in
        var i = 0
        for element in set {
            guard element == i else { fatalError() }
            i += 1
        }
        guard i == input.count else { fatalError() }
    }
}

benchmark.addTask(title: "IntBTree3.sharedInsert") { input, lookups in
    return { timer in
        var set = IntBTree3(order: 1024)
        timer.measure {
            var clone = set
            for value in input {
                set.insert(value)
                clone = set
            }
            noop(clone)
        }
    }
}
#endif

benchmark.addTask(title: "Array.sort") { input, lookups in
    return { timer in
        noop(input.sorted())
    }
}

benchmark.start()

