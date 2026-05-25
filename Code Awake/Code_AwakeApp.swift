//
//  Code_AwakeApp.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import SwiftUI
import AppKit
import Sparkle

@main
struct Code_AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var awakeController = AwakeController()
    @StateObject private var launchAtLoginController = LaunchAtLoginController()
    private let menuBarSymbolPointSize: CGFloat = 14
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            CodeAwakeMenuPanel(
                awakeController: awakeController,
                launchAtLoginController: launchAtLoginController,
                updateAction: { updaterController.checkForUpdates(nil) },
                lockScreenAction: lockScreenNow,
                donateAction: openDonatePage,
                quitAction: { NSApp.terminate(nil) }
            )
        } label: {
            Image(nsImage: Self.makeStatusBarIcon(
                enabled: awakeController.isEnabled,
                size: menuBarSymbolPointSize
            ))
            .resizable()
            .frame(width: menuBarSymbolPointSize, height: menuBarSymbolPointSize)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .newItem) { }
        }
    }

    private var menuTitle: String {
        "Keep Mac Awake"
    }

    private static func makeStatusBarIcon(enabled: Bool, size: CGFloat) -> NSImage {
        let symbolName = enabled ? "cup.and.saucer.fill" : "cup.and.saucer"
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let icon = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Keep Mac Awake"
        )?.withSymbolConfiguration(configuration) ?? NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Keep Mac Awake"
        ) ?? NSImage()

        icon.size = CGSize(width: size, height: size)
        icon.isTemplate = true
        return icon
    }

    private func openDonatePage() {
        guard let url = URL(string: "https://www.paypal.com/donate/?hosted_button_id=FF9ZWWCQR6X2W") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func lockScreenNow() {
        launchSystemTool("/usr/bin/open", arguments: ["-a", "ScreenSaverEngine"])
        launchSystemTool(
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            arguments: ["-suspend"]
        )
    }

    private func launchSystemTool(_ path: String, arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        try? process.run()
    }
}

private struct CodeAwakeMenuPanel: View {
    @ObservedObject var awakeController: AwakeController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @State private var updateIconRotation = 0.0

    let updateAction: () -> Void
    let lockScreenAction: () -> Void
    let donateAction: () -> Void
    let quitAction: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            MenuToggleRow(
                isEnabled: awakeController.keepAwakeEnabled,
                title: "Keep Mac Awake",
                icon: awakeController.keepAwakeEnabled ? "cup.and.saucer.fill" : "cup.and.saucer",
                action: { awakeController.setKeepAwakeEnabled(!awakeController.keepAwakeEnabled) }
            )

            MenuLockSleepRow(
                isEnabled: awakeController.preventLockAndSleepEnabled,
                toggleAction: {
                    awakeController.setPreventLockAndSleepEnabled(!awakeController.preventLockAndSleepEnabled)
                },
                lockAction: lockScreenAction
            )

            if let errorMessage = awakeController.errorMessage {
                MenuErrorText(errorMessage)
            }

            MenuTimerRow(
                title: "Auto Turn Off",
                icon: "timer",
                isKeepAwakeEnabled: awakeController.keepAwakeEnabled,
                selectedMinutes: awakeController.keepAwakeOffTimerMinutes,
                remainingSeconds: awakeController.keepAwakeRemainingSeconds,
                options: AwakeController.offTimerOptions,
                action: { selectedMinutes in
                    awakeController.setKeepAwakeOffTimerMinutes(selectedMinutes)
                }
            )

            Divider()
                .overlay(.white.opacity(0.10))

            MenuToggleRow(
                isEnabled: launchAtLoginController.isEnabled,
                title: "Launch at Login",
                icon: "arrow.up.forward.app",
                iconScale: 1.16,
                action: { launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled) }
            )

            if let errorMessage = launchAtLoginController.errorMessage {
                MenuErrorText(errorMessage)
            }

            MenuActionRow(
                title: "Check for Updates",
                icon: "arrow.triangle.2.circlepath",
                iconRotation: updateIconRotation,
                action: checkForUpdates
            )
            MenuActionRow(title: "Buy Me a Coffee", icon: "cup.and.heat.waves", action: donateAction)
            MenuActionRow(title: "Quit Code Awake", icon: "power", action: quitAction)
        }
        .padding(9)
        .frame(width: 268)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color(red: 0.13, green: 0.09, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func checkForUpdates() {
        withAnimation(.linear(duration: 0.7)) {
            updateIconRotation += 360
        }

        updateAction()
    }
}

