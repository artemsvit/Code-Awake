//
//  AwakeController.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import Foundation
import Combine
import IOKit.pwr_mgt
import IOKit.ps

final class AwakeController: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var keepAwakeOffTimerMinutes = 0
    @Published private(set) var keepAwakeRemainingSeconds = 0
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        keepAwakeEnabled
    }

    private let keepAwakeDefaultsKey = "keepAwakeEnabled"
    private let keepAwakeOffTimerDefaultsKey = "keepAwakeOffTimerMinutes"
    private let lowBatteryThreshold = 10
    static let offTimerOptions = [0, 30, 60, 120, 180, 240, 360, 480, 720]
    private var assertionIDs: [IOPMAssertionID] = []
    private var offTimer: Timer?
    private var batteryMonitorTimer: Timer?
    private let assertions: [(type: String, reason: CFString)] = [
        (kIOPMAssertionTypePreventSystemSleep, "Code Awake - Prevent system sleep" as CFString),
        (kIOPMAssertPreventUserIdleSystemSleep, "Code Awake - Prevent idle system sleep" as CFString),
        (kIOPMAssertNetworkClientActive, "Code Awake - Keep network clients active" as CFString)
    ]

    init() {
        keepAwakeEnabled = UserDefaults.standard.bool(forKey: keepAwakeDefaultsKey)
        keepAwakeOffTimerMinutes = UserDefaults.standard.integer(forKey: keepAwakeOffTimerDefaultsKey)
        _ = updateAssertions()
    }

    deinit {
        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
    }

    @discardableResult
    func setKeepAwakeEnabled(_ isEnabled: Bool) -> Bool {
        keepAwakeEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: keepAwakeDefaultsKey)
        return updateAssertions()
    }

    func setKeepAwakeOffTimerMinutes(_ minutes: Int) {
        let clampedMinutes = max(0, minutes)
        keepAwakeOffTimerMinutes = clampedMinutes
        UserDefaults.standard.set(clampedMinutes, forKey: keepAwakeOffTimerDefaultsKey)

        if keepAwakeEnabled {
            scheduleOffTimer()
        }
    }

    private func updateAssertions() -> Bool {
        if isEnabled {
            guard shouldAllowAwakeSession() else {
                keepAwakeEnabled = false
                UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
                releaseAssertions()
                cancelOffTimer()
                stopBatteryMonitor()
                return false
            }

            let didCreateAssertions = createAssertions()

            if !didCreateAssertions {
                keepAwakeEnabled = false
                UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
                cancelOffTimer()
                stopBatteryMonitor()
            }

            if didCreateAssertions {
                scheduleOffTimer()
                startBatteryMonitor()
            }

            return didCreateAssertions
        }

        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
        errorMessage = nil
        return true
    }

    private func createAssertions() -> Bool {
        releaseAssertions()

        for assertion in assertions {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                assertion.type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                assertion.reason,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                releaseAssertions()
                errorMessage = "Unable to keep awake."
                return false
            }

            assertionIDs.append(assertionID)
        }

        errorMessage = nil
        return true
    }

    private func releaseAssertions() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    private func scheduleOffTimer() {
        cancelOffTimer()

        guard keepAwakeEnabled, keepAwakeOffTimerMinutes > 0 else {
            keepAwakeRemainingSeconds = 0
            return
        }

        keepAwakeRemainingSeconds = keepAwakeOffTimerMinutes * 60
        offTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.keepAwakeRemainingSeconds -= 1

            if self.keepAwakeRemainingSeconds <= 0 {
                _ = self.setKeepAwakeEnabled(false)
            }
        }
    }

    private func cancelOffTimer() {
        offTimer?.invalidate()
        offTimer = nil
        keepAwakeRemainingSeconds = 0
    }

    private func startBatteryMonitor() {
        stopBatteryMonitor()

        batteryMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            self?.endSessionIfBatteryIsLow()
        }
    }

    private func stopBatteryMonitor() {
        batteryMonitorTimer?.invalidate()
        batteryMonitorTimer = nil
    }

    private func endSessionIfBatteryIsLow() {
        guard keepAwakeEnabled, !shouldAllowAwakeSession() else {
            return
        }

        keepAwakeEnabled = false
        UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
    }

    private func shouldAllowAwakeSession() -> Bool {
        guard let batteryState = currentBatteryState() else {
            return true
        }

        guard batteryState.isOnBatteryPower, batteryState.percent <= lowBatteryThreshold else {
            return true
        }

        errorMessage = "Awake mode turned off because battery is below \(lowBatteryThreshold)%."
        return false
    }

    private func currentBatteryState() -> (percent: Int, isOnBatteryPower: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
                  maxCapacity > 0 else {
                continue
            }

            let percent = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            let powerSourceState = description[kIOPSPowerSourceStateKey] as? String
            return (percent, powerSourceState == kIOPSBatteryPowerValue)
        }

        return nil
    }
}
