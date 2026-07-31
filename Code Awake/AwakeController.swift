//
//  AwakeController.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import Foundation
import Combine
import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import IOKit.ps

final class AwakeController: ObservableObject {
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var allowLockAndSleepEnabled = false
    @Published private(set) var allowClosedLidEnabled = false
    @Published private(set) var keepAwakeOffTimerMinutes = 0
    @Published private(set) var keepAwakeRemainingSeconds = 0
    @Published private(set) var displayDimDelayMinutes = 1
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        keepAwakeEnabled
    }

    private let keepAwakeDefaultsKey = "keepAwakeEnabled"
    private let allowLockAndSleepDefaultsKey = "allowLockAndSleepEnabled"
    private let allowClosedLidDefaultsKey = "allowClosedLidEnabled"
    private let keepAwakeOffTimerDefaultsKey = "keepAwakeOffTimerMinutes"
    private let keepAwakeOffTimerEndDateDefaultsKey = "keepAwakeOffTimerEndDate"
    private let displayDimDelayDefaultsKey = "displayDimDelayMinutes"
    private let lowBatteryThreshold = 10
    private let displayActivityPollInterval: TimeInterval = 0.5
    private let displayActivityRestoreIdleThreshold: TimeInterval = 1.5
    private let displayDimMinimumRescheduleDelay: TimeInterval = 0.5
    private let displayDimTestStartDelay: TimeInterval = 0.75
    private let displayDimTestDuration: TimeInterval = 10
    static let offTimerOptions = [0, 30, 60, 120, 180, 240, 360, 480, 720]
    static let displayDimDelayOptions = [0, 1, 5, 15, 30]
    private var assertionIDs: [IOPMAssertionID] = []
    private var offTimer: Timer?
    private var keepAwakeOffTimerEndDate: Date?
    private var batteryMonitorTimer: Timer?
    private var displayDimTimer: Timer?
    private var displayDimTestStartTimer: Timer?
    private var displayDimTestTimer: Timer?
    private var displayActivityTimer: Timer?
    private var displayActivityObservers: [Any] = []
    private var builtInDimOverlayWindows: [NSWindow] = []
    private var screenParametersObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var batteryProtectionPolicy: BatteryProtectionPolicy {
        BatteryProtectionPolicy(lowBatteryThreshold: lowBatteryThreshold)
    }
    private let assertionPolicy = AwakeAssertionPolicy()
    private let autoOffDeadlinePolicy = AutoOffDeadlinePolicy()
    private lazy var autoOffNotificationController: AutoOffNotificationController = {
        let controller = AutoOffNotificationController()
        controller.onExtend = { [weak self] in
            self?.extendKeepAwakeSession(by: 30 * 60)
        }
        controller.onStop = { [weak self] in
            _ = self?.setKeepAwakeEnabled(false)
        }
        return controller
    }()
    private var displayDimDelay: TimeInterval {
        TimeInterval(displayDimDelayMinutes * 60)
    }
    private var displayDimPolicy: DisplayDimPolicy {
        DisplayDimPolicy(
            dimDelay: displayDimDelay,
            activityRestoreIdleThreshold: displayActivityRestoreIdleThreshold,
            minimumRescheduleDelay: displayDimMinimumRescheduleDelay
        )
    }

    init() {
        keepAwakeEnabled = UserDefaults.standard.bool(forKey: keepAwakeDefaultsKey)
        allowLockAndSleepEnabled = UserDefaults.standard.bool(forKey: allowLockAndSleepDefaultsKey)
        allowClosedLidEnabled = UserDefaults.standard.bool(forKey: allowClosedLidDefaultsKey)
        keepAwakeOffTimerMinutes = UserDefaults.standard.integer(forKey: keepAwakeOffTimerDefaultsKey)
        keepAwakeOffTimerEndDate = Self.initialOffTimerEndDate(
            defaults: UserDefaults.standard,
            key: keepAwakeOffTimerEndDateDefaultsKey
        )
        displayDimDelayMinutes = Self.initialDisplayDimDelayMinutes(
            defaults: UserDefaults.standard,
            key: displayDimDelayDefaultsKey
        )
        recoverDisplayTransferSettingsFromPreviousDimmer()
        normalizeExpiredOffTimerSession()
        autoOffNotificationController.configure()
        startAppObservers()
        _ = updateAssertions()
    }

    deinit {
        removeTerminationObserver()
        removeScreenParametersObserver()
        shutdown()
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

    @discardableResult
    func setAllowClosedLidEnabled(_ isEnabled: Bool) -> Bool {
        allowClosedLidEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: allowClosedLidDefaultsKey)
        return updateAssertions()
    }

    func setKeepAwakeOffTimerMinutes(_ minutes: Int) {
        let clampedMinutes = max(0, minutes)
        keepAwakeOffTimerMinutes = clampedMinutes
        UserDefaults.standard.set(clampedMinutes, forKey: keepAwakeOffTimerDefaultsKey)

        if keepAwakeEnabled {
            setOffTimerEndDate(autoOffDeadlinePolicy.endDate(startingAt: Date(), minutes: clampedMinutes))
            scheduleOffTimer()
        } else {
            setOffTimerEndDate(nil)
        }
    }

    func setDisplayDimDelayMinutes(_ minutes: Int) {
        let normalizedMinutes = Self.normalizedDisplayDimDelayMinutes(minutes)
        displayDimDelayMinutes = normalizedMinutes
        UserDefaults.standard.set(normalizedMinutes, forKey: displayDimDelayDefaultsKey)

        if displayDimPolicy.shouldManageDimming(
            keepAwakeEnabled: keepAwakeEnabled,
            allowLockAndSleepEnabled: allowLockAndSleepEnabled
        ) {
            scheduleDisplayDimTimer()
        } else {
            cancelDisplayDimTimer(restoreBrightness: true)
        }
    }

    func showDisplayDimOverlayForTesting() {
        cancelDisplayDimTest()
        stopDisplayActivityMonitor()

        displayDimTestStartTimer = Timer.scheduledTimer(
            withTimeInterval: displayDimTestStartDelay,
            repeats: false
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.showBuiltInDisplayDimOverlay()
            self.displayDimTestTimer = Timer.scheduledTimer(
                withTimeInterval: self.displayDimTestDuration,
                repeats: false
            ) { [weak self] _ in
                self?.hideBuiltInDisplayDimOverlay()
            }
        }
    }

    func shutdown() {
        releaseAssertions()
        cancelOffTimer()
        stopBatteryMonitor()
        cancelDisplayDimTimer(restoreBrightness: true)
        cancelDisplayDimTest()
    }

    private func updateAssertions() -> Bool {
        if isEnabled {
            guard shouldAllowAwakeSession() else {
                keepAwakeEnabled = false
                UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
                releaseAssertions()
                cancelOffTimer()
                startBatteryMonitor()
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

    private static func normalizedDisplayDimDelayMinutes(_ minutes: Int) -> Int {
        displayDimDelayOptions.contains(minutes) ? minutes : 1
    }

    private static func initialDisplayDimDelayMinutes(defaults: UserDefaults, key: String) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return 1
        }

        return normalizedDisplayDimDelayMinutes(defaults.integer(forKey: key))
    }

    private static func initialOffTimerEndDate(defaults: UserDefaults, key: String) -> Date? {
        guard let timestamp = defaults.object(forKey: key) as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    private func createAssertions() -> Bool {
        releaseAssertions()

        let activeAssertions = assertionPolicy.activeAssertions(
            allowLockAndSleepEnabled: allowLockAndSleepEnabled,
            allowClosedLidEnabled: allowClosedLidEnabled
        )

        for assertion in activeAssertions {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                assertion.type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                assertion.reason as CFString,
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
            setOffTimerEndDate(nil)
            keepAwakeRemainingSeconds = 0
            return
        }

        if keepAwakeOffTimerEndDate == nil {
            setOffTimerEndDate(autoOffDeadlinePolicy.endDate(startingAt: Date(), minutes: keepAwakeOffTimerMinutes))
        }

        guard let keepAwakeOffTimerEndDate else {
            return
        }

        guard refreshOffTimerRemainingSeconds(until: keepAwakeOffTimerEndDate) else {
            return
        }

        if let warningDelay = autoOffDeadlinePolicy.warningDelay(until: keepAwakeOffTimerEndDate, now: Date()) {
            autoOffNotificationController.scheduleWarning(after: warningDelay)
        }

        offTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            guard let self else {
                return
            }

            _ = self.refreshOffTimerRemainingSeconds(until: keepAwakeOffTimerEndDate)
        }
    }

    private func cancelOffTimer() {
        offTimer?.invalidate()
        offTimer = nil
        keepAwakeRemainingSeconds = 0
        autoOffNotificationController.cancelWarning()
    }

    private func refreshOffTimerRemainingSeconds(until endDate: Date) -> Bool {
        let remainingSeconds = autoOffDeadlinePolicy.remainingSeconds(until: endDate, now: Date())
        keepAwakeRemainingSeconds = remainingSeconds

        guard remainingSeconds > 0 else {
            _ = setKeepAwakeEnabled(false)
            return false
        }

        return true
    }

    private func extendKeepAwakeSession(by seconds: TimeInterval) {
        guard keepAwakeEnabled else {
            return
        }

        let endDate = autoOffDeadlinePolicy.extending(
            endDate: keepAwakeOffTimerEndDate,
            by: seconds,
            now: Date()
        )
        setOffTimerEndDate(endDate)
        keepAwakeOffTimerMinutes = max(1, Int(ceil(endDate.timeIntervalSinceNow / 60)))
        UserDefaults.standard.set(keepAwakeOffTimerMinutes, forKey: keepAwakeOffTimerDefaultsKey)
        scheduleOffTimer()
    }

    private func setOffTimerEndDate(_ endDate: Date?) {
        keepAwakeOffTimerEndDate = endDate

        if let endDate {
            UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: keepAwakeOffTimerEndDateDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: keepAwakeOffTimerEndDateDefaultsKey)
        }
    }

    private func normalizeExpiredOffTimerSession() {
        guard let keepAwakeOffTimerEndDate else {
            return
        }

        guard keepAwakeOffTimerEndDate > Date() else {
            keepAwakeEnabled = false
            UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
            setOffTimerEndDate(nil)
            return
        }

        guard keepAwakeEnabled else {
            setOffTimerEndDate(nil)
            return
        }
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

    private func cancelDisplayDimTest() {
        displayDimTestStartTimer?.invalidate()
        displayDimTestStartTimer = nil
        displayDimTestTimer?.invalidate()
        displayDimTestTimer = nil
        hideBuiltInDisplayDimOverlay()
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

        showBuiltInDisplayDimOverlay()
        let didDimDisplay = !builtInDimOverlayWindows.isEmpty

        if didDimDisplay {
            startDisplayActivityMonitor()
        }
    }

    private func startDisplayActivityMonitor() {
        stopDisplayActivityMonitor()
        startDisplayActivityObservers()

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
        stopDisplayActivityObservers()
    }

    private func startDisplayActivityObservers() {
        stopDisplayActivityObservers()

        let eventMask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        if let localObserver = NSEvent.addLocalMonitorForEvents(matching: eventMask, handler: { [weak self] event in
            self?.restoreBrightnessAfterDisplayActivity(force: true)
            return event
        }) {
            displayActivityObservers.append(localObserver)
        }

        if let globalObserver = NSEvent.addGlobalMonitorForEvents(matching: eventMask, handler: { [weak self] _ in
            self?.restoreBrightnessAfterDisplayActivity(force: true)
        }) {
            displayActivityObservers.append(globalObserver)
        }
    }

    private func stopDisplayActivityObservers() {
        displayActivityObservers.forEach { NSEvent.removeMonitor($0) }
        displayActivityObservers.removeAll()
    }

    private func restoreBrightnessAfterDisplayActivity(force: Bool = false) {
        let isDimmed = !builtInDimOverlayWindows.isEmpty

        guard isDimmed else {
            stopDisplayActivityMonitor()
            return
        }

        guard force || displayDimPolicy.shouldRestoreDimming(
            isDimmed: isDimmed,
            currentIdleTime: currentSystemIdleTime()
        ) else {
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
        let eventIdleTime = currentEventIdleTime()
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )

        guard service != 0 else {
            return eventIdleTime
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
            return eventIdleTime
        }

        let hidIdleTime = TimeInterval(property.uint64Value) / 1_000_000_000

        guard let eventIdleTime else {
            return hidIdleTime
        }

        return min(hidIdleTime, eventIdleTime)
    }

    private func currentEventIdleTime() -> TimeInterval? {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel
        ]

        let idleTimes = eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.filter {
            $0.isFinite
        }

        return idleTimes.min().map { TimeInterval($0) }
    }

    private func restoreDisplayBrightness() {
        hideBuiltInDisplayDimOverlay()
    }

    private func recoverDisplayTransferSettingsFromPreviousDimmer() {
        CGDisplayRestoreColorSyncSettings()
    }

    private func showBuiltInDisplayDimOverlay() {
        hideBuiltInDisplayDimOverlay()

        builtInDimOverlayWindows = builtInScreens().map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.backgroundColor = NSColor.black.withAlphaComponent(0.90)
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = dimOverlayContentView(frame: screen.frame)
            window.orderFrontRegardless()
            return window
        }
    }

    private func dimOverlayContentView(frame: NSRect) -> NSView {
        guard let logoImage = NSImage(named: "WelcomeLogo") else {
            return NSView(frame: frame)
        }

        return DimOverlayContentView(frame: frame, logoImage: logoImage)
    }

    private func hideBuiltInDisplayDimOverlay() {
        builtInDimOverlayWindows.forEach { $0.orderOut(nil) }
        builtInDimOverlayWindows.removeAll()
    }

    private func builtInScreens() -> [NSScreen] {
        NSScreen.screens.filter { screen in
            guard let displayID = displayID(for: screen) else {
                return false
            }

            return CGDisplayIsBuiltin(displayID) != 0
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func startAppObservers() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshBuiltInDisplayDimOverlayForCurrentScreens()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.shutdown()
        }
    }

    private func removeScreenParametersObserver() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }

        screenParametersObserver = nil
    }

    private func removeTerminationObserver() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }

        terminationObserver = nil
    }

    private func refreshBuiltInDisplayDimOverlayForCurrentScreens() {
        if !builtInDimOverlayWindows.isEmpty {
            showBuiltInDisplayDimOverlay()
        }
    }

    private func startBatteryMonitor() {
        stopBatteryMonitor()

        batteryMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            self?.refreshBatteryProtectionState()
        }
    }

    private func stopBatteryMonitor() {
        batteryMonitorTimer?.invalidate()
        batteryMonitorTimer = nil
    }

    private func refreshBatteryProtectionState() {
        guard let batteryState = currentBatteryState() else {
            if !batteryProtectionPolicy.shouldMonitorBattery(
                keepAwakeEnabled: keepAwakeEnabled,
                errorMessage: errorMessage
            ) {
                stopBatteryMonitor()
            }

            return
        }

        if batteryProtectionPolicy.shouldClearPauseMessage(
            percent: batteryState.percent,
            isOnBatteryPower: batteryState.isOnBatteryPower,
            currentMessage: errorMessage
        ) {
            errorMessage = nil
        }

        guard keepAwakeEnabled,
              batteryProtectionPolicy.shouldPauseAwakeMode(
                percent: batteryState.percent,
                isOnBatteryPower: batteryState.isOnBatteryPower
              ) else {
            if !batteryProtectionPolicy.shouldMonitorBattery(
                keepAwakeEnabled: keepAwakeEnabled,
                errorMessage: errorMessage
            ) {
                stopBatteryMonitor()
            }

            return
        }

        errorMessage = batteryProtectionPolicy.pauseMessage
        keepAwakeEnabled = false
        UserDefaults.standard.set(false, forKey: keepAwakeDefaultsKey)
        releaseAssertions()
        cancelOffTimer()
        cancelDisplayDimTimer(restoreBrightness: true)
    }

    private func shouldAllowAwakeSession() -> Bool {
        guard let batteryState = currentBatteryState() else {
            if errorMessage == batteryProtectionPolicy.pauseMessage {
                errorMessage = nil
            }

            return true
        }

        if batteryProtectionPolicy.shouldClearPauseMessage(
            percent: batteryState.percent,
            isOnBatteryPower: batteryState.isOnBatteryPower,
            currentMessage: errorMessage
        ) {
            errorMessage = nil
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

private final class DimOverlayContentView: NSView {
    private let clockLabel = NSTextField(labelWithString: "")
    private var clockTimer: Timer?

    init(frame frameRect: NSRect, logoImage: NSImage) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let logoView = NSImageView(image: logoImage)
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.alphaValue = 0.88

        clockLabel.alignment = .center
        clockLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .light)
        clockLabel.lineBreakMode = .byClipping

        let contentStack = NSStackView(views: [logoView, clockLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        logoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            logoView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.21),
            logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor, multiplier: logoImage.size.height / logoImage.size.width),
            logoView.heightAnchor.constraint(lessThanOrEqualToConstant: 41)
        ])

        updateClock()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        clockTimer?.invalidate()
        clockTimer = nil

        guard window != nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
        clockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        clockTimer?.invalidate()
    }

    private func updateClock() {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        clockLabel.stringValue = formatter.string(from: Date())
    }
}