private struct MenuToggleRow: View {
    let isEnabled: Bool
    let title: String
    let icon: String
    var iconScale = 1.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .scaleEffect(iconScale)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                AwakeSwitch(isEnabled: isEnabled)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        isEnabled ? Color(red: 1.0, green: 0.62, blue: 0.52) : .white.opacity(0.70)
    }
}

private struct MenuLockSleepRow: View {
    let isEnabled: Bool
    let toggleAction: () -> Void
    let lockAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: toggleAction) {
                HStack(spacing: 9) {
                    Image(systemName: "lock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 24)

                    Text("Lock & Sleep")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            if isEnabled {
                Button(action: lockAction) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Button(action: toggleAction) {
                AwakeSwitch(isEnabled: isEnabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 36)
        .animation(.easeOut(duration: 0.16), value: isEnabled)
    }

    private var iconColor: Color {
        isEnabled ? Color(red: 1.0, green: 0.62, blue: 0.52) : .white.opacity(0.70)
    }
}

private struct AwakeSwitch: View {
    let isEnabled: Bool

    var body: some View {
        ZStack(alignment: isEnabled ? .trailing : .leading) {
            Group {
                if isEnabled {
                    LinearGradient(
                        colors: [
                            Color(red: 0.84, green: 0.49, blue: 0.92),
                            Color(red: 0.98, green: 0.78, blue: 0.58)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.secondary.opacity(0.18)
                }
            }
            .clipShape(Capsule())

            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .padding(3)
                .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
        }
        .frame(width: 36, height: 20)
    }
}

private struct MenuActionRow: View {
    let title: String
    let icon: String
    var iconRotation = 0.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .rotationEffect(.degrees(iconRotation))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MenuTimerRow: View {
    let title: String
    let icon: String
    let isKeepAwakeEnabled: Bool
    let selectedMinutes: Int
    let remainingSeconds: Int
    let options: [Int]
    let action: (Int) -> Void

    private var hasActiveTimer: Bool {
        selectedMinutes > 0
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { minutes in
                Button(action: { action(minutes) }) {
                    Text(self.optionLabel(for: minutes))
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(hasActiveTimer ? Color(red: 1.0, green: 0.62, blue: 0.52) : .white.opacity(0.72))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                Text(statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusLabel: String {
        guard isKeepAwakeEnabled, remainingSeconds > 0 else {
            return shortLabel(for: selectedMinutes)
        }

        return countdownLabel(for: remainingSeconds)
    }

    private func optionLabel(for minutes: Int) -> String {
        guard minutes > 0 else {
            return "Infinity"
        }

        return "After \(durationLabel(for: minutes))"
    }

    private func shortLabel(for minutes: Int) -> String {
        guard minutes > 0 else {
            return "Infinity"
        }

        return durationLabel(for: minutes)
    }

    private func countdownLabel(for seconds: Int) -> String {
        let hours = max(0, seconds) / 3600
        let minutes = (max(0, seconds) % 3600) / 60
        let remainingSeconds = max(0, seconds) % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        }

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private func durationLabel(for minutes: Int) -> String {
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

private struct MenuErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.56))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hasCompletedWelcomeKey = "hasCompletedWelcome"
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !UserDefaults.standard.bool(forKey: hasCompletedWelcomeKey) else {
            return
        }

        showWelcomeWindow()
    }

    private func showWelcomeWindow() {
        let welcomeView = WelcomeView { [weak self] in
            UserDefaults.standard.set(true, forKey: self?.hasCompletedWelcomeKey ?? "hasCompletedWelcome")
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Code Awake"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1.0)

        let hostingView = NSHostingView(rootView: welcomeView.frame(maxWidth: .infinity, maxHeight: .infinity))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
