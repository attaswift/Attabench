// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit
import BenchmarkResults
import BenchmarkRunner
import BenchmarkCharts
import BenchmarkIPC

enum UTI {
    static let png = "public.png"
    static let pdf = "com.adobe.pdf"
    static let attabench = "org.attaswift.attabench-benchmark"
    static let attaresult = "org.attaswift.attabench-results"
}

let attaresultExtension = NSWorkspace.shared.preferredFilenameExtension(forType: UTI.attaresult)!

enum ConsoleAttributes {
    private static let indentedParagraphStyle: NSParagraphStyle = {
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        return style
    }()
    static let standardOutput: [NSAttributedStringKey: Any] = [
        .font: NSFont(name: "Menlo-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(white: 0.3, alpha: 1),
        .paragraphStyle: indentedParagraphStyle
    ]
    static let standardError: [NSAttributedStringKey: Any] = [
        .font: NSFont(name: "Menlo-Bold", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor(white: 0.3, alpha: 1),
        .paragraphStyle: indentedParagraphStyle
    ]
    static let statusMessage: [NSAttributedStringKey: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.black,
        .paragraphStyle: NSParagraphStyle.default
    ]
    static let errorMessage: [NSAttributedStringKey: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.black,
        .paragraphStyle: NSParagraphStyle.default
    ]
}




class AttabenchDocument: NSDocument, BenchmarkDelegate {

    enum State {
        case noBenchmark
        case idle
        case loading(BenchmarkProcess)
        case waiting // We should be running, but parameters aren't ready yet
        case running(BenchmarkProcess)
        case stopping(BenchmarkProcess, then: Followup)
        case failedBenchmark

        enum Followup {
            case idle
            case reload
            case restart
        }

        var process: BenchmarkProcess? {
            switch self {
            case .loading(let process): return process
            case .running(let process): return process
            case .stopping(let process, _): return process
            default: return nil
            }
        }
    }

    var state: State = .idle {
        didSet { stateDidChange(from: oldValue, to: state) }
    }

    @IBOutlet weak var runButton: NSButton?
    @IBOutlet weak var minimumSizeButton: NSPopUpButton?
    @IBOutlet weak var maximumSizeButton: NSPopUpButton?
    @IBOutlet weak var rootSplitView: NSSplitView?

    @IBOutlet weak var leftPane: NSVisualEffectView?
    @IBOutlet weak var leftVerticalSplitView: NSSplitView?
    @IBOutlet weak var leftBar: ColoredView?
    @IBOutlet weak var batchCheckbox: NSButtonCell!
    @IBOutlet weak var taskFilterTextField: NSSearchField!
    @IBOutlet weak var showRunOptionsButton: NSButton?
    @IBOutlet weak var runOptionsPane: ColoredView?
    @IBOutlet var runOptionsViewController: RunOptionsViewController?
    @IBOutlet weak var tasksTableView: NSTableView?

    @IBOutlet weak var middleSplitView: NSSplitView?
    @IBOutlet weak var chartView: ChartView?
    @IBOutlet weak var middleBar: ColoredView?
    @IBOutlet weak var showLeftPaneButton: NSButton?
    @IBOutlet weak var showConsoleButton: NSButton?
    @IBOutlet weak var statusLabel: StatusLabel?
    @IBOutlet weak var consolePane: NSView?
    @IBOutlet weak var consoleTextView: NSTextView?

    var _log: NSMutableAttributedString? = nil
    var _status: String = "Ready"

    @objc dynamic var model = Attaresult() {
        didSet {
            self.tasks.value = model.taskNames.map { TaskModel(name: $0, checked: true) }
            self.runOptionsViewController?.model = model
        }
    }
    var tasks: ArrayVariable<TaskModel> = []
    lazy var selectedSizes: AnyObservableValue<Set<Int>>
        = self.observable(for: \.model.minimumSizeScale).combined(
            self.observable(for: \.model.maximumSizeScale),
            self.observable(for: \.model.sizeSubdivisions)) { [unowned self] _, _, _ in
                self.model.selectedSizes
    }

    let taskFilterString: OptionalVariable<String> = nil
    lazy var visibleTasks: AnyObservableArray<TaskModel>
        = self.tasks.filter { [taskFilterString] model -> AnyObservableValue<Bool> in
            let name = model.name.lowercased()
            return taskFilterString.map { pattern -> Bool in
                guard let p = pattern?.lowercased() else { return true }
                return name.contains(p)
            }
    }

    lazy var checkedTasks = self.visibleTasks.filter { $0.checked }
    lazy var tasksToRun = self.visibleTasks.filter { $0.checked && $0.isRunnable }

    lazy var batchCheckboxState: AnyObservableValue<NSControl.StateValue>
        = visibleTasks.observableCount.combined(checkedTasks.observableCount) { c1, c2 in
            if c1 == c2 { return .on }
            if c2 == 0 { return .off }
            return .mixed
    }

    let logarithmicSizeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicSize", defaultValue: true)
    let logarithmicTimeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicTime", defaultValue: true)
    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: true)
    let highlightActiveRange: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "HighlightActiveRange", defaultValue: true)
    let randomizeInputs: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "RandomizeInputs", defaultValue: false)
    let showTitle: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "ShowTitle", defaultValue: true)

    lazy var refreshChart = RateLimiter(maxDelay: 5) { [unowned self] in self._refreshChart() }

    var tasksTableViewController: TasksTableViewController?

    override init() {
        super.init()

        let runOptionsDidChangeSource
            = AnySource<Void>.merge(tasksToRun.changes.mapToVoid(),
                                    selectedSizes.changes.mapToVoid(),
                                    self.observable(for: \.model.iterations).changes.mapToVoid(),
                                    self.observable(for: \.model.minimumDuration).changes.mapToVoid(),
                                    self.observable(for: \.model.maximumDuration).changes.mapToVoid())
        self.glue.connector.connect(runOptionsDidChangeSource) { [unowned self] change in
            self.updateChangeCount(.changeDone)
            self.runOptionsDidChange()
        }

        let chartOptionsDidChangeSource
            = AnySource<Void>.merge(checkedTasks.changes.mapToVoid(),
                                    selectedSizes.changes.mapToVoid())
        self.glue.connector.connect(chartOptionsDidChangeSource) { [unowned self] change in
            self.refreshChart.now()
        }

        let sizeChangeSource
            = AnySource<Void>.merge(self.observable(for: \.model.minimumSizeScale).changes.mapToVoid(),
                                    self.observable(for: \.model.maximumSizeScale).changes.mapToVoid())
        self.glue.connector.connect(sizeChangeSource) { [unowned self] _ in
            self.refreshSizePopUpState()
        }
        self.glue.connector.connect(batchCheckboxState.futureValues) { [unowned self] state in
            self.batchCheckbox?.state = state
        }
        self.glue.connector.connect(taskFilterString.futureValues) { [unowned self] filter in
            guard let field = self.taskFilterTextField else { return }
            if field.stringValue != filter {
                self.taskFilterTextField.stringValue = filter ?? ""
            }
        }
    }

    deinit {
        self.state = .idle
    }

    override var windowNibName: NSNib.Name? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return NSNib.Name("AttabenchDocument")
    }

    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        consoleTextView!.textStorage!.setAttributedString(_log ?? NSAttributedString())
        let tasksTVC = TasksTableViewController(tableView: tasksTableView!, contents: visibleTasks)
        self.tasksTableViewController = tasksTVC
        self.tasksTableView!.delegate = tasksTVC
        self.tasksTableView!.dataSource = tasksTVC
        self.statusLabel!.immediateStatus = _status
        self.chartView!.documentBasename = self.displayName
        self.batchCheckbox.state = self.batchCheckboxState.value

        self.runOptionsViewController!.model = model
        let runOptionsView = self.runOptionsViewController!.view
        runOptionsView.frame = self.runOptionsPane!.bounds
        self.runOptionsPane!.addSubview(runOptionsView)

        refreshRunButton()
        refreshSizePopUpMenus()
        refreshSizePopUpState()
        refreshChart.now()
    }

    func stateDidChange(from old: State, to new: State) {
        switch old {
        case .loading(let process):
            process.stop()
        case .running(let process):
            process.stop()
        default:
            break
        }

        switch new {
        case .noBenchmark:
            self.setStatus(.immediate, "Attabench document cannot be found; can't take new measurements")
        case .idle:
            self.setStatus(.immediate, "Ready")
        case .loading(_):
            self.setStatus(.immediate, "Loading \(model.benchmarkDisplayName)...")
        case .waiting:
            self.setStatus(.immediate, "No executable tasks selected, pausing")
        case .running(_):
            self.setStatus(.immediate, "Starting \(model.benchmarkDisplayName)...")
        case .stopping(_, then: .restart):
            self.setStatus(.immediate, "Restarting \(model.benchmarkDisplayName)...")
        case .stopping(_, then: _):
            self.setStatus(.immediate, "Stopping \(model.benchmarkDisplayName)...")
        case .failedBenchmark:
            self.setStatus(.immediate, "Failed")
        }
        self.refreshRunButton()
    }

    func refreshRunButton() {
        switch state {
        case .noBenchmark:
            self.runButton?.isEnabled = false
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
        case .idle:
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
        case .loading(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .waiting:
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .running(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: .restart):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: _):
            self.runButton?.isEnabled = false
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .failedBenchmark:
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
            self.runButton?.isEnabled = true
        }
    }
}

