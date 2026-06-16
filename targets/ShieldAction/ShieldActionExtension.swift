import ManagedSettings
import ManagedSettingsUI
import UIKit
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {
  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"
  private let pendingUnlockKey = "appBlocker.pendingUnlock.v1"
  private let pendingInterceptsKey = "appBlocker.pendingIntercepts.v1"
  private let lastInterceptTsKey = "appBlocker.lastInterceptTs.v1"
  private let interceptDebounceMs: Double = 2_000
  private let maxPendingIntercepts = 200
  private let pendingUnlockNotificationIdentifier = "expo.appblocker.pendingUnlock.local"
  // Notification copy + behavior — configurable via plugin options so apps
  // can localize without forking. Defaults preserve the original English
  // copy and the icon attachment.
  private let notificationTitle = "NOTIFICATION_TITLE_PLACEHOLDER"
  private let notificationBody = "NOTIFICATION_BODY_PLACEHOLDER"
  private let notificationAttachIcon = NOTIFICATION_ATTACH_ICON_PLACEHOLDER

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
    // Any interaction with the shield is a confirmed block event. The
    // ShieldConfiguration data source is cached by the system and not
    // re-invoked per open, so this — the action handler, which fires every
    // time — is the reliable place to record the block.
    recordIntercept()
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

  /// Queue a block event (JSON-string queue in the App Group), debounced,
  /// for the app to drain into `blocker_intercepts`.
  private func recordIntercept() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
    defaults.synchronize()

    let nowMs = Date().timeIntervalSince1970 * 1000.0
    let lastMs = defaults.double(forKey: lastInterceptTsKey)
    if lastMs > 0, (nowMs - lastMs) < interceptDebounceMs { return }

    var queue: [[String: Any]] = []
    if let json = defaults.string(forKey: pendingInterceptsKey),
       let data = json.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      queue = parsed
    }
    queue.append(["appName": NSNull(), "interceptedAt": nowMs])
    if queue.count > maxPendingIntercepts {
      queue = Array(queue.suffix(maxPendingIntercepts))
    }
    if let data = try? JSONSerialization.data(withJSONObject: queue),
       let json = String(data: data, encoding: .utf8) {
      defaults.set(json, forKey: pendingInterceptsKey)
    }
    defaults.set(nowMs, forKey: lastInterceptTsKey)
    defaults.synchronize()
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
    content.title = notificationTitle
    content.body = notificationBody
    content.sound = .default
    content.userInfo = ["link": "/unlock"]

    // Attach the app icon to the notification only when the app opted in.
    // When false the system app icon is the only icon shown — avoids the
    // "duplicate icon" look on iOS notification banners.
    if notificationAttachIcon, let iconURL = iconFileURL() {
      if let attachment = try? UNNotificationAttachment(identifier: "icon", url: iconURL, options: nil) {
        content.attachments = [attachment]
      }
    }

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

  private func iconFileURL() -> URL? {
    let bundle = Bundle(for: type(of: self))
    // Try shield-icon first (copied by config plugin)
    if let url = bundle.url(forResource: "shield-icon", withExtension: "png") { return url }
    // Try from app group shared container
    if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
      let sharedIcon = container.appendingPathComponent("notification-icon.png")
      if FileManager.default.fileExists(atPath: sharedIcon.path) { return sharedIcon }
    }
    return nil
  }
}
