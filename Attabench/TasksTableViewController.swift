// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit

extension NSUserInterfaceItemIdentifier {
    static let taskColumn = NSUserInterfaceItemIdentifier(rawValue: "TaskColumn")
}

class TasksTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    unowned let document: AttabenchDocument

    init(_ document: AttabenchDocument) {
        self.document = document
        super.init()
        self.glue.connector.connect(document.tasks.changes) { [unowned self] change in
            self.apply(change)
        }
    }

    func apply(_ change: ArrayChange<TaskModel>) {
        guard let table = document.tasksTableView else { return }
        let batch = change.separated()
        table.beginUpdates()
        table.removeRows(at: batch.deleted, withAnimation: [.effectFade, .slideUp])
        table.insertRows(at: batch.inserted, withAnimation: [.effectFade, .slideDown])
        for (from, to) in batch.moved {
            table.moveRow(at: from, to: to)
        }
        table.endUpdates()
        print("Removed: \(batch.deleted), inserted: \(batch.inserted), moved: \(batch.moved)")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return document.tasks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, id == .taskColumn else { return nil }
        let task = document.tasks[row]
        let cell = tableView.makeView(withIdentifier: .taskColumn, owner: nil) as! TaskCellView
        cell.task = task
        cell.document = document
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