extension AttabenchDocument {
    override class var readableTypes: [String] { return [UTI.attabench, UTI.attaresult] }
    override class var writableTypes: [String] { return [UTI.attaresult] }
    override class var autosavesInPlace: Bool { return true }

    override func data(ofType typeName: String) throws -> Data {
        switch typeName {
        case UTI.attaresult:
            model.taskNames = self.tasks.value.map { $0.name }
            return try JSONEncoder().encode(model)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        switch typeName {
        case UTI.attaresult:
            let data = try Data(contentsOf: url)
            self.model = try JSONDecoder().decode(Attaresult.self, from: data)
            if let url = model.benchmarkURL {
                do {
                    log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
                    self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
                }
                catch {
                    log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                    self.state = .failedBenchmark
                }
            }
            else {
                self.state = .noBenchmark
            }
        case UTI.attabench:
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            do {
                let resultsURL = url.deletingPathExtension().appendingPathExtension(attaresultExtension)
                self.fileURL = resultsURL
                self.fileType = UTI.attaresult
                if (try? resultsURL.checkResourceIsReachable()) == true {
                    let data = try Data(contentsOf: resultsURL)
                    self.model = try JSONDecoder().decode(Attaresult.self, from: data)
                    model.benchmarkURL = url
                    self.fileModificationDate = (try? resultsURL.resourceValues(forKeys: [URLResourceKey.contentModificationDateKey]))?.contentModificationDate
                }
                else {
                    self.model = Attaresult()
                    self.model.benchmarkURL = url
                    self.isDraft = true
                }
                self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
            }
            catch {
                log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                self.state = .failedBenchmark
                throw error
            }
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
}

extension AttabenchDocument {
    //MARK: Logging & Status Messages

    enum LogKind {
        case standardOutput
        case standardError
        case status
    }
    func log(_ kind: LogKind, _ text: String) {
        let attributes: [NSAttributedStringKey: Any]
        switch kind {
        case .standardOutput: attributes = ConsoleAttributes.standardOutput
        case .standardError: attributes = ConsoleAttributes.standardError
        case .status: attributes = ConsoleAttributes.statusMessage
        }
        let atext = NSAttributedString(string: text, attributes: attributes)
        if let textView = self.consoleTextView {
            if !textView.textStorage!.string.hasSuffix("\n") {
                textView.textStorage!.mutableString.append("\n")
            }
            textView.textStorage!.append(atext)
            textView.scrollToEndOfDocument(nil)
        }
        else if let pendingLog = self._log {
            if !pendingLog.string.hasSuffix("\n") {
                pendingLog.mutableString.append("\n")
            }
            pendingLog.append(atext)
        }
        else {
            _log = (atext.mutableCopy() as! NSMutableAttributedString)
        }
    }

    @IBAction func clearConsole(_ sender: Any) {
        _log = nil
        self.consoleTextView?.textStorage?.setAttributedString(NSAttributedString())
    }

    enum StatusUpdate {
        case immediate
        case lazy
    }
    func setStatus(_ kind: StatusUpdate, _ text: String) {
        self._status = text
        switch kind {
        case .immediate: self.statusLabel?.immediateStatus = text
        case .lazy: self.statusLabel?.lazyStatus = text
        }
    }
}

extension AttabenchDocument {
    //MARK: BenchmarkDelegate

    func benchmark(_ benchmark: BenchmarkProcess, didReceiveListOfTasks taskNames: [String]) {
        guard case .loading(let process) = state, process === benchmark else { benchmark.stop(); return }
        let fresh = Set(taskNames)
        let stale = Set(self.tasks.value.map { $0.name })
        let newTasks = fresh.subtracting(stale)
        let missingTasks = stale.subtracting(fresh)

        self.tasks.append(contentsOf: taskNames
            .filter { newTasks.contains($0) }
            .map { TaskModel(name: $0, checked: true) })

        for task in tasks.value {
            task.isRunnable.value = fresh.contains(task.name)
        }

        log(.status, "Received \(tasks.count) task names (\(newTasks.count) new, \(missingTasks.count) missing).")
    }

    func benchmark(_ benchmark: BenchmarkProcess, willMeasureTask task: String, atSize size: Int) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        setStatus(.lazy, "Measuring size \(size.sizeLabel) for task \(task)")
    }

    func benchmark(_ benchmark: BenchmarkProcess, didMeasureTask task: String, atSize size: Int, withResult time: Time) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        model.addMeasurement(time, forTask: task, size: size)
        self.updateChangeCount(.changeDone)
        self.refreshChart.later()
    }

    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardOutput line: String) {
        guard self.state.process === benchmark else { benchmark.stop(); return }
        log(.standardOutput, line)
    }

    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardError line: String) {
        guard self.state.process === benchmark else { benchmark.stop(); return }
        log(.standardError, line)
    }

    func benchmark(_ benchmark: BenchmarkProcess, didFailWithError error: String) {
        guard self.state.process === benchmark else { return }
        log(.status, error)
        processDidStop(success: false)
    }

    func benchmarkDidStop(_ benchmark: BenchmarkProcess) {
        guard self.state.process === benchmark else { return }
        log(.status, "Process finished.")
        processDidStop(success: true)
    }
}

