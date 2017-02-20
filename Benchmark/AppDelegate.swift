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
let maximumScale = 28

@NSApplicationMain
class AppDelegate: NSObject {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var backgroundView: ColoredView!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var suitePopUpButton: NSPopUpButton!
    @IBOutlet weak var minSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var maxSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var benchmarksPopUpButton: NSPopUpButton!
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

    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: true)
    let presentationMode: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "PresentationMode", defaultValue: false)

    let randomizeInputs: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "RandomizeInputs", defaultValue: false)

    var status: String = "" {
        didSet {
            guard !progressRefreshScheduled else { return }
            let now = Date()
            if nextProgressUpdate < now {
                self.progressButton.title = status
                nextProgressUpdate = now.addingTimeInterval(progressRefreshDelay)
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
            defaults.set(suite.title, forKey: "SelectedSuite")

            if let menu = self.suitePopUpButton.menu {
                let item = menu.items.first(where: { $0.title == suite.title })
                if self.suitePopUpButton.selectedItem !== item {
                    self.suitePopUpButton.select(item)
                }
            }
            refreshChart()
            refreshScale()
            refreshBenchmarks()
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
        for suite in CollectionBenchmarks.generateBenchmarks() {
            harness.load(suite)
        }

        if harness.suites.isEmpty {
            self.status = "No benchmarks available"
            return
        }
        self.status = "Ready"
        self.runButton.isEnabled = true
        self.startMenuItem.isEnabled = true

        let defaults = UserDefaults.standard
        let selectedTitle = defaults.string(forKey: "SelectedSuite")
        let suite = harness.suites.first(where: { $0.title == selectedTitle }) ?? harness.suites.first!

        self.selectedSuite = suite

        let suiteMenu = NSMenu()
        suiteMenu.removeAllItems()
        var i = 1
        for suite in harness.suites {
            let item = NSMenuItem(title: suite.title,
                                  action: #selector(AppDelegate.didSelectSuite(_:)),
                                  keyEquivalent: i <= 9 ? "\(i)" : "")
            suiteMenu.addItem(item)
            i += 1
        }
        self.suitePopUpButton.menu = suiteMenu

        let minSizeMenu = NSMenu()
        for i in minimumScale ... maximumScale {
            let item = NSMenuItem(title: "\((1 << i).label)≤",
                action: #selector(AppDelegate.didSelectMinSize(_:)),
                keyEquivalent: "")
            item.tag = i
            minSizeMenu.addItem(item)
        }
        self.minSizePopUpButton.menu = minSizeMenu

        let maxSizeMenu = NSMenu()
        for i in minimumScale ... maximumScale {
            let item = NSMenuItem(title: "≤\((1 << i).label)",
                action: #selector(AppDelegate.didSelectMaxSize(_:)),
                keyEquivalent: "")
            item.tag = i
            maxSizeMenu.addItem(item)
        }
        self.maxSizePopUpButton.menu = maxSizeMenu

        self.glue.connector.connect(self.amortized.futureValues) { value in
            self.refreshChart()
        }
        self.glue.connector.connect(self.presentationMode.values) { value in
            self.backgroundView.backgroundColor = value ? NSColor.black : NSColor.white
        }
        self.glue.connector.connect(self.presentationMode.futureValues) { value in
            self.refreshChart()
        }
        self.glue.connector.connect(self.randomizeInputs.futureValues) { value in
            self.refreshRunnerParams()
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
    func harness(_ harness: Harness, didStartMeasuringSuite suite: String, benchmark: String, size: Int) {
        self.status = "Measuring \(suite) : \(size.label) : \(benchmark)"
    }

    func harness(_ harness: Harness, didMeasureInstanceInSuite suite: String, benchmark: String, size: Int, withResult time: TimeInterval) {
        //print(benchmark, size, time)
        scheduleChartRefresh()
        window.isDocumentEdited = true
        scheduleSave()
    }

    func harness(_ harness: Harness, didStopMeasuringSuite suite: String) {
        self.save()
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
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
        if amortized.value {
            chart = Chart(size: size, suite: suite,
                          highlightedSizes: suite.sizeRange,
                          amortized: true,
                          presentation: presentationMode.value)
        }
        else {
            chart = Chart(size: size, suite: suite,
                          highlightedSizes: suite.sizeRange,
//                          sizeRange: 1 ..< (1 << 20),
//                          timeRange: 1e-7 ..< 1000,
                          amortized: false,
                          presentation: presentationMode.value)
        }
        let image = chart.image
        self.chartImageView.image = image
        self.chartImageView.name = "\(suite.title) - \(benchmarksPopUpButton.title)"
    }

    @IBAction func newDocument(_ sender: AnyObject) {
        let selected = self.selectedBenchmarks
        let scale = self.maxScale
        try? harness.reset()
        self.selectedBenchmarks = selected
        self.maxScale = scale
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

    @IBAction func didSelectSuite(_ sender: NSMenuItem) {
        let index = suitePopUpButton.indexOfSelectedItem
        selectedSuite = harness.suites[index == -1 ? 0 : index]
    }

    @IBAction func selectNextSuite(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let index = self.harness.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = self.harness.suites[(index + 1) % self.harness.suites.count]
    }

    @IBAction func selectPreviousSuite(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let index = self.harness.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = index == 0 ? self.harness.suites.last! : self.harness.suites[index - 1]
    }

    var selectedBenchmarks: Set<String> {
        get {
            return self.selectedSuite.selectedBenchmarkSet
        }
        set {
            self.selectedSuite.selectedBenchmarkSet = newValue
            refreshBenchmarks()
            refreshChart()
            refreshRunnerParams()
        }
    }

    func refreshBenchmarks() {
        let suite = self.selectedSuite ?? self.harness.suites[0]
        let selected = self.selectedBenchmarks

        let title: String
        switch selected.count {
        case 0:
            fatalError()
        case 1:
            title = selected.first!
        case suite.benchmarkTitles.count:
            title = "All Benchmarks"
        default:
            title = "\(selected.count) Benchmarks"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "All Benchmarks", action: #selector(AppDelegate.selectAllBenchmarks(_:)), keyEquivalent: "a")
        let submenu = NSMenu()
        let submenuItem = NSMenuItem(title: "Just One", action: nil, keyEquivalent: "")
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
        menu.addItem(NSMenuItem.separator())

        for title in suite.benchmarkTitles {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.toggleBenchmark(_:)), keyEquivalent: "")
            item.state = selected.contains(title) ? NSOnState : NSOffState
            menu.addItem(item)

            submenu.addItem(withTitle: title, action: #selector(AppDelegate.selectBenchmark(_:)), keyEquivalent: "")
        }
        self.benchmarksPopUpButton.menu = menu
    }

    @IBAction func selectAllBenchmarks(_ sender: AnyObject) {
        self.selectedBenchmarks = []
    }

    @IBAction func toggleBenchmark(_ sender: NSMenuItem) {
        var selected = self.selectedBenchmarks
        if selected.contains(sender.title) {
            selected.remove(sender.title)
        }
        else {
            selected.insert(sender.title)
        }
        if selected.isEmpty {
            self.selectedBenchmarks = []
        }
        else {
            self.selectedBenchmarks = selected
        }
    }

    @IBAction func selectBenchmark(_ sender: NSMenuItem) {
        let title = sender.title
        self.selectedBenchmarks = [title]
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
