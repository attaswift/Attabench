//
//  AppDelegate.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-19.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa
import GlueKit
import BenchmarkingTools
import Benchmarks

let minimumScale = 0
let maximumScale = 32

@NSApplicationMain
class AppDelegate: NSObject {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var backgroundView: ColoredView!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var benchmarksPopUpButton: NSPopUpButton!
    @IBOutlet weak var minSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var maxSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var tasksPopUpButton: NSPopUpButton!
    @IBOutlet weak var startMenuItem: NSMenuItem!
    @IBOutlet weak var progressButton: NSButton!
    @IBOutlet weak var chartImageView: DraggableImageView!

    let harness = Harness()

    let progressRefreshDelay = 0.1
    var progressRefreshScheduled = false
    var nextProgressUpdate = Date.distantPast

    let chartRefreshDelay = 0.25
    var chartRefreshScheduled = false
    var saveScheduled = false
    var terminating = false
    var shouldBeRunning = false
    var benchmarkActivity: NSObjectProtocol? = nil

    let logarithmicSizeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicSize", defaultValue: true)
    let logarithmicTimeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicTime", defaultValue: true)
    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: true)
    let presentationMode: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "PresentationMode", defaultValue: false)
    let highlightActiveRange: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "HighlightActiveRange", defaultValue: true)
    let randomizeInputs: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "RandomizeInputs", defaultValue: false)
    let showTitle: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "ShowTitle", defaultValue: true)

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            "LogarithmicSize": true,
            "LogarithmicTime": true,
            "Amortized": true,
            "PresentationMode": false,
            "HighlightActiveRange": true,
            "RandomizeInputs": false,
            "ShowTitle": true
            ])
    }

    var status: String = "" {
        didSet {
            guard !progressRefreshScheduled else { return }
            let now = Date()
            if nextProgressUpdate < now {
                refreshProgress()
            }
            else {
                scheduleProgressRefresh()
            }
        }
    }

    var selectedSuite: Suite! {
        didSet {
            guard let suite = selectedSuite else { return }
            let defaults = UserDefaults.standard
            defaults.set(suite.title, forKey: "SelectedBenchmark")

            refreshRunnerParams()
            refreshSuite()
            refreshScale()
            refreshTasks()
            refreshChart()
        }
    }
}

extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.titleVisibility = .hidden

        self.status = "Loading benchmarks"
        self.runButton.isEnabled = false
        self.startMenuItem.isEnabled = false

        harness.delegate = self
        for benchmark in Benchmarks.generateBenchmarks() {
            harness.load(benchmark)
        }

        if harness.suites.isEmpty {
            self.status = "No benchmarks available"
            return
        }
        self.status = "Ready"
        self.runButton.isEnabled = true
        self.startMenuItem.isEnabled = true

        let defaults = UserDefaults.standard
        let selectedTitle = defaults.string(forKey: "SelectedBenchmark")
        let suite = harness.suites.first(where: { $0.title == selectedTitle }) ?? harness.suites.first!

        self.selectedSuite = suite

        let benchmarkMenu = NSMenu()
        benchmarkMenu.removeAllItems()
        var i = 1
        for suite in harness.suites {
            let item = NSMenuItem(title: suite.title,
                                  action: #selector(AppDelegate.didSelectBenchmark(_:)),
                                  keyEquivalent: i <= 9 ? "\(i)" : "")
            benchmarkMenu.addItem(item)
            i += 1
        }
        self.benchmarksPopUpButton.menu = benchmarkMenu

        let minSizeMenu = NSMenu()
        for i in minimumScale ... maximumScale {
            let item = NSMenuItem(title: "\((1 << i).sizeLabel)≤",
                action: #selector(AppDelegate.didSelectMinSize(_:)),
                keyEquivalent: "")
            item.tag = i
            minSizeMenu.addItem(item)
        }
        self.minSizePopUpButton.menu = minSizeMenu

        let maxSizeMenu = NSMenu()
        for i in minimumScale ... maximumScale {
            let item = NSMenuItem(title: "≤\((1 << i).sizeLabel)",
                action: #selector(AppDelegate.didSelectMaxSize(_:)),
                keyEquivalent: "")
            item.tag = i
            maxSizeMenu.addItem(item)
        }
        self.maxSizePopUpButton.menu = maxSizeMenu

        self.glue.connector.connect(self.presentationMode.values) { value in
            self.backgroundView.backgroundColor = value ? NSColor.black : NSColor.white
        }
        self.glue.connector.connect(self.randomizeInputs.futureValues) { value in
            self.refreshRunnerParams()
        }
        self.glue.connector.connect(
            AnySource<Void>.merge(
                [logarithmicSizeScale, logarithmicTimeScale, amortized, presentationMode, highlightActiveRange, showTitle]
                    .map { $0.futureValues.map { _ in () } }
            )
        ) { value in
            self.refreshChart()
        }
        self.refreshSuite()
        self.refreshScale()
        self.refreshTasks()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
        if harness.state == .idle {
            return .terminateNow
        }
        terminating = true
        self.stop()
        return .terminateLater
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        self.save()
    }
}