extension AttabenchDocument {
    //MARK: Start/stop

    func processDidStop(success: Bool) {
        refreshChart.nowIfNeeded()
        switch self.state {
        case .loading(_):
            self.state = success ? .idle : .failedBenchmark
        case .stopping(_, then: .idle):
            self.state = .idle
        case .stopping(_, then: .restart):
            self.state = .idle
            startMeasuring()
        case .stopping(_, then: .reload):
            _reload()
        default:
            self.state = .idle
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(AttabenchDocument.startStopAction(_:))?:
            let startLabel = "Start Running"
            let stopLabel = "Stop Running"

            guard model.benchmarkURL != nil else { return false }
            switch self.state {
            case .noBenchmark:
                menuItem.title = startLabel
                return false
            case .idle:
                menuItem.title = startLabel
                return true
            case .failedBenchmark:
                menuItem.title = startLabel
                return false
            case .loading(_):
                menuItem.title = stopLabel
                return true
            case .waiting:
                menuItem.title = stopLabel
                return true
            case .running(_):
                menuItem.title = stopLabel
                return true
            case .stopping(_, then: .restart):
                menuItem.title = stopLabel
                return true
            case .stopping(_, then: _):
                menuItem.title = stopLabel
                return false
            }
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    @IBAction func chooseBenchmark(_ sender: AnyObject) {
        guard let window = self.windowControllers.first?.window else { return }
        let openPanel = NSOpenPanel()
        openPanel.message = "This result file has no associated Attabench document. To add more measurements, you need to select a benchmark file."
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = [UTI.attabench]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            guard let url = openPanel.urls.first else { return }
            self.model.benchmarkURL = url
            self._reload()
        }
    }

    func _reload() {
        do {
            guard let url = model.benchmarkURL else { chooseBenchmark(self); return }
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
        }
        catch {
            log(.status, "Failed to load benchmark: \(error.localizedDescription)")
            self.state = .failedBenchmark
        }
    }

    @IBAction func reloadAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark:
            chooseBenchmark(sender)
        case .idle, .failedBenchmark, .waiting:
            _reload()
        case .running(let process):
            self.state = .stopping(process, then: .reload)
            process.stop()
        case .loading(let process):
            self.state = .stopping(process, then: .reload)
            process.stop()
        case .stopping(let process, then: _):
            self.state = .stopping(process, then: .reload)
        }
    }

    @IBAction func startStopAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark, .failedBenchmark:
            NSSound.beep()
        case .idle:
            guard !tasks.isEmpty else { return }
            self.startMeasuring()
        case .waiting:
            self.state = .idle
        case .running(let process):
            self.state = .stopping(process, then: .idle)
            process.stop()
        case .loading(let process):
            self.state = .failedBenchmark
            process.stop()
        case .stopping(let process, then: .restart):
            self.state = .stopping(process, then: .idle)
        case .stopping(let process, then: .reload):
            self.state = .stopping(process, then: .idle)
        case .stopping(let process, then: .idle):
            self.state = .stopping(process, then: .restart)
        }
    }

    func startMeasuring() {
        guard let source = self.model.benchmarkURL else { log(.status, "Can't start measuring"); return }
        switch self.state {
        case .waiting, .idle: break
        default: return
        }
        let tasks = tasksToRun.value.map { $0.name }
        let sizes = model.selectedSizes.sorted()
        guard !tasks.isEmpty, !sizes.isEmpty else {
            self.state = .waiting
            return
        }

        log(.status, "\nRunning \(model.benchmarkDisplayName) with \(tasks.count) tasks at sizes from \(sizes.first!.sizeLabel) to \(sizes.last!.sizeLabel).")
        let options = RunOptions(tasks: tasks,
                                 sizes: sizes,
                                 iterations: model.iterations,
                                 minimumDuration: model.minimumDuration,
                                 maximumDuration: model.maximumDuration)
        do {
            self.state = .running(try BenchmarkProcess(url: source, command: .run(options), delegate: self, on: .main))
        }
        catch {
            self.log(.status, error.localizedDescription)
            self.state = .idle
        }
    }

    func runOptionsDidChange() {
        switch self.state {
        case .waiting:
            startMeasuring()
        case .running(let process):
            self.state = .stopping(process, then: .restart)
        default:
            break
        }
    }
}

