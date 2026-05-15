//
//  AwakeController.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import Foundation
import Combine
import IOKit.pwr_mgt

final class AwakeController: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        keepAwakeEnabled
    }

    private let keepAwakeDefaultsKey = "keepAwakeEnabled"
    private var assertionIDs: [IOPMAssertionID] = []
    private let assertions: [(type: String, reason: CFString)] = [
        (kIOPMAssertionTypePreventSystemSleep, "Code Awake - Prevent system sleep" as CFString),
        (kIOPMAssertPreventUserIdleSystemSleep, "Code Awake - Prevent idle system sleep" as CFString),
        (kIOPMAssertPreventUserIdleDisplaySleep, "Code Awake - Prevent display sleep" as CFString),
        (kIOPMAssertNetworkClientActive, "Code Awake - Keep network clients active" as CFString)
    ]

    init() {
        keepAwakeEnabled = UserDefaults.standard.bool(forKey: keepAwakeDefaultsKey)
        _ = updateAssertions()
    }

    deinit {
        releaseAssertions()
    }

    @discardableResult
    func setKeepAwakeEnabled(_ isEnabled: Bool) -> Bool {
        keepAwakeEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: keepAwakeDefaultsKey)
        return updateAssertions()
    }

    private func updateAssertions() -> Bool {
        if isEnabled {
            let didCreateAssertions = createAssertions()

            if !didCreateAssertions {
                keepAwakeEnabled = false
                UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
            }

            return didCreateAssertions
        }

        releaseAssertions()
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
}