extension AppDelegate: HarnessDelegate {
    //MARK: HarnessDelegate

    func harness(_ harness: Harness, willStartMeasuring instance: BenchmarkInstanceKey) {
        self.status = "Measuring \(instance.benchmark) : \(instance.size.sizeLabel) : \(instance.task)"
    }

    func harness(_ harness: Harness, didMeasure instance: BenchmarkInstanceKey, withResult time: TimeInterval) {
        scheduleChartRefresh()
        window.isDocumentEdited = true
        scheduleSave()
    }

    func harnessDidStopRunning(_ harness: Harness) {
        self.save()
        ProcessInfo.processInfo.endActivity(benchmarkActivity!)
        benchmarkActivity = nil
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        if randomizeInputs.value {
            selectedSuite.benchmark.forgetInputs()
        }
        if !self.terminating && self.shouldBeRunning {
            self.start()
        }
        else {
            self.runButton.image = #imageLiteral(resourceName: "RunTemplate")
            self.runButton.isEnabled = true
            self.startMenuItem.title = "Start Running"
            self.startMenuItem.isEnabled = true
            self.status = "Idle"
        }
    }
}
extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        self.refreshChart()
    }
}

extension AppDelegate {
    //MARK: Copy image to pasteboard
    @IBAction func copy(_ sender: Any?) {
        guard let image = chartImageView.image else { NSBeep(); return }
        let pb = NSPasteboard.general()
        pb.clearContents()
        pb.writeObjects([image])
    }

    @IBAction func cut(_ sender: Any?) {
        self.copy(sender)
    }
}

extension AppDelegate {
    //MARK: Actions