extension AttabenchDocument {
    //MARK: Size selection

    func refreshSizePopUpMenus() {
        if let minButton = self.minimumSizeButton {
            let minSizeMenu = NSMenu()
            for i in 0 ... model.largestPossibleSizeScale {
                let item = NSMenuItem(title: "\((1 << i).sizeLabel)≤",
                    action: #selector(AttabenchDocument.didSelectMinimumSize(_:)),
                    keyEquivalent: "")
                item.tag = i
                minSizeMenu.addItem(item)
            }
            minButton.menu = minSizeMenu
        }

        if let maxButton = self.maximumSizeButton {
            let maxSizeMenu = NSMenu()
            for i in 0 ... model.largestPossibleSizeScale {
                let item = NSMenuItem(title: "≤\((1 << i).sizeLabel)",
                    action: #selector(AttabenchDocument.didSelectMaximumSize(_:)),
                    keyEquivalent: "")
                item.tag = i
                maxSizeMenu.addItem(item)
            }
            maxButton.menu = maxSizeMenu
        }
    }

    func refreshSizePopUpState() {
        if let button = self.minimumSizeButton {
            let scale = model.minimumSizeScale
            let item = button.menu?.items.first(where: { $0.tag == scale })
            if button.selectedItem !== item {
                button.select(item)
            }
        }
        if let button = self.maximumSizeButton {
            let maxScale = model.maximumSizeScale
            let item = button.menu?.items.first(where: { $0.tag == maxScale })
            if button.selectedItem !== item {
                button.select(item)
            }
        }
    }

