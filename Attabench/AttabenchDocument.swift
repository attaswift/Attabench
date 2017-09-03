// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit
import BenchmarkResults
import BenchmarkRunner
import BenchmarkCharts


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
        case idle
        case loading(BenchmarkProcess)
        case running(BenchmarkProcess)
        case stopping(BenchmarkProcess, restart: Bool)
        case failedBenchmark

        var process: BenchmarkProcess? {
            switch self {
            case .loading(let process): return process
            case .running(let process): return process
            case .stopping(let process, _): return process
            default: return nil
            }
        }
    }

    var results = BenchmarkResults()

    var sourceDisplayName: String {
        guard let source = results.source else { return "benchmark" }
        return FileManager().displayName(atPath: source.path)
    }

    var state: State = .idle {
        didSet {
            switch oldValue {
            case .loading(let process):
                process.stop()
            case .running(let process):
                process.stop()
            default:
                break
            }

            switch state {
            case .idle:
                self.setStatus(.immediate, "Ready")
            case .loading(_):
                self.setStatus(.immediate, "Loading \(sourceDisplayName)...")
            case .running(_):
                self.setStatus(.immediate, "Starting \(sourceDisplayName)...")
            case .stopping(_, restart: false):
                self.setStatus(.immediate, "Stopping \(sourceDisplayName)...")
            case .stopping(_, restart: true):
                self.setStatus(.immediate, "Restarting \(sourceDisplayName)...")
            case .failedBenchmark:
                self.setStatus(.immediate, "Failed")
            }
            self.refreshRunButton()
        }
    }

    func refreshRunButton() {
        switch state {
        case .idle:
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
        case .loading(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .running(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, restart: false):
            self.runButton?.isEnabled = false
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, restart: true):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .failedBenchmark:
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
            self.runButton?.isEnabled = true
        }
    }

    var tasks: ArrayVariable<TaskModel> = []
    lazy var checkedTasks = self.tasks.filter { $0.checked }
    var minimumSizeScale: IntVariable = 0
    var maximumSizeScale: IntVariable = 20
    var sizeSubdivisions: IntVariable = 8
    var iterations: IntVariable = 3
    let minDuration: DoubleVariable = 0.01
    let maxDuration: DoubleVariable = 10.0

    var largestSizeScaleAvailable: IntVariable = 32

    static func sizes(from start: Int, through end: Int, subdivisions: Int = 8) -> Set<Int> {
        let a = max(0, min(start, end))
        let b = max(0, max(start, end))
        var sizes: Set<Int> = []
        for i in subdivisions * a ... subdivisions * b {
            let size = exp2(Double(i) / Double(subdivisions))
            sizes.insert(Int(size))
        }
        return sizes
    }

    lazy var selectedSizes = minimumSizeScale.combined(maximumSizeScale, sizeSubdivisions) {
        AttabenchDocument.sizes(from: $0, through: $1, subdivisions: $2)
    }

    @IBOutlet weak var tasksTableView: NSTableView?
    @IBOutlet weak var consoleTextView: NSTextView?
    @IBOutlet weak var chartView: ChartView?
    @IBOutlet weak var runButton: NSButton?
    @IBOutlet weak var minimumSizeButton: NSPopUpButton?
    @IBOutlet weak var maximumSizeButton: NSPopUpButton?
    @IBOutlet weak var statusLabel: StatusLabel?

    var tasksTableViewController: TasksTableViewController?

    override init() {
        super.init()

        let runOptionsDidChangeSource
            = AnySource<Void>.merge(checkedTasks.changes.mapToVoid(),
                                    selectedSizes.changes.mapToVoid(),
                                    minDuration.changes.mapToVoid(),
                                    maxDuration.changes.mapToVoid(),
                                    iterations.changes.mapToVoid())
        self.glue.connector.connect(runOptionsDidChangeSource) { [unowned self] change in
            self.runOptionsDidChange()
        }
        self.glue.connector.connect(largestSizeScaleAvailable.values) { [unowned self] value in
            self.refreshSizePopUpMenus()
        }

        let sizeChangeSource
            = AnySource<Void>.merge(minimumSizeScale.changes.mapToVoid(),
                                    maximumSizeScale.changes.mapToVoid())
        self.glue.connector.connect(sizeChangeSource) { [unowned self] _ in
            self.refreshSizePopUpState()
        }
    }

    deinit {
        self.state = .idle
    }

    override class var readableTypes: [String] { return [UTI.attabench, UTI.attaresult] }
    override class var writableTypes: [String] { return [UTI.attaresult] }
    override class var autosavesInPlace: Bool { return true }

    override var windowNibName: NSNib.Name? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return NSNib.Name("AttabenchDocument")
    }

    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        consoleTextView!.textStorage!.setAttributedString(pendingLog ?? NSAttributedString())
        let tasksTVC = TasksTableViewController(self)
        self.tasksTableViewController = tasksTVC
        self.tasksTableView!.delegate = tasksTVC
        self.tasksTableView!.dataSource = tasksTVC
        self.statusLabel!.immediateStatus = _status
        self.chartView!.documentBasename = self.displayName
        refreshRunButton()
        refreshSizePopUpMenus()
        refreshSizePopUpState()
    }

    override func data(ofType typeName: String) throws -> Data {
        switch typeName {
        case UTI.attaresult:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            return try encoder.encode(results)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        switch typeName {
        case UTI.attaresult:
            let data = try Data(contentsOf: url)
            self.results = try JSONDecoder().decode(BenchmarkResults.self, from: data)
            if let url = results.source {
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
                log(.status, "Attabench document cannot be found; can't take new measurements")
                self.state = .idle
            }
        case UTI.attabench:
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            do {
                let resultsURL = url.deletingPathExtension().appendingPathExtension(attaresultExtension)
                self.fileURL = resultsURL
                self.fileType = UTI.attaresult
                if (try? resultsURL.checkResourceIsReachable()) == true {
                    let data = try Data(contentsOf: resultsURL)
                    self.results = try JSONDecoder().decode(BenchmarkResults.self, from: data)
                    results.source = url
                    self.fileModificationDate = (try? resultsURL.resourceValues(forKeys: [URLResourceKey.contentModificationDateKey]))?.contentModificationDate
                }
                else {
                    self.results = BenchmarkResults(source: url)
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

    //MARK: Logging & Status Messages

    enum LogKind {
        case standardOutput
        case standardError
        case status
    }
    var pendingLog: NSMutableAttributedString? = nil
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
        else if let pendingLog = self.pendingLog {
            if !pendingLog.string.hasSuffix("\n") {
                pendingLog.mutableString.append("\n")
            }
            pendingLog.append(atext)
        }
        else {
            pendingLog = (atext.mutableCopy() as! NSMutableAttributedString)
        }
    }

    @IBAction func clearConsole(_ sender: Any) {
        pendingLog = nil
        self.consoleTextView?.textStorage?.setAttributedString(NSAttributedString())
    }

    var _status: String = "Ready"
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

    //MARK: BenchmarkDelegate

    func benchmark(_ benchmark: BenchmarkProcess, didReceiveListOfTasks tasks: [String]) {
        guard case .loading(let process) = state, process === benchmark else { benchmark.stop(); return }
        self.tasks.value = tasks.map { TaskModel(name: $0, checked: true) }
        log(.status, "Received \(tasks.count) task names.")
    }

    func benchmark(_ benchmark: BenchmarkProcess, willMeasureTask task: String, atSize size: Int) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        setStatus(.lazy, "Measuring size \(size.sizeLabel) for task \(task)")
    }

    func benchmark(_ benchmark: BenchmarkProcess, didMeasureTask task: String, atSize size: Int, withResult time: Time) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        self.results.addMeasurement(time, forTask: task, size: size)
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
        processDidStop()
    }

    func benchmarkDidStop(_ benchmark: BenchmarkProcess) {
        guard self.state.process === benchmark else { return }
        log(.status, "Process finished.")
        processDidStop()
    }

    //MARK: Start/stop

    func processDidStop() {
        switch self.state {
        case .stopping(_, restart: true):
            self.state = .idle
            startMeasuring()
        default:
            self.state = .idle
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(AttabenchDocument.startStopAction(_:))?:
            let startLabel = "Start Running"
            let stopLabel = "Stop Running"

            guard results.source != nil else { return false }
            switch self.state {
            case .idle:
                menuItem.title = startLabel
                return true
            case .failedBenchmark:
                menuItem.title = "Load Benchmark"
                return true
            case .loading(_):
                menuItem.title = stopLabel
                return true
            case .running(_):
                menuItem.title = stopLabel
                return true
            case .stopping(_, restart: true):
                menuItem.title = stopLabel
                return true
            case .stopping(_, restart: false):
                menuItem.title = stopLabel
                return false
            }
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    @IBAction func startStopAction(_ sender: AnyObject) {
        switch state {
        case .idle:
            guard !tasks.isEmpty else { return }
            self.startMeasuring()
        case .running(let process):
            self.state = .stopping(process, restart: false)
            process.stop()
        case .loading(let process):
            self.state = .failedBenchmark
            process.stop()
        case .stopping(let process, restart: true):
            self.state = .stopping(process, restart: false)
        case .stopping(_, restart: false):
            break
        case .failedBenchmark:
            do {
                guard let url = results.source else { NSSound.beep(); return }
                log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
                self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
            }
            catch {
                log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                self.state = .failedBenchmark
            }
            break
        }
    }

    func startMeasuring() {
        guard case .idle = self.state else { return }
        guard let source = self.results.source else { return }

        let tasks = checkedTasks.value.map { $0.name.value }
        guard !tasks.isEmpty else { log(.status, "No tasks selected"); return }

        let sizes = selectedSizes.value.sorted()
        guard !sizes.isEmpty else { log(.status, "No sizes selected"); return }

        log(.status, "\nRunning \(sourceDisplayName) with \(tasks.count) tasks at sizes from \(sizes.first!.sizeLabel) to \(sizes.last!.sizeLabel).")
        let options = BenchmarkRunOptions(tasks: tasks,
                                          sizes: sizes,
                                          iterations: iterations.value,
                                          minDuration: minDuration.value,
                                          maxDuration: maxDuration.value)
        do {
            self.state = .running(try BenchmarkProcess(url: source, command: .run(options), delegate: self, on: .main))
        }
        catch {
            self.log(.status, error.localizedDescription)
            self.state = .idle
        }
    }

    func runOptionsDidChange() {
        refreshChart.now()
        switch self.state {
        case .running(let process):
            self.state = .stopping(process, restart: true)
        default:
            break
        }
    }

    //MARK: Size selection

    func refreshSizePopUpMenus() {
        if let minButton = self.minimumSizeButton {
            let minSizeMenu = NSMenu()
            for i in 0 ... largestSizeScaleAvailable.value {
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
            for i in 0 ... largestSizeScaleAvailable.value {
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
            let scale = self.minimumSizeScale.value
            let item = button.menu?.items.first(where: { $0.tag == scale })
            if button.selectedItem !== item {
                button.select(item)
            }
        }
        if let button = self.maximumSizeButton {
            let maxScale = self.maximumSizeScale.value
            let item = button.menu?.items.first(where: { $0.tag == maxScale })
            if button.selectedItem !== item {
                button.select(item)
            }
        }
    }

    @IBAction func didSelectMinimumSize(_ sender: NSMenuItem) {
        let scale = sender.tag
        self.minimumSizeScale.value = scale
        if self.maximumSizeScale.value < scale {
            self.maximumSizeScale.value = scale
        }
    }

    @IBAction func didSelectMaximumSize(_ sender: NSMenuItem) {
        let scale = sender.tag
        self.maximumSizeScale.value = scale
        if self.minimumSizeScale.value > scale {
            self.minimumSizeScale.value = scale
        }
    }

    @IBAction func increaseMinScale(_ sender: AnyObject) {
        let v = self.minimumSizeScale.value + 1
        guard v <= self.largestSizeScaleAvailable.value else { return }
        self.minimumSizeScale.value = v
        if self.maximumSizeScale.value < v {
            self.maximumSizeScale.value = v
        }
    }

    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        let v = self.minimumSizeScale.value - 1
        guard v >= 0 else { return }
        self.minimumSizeScale.value = v
    }

    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        let v = self.maximumSizeScale.value + 1
        guard v <= self.largestSizeScaleAvailable.value else { return }
        self.maximumSizeScale.value = v
    }

    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        let v = self.maximumSizeScale.value - 1
        guard v >= 0 else { return }
        self.maximumSizeScale.value = v
        if self.minimumSizeScale.value > v {
            self.minimumSizeScale.value = v
        }
    }

    //MARK: Chart rendering

    let logarithmicSizeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicSize", defaultValue: true)
    let logarithmicTimeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicTime", defaultValue: true)
    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: true)
    let highlightActiveRange: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "HighlightActiveRange", defaultValue: true)
    let randomizeInputs: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "RandomizeInputs", defaultValue: false)
    let showTitle: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "ShowTitle", defaultValue: true)

    lazy var refreshChart = RateLimiter(maxDelay: 5) { [unowned self] in self._refreshChart() }

    private func _refreshChart() {
        guard let chartView = self.chartView else { return }

        let tasks = checkedTasks.value.map { $0.name.value }

        var options = BenchmarkChart.Options()
        options.amortizedTime = self.amortized.value
        options.logarithmicSize = self.logarithmicSizeScale.value
        options.logarithmicTime = self.logarithmicTimeScale.value

        if highlightActiveRange.value {
            options.sizeRange = (1 << minimumSizeScale.value) ... (1 << maximumSizeScale.value)
        }
        options.alsoIncludeMeasuredSizes = true
        options.alsoIncludeMeasuredTimes = true

        options.centerBand = .average
        if tasks.count < 10 {
            options.topBand = .sigma(2)
            options.bottomBand = .minimum
        }

        chartView.chart = BenchmarkChart(title: "",
                                         results: results,
                                         tasks: tasks,
                                         options: options)
    }

}

