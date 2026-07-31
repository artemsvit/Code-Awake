//
//  AppLogic.swift
//  Code Awake
//
//  Created by Codex on 26.05.2026.
//

import Foundation

struct AwakePowerAssertion: Equatable {
    let type: String
    let reason: String
}

struct AwakeAssertionPolicy {
    private let systemAssertions = [
        AwakePowerAssertion(
            type: "PreventUserIdleSystemSleep",
            reason: "Code Awake - Prevent idle system sleep"
        ),
        AwakePowerAssertion(
            type: "NetworkClientActive",
            reason: "Code Awake - Keep network clients active"
        )
    ]

    private let displayAssertions = [
        AwakePowerAssertion(
            type: "PreventUserIdleDisplaySleep",
            reason: "Code Awake - Prevent display sleep and lock timing"
        )
    ]

    private let closedLidAssertion = AwakePowerAssertion(
        type: "PreventSystemSleep",
        reason: "Code Awake - Best-effort closed lid mode"
    )

    func activeAssertions(
        allowLockAndSleepEnabled: Bool,
        allowClosedLidEnabled: Bool = false
    ) -> [AwakePowerAssertion] {
        let baseAssertions = allowLockAndSleepEnabled ? systemAssertions : systemAssertions + displayAssertions
        return allowClosedLidEnabled ? baseAssertions + [closedLidAssertion] : baseAssertions
    }
}

struct BatteryProtectionPolicy {
    let lowBatteryThreshold: Int

    func shouldPauseAwakeMode(percent: Int, isOnBatteryPower: Bool) -> Bool {
        isOnBatteryPower && percent <= lowBatteryThreshold
    }

    func shouldMonitorBattery(keepAwakeEnabled: Bool, errorMessage: String?) -> Bool {
        keepAwakeEnabled || errorMessage == pauseMessage
    }

    func shouldClearPauseMessage(percent: Int, isOnBatteryPower: Bool, currentMessage: String?) -> Bool {
        currentMessage == pauseMessage && !shouldPauseAwakeMode(percent: percent, isOnBatteryPower: isOnBatteryPower)
    }

    var pauseMessage: String {
        "Paused: Battery below \(lowBatteryThreshold)%."
    }
}

struct DisplayDimPolicy {
    let dimDelay: TimeInterval
    let activityRestoreIdleThreshold: TimeInterval
    let minimumRescheduleDelay: TimeInterval

    func shouldManageDimming(keepAwakeEnabled: Bool, allowLockAndSleepEnabled: Bool) -> Bool {
        keepAwakeEnabled && !allowLockAndSleepEnabled && dimDelay > 0
    }

    func delayUntilDim(currentIdleTime: TimeInterval?) -> TimeInterval {
        guard let currentIdleTime else {
            return dimDelay
        }

        return max(minimumRescheduleDelay, dimDelay - currentIdleTime)
    }

    func shouldDimNow(currentIdleTime: TimeInterval?) -> Bool {
        guard let currentIdleTime else {
            return true
        }

        return currentIdleTime >= dimDelay
    }

    func shouldRestoreBrightness(hasStoredBrightness: Bool, currentIdleTime: TimeInterval?) -> Bool {
        guard hasStoredBrightness, let currentIdleTime else {
            return false
        }

        return currentIdleTime <= activityRestoreIdleThreshold
    }

    func shouldRestoreDimming(isDimmed: Bool, currentIdleTime: TimeInterval?) -> Bool {
        guard isDimmed, let currentIdleTime else {
            return false
        }

        return currentIdleTime <= activityRestoreIdleThreshold
    }
}

struct AutoOffDeadlinePolicy {
    let notificationLeadTime: TimeInterval = 5 * 60

    func endDate(startingAt date: Date, minutes: Int) -> Date? {
        guard minutes > 0 else {
            return nil
        }

        return date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func remainingSeconds(until endDate: Date, now: Date) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSince(now))))
    }

    func warningDelay(until endDate: Date, now: Date) -> TimeInterval? {
        let delay = endDate.timeIntervalSince(now) - notificationLeadTime
        return delay > 0 ? delay : nil
    }

    func extending(endDate: Date?, by seconds: TimeInterval, now: Date) -> Date {
        max(endDate ?? now, now).addingTimeInterval(seconds)
    }
}

enum AutoTurnOffFormatter {
    static func optionLabel(for minutes: Int) -> String {
        guard minutes > 0 else {
            return "Infinity"
        }

        return "After \(durationLabel(for: minutes))"
    }

    static func shortLabel(for minutes: Int) -> String {
        guard minutes > 0 else {
            return "Infinity"
        }

        return durationLabel(for: minutes)
    }

    static func countdownLabel(for seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let remainingSeconds = safeSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        }

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private static func durationLabel(for minutes: Int) -> String {
        guard minutes >= 60 else {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainingMinutes)m"
    }
}

enum DisplayDimDelayFormatter {
    static func optionLabel(for minutes: Int) -> String {
        guard minutes > 0 else {
            return "Off"
        }

        return "Dim display after \(durationLabel(for: minutes))"
    }

    private static func durationLabel(for minutes: Int) -> String {
        minutes == 1 ? "1 min" : "\(minutes) min"
    }
}

enum RuntimeEnvironment {
    static func isRunningTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
