//
//  Code_AwakeApp.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import SwiftUI
import AppKit

@main
struct Code_AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var awakeController = AwakeController()
    @StateObject private var launchAtLoginController = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            CodeAwakeMenuPanel(
                awakeController: awakeController,
                launchAtLoginController: launchAtLoginController,
                donateAction: openDonatePage,
                quitAction: { NSApp.terminate(nil) }
            )
        } label: {
            Image(systemName: awakeController.isEnabled ? "cup.and.saucer.fill" : "cup.and.saucer")
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

    private func openDonatePage() {
        guard let url = URL(string: "https://www.paypal.com/donate/?hosted_button_id=FF9ZWWCQR6X2W") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct CodeAwakeMenuPanel: View {
    @ObservedObject var awakeController: AwakeController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    let donateAction: () -> Void
    let quitAction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            MenuToggleRow(
                isEnabled: awakeController.isEnabled,
                title: "Keep Mac Awake",
                icon: awakeController.isEnabled ? "cup.and.saucer.fill" : "cup.and.saucer",
                action: { awakeController.setEnabled(!awakeController.isEnabled) }
            )

            if let errorMessage = awakeController.errorMessage {
                MenuErrorText(errorMessage)
            }

            Divider()
                .overlay(.white.opacity(0.10))

            MenuToggleRow(
                isEnabled: launchAtLoginController.isEnabled,
                title: "Launch at Login",
                icon: "restart.circle",
                action: { launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled) }
            )

            if let errorMessage = launchAtLoginController.errorMessage {
                MenuErrorText(errorMessage)
            }

            MenuActionRow(title: "Buy Me a Coffee", icon: "cup.and.saucer", action: donateAction)
            MenuActionRow(title: "Quit Code Awake", icon: "power", action: quitAction)
        }
        .padding(12)
        .frame(width: 286)
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
}

private struct MenuToggleRow: View {
    let isEnabled: Bool
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color(red: 1.0, green: 0.62, blue: 0.52) : .white.opacity(0.70))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 16)

                AwakeSwitch(isEnabled: isEnabled)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.white.opacity(isEnabled ? 0.08 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .frame(width: 18, height: 18)
                .padding(3)
                .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
        }
        .frame(width: 46, height: 24)
    }
}

private struct MenuActionRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MenuErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.56))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
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