    static let presentationImageSize = CGSize(width: 1280, height: 720)

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.run(_:)) {
            return harness.state != .stopping
        }
        return true
    }

    func refreshSuite() {
        if let menu = self.benchmarksPopUpButton.menu {
            let item = menu.items.first(where: { $0.title == selectedSuite.title })
            if self.benchmarksPopUpButton.selectedItem !== item {
                self.benchmarksPopUpButton.select(item)
            }
        }
    }

    func scheduleProgressRefresh() {
        if !progressRefreshScheduled {
            self.perform(#selector(AppDelegate.refreshProgress), with: nil, afterDelay: progressRefreshDelay)
            progressRefreshScheduled = true
        }
    }

    func refreshProgress() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(AppDelegate.refreshProgress), object: nil)
        progressRefreshScheduled = false

        self.progressButton.title = self.status
        nextProgressUpdate = Date(timeIntervalSinceNow: progressRefreshDelay)
    }

    func scheduleChartRefresh() {
        if !chartRefreshScheduled {
            self.perform(#selector(AppDelegate.refreshChart), with: nil, afterDelay: 0.1)
            chartRefreshScheduled = true
        }
    }

    func cancelChartRefresh() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(AppDelegate.refreshChart), object: nil)
        chartRefreshScheduled = false
    }

    func refreshChart() {
        cancelChartRefresh()
        guard !harness.suites.isEmpty else { return }
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let size = presentationMode.value ? AppDelegate.presentationImageSize : chartImageView.bounds.size
        let highlight = highlightActiveRange.value ? suite.sizeRange : nil
        let chart = Chart(suite: suite,
                          highlightedSizes: highlight,
                          logarithmicSizeScale: logarithmicSizeScale.value,
                          logarithmicTimeScale: logarithmicTimeScale.value,
                          amortized: amortized.value)
        let legendDistance = min(0.05 * size.width, 0.05 * size.height)
        let renderer = ChartRenderer(rect: CGRect(origin: .zero, size: size),
                                     chart: chart,
                                     theme: presentationMode.value ? .presentation : .normal,
                                     showTitle: showTitle.value,
                                     legend: (position: .topLeft, distance: CGSize(width: legendDistance, height: legendDistance)))
        self.chartImageView.image = renderer.image
        self.chartImageView.name = "\(suite.title) - \(tasksPopUpButton.title)"
    }

    @IBAction func deleteResults(_ sender: AnyObject) {
        try? self.selectedSuite.reset()
    }

    @IBAction func deleteAllResults(_ sender: AnyObject) {
        try? harness.reset()
    }

    func scheduleSave() {
        if !saveScheduled {
            self.perform(#selector(AppDelegate.save), with: nil, afterDelay: 30.0)
            saveScheduled = true
        }
    }

    func cancelSave() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(AppDelegate.save), object: nil)
        saveScheduled = false
    }

    func save() {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.suddenTerminationDisabled],
            reason: "Saving")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            cancelSave()
            try harness.save()
            window.isDocumentEdited = false
        }
        catch {
            // Ignore for now
        }
    }

    @IBAction func saveDocument(_ sender: AnyObject) {
        self.save()
    }

    func start() {
        guard self.harness.state == .idle, !self.terminating else { return }
        let suite = self.selectedSuite ?? self.harness.suites[0]
        self.runButton.image = #imageLiteral(resourceName: "StopTemplate")
        self.startMenuItem.title = "Stop Running"
        self.status = "Running \(suite.title)"
        precondition(benchmarkActivity == nil)
        self.benchmarkActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .latencyCritical, .userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Running Benchmarks")
        self.harness.start(suite: suite, randomized: randomizeInputs.value)
    }

    func stop() {
        guard self.harness.state == .running else { return }
        self.runButton.isEnabled = false
        self.startMenuItem.isEnabled = false
        self.status = "Stopping..."
        if self.harness.state == .running {
            self.harness.stop()
        }
    }

    @IBAction func run(_ sender: AnyObject) {
        switch self.harness.state {
        case .idle:
            self.shouldBeRunning = true
            self.start()
        case .running:
            self.shouldBeRunning = false
            self.stop()
        case .stopping:
            // Do nothing
            break
        }
    }

    func refreshRunnerParams() {
        if self.harness.state == .running {
            self.harness.stop()
        }
        else {
            DispatchQueue.main.async {
                self.save()
            }
        }
    }

    @IBAction func didSelectBenchmark(_ sender: NSMenuItem) {
        let index = benchmarksPopUpButton.indexOfSelectedItem
        selectedSuite = harness.suites[index == -1 ? 0 : index]
    }

    @IBAction func selectNextBenchmark(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let index = self.harness.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = self.harness.suites[(index + 1) % self.harness.suites.count]
    }

    @IBAction func selectPreviousBenchmark(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let index = self.harness.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = index == 0 ? self.harness.suites.last! : self.harness.suites[index - 1]
    }

    var selectedTasks: Set<String> {
        get {
            return self.selectedSuite.selectedTaskSet
        }
        set {
            self.selectedSuite.selectedTaskSet = newValue
            refreshTasks()
            refreshChart()
            refreshRunnerParams()
        }
    }

    func refreshTasks() {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let selected = self.selectedTasks

        let title: String
        switch selected.count {
        case 0:
            fatalError()
        case 1:
            title = selected.first!
        case suite.taskTitles.count:
            title = "All Tasks"
        default:
            title = "\(selected.count) Tasks"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "All Tasks", action: #selector(AppDelegate.selectAllTasks(_:)), keyEquivalent: "a")
        let submenu = NSMenu()
        let submenuItem = NSMenuItem(title: "Just One", action: nil, keyEquivalent: "")
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
        menu.addItem(NSMenuItem.separator())

        for title in suite.taskTitles {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.toggleTask(_:)), keyEquivalent: "")
            item.state = selected.contains(title) ? NSOnState : NSOffState
            menu.addItem(item)

            submenu.addItem(withTitle: title, action: #selector(AppDelegate.selectTask(_:)), keyEquivalent: "")
        }
        self.tasksPopUpButton.menu = menu
    }

    @IBAction func selectAllTasks(_ sender: AnyObject) {
        self.selectedTasks = []
    }

    @IBAction func toggleTask(_ sender: NSMenuItem) {
        var selected = self.selectedTasks
        if selected.contains(sender.title) {
            selected.remove(sender.title)
        }
        else {
            selected.insert(sender.title)
        }
        self.selectedTasks = selected
    }

    @IBAction func selectTask(_ sender: NSMenuItem) {
        let title = sender.title
        self.selectedTasks = [title]
    }
    var maxScale: Int {
        get {
            return self.selectedSuite.scaleRange.upperBound
        }
        set {
            let upper = max(min(newValue, maximumScale), minimumScale)
            let lower = min(upper, selectedSuite.scaleRange.lowerBound)
            self.selectedSuite.scaleRange = lower ... upper
            refreshScale()
            refreshChart()
            refreshRunnerParams()
        }
    }
    var minScale: Int {
        get {
            return self.selectedSuite.scaleRange.lowerBound
        }
        set {
            let lower = max(min(newValue, maximumScale), minimumScale)
            let upper = max(lower, selectedSuite.scaleRange.upperBound)
            selectedSuite.scaleRange = lower ... upper
            refreshScale()
            refreshChart()
            refreshRunnerParams()
        }
    }

    func refreshScale() {
        let minScale = self.minScale
        if let item = self.minSizePopUpButton.menu?.items.first(where: { $0.tag == minScale }) {
            if self.minSizePopUpButton.selectedItem !== item {
                self.minSizePopUpButton.select(item)
            }
        }
        else {
            self.minSizePopUpButton.select(nil)
        }

        let maxScale = self.maxScale
        if let item = self.maxSizePopUpButton.menu?.items.first(where: { $0.tag == maxScale }) {
            if self.maxSizePopUpButton.selectedItem !== item {
                self.maxSizePopUpButton.select(item)
            }
        }
        else {
            self.maxSizePopUpButton.select(nil)
        }
    }

    @IBAction func didSelectMinSize(_ sender: NSMenuItem) {
        self.minScale = sender.tag
    }
    @IBAction func didSelectMaxSize(_ sender: NSMenuItem) {
        self.maxScale = sender.tag
    }

    @IBAction func increaseMinScale(_ sender: AnyObject) {
        self.minScale += 1
    }
    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        self.minScale -= 1
    }
    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        self.maxScale += 1
    }
    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        self.maxScale -= 1
    }
}
