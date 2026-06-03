//
//  AppLogicTests.swift
//  Code Awake Tests
//
//  Created by Codex on 26.05.2026.
//

import XCTest
@testable import Code_Awake

final class AppLogicTests: XCTestCase {
    func testAwakeAssertionPolicyLetsMacOSLockAndDisplaySleepWhenEnabled() {
        let policy = AwakeAssertionPolicy()

        XCTAssertEqual(
            policy.activeAssertions(allowLockAndSleepEnabled: true),
            [
                AwakePowerAssertion(
                    type: "PreventUserIdleSystemSleep",
                    reason: "Code Awake - Prevent idle system sleep"
                ),
                AwakePowerAssertion(
                    type: "NetworkClientActive",
                    reason: "Code Awake - Keep network clients active"
                )
            ]
        )
    }

    func testAwakeAssertionPolicyBlocksDisplaySleepAndLockTimingWhenDisabled() {
        let policy = AwakeAssertionPolicy()

        XCTAssertEqual(
            policy.activeAssertions(allowLockAndSleepEnabled: false),
            [
                AwakePowerAssertion(
                    type: "PreventUserIdleSystemSleep",
                    reason: "Code Awake - Prevent idle system sleep"
                ),
                AwakePowerAssertion(
                    type: "NetworkClientActive",
                    reason: "Code Awake - Keep network clients active"
                ),
                AwakePowerAssertion(
                    type: "PreventUserIdleDisplaySleep",
                    reason: "Code Awake - Prevent display sleep and lock timing"
                )
            ]
        )
    }

    func testAwakeAssertionPolicyDoesNotUseDeprecatedAssertionTypes() {
        let policy = AwakeAssertionPolicy()
        let assertionTypes = Set(
            policy.activeAssertions(allowLockAndSleepEnabled: true).map(\.type)
                + policy.activeAssertions(allowLockAndSleepEnabled: false).map(\.type)
        )

        XCTAssertFalse(assertionTypes.contains("PreventSystemSleep"))
        XCTAssertFalse(assertionTypes.contains("NoDisplaySleepAssertion"))
    }

    func testBatteryProtectionPausesOnlyLowBatteryPower() {
        let policy = BatteryProtectionPolicy(lowBatteryThreshold: 10)

        XCTAssertTrue(policy.shouldPauseAwakeMode(percent: 10, isOnBatteryPower: true))
        XCTAssertTrue(policy.shouldPauseAwakeMode(percent: 5, isOnBatteryPower: true))
        XCTAssertFalse(policy.shouldPauseAwakeMode(percent: 11, isOnBatteryPower: true))
        XCTAssertFalse(policy.shouldPauseAwakeMode(percent: 5, isOnBatteryPower: false))
        XCTAssertEqual(policy.pauseMessage, "Paused: Battery below 10%.")
    }

    func testBatteryProtectionKeepsMonitoringWhilePauseMessageIsVisible() {
        let policy = BatteryProtectionPolicy(lowBatteryThreshold: 10)

        XCTAssertTrue(policy.shouldMonitorBattery(keepAwakeEnabled: true, errorMessage: nil))
        XCTAssertTrue(policy.shouldMonitorBattery(keepAwakeEnabled: false, errorMessage: policy.pauseMessage))
        XCTAssertFalse(policy.shouldMonitorBattery(keepAwakeEnabled: false, errorMessage: nil))
        XCTAssertFalse(policy.shouldMonitorBattery(keepAwakeEnabled: false, errorMessage: "Unable to keep awake."))
    }

    func testBatteryProtectionClearsPauseMessageAfterRecovery() {
        let policy = BatteryProtectionPolicy(lowBatteryThreshold: 10)

        XCTAssertTrue(policy.shouldClearPauseMessage(percent: 11, isOnBatteryPower: true, currentMessage: policy.pauseMessage))
        XCTAssertTrue(policy.shouldClearPauseMessage(percent: 5, isOnBatteryPower: false, currentMessage: policy.pauseMessage))
        XCTAssertFalse(policy.shouldClearPauseMessage(percent: 10, isOnBatteryPower: true, currentMessage: policy.pauseMessage))
        XCTAssertFalse(policy.shouldClearPauseMessage(percent: 11, isOnBatteryPower: true, currentMessage: "Unable to keep awake."))
    }

