// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit

class TaskCellView: NSTableCellView {
    @IBOutlet weak var checkbox: NSButton?
    weak var document: AttabenchDocument?

    override func awakeFromNib() {
        self.appearance = NSAppearance(named: .vibrantLight)
    }

    private var taskConnections = Connector()
    var task: TaskModel? = nil {
        didSet {
            taskConnections.disconnect()
            if let task = task {
                taskConnections.connect(task.name.values) { [unowned self] value in
                    self.textField?.stringValue = value
                }
                taskConnections.connect(task.checked.values) { [unowned self] value in
                    guard let checkbox = self.checkbox else { return }
                    let v: NSControl.StateValue = (value ? .on : .off)
                    if checkbox.state != v {
                        checkbox.state = v
                    }
                }
            }
        }
    }

    @IBAction func checkboxAction(_ sender: NSButton) {
        guard let document = document else { return }
        guard let tableView = document.tasksTableView else { return }
        let row = tableView.row(for: self)
        guard row != -1 else { return }

        let clearOthers = NSEvent.modifierFlags.contains(.shift)

        let selectedRows = tableView.selectedRowIndexes.contains(row)
            ? tableView.selectedRowIndexes
            : IndexSet(integer: row)

        let value = (sender.state == .on)

        let tasks = selectedRows.map { document.tasks[$0] }
        let clearedTasks = clearOthers
            ? (IndexSet(integersIn: 0 ..< tableView.numberOfRows)
                .subtracting(selectedRows)
                .map { document.tasks[$0] })
            : []

        tasks.forEach { $0.checked.apply(.beginTransaction) }
        clearedTasks.forEach { $0.checked.apply(.beginTransaction) }
        tasks.forEach { $0.checked.value = value }
        clearedTasks.forEach { $0.checked.value = false }
        tasks.forEach { $0.checked.apply(.endTransaction) }
        clearedTasks.forEach { $0.checked.apply(.endTransaction) }
    }
}