    @IBAction func didSelectMinimumSize(_ sender: NSMenuItem) {
        let scale = sender.tag
        model.minimumSizeScale = scale
        if model.maximumSizeScale < scale {
            model.maximumSizeScale = scale
        }
    }

    @IBAction func didSelectMaximumSize(_ sender: NSMenuItem) {
        let scale = sender.tag
        model.maximumSizeScale = scale
        if model.minimumSizeScale > scale {
            model.minimumSizeScale = scale
        }
    }

    @IBAction func increaseMinScale(_ sender: AnyObject) {
        let v = model.minimumSizeScale + 1
        guard v <= model.largestPossibleSizeScale else { return }
        model.minimumSizeScale = v
        if model.maximumSizeScale < v {
            model.maximumSizeScale = v
        }
    }

    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        let v = model.minimumSizeScale - 1
        guard v >= 0 else { return }
        model.minimumSizeScale = v
    }

    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        let v = model.maximumSizeScale + 1
        guard v <= model.largestPossibleSizeScale else { return }
        model.maximumSizeScale = v
    }

    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        let v = model.maximumSizeScale - 1
        guard v >= 0 else { return }
        model.maximumSizeScale = v
        if model.minimumSizeScale > v {
            model.minimumSizeScale = v
        }
    }
}

