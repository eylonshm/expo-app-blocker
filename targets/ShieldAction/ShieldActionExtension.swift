import ManagedSettings
import ManagedSettingsUI
import UIKit
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {
  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"
  private let pendingUnlockKey = "appBlocker.pendingUnlock.v1"
  private let pendingUnlockNotificationIdentifier = "expo.appblocker.pendingUnlock.local"

  override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    handleAction(action, completionHandler: completionHandler)
  }

  private func handleAction(_ action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    switch action {
    case .primaryButtonPressed:
      setPendingUnlockFlag()
      schedulePendingUnlockNotification { didSchedule in
        let response: ShieldActionResponse = didSchedule ? .none : .defer
        self.complete(on: response, completionHandler: completionHandler)
      }

    case .secondaryButtonPressed:
      complete(on: .close, completionHandler: completionHandler)

    @unknown default:
      complete(on: .close, completionHandler: completionHandler)
    }
  }

  private func complete(on response: ShieldActionResponse, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    if Thread.isMainThread {
      completionHandler(response)
      return
    }

    DispatchQueue.main.async {
      completionHandler(response)
    }
  }

  private func setPendingUnlockFlag() {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
    sharedDefaults.set(true, forKey: pendingUnlockKey)
    sharedDefaults.synchronize()

    let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(
      notificationCenter,
      CFNotificationName("expo.appblocker.pendingUnlock" as CFString),
      nil,
      nil,
      true
    )
  }

  private func schedulePendingUnlockNotification(completion: @escaping (Bool) -> Void) {
    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = "App Blocker"
    content.body = "Tap to return to the app and complete the unlock challenge."
    content.sound = .default
    content.userInfo = ["link": "/unlock"]

    let request = UNNotificationRequest(
      identifier: pendingUnlockNotificationIdentifier,
      content: content,
      trigger: nil
    )

    center.removePendingNotificationRequests(withIdentifiers: [pendingUnlockNotificationIdentifier])
    center.add(request) { error in
      completion(error == nil)
    }
  }
}
