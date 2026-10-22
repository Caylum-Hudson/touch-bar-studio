//
//  NetworkBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 23/02/2019.
//  Copyright © 2019 Anton Palgunov. All rights reserved.
//

import Foundation

class NetworkBarItem: CustomButtonTouchBarItem, Widget {
    static var name: String = "network"
    static var identifier: String = "com.toxblh.mtmr.network"
    
    private let flip: Bool
    private let units: String
    private var pipe: Pipe?
    private var outputHandle: FileHandle?
    private var bandwidthProcess: Process?
    private var dataAvailableObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var pendingOutput = Data()
    
    init(identifier: NSTouchBarItem.Identifier, flip: Bool = false, units: String) {
        self.flip = flip
        self.units = units
        super.init(identifier: identifier, title: " ")
        startMonitoringProcess()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startMonitoringProcess() {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["netstat", "-w1", "-l", "en0"]
        process.standardOutput = pipe
        let outputHandle = pipe.fileHandleForReading
        self.pipe = pipe
        self.outputHandle = outputHandle
        self.bandwidthProcess = process

        dataAvailableObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSFileHandleDataAvailable,
            object: outputHandle,
            queue: .main
        ) { [weak self] _ in
            self?.readAvailableNetworkData()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: process,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stopMonitoringProcess(terminate: false)
        }

        outputHandle.waitForDataInBackgroundAndNotify(forModes: [RunLoop.Mode.common])
        do {
            try process.run()
        } catch {
            stopMonitoringProcess(terminate: false)
            NSLog("Could not start network monitor: %@", error.localizedDescription)
        }
    }

    private func readAvailableNetworkData() {
        guard let outputHandle else { return }
        let data = outputHandle.availableData
        guard !data.isEmpty else {
            // EOF can arrive before the process termination notification. Close
            // the owned child here as well so its lifetime never depends on
            // which notification reaches the main queue first.
            stopMonitoringProcess(terminate: true)
            return
        }
        pendingOutput.append(data)
        // netstat emits a header and one row per interval. Process complete
        // lines only, and cap retained data if an unexpected producer floods
        // the pipe without line breaks.
        if pendingOutput.count > 16_384 {
            pendingOutput.removeAll(keepingCapacity: true)
        } else if let text = String(data: pendingOutput, encoding: .utf8),
                  let lastNewline = text.lastIndex(of: "\n") {
            let complete = text[..<lastNewline]
            pendingOutput = Data(text[text.index(after: lastNewline)...].utf8)
            for line in complete.split(whereSeparator: \.isNewline) {
                let columns = line.split(whereSeparator: \.isWhitespace)
                if columns.count >= 6, let down = UInt64(columns[2]), let up = UInt64(columns[5]) {
                    setTitle(up: getHumanizeSize(speed: up), down: getHumanizeSize(speed: down))
                }
            }
        }
        outputHandle.waitForDataInBackgroundAndNotify(forModes: [RunLoop.Mode.common])
    }

    private func stopMonitoringProcess(terminate: Bool) {
        if let observer = dataAvailableObserver {
            NotificationCenter.default.removeObserver(observer)
            dataAvailableObserver = nil
        }
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
            terminationObserver = nil
        }
        if terminate, let process = bandwidthProcess, process.isRunning {
            process.terminate()
        }
        try? outputHandle?.close()
        outputHandle = nil
        pipe = nil
        bandwidthProcess = nil
    }

    deinit {
        stopMonitoringProcess(terminate: true)
    }

    func getHumanizeSize(speed: UInt64) -> String {
        let humanText: String
        
        func speedB(speed: UInt64)-> String {
            return String(format: "%.0f", Double(speed)) + " B/s"
        }
        
        func speedKB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / 1024) + " KB/s"
        }
        
        func speedMB(speed: UInt64)-> String {
            return String(format: "%.1f", Double(speed) / (1024 * 1024)) + " MB/s"
        }
        
        func speedGB(speed: UInt64)-> String {
            return String(format: "%.2f", Double(speed) / (1024 * 1024 * 1024)) + " GB/s"
        }
        
        switch self.units {
        case "B/s":
            humanText = speedB(speed: speed)
        case "KB/s":
            humanText = speedKB(speed: speed)
        case "MB/s":
            humanText = speedMB(speed: speed)
        case "GB/s":
            humanText = speedGB(speed: speed)
        default:
            if speed < 1024 {
                humanText = speedB(speed: speed)
            } else if speed < (1024 * 1024) {
                humanText = speedKB(speed: speed)
            } else if speed < (1024 * 1024 * 1024) {
                humanText = speedMB(speed: speed)
            } else {
                humanText = speedGB(speed: speed)
            }
        }

        return humanText
    }
    
    func appendUpSpeed(appendString: NSMutableAttributedString, up: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↑" : "↑",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.blue,
                NSAttributedString.Key.font: titleFont,
                ]))
        
        appendString.append(NSMutableAttributedString(
            string: up,
            attributes: [
                NSAttributedString.Key.font: titleFont,
                ]))
    }
    
    func appendDownSpeed(appendString: NSMutableAttributedString, down: String, titleFont: NSFont, newStr: Bool = false) {
        appendString.append(NSMutableAttributedString(
            string: newStr ? "\n↓" : "↓",
            attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.red,
                NSAttributedString.Key.font: titleFont,
                ]))
            
            appendString.append(NSMutableAttributedString(
                string: down,
                attributes: [
                    NSAttributedString.Key.font: titleFont
                ]))
    }
    
    func setTitle(up: String, down: String) {
        let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: NSFont.Weight.light)
        
        let newTitle: NSMutableAttributedString = NSMutableAttributedString(string: "")
        
        if (self.flip) {
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont)
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont, newStr: true)
        } else {
            appendDownSpeed(appendString: newTitle, down: down, titleFont: titleFont)
            appendUpSpeed(appendString: newTitle, up: up, titleFont: titleFont, newStr: true)
        }
        
        
        self.attributedTitle = newTitle
    }
}