    func testDisplayDimPolicyOnlyRunsWhenLockSleepIsOff() {
        let policy = DisplayDimPolicy(
            dimDelay: 60,
            activityRestoreIdleThreshold: 1.5,
            minimumRescheduleDelay: 0.5
        )

        XCTAssertTrue(policy.shouldManageDimming(keepAwakeEnabled: true, allowLockAndSleepEnabled: false))
        XCTAssertFalse(policy.shouldManageDimming(keepAwakeEnabled: true, allowLockAndSleepEnabled: true))
        XCTAssertFalse(policy.shouldManageDimming(keepAwakeEnabled: false, allowLockAndSleepEnabled: false))
    }

    func testDisplayDimPolicyCanBeDisabled() {
        let policy = DisplayDimPolicy(
            dimDelay: 0,
            activityRestoreIdleThreshold: 1.5,
            minimumRescheduleDelay: 0.5
        )

        XCTAssertFalse(policy.shouldManageDimming(keepAwakeEnabled: true, allowLockAndSleepEnabled: false))
    }

    func testDisplayDimPolicyWaitsForOneMinuteOfRealIdleTime() {
        let policy = DisplayDimPolicy(
            dimDelay: 60,
            activityRestoreIdleThreshold: 1.5,
            minimumRescheduleDelay: 0.5
        )

        XCTAssertFalse(policy.shouldDimNow(currentIdleTime: 20))
        XCTAssertTrue(policy.shouldDimNow(currentIdleTime: 60))
        XCTAssertTrue(policy.shouldDimNow(currentIdleTime: nil))
        XCTAssertEqual(policy.delayUntilDim(currentIdleTime: 20), 40)
        XCTAssertEqual(policy.delayUntilDim(currentIdleTime: 59.8), 0.5)
        XCTAssertEqual(policy.delayUntilDim(currentIdleTime: nil), 60)
    }

    func testDisplayDimPolicyRestoresOnlyAfterActivityWhileDimmed() {
        let policy = DisplayDimPolicy(
            dimDelay: 60,
            activityRestoreIdleThreshold: 1.5,
            minimumRescheduleDelay: 0.5
        )

        XCTAssertTrue(policy.shouldRestoreBrightness(hasStoredBrightness: true, currentIdleTime: 0.4))
        XCTAssertFalse(policy.shouldRestoreBrightness(hasStoredBrightness: true, currentIdleTime: 3))
        XCTAssertFalse(policy.shouldRestoreBrightness(hasStoredBrightness: false, currentIdleTime: 0.4))
        XCTAssertFalse(policy.shouldRestoreBrightness(hasStoredBrightness: true, currentIdleTime: nil))
        XCTAssertTrue(policy.shouldRestoreDimming(isDimmed: true, currentIdleTime: 0.4))
        XCTAssertFalse(policy.shouldRestoreDimming(isDimmed: true, currentIdleTime: 3))
        XCTAssertFalse(policy.shouldRestoreDimming(isDimmed: false, currentIdleTime: 0.4))
        XCTAssertFalse(policy.shouldRestoreDimming(isDimmed: true, currentIdleTime: nil))
    }

    func testAutoTurnOffLabels() {
        XCTAssertEqual(AutoTurnOffFormatter.optionLabel(for: 0), "Infinity")
        XCTAssertEqual(AutoTurnOffFormatter.optionLabel(for: 30), "After 30 min")
        XCTAssertEqual(AutoTurnOffFormatter.optionLabel(for: 60), "After 1h")
        XCTAssertEqual(AutoTurnOffFormatter.optionLabel(for: 90), "After 1h 30m")
        XCTAssertEqual(AutoTurnOffFormatter.shortLabel(for: 120), "2h")
        XCTAssertEqual(AutoTurnOffFormatter.countdownLabel(for: 65), "1:05")
        XCTAssertEqual(AutoTurnOffFormatter.countdownLabel(for: 3661), "1:01:01")
        XCTAssertEqual(AutoTurnOffFormatter.countdownLabel(for: -5), "0:00")
    }

    func testDisplayDimDelayLabels() {
        XCTAssertEqual(DisplayDimDelayFormatter.optionLabel(for: 0), "Off")
        XCTAssertEqual(DisplayDimDelayFormatter.optionLabel(for: 1), "Dim display after 1 min")
        XCTAssertEqual(DisplayDimDelayFormatter.optionLabel(for: 5), "Dim display after 5 min")
        XCTAssertEqual(DisplayDimDelayFormatter.optionLabel(for: 15), "Dim display after 15 min")
        XCTAssertEqual(DisplayDimDelayFormatter.optionLabel(for: 30), "Dim display after 30 min")
    }

    func testRuntimeEnvironmentDetectsXCTest() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]))
        XCTAssertFalse(RuntimeEnvironment.isRunningTests(environment: [:]))
    }
}
