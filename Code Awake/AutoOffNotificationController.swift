//
//  AutoOffNotificationController.swift
//  Code Awake
//

import Foundation
import UserNotifications

final class AutoOffNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private enum Identifier {
        static let category = "autoOffWarning"
        static let warningRequest = "autoOffWarningRequest"
        static let extend = "extendAutoOffSession"
        static let stop = "stopAutoOffSession"
    }

    var onExtend: (() -> Void)?
    var onStop: (() -> Void)?

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()
    }

    func configure() {
        notificationCenter.delegate = self

        let extendAction = UNNotificationAction(
            identifier: Identifier.extend,
            title: "Add 30 min",
            options: []
        )
        let stopAction = UNNotificationAction(
            identifier: Identifier.stop,
            title: "Stop Now",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [extendAction, stopAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
    }

    func scheduleWarning(after delay: TimeInterval) {
        guard delay > 0 else {
            cancelWarning()
            return
        }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.addWarningRequest(after: delay)
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else {
                        return
                    }

                    self.addWarningRequest(after: delay)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func cancelWarning() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifier.warningRequest])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Identifier.warningRequest])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == Identifier.warningRequest else {
            completionHandler()
            return
        }

        DispatchQueue.main.async { [weak self] in
            switch response.actionIdentifier {
            case Identifier.extend:
                self?.onExtend?()
            case Identifier.stop:
                self?.onStop?()
            default:
                break
            }

            completionHandler()
        }
    }

    private func addWarningRequest(after delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Code Awake will turn off soon"
        content.body = "Your Mac will stop being kept awake in 5 minutes."
        content.sound = .default
        content.categoryIdentifier = Identifier.category

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: Identifier.warningRequest,
            content: content,
            trigger: trigger
        )

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifier.warningRequest])
        notificationCenter.add(request)
    }
}
