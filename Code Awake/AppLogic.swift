//
//  AppLogic.swift
//  Code Awake
//
//  Created by Codex on 26.05.2026.
//

import Foundation

struct BatteryProtectionPolicy {
    let lowBatteryThreshold: Int

    func shouldPauseAwakeMode(percent: Int, isOnBatteryPower: Bool) -> Bool {
        isOnBatteryPower && percent <= lowBatteryThreshold
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
        keepAwakeEnabled && !allowLockAndSleepEnabled
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

enum RuntimeEnvironment {
    static func isRunningTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
