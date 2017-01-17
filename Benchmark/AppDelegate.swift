//
//  AppDelegate.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-01-19.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Cocoa
import BenchmarkingTools
import CollectionBenchmarks

@NSApplicationMain
class AppDelegate: NSObject {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var suitePopUpButton: NSPopUpButton!
    @IBOutlet weak var suiteMenu: NSMenu!
    @IBOutlet weak var progressButton: NSButton!
    @IBOutlet weak var chartImageView: NSImageView!
    @IBOutlet weak var startMenuItem: NSMenuItem!

    let runner = Runner()

    var refreshScheduled = false

    var status: String = "" {
        didSet {
            self.progressButton.title = status
        }
    }

    var selectedSuite: BenchmarkSuiteProtocol {
        let index = suitePopUpButton.indexOfSelectedItem
        if index == -1 { return runner.suites[0] }
        return runner.suites[index]
    }
}

extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.titleVisibility = .hidden

        self.status = "Loading benchmarks"
        self.suiteMenu.removeAllItems()
        self.runButton.isEnabled = false

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

        let defaults = UserDefaults.standard
        let selectedTitle = defaults.string(forKey: "SelectedSuite")
        let selectedIndex = runner.suites.index(where: { $0.title == selectedTitle }) ?? 0

        self.suiteMenu.removeAllItems()
        for suite in runner.suites {
            let item = NSMenuItem(title: suite.title, action: #selector(AppDelegate.didSelectSuite(_:)), keyEquivalent: "")
            self.suiteMenu.addItem(item)
        }
        let selectedItem = self.suiteMenu.items[selectedIndex]
        self.suitePopUpButton.select(selectedItem)

        refreshChart()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if runner.state == .running {
            runner.stop()
        }
        try? runner.save()
    }
}

extension AppDelegate: RunnerDelegate {
    //MARK: RunnerDelegate
    func runner(_ runner: Runner, didStartMeasuringSuite suite: String, benchmark: String, size: Int) {
        self.status = "Measuring \(benchmark) at size \(size)"
    }

    func runner(_ runner: Runner, didMeasureInstanceInSuite suite: String, benchmark: String, size: Int, withResult time: TimeInterval) {
        print(benchmark, size, time)
        scheduleRefresh()
    }

    func runner(_ runner: Runner, didStopMeasuringSuite suite: String) {
        self.runButton.image = #imageLiteral(resourceName: "Run")
        self.runButton.isEnabled = true
        self.startMenuItem.title = "Start Running"
        self.startMenuItem.isEnabled = true
        self.suitePopUpButton.isEnabled = true
        self.status = "Idle"
        try? self.runner.save()
    }
}

extension AppDelegate {
    //MARK: Actions

    static let imageSize = CGSize(width: 1024, height: 768)

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
        let suite = self.selectedSuite
        let results = runner.results(for: suite)
        let chart = Chart(size: AppDelegate.imageSize, suite: suite, results: results)
        self.chartImageView.image = chart.image
    }

    @IBAction func newDocument(_ sender: AnyObject) {
        runner.reset()
        refreshChart()
    }

    @IBAction func saveDocument(_ sender: AnyObject) {
        try? runner.save()
    }

    @IBAction func run(_ sender: AnyObject) {
        switch self.runner.state {
        case .idle:
            let suite = self.selectedSuite
            self.suitePopUpButton.isEnabled = false
            self.runButton.image = #imageLiteral(resourceName: "Stop")
            self.startMenuItem.title = "Stop Running"
            self.status = "Running \(suite.title)"
            self.runner.start(suite: suite, maxScale: 18)
        case .running:
            self.runButton.isEnabled = false
            self.startMenuItem.isEnabled = false
            self.status = "Stopping..."
            self.runner.stop()
        case .stopping:
            // Do nothing
            break
        }
    }

    @IBAction func didSelectSuite(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.set(sender.title, forKey: "SelectedSuite")
        refreshChart()
    }
}

extension AppDelegate: NSWindowDelegate {
    //MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: window)
    }
}
