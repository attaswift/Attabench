// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit
import BenchmarkModel
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

    var state: State = .noBenchmark {
        didSet { stateDidChange(from: oldValue, to: state) }
    }
    var activity: NSObjectProtocol? // Preventing system sleep

    let model = Variable<Attaresult>(Attaresult())
    var m: Attaresult {
        get { return model.value }
        set { model.value = newValue }
    }

    let taskFilterString: OptionalVariable<String> = nil
    lazy var taskFilter: AnyObservableValue<TaskFilter>
        = self.taskFilterString.map { TaskFilter($0) }

    lazy var visibleTasks: AnyObservableArray<Task>
        = self.model.map{$0.tasks}.filter { [taskFilter] task in taskFilter.map { $0.test(task) } }

    struct TaskFilter {
        typealias Pattern = (string: String, isNegative: Bool)
        let patterns: [[Pattern]]

        init(_ pattern: String?) {
            self.patterns = (pattern ?? "")
                .lowercased()
                .components(separatedBy: ",")
                .map { (pattern: String) -> [Pattern] in
                    pattern
                        .components(separatedBy: .whitespacesAndNewlines)
                        .map { (word: String) -> Pattern in
                            word.hasPrefix("!")
                                ? (string: String(word.dropFirst()), isNegative: true)
                                : (string: word, isNegative: false) }
                        .filter { (pattern: Pattern) -> Bool in !pattern.string.isEmpty }
            }
                .filter { !$0.isEmpty }
        }

        func test(_ task: Task) -> Bool {
            guard !patterns.isEmpty else { return true }
            let name = task.name.lowercased()
            return patterns.contains { (conjunctive: [Pattern]) -> Bool in
                !conjunctive.contains { (pattern: Pattern) -> Bool in
                    name.contains(pattern.string) == pattern.isNegative
                }
            }
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

    let theme = Variable<BenchmarkTheme>(BenchmarkTheme.Predefined.screen)

    var _log: NSMutableAttributedString? = nil
    var _status: String = "Ready"

    lazy var refreshChart = RateLimiter(maxDelay: 5, async: true) { [unowned self] in self._refreshChart() }
    var tasksTableViewController: GlueKitTableViewController<Task, TaskCellView>?

    var pendingResults: [(task: String, size: Int, time: Time)] = []
    lazy var processPendingResults = RateLimiter(maxDelay: 0.2) { [unowned self] in
        for (task, size, time) in self.pendingResults {
            self.m.addMeasurement(time, forTask: task, size: size)
        }
        self.pendingResults = []
        self.updateChangeCount(.changeDone)
        self.refreshChart.later()
    }

    @IBOutlet weak var runButton: NSButton?
    @IBOutlet weak var minimumSizeButton: NSPopUpButton?
    @IBOutlet weak var maximumSizeButton: NSPopUpButton?
    @IBOutlet weak var rootSplitView: NSSplitView?

    @IBOutlet weak var leftPane: NSVisualEffectView?
    @IBOutlet weak var leftVerticalSplitView: NSSplitView?
    @IBOutlet weak var tasksTableView: NSTableView?
    @IBOutlet weak var leftBar: ColoredView?
    @IBOutlet weak var batchCheckbox: NSButtonCell!
    @IBOutlet weak var taskFilterTextField: NSSearchField!
    @IBOutlet weak var showRunOptionsButton: NSButton?
    @IBOutlet weak var runOptionsPane: ColoredView?
    @IBOutlet weak var iterationsField: NSTextField?
    @IBOutlet weak var iterationsStepper: NSStepper?
    @IBOutlet weak var minimumDurationField: NSTextField?
    @IBOutlet weak var maximumDurationField: NSTextField?

    @IBOutlet weak var middleSplitView: NSSplitView?
    @IBOutlet weak var chartView: ChartView?
    @IBOutlet weak var middleBar: ColoredView?
    @IBOutlet weak var showLeftPaneButton: NSButton?
    @IBOutlet weak var showConsoleButton: NSButton?
    @IBOutlet weak var statusLabel: StatusLabel?
    @IBOutlet weak var showRightPaneButton: NSButton?
    @IBOutlet weak var consolePane: NSView?
    @IBOutlet weak var consoleTextView: NSTextView?

    @IBOutlet weak var rightPane: ColoredView?
    
    @IBOutlet weak var themePopUpButton: NSPopUpButton?
    @IBOutlet weak var amortizedCheckbox: NSButton?
    @IBOutlet weak var logarithmicSizeCheckbox: NSButton?
    @IBOutlet weak var logarithmicTimeCheckbox: NSButton?

    @IBOutlet weak var centerBandPopUpButton: NSPopUpButton?
    @IBOutlet weak var errorBandPopUpButton: NSPopUpButton?
    
    @IBOutlet weak var highlightSelectedSizeRangeCheckbox: NSButton?
    @IBOutlet weak var displayIncludeAllMeasuredSizesCheckbox: NSButton?
    @IBOutlet weak var displayIncludeSizeScaleRangeCheckbox: NSButton?
    @IBOutlet weak var displaySizeScaleRangeMinPopUpButton: NSPopUpButton?
    @IBOutlet weak var displaySizeScaleRangeMaxPopUpButton: NSPopUpButton?

    @IBOutlet weak var displayIncludeAllMeasuredTimesCheckbox: NSButton?
    @IBOutlet weak var displayIncludeTimeRangeCheckbox: NSButton?
    @IBOutlet weak var displayTimeRangeMinPopUpButton: NSPopUpButton?
    @IBOutlet weak var displayTimeRangeMaxPopUpButton: NSPopUpButton?

    @IBOutlet weak var progressRefreshIntervalField: NSTextField?
    @IBOutlet weak var chartRefreshIntervalField: NSTextField?

    override init() {
        super.init()

        self.glue.connector.connect(self.theme.values) { [unowned self] theme in
            self.m.themeName.value = theme.name
        }
        
        self.glue.connector.connect([tasksToRun.tick, model.map{$0.runOptionsTick}].gather()) { [unowned self] in
            self.updateChangeCount(.changeDone)
            self.runOptionsDidChange()
        }

        self.glue.connector.connect([checkedTasks.tick,
                                     model.map{$0.runOptionsTick},
                                     model.map{$0.chartOptionsTick}].gather()) { [unowned self] in
            self.updateChangeCount(.changeDone)
            self.refreshChart.now()
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
        self.glue.connector.connect(model.map{$0.progressRefreshInterval}.values) { [unowned self] interval in
            self.statusLabel?.refreshRate = interval.seconds
            self.processPendingResults.maxDelay = interval.seconds
        }
        self.glue.connector.connect(model.map{$0.chartRefreshInterval}.values) { [unowned self] interval in
            self.refreshChart.maxDelay = interval.seconds
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
        let tasksTVC = GlueKitTableViewController<Task, TaskCellView>(tableView: tasksTableView!, contents: visibleTasks) { [unowned self] cell, item in
            cell.task = item
            cell.context = self
        }
        self.tasksTableViewController = tasksTVC
        self.tasksTableView!.delegate = tasksTVC
        self.tasksTableView!.dataSource = tasksTVC
        self.statusLabel!.immediateStatus = _status
        self.chartView!.documentBasename = self.displayName
        self.chartView!.theme = self.theme.anyObservableValue
        self.batchCheckbox.state = self.batchCheckboxState.value

        self.iterationsField!.glue.value <-- model.map{$0.iterations}
        self.iterationsStepper!.glue.intValue <-- model.map{$0.iterations}
        self.minimumDurationField!.glue.value <-- model.map{$0.durationRange.lowerBound}
        self.maximumDurationField!.glue.value <-- model.map{$0.durationRange.upperBound}

        self.amortizedCheckbox!.glue.state <-- model.map{$0.amortizedTime}
        self.logarithmicSizeCheckbox!.glue.state <-- model.map{$0.logarithmicSizeScale}
        self.logarithmicTimeCheckbox!.glue.state <-- model.map{$0.logarithmicTimeScale}

        self.progressRefreshIntervalField!.glue.value <-- model.map{$0.progressRefreshInterval}
        self.chartRefreshIntervalField!.glue.value <-- model.map{$0.chartRefreshInterval}

        self.centerBandPopUpButton!.glue <-- NSPopUpButton.Choices<CurveBandValues>(
            model: model.map{$0.centerBand}
                .map({ CurveBandValues($0) },
                     inverse: { $0.band }),
            values: [
                "None": .none,
                "Minimum": .minimum,
                "Average": .average,
                "Maximum": .maximum,
                "Sample Size": .count,
            ])

        self.errorBandPopUpButton!.glue <-- NSPopUpButton.Choices<ErrorBandValues>(
            model: model.map{$0.topBand}.combined(model.map{$0.bottomBand})
                .map({ ErrorBandValues(top: $0.0, bottom: $0.1) },
                     inverse: { ($0.top, $0.bottom) }),
            values: [
                "None": .none,
                "Maximum": .maximum,
                "μ + σ": .sigma1,
                "μ + 2σ": .sigma2,
                "μ + 3σ": .sigma3,
            ])

        self.themePopUpButton!.glue <-- NSPopUpButton.Choices<BenchmarkTheme>(
            model: self.theme,
            values: BenchmarkTheme.Predefined.themes.map { (label: $0.name, value: $0) })

        let sizeChoices: [(label: String, value: Int)]
            = (0 ... Attaresult.largestPossibleSizeScale).map { ((1 << $0).sizeLabel, $0) }
        let lowerBoundSizeChoices = sizeChoices.map { (label: "\($0.0) ≤", value: $0.1) }
        let upperBoundSizeChoices = sizeChoices.map { (label: "≤ \($0.0)", value: $0.1) }
        
        self.minimumSizeButton!.glue <-- NSPopUpButton.Choices<Int>(
            model: model.map{$0.sizeScaleRange.lowerBound},
            values: lowerBoundSizeChoices)
        
        self.maximumSizeButton!.glue <-- NSPopUpButton.Choices<Int>(
            model: model.map{$0.sizeScaleRange.upperBound},
            values: upperBoundSizeChoices)
        
        self.highlightSelectedSizeRangeCheckbox!.glue.state <-- model.map{$0.highlightSelectedSizeRange}
        self.displayIncludeAllMeasuredSizesCheckbox!.glue.state <-- model.map{$0.displayIncludeAllMeasuredSizes}
        self.displayIncludeSizeScaleRangeCheckbox!.glue.state <-- model.map{$0.displayIncludeSizeScaleRange}
        
        self.displaySizeScaleRangeMinPopUpButton!.glue <-- NSPopUpButton.Choices<Int>(
            model: model.map{$0.displaySizeScaleRange.lowerBound},
            values: lowerBoundSizeChoices)
        self.displaySizeScaleRangeMinPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeSizeScaleRange}

        self.displaySizeScaleRangeMaxPopUpButton!.glue <-- NSPopUpButton.Choices<Int>(
            model: model.map{$0.displaySizeScaleRange.upperBound},
            values: upperBoundSizeChoices)
        self.displaySizeScaleRangeMaxPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeSizeScaleRange}

        
        var timeChoices: [(label: String, value: Time)] = []
        var time = Time(picoseconds: 1)
        for _ in 0 ..< 20 {
            timeChoices.append(("\(time)", time))
            time = 10 * time
        }
        self.displayIncludeAllMeasuredTimesCheckbox!.glue.state <-- model.map{$0.displayIncludeAllMeasuredTimes}

        self.displayIncludeTimeRangeCheckbox!.glue.state <-- model.map{$0.displayIncludeTimeRange}
        
        self.displayTimeRangeMinPopUpButton!.glue <-- NSPopUpButton.Choices<Time>(
            model: model.map{$0.displayTimeRange.lowerBound},
            values: timeChoices)
        self.displayTimeRangeMinPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeTimeRange}
        
        self.displayTimeRangeMaxPopUpButton!.glue <-- NSPopUpButton.Choices<Time>(
            model: model.map{$0.displayTimeRange.upperBound},
            values: timeChoices)
        self.displayTimeRangeMaxPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeTimeRange}

        refreshRunButton()
        refreshChart.now()
    }
    
    enum CurveBandValues: Equatable {
        case none
        case average
        case minimum
        case maximum
        case count
        case other(TimeSample.Band?)

        init(_ band: TimeSample.Band?) {
            switch band {
            case nil: self = .none
            case .average?: self = .average
            case .minimum?: self = .minimum
            case .maximum?: self = .maximum
            case .count?: self = .count
            default: self = .other(band)
            }
        }

        var band: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .average: return .average
            case .minimum: return .minimum
            case .maximum: return .maximum
            case .count: return .count
            case .other(let band): return band
            }
        }

        static func ==(left: CurveBandValues, right: CurveBandValues) -> Bool {
            return left.band == right.band
        }
    }

    enum ErrorBandValues: Equatable {
        case none
        case maximum
        case sigma1
        case sigma2
        case sigma3
        case other(top: TimeSample.Band?, bottom: TimeSample.Band?)

        var top: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .maximum: return .maximum
            case .sigma1: return .sigma(1)
            case .sigma2: return .sigma(2)
            case .sigma3: return .sigma(3)
            case .other(top: let top, bottom: _): return top
            }
        }

        var bottom: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .maximum: return .minimum
            case .sigma1: return .minimum
            case .sigma2: return .minimum
            case .sigma3: return .minimum
            case .other(top: _, bottom: let bottom): return bottom
            }
        }

        init(top: TimeSample.Band?, bottom: TimeSample.Band?) {
            switch (top, bottom) {
            case (nil, nil): self = .none
            case (.maximum?, .minimum?): self = .maximum
            case (.sigma(1)?, .minimum?): self = .sigma1
            case (.sigma(2)?, .minimum?): self = .sigma2
            case (.sigma(3)?, .minimum?): self = .sigma3
            case let (t, b): self = .other(top: t, bottom: b)
            }
        }

        static func ==(left: ErrorBandValues, right: ErrorBandValues) -> Bool {
            return left.top == right.top && left.bottom == right.bottom
        }

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

        let name = m.benchmarkDisplayName.value

        switch new {
        case .noBenchmark:
            self.setStatus(.immediate, "Attabench document cannot be found; can't take new measurements")
        case .idle:
            self.setStatus(.immediate, "Ready")
        case .loading(_):
            self.setStatus(.immediate, "Loading \(name)...")
        case .waiting:
            self.setStatus(.immediate, "No executable tasks selected, pausing")
        case .running(_):
            self.setStatus(.immediate, "Starting \(name)...")
        case .stopping(_, then: .restart):
            self.setStatus(.immediate, "Restarting \(name)...")
        case .stopping(_, then: _):
            self.setStatus(.immediate, "Stopping \(name)...")
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
            return try JSONEncoder().encode(m)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
    func readAttaresult(_ data: Data) throws {
        self.m = try JSONDecoder().decode(Attaresult.self, from: data)
        self.theme.value = BenchmarkTheme.Predefined.theme(named: self.m.themeName.value) ?? BenchmarkTheme.Predefined.screen
    }

    override func read(from url: URL, ofType typeName: String) throws {
        switch typeName {
        case UTI.attaresult:
            try self.readAttaresult(try Data(contentsOf: url))
            if let url = m.benchmarkURL.value {
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
                self.isDraft = true
                self.fileType = UTI.attaresult
                self.fileURL = nil
                self.fileModificationDate = nil
                self.displayName = url.deletingPathExtension().lastPathComponent
                self.m = Attaresult()
                self.m.benchmarkURL.value = url
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
        let stale = Set(m.tasks.value.map { $0.name })
        let newTasks = fresh.subtracting(stale)
        let missingTasks = stale.subtracting(fresh)

        m.tasks.append(contentsOf:
            taskNames
                .filter { newTasks.contains($0) }
                .map { Task(name: $0) })

        for task in m.tasks.value {
            task.isRunnable.value = fresh.contains(task.name)
        }

        log(.status, "Received \(m.tasks.count) task names (\(newTasks.count) new, \(missingTasks.count) missing).")
    }

    func benchmark(_ benchmark: BenchmarkProcess, willMeasureTask task: String, atSize size: Int) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        setStatus(.lazy, "Measuring size \(size.sizeLabel) for task \(task)")
    }

    func benchmark(_ benchmark: BenchmarkProcess, didMeasureTask task: String, atSize size: Int, withResult time: Time) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        pendingResults.append((task, size, time))
        processPendingResults.later()
        if pendingResults.count > 10000 {
            // Don't let reports swamp the run loop.
            log(.status, "Receiving reports too quickly; terminating benchmark.")
            log(.status, "Try selected larger sizes, or increasing the iteration count or minimum duration in Run Options.")
            stopMeasuring()
        }
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
        if let activity = self.activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
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
        guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        switch action {
        case #selector(AttabenchDocument.startStopAction(_:)):
            let startLabel = "Start Running"
            let stopLabel = "Stop Running"

            guard m.benchmarkURL.value != nil else { return false }
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
        case #selector(AttabenchDocument.delete(_:)):
            return self.tasksTableView?.selectedRowIndexes.isEmpty == false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
    
    
    @IBAction func delete(_ sender: AnyObject) {
        // FIXME this is horrible. Implement Undo etc.
        let tasks = (self.tasksTableView?.selectedRowIndexes ?? []).map { self.visibleTasks[$0] }
        m.tasks.withTransaction {
            for task in tasks {
                task.deleteResults(in: NSEvent.modifierFlags.contains(.shift)
                    ? nil
                    : self.m.selectedSizeRange.value)
                if !task.isRunnable.value && task.sampleCount.value == 0 {
                    self.m.remove(task)
                }
            }
        }
        self.refreshChart.now()
        self.updateChangeCount(.changeDone)
    }


    @IBAction func chooseBenchmark(_ sender: AnyObject) {
        guard let window = self.windowControllers.first?.window else { return }
        let openPanel = NSOpenPanel()
        openPanel.message = "This result file has no associated Attabench document. To add measurements, you need to select a benchmark file."
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = [UTI.attabench]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            guard let url = openPanel.urls.first else { return }
            self.m.benchmarkURL.value = url
            self._reload()
        }
    }

    func _reload() {
        do {
            guard let url = m.benchmarkURL.value else { chooseBenchmark(self); return }
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
            guard !m.tasks.isEmpty else { return }
            self.startMeasuring()
        case .waiting:
            self.state = .idle
        case .running(_):
            stopMeasuring()
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

    func stopMeasuring() {
        guard case .running(let process) = state else { return }
        self.state = .stopping(process, then: .idle)
        process.stop()
    }

    func startMeasuring() {
        guard let source = self.m.benchmarkURL.value else { log(.status, "Can't start measuring"); return }
        switch self.state {
        case .waiting, .idle: break
        default: return
        }
        let tasks = tasksToRun.value.map { $0.name }
        let sizes = self.m.selectedSizes.value.sorted()
        guard !tasks.isEmpty, !sizes.isEmpty else {
            self.state = .waiting
            return
        }

        log(.status, "\nRunning \(m.benchmarkDisplayName.value) with \(tasks.count) tasks at sizes from \(sizes.first!.sizeLabel) to \(sizes.last!.sizeLabel).")
        let options = RunOptions(tasks: tasks,
                                 sizes: sizes,
                                 iterations: m.iterations.value,
                                 minimumDuration: m.durationRange.value.lowerBound.seconds,
                                 maximumDuration: m.durationRange.value.upperBound.seconds)
        do {
            self.state = .running(try BenchmarkProcess(url: source, command: .run(options), delegate: self, on: .main))
            self.activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Benchmarking")
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

    @IBAction func increaseMinScale(_ sender: AnyObject) {
        m.sizeScaleRange.lowerBound.value += 1
    }

    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        m.sizeScaleRange.lowerBound.value -= 1
    }

    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        m.sizeScaleRange.upperBound.value += 1
    }

    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        m.sizeScaleRange.upperBound.value -= 1
    }
}

extension AttabenchDocument {
    //MARK: Chart rendering

    private func _refreshChart() {
        guard let chartView = self.chartView else { return }

        let tasks = checkedTasks.value

        var options = BenchmarkChart.Options()
        options.amortizedTime = m.amortizedTime.value
        options.logarithmicSize = m.logarithmicSizeScale.value
        options.logarithmicTime = m.logarithmicTimeScale.value

        var sizeBounds = Bounds<Int>()
        if m.highlightSelectedSizeRange.value {
            let r = m.sizeScaleRange.value
            sizeBounds.formUnion(with: Bounds((1 << r.lowerBound) ... (1 << r.upperBound)))
        }
        if m.displayIncludeSizeScaleRange.value {
            let r = m.displaySizeScaleRange.value
            sizeBounds.formUnion(with: Bounds((1 << r.lowerBound) ... (1 << r.upperBound)))
        }
        options.displaySizeRange = sizeBounds.range
        options.displayAllMeasuredSizes = m.displayIncludeAllMeasuredSizes.value

        var timeBounds = Bounds<Time>()
        if m.displayIncludeTimeRange.value {
            let r = m.displayTimeRange.value
            timeBounds.formUnion(with: Bounds(r))
        }
        if let r = timeBounds.range {
            options.displayTimeRange = r.lowerBound ... r.upperBound
        }
        options.displayAllMeasuredTimes = m.displayIncludeAllMeasuredTimes.value

        options.topBand = m.topBand.value
        options.centerBand = m.centerBand.value
        options.bottomBand = m.bottomBand.value

        chartView.chart = BenchmarkChart(title: "", tasks: tasks, options: options)
    }
}

extension AttabenchDocument: NSSplitViewDelegate {
    @IBAction func showHideLeftPane(_ sender: Any) {
        guard let pane = self.leftPane else { return }
        pane.isHidden = !pane.isHidden
    }

    @IBAction func showHideRightPane(_ sender: Any) {
        guard let pane = self.rightPane else { return }
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
        if subview === self.rightPane { return true }
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
        if splitView === rootSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.rightPane!) ? .off : .on
            if showRightPaneButton!.state != state {
                showRightPaneButton!.state = state
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
    
    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        if splitView === middleSplitView, dividerIndex == 1 {
            let status = splitView.convert(self.statusLabel!.bounds, from: self.statusLabel!)
            let bar = splitView.convert(self.middleBar!.bounds, from: self.middleBar!)
            return CGRect(x: status.minX, y: bar.minY, width: status.width, height: bar.height)
        }
        return .zero
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
        case taskFilterString
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(self.taskFilterString.value, forKey: RestorationKey.taskFilterString.rawValue)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        self.taskFilterString.value = coder.decodeObject(forKey: RestorationKey.taskFilterString.rawValue) as? String
    }
}
