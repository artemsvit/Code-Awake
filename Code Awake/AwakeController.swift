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
import IOKit.graphics

final class AwakeController: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var allowLockAndSleepEnabled = false
    @Published private(set) var keepAwakeOffTimerMinutes = 0
    @Published private(set) var keepAwakeRemainingSeconds = 0
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        keepAwakeEnabled
    }

    private let keepAwakeDefaultsKey = "keepAwakeEnabled"
    private let allowLockAndSleepDefaultsKey = "allowLockAndSleepEnabled"
    private let keepAwakeOffTimerDefaultsKey = "keepAwakeOffTimerMinutes"
    private let lowBatteryThreshold = 10
    private let displayDimDelay: TimeInterval = 60
    private let displayActivityPollInterval: TimeInterval = 0.5
    private let displayActivityRestoreIdleThreshold: TimeInterval = 1.5
    private let displayDimMinimumRescheduleDelay: TimeInterval = 0.5
    private let dimmedDisplayBrightness: Float = 0.1
    static let offTimerOptions = [0, 30, 60, 120, 180, 240, 360, 480, 720]
    private var assertionIDs: [IOPMAssertionID] = []
    private var offTimer: Timer?
    private var batteryMonitorTimer: Timer?
    private var displayDimTimer: Timer?
    private var displayActivityTimer: Timer?
    private var originalDisplayBrightnessValues: [Float]?
    private var batteryProtectionPolicy: BatteryProtectionPolicy {
        BatteryProtectionPolicy(lowBatteryThreshold: lowBatteryThreshold)
    }
    private var displayDimPolicy: DisplayDimPolicy {
        DisplayDimPolicy(
            dimDelay: displayDimDelay,
            activityRestoreIdleThreshold: displayActivityRestoreIdleThreshold,
            minimumRescheduleDelay: displayDimMinimumRescheduleDelay
        )
    }
    private let assertions: [(type: String, reason: CFString)] = [
        (kIOPMAssertionTypePreventSystemSleep, "Code Awake - Prevent system sleep" as CFString),
        (kIOPMAssertPreventUserIdleSystemSleep, "Code Awake - Prevent idle system sleep" as CFString),
        (kIOPMAssertNetworkClientActive, "Code Awake - Keep network clients active" as CFString)
    ]
    private let displaySleepAssertions: [(type: String, reason: CFString)] = [
        (kIOPMAssertionTypeNoDisplaySleep, "Code Awake - Prevent display sleep and lock timing" as CFString)
    ]

    init() {
        keepAwakeEnabled = UserDefaults.standard.bool(forKey: keepAwakeDefaultsKey)
        allowLockAndSleepEnabled = UserDefaults.standard.bool(forKey: allowLockAndSleepDefaultsKey)
        keepAwakeOffTimerMinutes = UserDefaults.standard.integer(forKey: keepAwakeOffTimerDefaultsKey)
        _ = updateAssertions()
    }

    deinit {
        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
        cancelDisplayDimTimer(restoreBrightness: true)
        stopDisplayActivityMonitor()
    }

    @discardableResult
    func setKeepAwakeEnabled(_ isEnabled: Bool) -> Bool {
        keepAwakeEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: keepAwakeDefaultsKey)
        return updateAssertions()
    }

    @discardableResult
    func setAllowLockAndSleepEnabled(_ isEnabled: Bool) -> Bool {
        allowLockAndSleepEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: allowLockAndSleepDefaultsKey)
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
                cancelDisplayDimTimer(restoreBrightness: true)
                return false
            }

            let didCreateAssertions = createAssertions()

            if !didCreateAssertions {
                keepAwakeEnabled = false
                UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
                cancelOffTimer()
                stopBatteryMonitor()
                cancelDisplayDimTimer(restoreBrightness: true)
            }

            if didCreateAssertions {
                scheduleOffTimer()
                startBatteryMonitor()
                updateDisplayDimming()
            }

            return didCreateAssertions
        }

        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
        cancelDisplayDimTimer(restoreBrightness: true)
        errorMessage = nil
        return true
    }

    private func createAssertions() -> Bool {
        releaseAssertions()

        let activeAssertions = allowLockAndSleepEnabled ? assertions : assertions + displaySleepAssertions

        for assertion in activeAssertions {
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

    private func updateDisplayDimming() {
        if displayDimPolicy.shouldManageDimming(
            keepAwakeEnabled: keepAwakeEnabled,
            allowLockAndSleepEnabled: allowLockAndSleepEnabled
        ) {
            scheduleDisplayDimTimer()
        } else {
            cancelDisplayDimTimer(restoreBrightness: true)
        }
    }

    private func scheduleDisplayDimTimer() {
        cancelDisplayDimTimer(restoreBrightness: true)

        displayDimTimer = Timer.scheduledTimer(
            withTimeInterval: displayDimPolicy.delayUntilDim(currentIdleTime: currentSystemIdleTime()),
            repeats: false
        ) { [weak self] _ in
            self?.dimDisplays()
        }
    }

    private func cancelDisplayDimTimer(restoreBrightness: Bool) {
        displayDimTimer?.invalidate()
        displayDimTimer = nil
        stopDisplayActivityMonitor()

        if restoreBrightness {
            restoreDisplayBrightness()
        }
    }

    private func dimDisplays() {
        guard displayDimPolicy.shouldManageDimming(
            keepAwakeEnabled: keepAwakeEnabled,
            allowLockAndSleepEnabled: allowLockAndSleepEnabled
        ) else {
            return
        }

        guard displayDimPolicy.shouldDimNow(currentIdleTime: currentSystemIdleTime()) else {
            scheduleDisplayDimTimer()
            return
        }

        if originalDisplayBrightnessValues == nil {
            let brightnessValues = currentDisplayBrightnessValues()

            guard !brightnessValues.isEmpty else {
                return
            }

            originalDisplayBrightnessValues = brightnessValues
        }

        setDisplayBrightness(dimmedDisplayBrightness)
        startDisplayActivityMonitor()
    }

    private func startDisplayActivityMonitor() {
        stopDisplayActivityMonitor()

        displayActivityTimer = Timer.scheduledTimer(
            withTimeInterval: displayActivityPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.restoreBrightnessAfterDisplayActivity()
        }
    }

    private func stopDisplayActivityMonitor() {
        displayActivityTimer?.invalidate()
        displayActivityTimer = nil
    }

    private func restoreBrightnessAfterDisplayActivity() {
        let hasStoredBrightness = originalDisplayBrightnessValues != nil

        guard displayDimPolicy.shouldRestoreBrightness(
            hasStoredBrightness: hasStoredBrightness,
            currentIdleTime: currentSystemIdleTime()
        ) else {
            if !hasStoredBrightness {
                stopDisplayActivityMonitor()
            }

            return
        }

        stopDisplayActivityMonitor()
        restoreDisplayBrightness()

        if displayDimPolicy.shouldManageDimming(
            keepAwakeEnabled: keepAwakeEnabled,
            allowLockAndSleepEnabled: allowLockAndSleepEnabled
        ) {
            scheduleDisplayDimTimer()
        }
    }

    private func currentSystemIdleTime() -> TimeInterval? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )

        guard service != 0 else {
            return nil
        }

        defer {
            IOObjectRelease(service)
        }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return nil
        }

        return TimeInterval(property.uint64Value) / 1_000_000_000
    }

    private func restoreDisplayBrightness() {
        guard let originalDisplayBrightnessValues else {
            return
        }

        var restoreIndex = 0

        withDisplayServices { service in
            guard restoreIndex < originalDisplayBrightnessValues.count else {
                return
            }

            var currentBrightness: Float = 0

            guard IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &currentBrightness
            ) == kIOReturnSuccess else {
                return
            }

            IODisplaySetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                originalDisplayBrightnessValues[restoreIndex]
            )
            restoreIndex += 1
        }

        self.originalDisplayBrightnessValues = nil
    }

    private func currentDisplayBrightnessValues() -> [Float] {
        var brightnessValues: [Float] = []

        withDisplayServices { service in
            var brightness: Float = 0

            guard IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &brightness
            ) == kIOReturnSuccess else {
                return
            }

            brightnessValues.append(brightness)
        }

        return brightnessValues
    }

    private func setDisplayBrightness(_ brightness: Float) {
        let clampedBrightness = min(max(brightness, 0), 1)

        withDisplayServices { service in
            IODisplaySetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                clampedBrightness
            )
        }
    }

    private func withDisplayServices(_ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )

        guard result == kIOReturnSuccess else {
            return
        }

        defer {
            IOObjectRelease(iterator)
        }

        var service = IOIteratorNext(iterator)

        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
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
        cancelDisplayDimTimer(restoreBrightness: true)
    }

    private func shouldAllowAwakeSession() -> Bool {
        guard let batteryState = currentBatteryState() else {
            return true
        }

        guard batteryProtectionPolicy.shouldPauseAwakeMode(
            percent: batteryState.percent,
            isOnBatteryPower: batteryState.isOnBatteryPower
        ) else {
            return true
        }

        errorMessage = batteryProtectionPolicy.pauseMessage
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
