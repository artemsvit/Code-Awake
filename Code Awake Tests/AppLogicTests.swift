//
//  AppLogicTests.swift
//  Code Awake Tests
//
//  Created by Codex on 26.05.2026.
//

import XCTest
@testable import Code_Awake

final class AppLogicTests: XCTestCase {
    func testBatteryProtectionPausesOnlyLowBatteryPower() {
        let policy = BatteryProtectionPolicy(lowBatteryThreshold: 10)

        XCTAssertTrue(policy.shouldPauseAwakeMode(percent: 10, isOnBatteryPower: true))
        XCTAssertTrue(policy.shouldPauseAwakeMode(percent: 5, isOnBatteryPower: true))
        XCTAssertFalse(policy.shouldPauseAwakeMode(percent: 11, isOnBatteryPower: true))
        XCTAssertFalse(policy.shouldPauseAwakeMode(percent: 5, isOnBatteryPower: false))
        XCTAssertEqual(policy.pauseMessage, "Paused: Battery below 10%.")
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

    func testRuntimeEnvironmentDetectsXCTest() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]))
        XCTAssertFalse(RuntimeEnvironment.isRunningTests(environment: [:]))
    }
}
