//
//  AppDelegate.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-01-19.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Cocoa
import GlueKit
import BenchmarkingTools
import CollectionBenchmarks

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
    @IBOutlet weak var jobsPopUpButton: NSPopUpButton!
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
    var waitingForParamsChange = false

    let logarithmicSizeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicSize", defaultValue: true)
    let logarithmicTimeScale: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "LogarithmicTime", defaultValue: true)
    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: true)
    let presentationMode: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "PresentationMode", defaultValue: false)
    let highlightActiveRange: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "HighlightActiveRange", defaultValue: true)
    let randomizeInputs: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "RandomizeInputs", defaultValue: false)
    let showTitle: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "ShowTitle", defaultValue: true)

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

            if let menu = self.benchmarksPopUpButton.menu {
                let item = menu.items.first(where: { $0.title == suite.title })
                if self.benchmarksPopUpButton.selectedItem !== item {
                    self.benchmarksPopUpButton.select(item)
                }
            }
            refreshChart()
            refreshScale()
            refreshJobs()
            refreshRunnerParams()
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
        for benchmark in CollectionBenchmarks.generateBenchmarks() {
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
    func harness(_ harness: Harness, didStartMeasuringBenchmark benchmark: String, job: String, size: Int) {
        self.status = "Measuring \(benchmark) : \(size.sizeLabel) : \(job)"
    }

    func harness(_ harness: Harness, didMeasureInstanceInBenchmark benchmark: String, job: String, size: Int, withResult time: TimeInterval) {
        //print(jobs, size, time)
        scheduleChartRefresh()
        window.isDocumentEdited = true
        scheduleSave()
    }

    func harness(_ harness: Harness, didStopMeasuringBenchmark benchmark: String) {
        self.save()
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        if randomizeInputs.value {
            selectedSuite.benchmark.forgetInputs()
        }
        if !terminating && waitingForParamsChange {
            waitingForParamsChange = false
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
        let chart: Chart

        let size = presentationMode.value ? AppDelegate.presentationImageSize : chartImageView.bounds.size
        let highlight = highlightActiveRange.value ? suite.sizeRange : nil
        chart = Chart(size: size, suite: suite,
                      highlightedSizes: highlight,
                      logarithmicSizeScale: logarithmicSizeScale.value,
                      logarithmicTimeScale: logarithmicTimeScale.value,
                      amortized: amortized.value,
                      presentation: presentationMode.value,
                      showTitle: showTitle.value)
        let image = chart.image
        self.chartImageView.image = image
        self.chartImageView.name = "\(suite.title) - \(jobsPopUpButton.title)"
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
        guard self.harness.state == .idle else { return }
        let suite = self.selectedSuite ?? self.harness.suites[0]
        self.runButton.image = #imageLiteral(resourceName: "StopTemplate")
        self.startMenuItem.title = "Stop Running"
        self.status = "Running \(suite.title)"
        self.harness.start(suite: suite, randomized: randomizeInputs.value)
    }

    func stop() {
        guard self.harness.state == .running || self.waitingForParamsChange else { return }
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
            self.start()
        case .running:
            self.stop()
        case .stopping:
            // Do nothing
            break
        }
    }

    func refreshRunnerParams() {
        if self.harness.state == .running {
            self.waitingForParamsChange = true
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

    var selectedJobs: Set<String> {
        get {
            return self.selectedSuite.selectedJobSet
        }
        set {
            self.selectedSuite.selectedJobSet = newValue
            refreshJobs()
            refreshChart()
            refreshRunnerParams()
        }
    }

    func refreshJobs() {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let selected = self.selectedJobs

        let title: String
        switch selected.count {
        case 0:
            fatalError()
        case 1:
            title = selected.first!
        case suite.jobTitles.count:
            title = "All Jobs"
        default:
            title = "\(selected.count) Jobs"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "All Jobs", action: #selector(AppDelegate.selectAllJobs(_:)), keyEquivalent: "a")
        let submenu = NSMenu()
        let submenuItem = NSMenuItem(title: "Just One", action: nil, keyEquivalent: "")
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
        menu.addItem(NSMenuItem.separator())

        for title in suite.jobTitles {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.toggleJob(_:)), keyEquivalent: "")
            item.state = selected.contains(title) ? NSOnState : NSOffState
            menu.addItem(item)

            submenu.addItem(withTitle: title, action: #selector(AppDelegate.selectJob(_:)), keyEquivalent: "")
        }
        self.jobsPopUpButton.menu = menu
    }

    @IBAction func selectAllJobs(_ sender: AnyObject) {
        self.selectedJobs = []
    }

    @IBAction func toggleJob(_ sender: NSMenuItem) {
        var selected = self.selectedJobs
        if selected.contains(sender.title) {
            selected.remove(sender.title)
        }
        else {
            selected.insert(sender.title)
        }
        if selected.isEmpty {
            self.selectedJobs = []
        }
        else {
            self.selectedJobs = selected
        }
    }

    @IBAction func selectJob(_ sender: NSMenuItem) {
        let title = sender.title
        self.selectedJobs = [title]
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
