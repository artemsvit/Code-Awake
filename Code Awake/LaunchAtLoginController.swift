//
//  LaunchAtLoginController.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import Foundation
import Combine
import ServiceManagement

final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            errorMessage = nil
        } catch {
            errorMessage = "Unable to update login item."
        }

        refresh()
    }

    private func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
