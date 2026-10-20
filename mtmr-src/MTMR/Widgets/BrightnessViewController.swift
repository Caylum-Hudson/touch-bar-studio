import AppKit
import AVFoundation
import Cocoa
import CoreAudio
import CoreGraphics
import Darwin

/// Resolves the display that the brightness slider controls. Keeping selection
/// separate makes the built-in display preference easy to exercise without
/// writing a brightness value during diagnostics.
enum BrightnessDisplaySelection {
    static func builtInDisplay(from displayIDs: [CGDirectDisplayID], isBuiltIn: (CGDirectDisplayID) -> Bool) -> CGDirectDisplayID? {
        displayIDs.first(where: isBuiltIn)
    }
}

/// Private DisplayServices ABI also used by nriley/brightness and Hammerspoon:
/// int GetBrightness(CGDirectDisplayID, float *), int SetBrightness(CGDirectDisplayID, float).
/// Load optionally so unsupported systems can report unavailability safely.
private enum DisplayBrightnessService {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    static let get: Get? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    static let set: Set? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }
}

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private(set) var lastBrightnessStatus = "Brightness has not been read yet"
    private var timer: Timer?
    var currentBrightness: Float? { readBrightness() }

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)

        sliderItem = image.map(CustomSlider.init(knob:)) ?? CustomSlider()
        sliderItem.target = self
        sliderItem.action = #selector(sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        let initialBrightness = readBrightness()
        sliderItem.floatValue = (initialBrightness ?? 0) * 100
        sliderItem.isEnabled = initialBrightness != nil
        sliderItem.toolTip = initialBrightness == nil ? lastBrightnessStatus : "Adjust display brightness"
        sliderItem.setAccessibilityHelp(sliderItem.toolTip)
        view = sliderItem

        let safeInterval = refreshInterval.isFinite ? max(0.2, refreshInterval) : 1.0
        timer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: true) { [weak self] _ in
            self?.updateBrightnessSlider()
        }
        if let timer = timer { RunLoop.current.add(timer, forMode: .common) }
    }

    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
        sliderItem.unbind(NSBindingName.value)
    }

    @objc func updateBrightnessSlider() {
        DispatchQueue.main.async {
            if let brightness = self.readBrightness() {
                self.sliderItem.floatValue = brightness * 100
                self.sliderItem.isEnabled = true
                self.sliderItem.toolTip = "Adjust display brightness"
            } else {
                self.sliderItem.isEnabled = false
                self.sliderItem.toolTip = self.lastBrightnessStatus
            }
            self.sliderItem.setAccessibilityHelp(self.sliderItem.toolTip)
        }
    }

    @objc func sliderValueChanged(_ sender: Any) {
        guard let slider = sender as? NSSlider else { return }
        writeBrightness(level: Float(slider.doubleValue / 100))
    }

    /// Explicit write hook for a reversible brightness round-trip check.
    /// Callers should save `currentBrightness` first and restore that value.
    @discardableResult
    func setBrightnessForCheck(_ level: Float) -> String {
        writeBrightness(level: level)
        return lastBrightnessStatus
    }

    /// Read-only diagnostic reports the selected display and service result.
    func brightnessDiagnostic() -> String {
        _ = readBrightness()
        return lastBrightnessStatus
    }

    private func readBrightness() -> Float? {
        guard let displayID = activeBuiltInDisplayID() else {
            lastBrightnessStatus = "No active built-in display was found"
            return nil
        }
        guard let getBrightness = DisplayBrightnessService.get else {
            lastBrightnessStatus = "DisplayServices brightness reading is unavailable"
            return nil
        }
        var value: Float = 0
        let result = getBrightness(displayID, &value)
        guard result == 0, value.isFinite, (0.0...1.0).contains(value) else {
            lastBrightnessStatus = "DisplayServices read failed for display \(displayID): code \(result), value \(value)"
            return nil
        }
        lastBrightnessStatus = "DisplayServices read brightness \(value) from built-in display \(displayID)"
        return value
    }

    private func writeBrightness(level: Float) {
        guard let displayID = activeBuiltInDisplayID(), level.isFinite else {
            lastBrightnessStatus = "Write skipped: no built-in display or invalid brightness"
            return
        }
        guard let setBrightness = DisplayBrightnessService.set else {
            lastBrightnessStatus = "DisplayServices brightness writing is unavailable"
            sliderItem.toolTip = lastBrightnessStatus
            sliderItem.setAccessibilityHelp(lastBrightnessStatus)
            return
        }
        let clampedLevel = min(max(level, 0), 1)
        let result = setBrightness(displayID, clampedLevel)
        let actual = readBrightness()
        if result != 0 {
            lastBrightnessStatus = "DisplayServices write failed for display \(displayID): code \(result)"
        } else if let actual = actual, abs(actual - clampedLevel) <= 0.02 {
            lastBrightnessStatus = "DisplayServices wrote \(clampedLevel) to built-in display \(displayID); read back \(actual)"
        } else {
            lastBrightnessStatus = "DisplayServices accepted write to display \(displayID); requested value has not read back"
        }
        sliderItem.isEnabled = actual != nil
        sliderItem.toolTip = lastBrightnessStatus
        sliderItem.setAccessibilityHelp(lastBrightnessStatus)
    }

    private func activeBuiltInDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        let firstResult = CGGetActiveDisplayList(0, nil, &displayCount)
        guard firstResult == .success, displayCount > 0 else { return nil }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let secondResult = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        guard secondResult == .success else { return nil }
        return BrightnessDisplaySelection.builtInDisplay(from: Array(displayIDs.prefix(Int(displayCount))), isBuiltIn: { CGDisplayIsBuiltin($0) != 0 })
    }

}