extension AttabenchDocument {
    //MARK: Chart rendering

    private func _refreshChart() {
        guard let chartView = self.chartView else { return }

        let tasks = checkedTasks.value.map { $0.name }

        var options = BenchmarkChart.Options()
        options.amortizedTime = self.amortized.value
        options.logarithmicSize = self.logarithmicSizeScale.value
        options.logarithmicTime = self.logarithmicTimeScale.value

        if highlightActiveRange.value {
            options.sizeRange = model.selectedSizeRange
        }
        options.alsoIncludeMeasuredSizes = true
        options.alsoIncludeMeasuredTimes = true

        options.centerBand = .average
        if tasks.count < 100 {
            options.topBand = .sigma(2)
            options.bottomBand = .minimum
        }

        chartView.chart = BenchmarkChart(title: "",
                                         results: model.results,
                                         tasks: tasks,
                                         options: options)
    }
}

extension AttabenchDocument: NSSplitViewDelegate {
    @IBAction func shoHideLeftPane(_ sender: Any) {
        guard let pane = self.leftPane else { return }
        pane.isHidden = !pane.isHidden
    }

    @IBAction func showHideRunOptions(_ sender: NSButton) {
        guard let pane = self.runOptionsPane else { return }
        pane.isHidden = !pane.isHidden
    }
    @IBAction func showHideConsole(_ sender: NSButton) {
        guard let pane = self.consolePane else { return }
        pane.isHidden = !pane.isHidden
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if subview === self.leftPane { return true }
        if subview === self.runOptionsPane { return true }
        if subview === self.consolePane { return true }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        if splitView === rootSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.leftPane!) ? .off : .on
            if showLeftPaneButton!.state != state {
                showLeftPaneButton!.state = state
            }
        }
        else if splitView === leftVerticalSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.runOptionsPane!) ? .off : .on
            if showRunOptionsButton!.state != state {
                showRunOptionsButton!.state = state
            }
        }
        else if splitView === middleSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.consolePane!) ? .off : .on
            if showConsoleButton!.state != state {
                showConsoleButton!.state = state
            }
        }
    }
}

extension AttabenchDocument {
    @IBAction func batchCheckboxAction(_ sender: NSButton) {
        let v = (sender.state != .off)
        self.visibleTasks.value.forEach { $0.checked.apply(.beginTransaction) }
        self.visibleTasks.value.forEach { $0.checked.value = v }
        self.visibleTasks.value.forEach { $0.checked.apply(.endTransaction) }
    }
}

extension AttabenchDocument: NSTextFieldDelegate {
    override func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject === self.taskFilterTextField else {
            super.controlTextDidChange(obj)
            return
        }
        let v = self.taskFilterTextField!.stringValue
        self.taskFilterString.value = v.isEmpty ? nil : v
    }
}

extension AttabenchDocument {
    //MARK: State restoration
    enum RestorationKey: String {
        case checkedTasks = "checkedTasks"
        case taskFilterString = "taskFilterString"
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(self.taskFilterString.value, forKey: RestorationKey.taskFilterString.rawValue)
        coder.encode(self.tasks.value.filter { $0.checked.value }.map { $0.name } as NSArray,
                     forKey: RestorationKey.checkedTasks.rawValue)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        self.taskFilterString.value = coder.decodeObject(forKey: RestorationKey.taskFilterString.rawValue) as? String

        if let taskNames = coder.decodeObject(forKey: RestorationKey.checkedTasks.rawValue) as? [String] {
            let names = Set(taskNames)
            for task in tasks.value {
                task.checked.value = names.contains(task.name)
            }
        }
    }
}
