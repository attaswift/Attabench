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

@NSApplicationMain
class AppDelegate: NSObject {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var suitePopUpButton: NSPopUpButton!
    @IBOutlet weak var maxSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var startMenuItem: NSMenuItem!
    @IBOutlet weak var progressButton: NSButton!
    @IBOutlet weak var chartImageView: DraggableImageView!

    let runner = Runner()

    var refreshScheduled = false
    var saveScheduled = false
    var terminating = false

    let amortized: AnyUpdatableValue<Bool> = UserDefaults.standard.glue.updatable(forKey: "Amortized", defaultValue: false)

    var status: String = "" {
        didSet {
            self.progressButton.title = status
        }
    }

    var selectedSuite: BenchmarkSuiteProtocol? {
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
            refreshMaxScale()
        }
    }
}

extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.titleVisibility = .hidden

        self.status = "Loading benchmarks"
        self.runButton.isEnabled = false
        self.startMenuItem.isEnabled = false

        runner.delegate = self
        for suite in CollectionBenchmarks.generateBenchmarks() {
            runner.load(suite)
        }

        if runner.suites.isEmpty {
            self.status = "No benchmarks available"
            return
        }
        self.status = "Ready"
        self.runButton.isEnabled = true
        self.startMenuItem.isEnabled = true

        let defaults = UserDefaults.standard
        let selectedTitle = defaults.string(forKey: "SelectedSuite")
        let suite = runner.suites.first(where: { $0.title == selectedTitle }) ?? runner.suites.first!

        let suiteMenu = NSMenu()
        suiteMenu.removeAllItems()
        var i = 1
        for suite in runner.suites {
            let item = NSMenuItem(title: suite.title,
                                  action: #selector(AppDelegate.didSelectSuite(_:)),
                                  keyEquivalent: i <= 9 ? "\(i)" : "")
            suiteMenu.addItem(item)
            i += 1
        }
        self.suitePopUpButton.menu = suiteMenu

        let sizeMenu = NSMenu()
        for i in 4 ..< 30 {
            let item = NSMenuItem(title: "≤\((1 << i).label)",
                action: #selector(AppDelegate.didSelectMaxSize(_:)),
                keyEquivalent: "")
            item.tag = i
            sizeMenu.addItem(item)
        }
        self.maxSizePopUpButton.menu = sizeMenu

        self.selectedSuite = suite

        self.glue.connector.connect(self.amortized.futureValues) { value in
            self.refreshChart()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
        if runner.state == .idle {
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

extension AppDelegate: RunnerDelegate {
    //MARK: RunnerDelegate
    func runner(_ runner: Runner, didStartMeasuringSuite suite: String, benchmark: String, size: Int) {
        self.status = "Measuring \(suite) : \(benchmark) : \(size.label)"
    }

    func runner(_ runner: Runner, didMeasureInstanceInSuite suite: String, benchmark: String, size: Int, withResult time: TimeInterval) {
        //print(benchmark, size, time)
        scheduleRefresh()
        window.isDocumentEdited = true
        scheduleSave()
    }

    func runner(_ runner: Runner, didStopMeasuringSuite suite: String) {
        self.runButton.image = #imageLiteral(resourceName: "RunTemplate")
        self.runButton.isEnabled = true
        self.startMenuItem.title = "Start Running"
        self.startMenuItem.isEnabled = true
        self.status = "Idle"
        self.save()
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}

extension AppDelegate {
    //MARK: Actions

    static let imageSize = CGSize(width: 1280, height: 720)

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.run(_:)) {
            return runner.state != .stopping
        }
        return true
    }

    func scheduleRefresh() {
        if !refreshScheduled {
            self.perform(#selector(AppDelegate.refreshChart), with: nil, afterDelay: 0.1)
            refreshScheduled = true
        }
    }

    func cancelRefresh() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(AppDelegate.refreshChart), object: nil)
        refreshScheduled = false
    }

    func refreshChart() {
        cancelRefresh()
        let suite = self.selectedSuite ?? self.runner.suites[0]
        let results = runner.results(for: suite)
        let chart: Chart
        if amortized.value {
            chart = Chart(size: AppDelegate.imageSize, suite: suite, results: results, amortized: true)
        }
        else {
            chart = Chart(size: AppDelegate.imageSize, suite: suite, results: results,
                          sizeRange: 1 ..< (1 << 20),
                          timeRange: 1e-7 ..< 1000,
                          amortized: false)
        }
        let image = chart.image
        self.chartImageView.image = image
        self.chartImageView.name = chart.title

    }

    @IBAction func newDocument(_ sender: AnyObject) {
        runner.reset()
        refreshChart()
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
            try runner.save()
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
        guard self.runner.state == .idle else { return }
        let suite = self.selectedSuite ?? self.runner.suites[0]
        self.runButton.image = #imageLiteral(resourceName: "StopTemplate")
        self.startMenuItem.title = "Stop Running"
        self.status = "Running \(suite.title)"
        self.runner.start(suite: suite)
    }

    func stop() {
        guard self.runner.state == .running else { return }
        self.runButton.isEnabled = false
        self.startMenuItem.isEnabled = false
        self.status = "Stopping..."
        self.runner.stop()
    }

    @IBAction func run(_ sender: AnyObject) {
        switch self.runner.state {
        case .idle:
            self.start()
        case .running:
            self.stop()
        case .stopping:
            // Do nothing
            break
        }
    }

    @IBAction func didSelectSuite(_ sender: NSMenuItem) {
        let index = suitePopUpButton.indexOfSelectedItem
        selectedSuite = runner.suites[index == -1 ? 0 : index]
    }

    @IBAction func selectNextSuite(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.runner.suites[0]
        let index = self.runner.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = self.runner.suites[(index + 1) % self.runner.suites.count]
    }

    @IBAction func selectPreviousSuite(_ sender: AnyObject?) {
        let suite = self.selectedSuite ?? self.runner.suites[0]
        let index = self.runner.suites.index(where: { $0.title == suite.title }) ?? 0
        self.selectedSuite = index == 0 ? self.runner.suites.last! : self.runner.suites[index - 1]
    }

    @IBAction func didSelectMaxSize(_ sender: NSMenuItem) {
        let i = sender.tag
        let suite = self.selectedSuite ?? self.runner.suites[0]
        runner.results(for: suite).scaleRange = 0 ... i
        refreshMaxScale()
    }

    func refreshMaxScale() {
        let suite = self.selectedSuite ?? self.runner.suites[0]
        let maxScale = self.runner.results(for: suite).scaleRange.upperBound
        if let item = self.maxSizePopUpButton.menu?.items.first(where: { $0.tag == maxScale }) {
            if self.maxSizePopUpButton.selectedItem !== item {
                self.maxSizePopUpButton.select(item)
            }
        }
        else {
            self.maxSizePopUpButton.select(nil)
        }
    }

    @IBAction func maximumScaleStepperChanged(_ sender: NSStepper) {
        let suite = self.selectedSuite ?? self.runner.suites[0]
        runner.results(for: suite).scaleRange = 0 ... sender.integerValue
        refreshMaxScale()
    }
}
