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
    var saveScheduled = false
    var terminating = false


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

            let index = self.suiteMenu.items.index(where: { $0.title == suite.title }) ?? 0
            if self.suitePopUpButton.indexOfSelectedItem != index {
                self.suitePopUpButton.selectItem(at: index)
            }
            refreshChart()
        }
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
        let suite = runner.suites.first(where: { $0.title == selectedTitle }) ?? runner.suites.first!

        self.suiteMenu.removeAllItems()
        var i = 1
        for suite in runner.suites {
            let item = NSMenuItem(title: suite.title,
                                  action: #selector(AppDelegate.didSelectSuite(_:)),
                                  keyEquivalent: i <= 9 ? "\(i)" : "")
            self.suiteMenu.addItem(item)
            i += 1
        }
        self.selectedSuite = suite
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
        self.status = "Measuring \(benchmark) at size \(size)"
    }

    func runner(_ runner: Runner, didMeasureInstanceInSuite suite: String, benchmark: String, size: Int, withResult time: TimeInterval) {
        print(benchmark, size, time)
        scheduleRefresh()
        window.isDocumentEdited = true
        scheduleSave()
    }

    func runner(_ runner: Runner, didStopMeasuringSuite suite: String) {
        self.runButton.image = #imageLiteral(resourceName: "RunTemplate")
        self.runButton.isEnabled = true
        self.startMenuItem.title = "Start Running"
        self.startMenuItem.isEnabled = true
        self.suitePopUpButton.isEnabled = true
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
        let chart = Chart(size: AppDelegate.imageSize, suite: suite, results: results)
        self.chartImageView.image = chart.image
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
        let suite = self.selectedSuite ?? self.runner.suites[0]
        self.suitePopUpButton.isEnabled = false
        self.runButton.image = #imageLiteral(resourceName: "StopTemplate")
        self.startMenuItem.title = "Stop Running"
        self.status = "Running \(suite.title)"
        self.runner.start(suite: suite, maxScale: 20)
    }

    func stop() {
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
}
