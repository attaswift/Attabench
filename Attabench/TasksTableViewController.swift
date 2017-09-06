// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit
import BenchmarkModel

extension NSUserInterfaceItemIdentifier {
    static let taskColumn = NSUserInterfaceItemIdentifier(rawValue: "TaskColumn")
}

class TasksTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    let contents: AnyObservableArray<Task>
    let tableView: NSTableView

    init(tableView: NSTableView, contents: AnyObservableArray<Task>) {
        self.tableView = tableView
        self.contents = contents
        super.init()
        self.glue.connector.connect(contents.changes) { [unowned self] change in
            self.apply(change)
        }
    }

    func apply(_ change: ArrayChange<Task>) {
        let batch = change.separated()
        tableView.beginUpdates()
        tableView.removeRows(at: batch.deleted, withAnimation: [.effectFade, .slideUp])
        tableView.insertRows(at: batch.inserted, withAnimation: [.effectFade, .slideDown])
        for (from, to) in batch.moved {
            tableView.moveRow(at: from, to: to)
        }
        tableView.endUpdates()
        //print("Removed: \(batch.deleted), inserted: \(batch.inserted), moved: \(batch.moved)")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return contents.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, id == .taskColumn else { return nil }
        let task = contents[row]
        let cell = tableView.makeView(withIdentifier: .taskColumn, owner: nil) as! TaskCellView
        cell.task = task
        cell.context = self
        return cell
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {

        return proposedSelectionIndexes
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelect tableColumn: NSTableColumn?) -> Bool {
        return false
    }
}
