import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

@available(iOS 15.0, *)
// NOTE: the class name MUST be `DeviceActivityMonitorExtension` — it has to match
// the `NSExtensionPrincipalClass` (`$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`)
// that @bacons/apple-targets writes into the extension's Info.plist. If it doesn't
// match, iOS cannot instantiate the extension and NONE of the callbacks fire.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  // CONFIGURE: Replace with your App Group identifier
  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"
  // Holds the grant's wall-clock expiration (Date); kept in sync with
  // ExpoAppBlockerModule.swift. Presence + a future date means an unlock is active.
  private let temporaryUnlockKey = "appBlocker.temporaryUnlock.v1"
  private let blockConfigStorageKey = "appBlocker.blockConfiguration.v1"

  private let store = ManagedSettingsStore()
  private var sharedDefaults: UserDefaults?

  override init() {
    super.init()
    sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
  }

  // Fires at `intervalEnd − warningTime`, which the host aligns to the grant's
  // real expiration. This is the ONLY callback that fires for sub-15-min grants
  // (Apple's schedule interval minimum is 15 min), so it's the primary
  // re-block-while-inside path. `intervalDidEnd` covers the ≥15-min case + safety.
  override func intervalWillEndWarning(for activity: DeviceActivityName) {
    super.intervalWillEndWarning(for: activity)
    relockIfExpired()
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    relockIfExpired()
  }

  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
  }

  /// Re-apply the shield once the grant's wall-clock expiration has arrived.
  /// Guards against the spurious callback that `stopMonitoring()` fires during a
  /// re-grant: if the stored expiration is still comfortably in the future
  /// (> 60s), this is a re-arm — not an expiry — so the fresh grant is kept.
  /// The 60s tolerance also absorbs callback/clock skew at the real boundary.
  private func relockIfExpired() {
    if let expiration = sharedDefaults?.object(forKey: temporaryUnlockKey) as? Date,
       expiration.timeIntervalSinceNow > 60 {
      return
    }
    sharedDefaults?.removeObject(forKey: temporaryUnlockKey)
    reapplyBlockConfiguration()
  }

  private func reapplyBlockConfiguration() {
    let userDefaults = sharedDefaults ?? UserDefaults.standard

    guard let configDict = userDefaults.dictionary(forKey: blockConfigStorageKey) else {
      store.shield.applications = nil
      store.shield.applicationCategories = nil
      store.shield.webDomains = nil
      return
    }

    guard let blockConfig = parseBlockConfig(configDict) else {
      return
    }

    applyBlocks(blockConfig)
  }

  private func parseBlockConfig(_ dict: [String: Any]) -> MonitorBlockConfig? {
    let rawItems: [[String: Any]]
    if let blockedItems = dict["blockedItems"] as? [[String: Any]] {
      rawItems = blockedItems
    } else if let appSelections = dict["appSelections"] as? [[String: Any]] {
      rawItems = appSelections.map { item in
        var normalized = item
        normalized["type"] = "app"
        return normalized
      }
    } else {
      return nil
    }

    let items: [MonitorBlockedItemInfo] = rawItems.compactMap { selection -> MonitorBlockedItemInfo? in
      guard let tokenString = selection["token"] as? String else {
        return nil
      }

      let itemTypeRaw = (selection["type"] as? String ?? "app").lowercased()
      let itemType: MonitorBlockedItemType
      switch itemTypeRaw {
      case "category":
        itemType = .category
      case "webdomain":
        itemType = .webDomain
      default:
        itemType = .app
      }

      return MonitorBlockedItemInfo(
        type: itemType,
        tokenId: tokenString,
        appToken: itemType == .app ? decodeApplicationToken(from: tokenString) : nil,
        categoryToken: itemType == .category ? decodeCategoryToken(from: tokenString) : nil,
        webDomainToken: itemType == .webDomain ? decodeWebDomainToken(from: tokenString) : nil
      )
    }

    let isActive = dict["isActive"] as? Bool ?? true
    return MonitorBlockConfig(items: items, isActive: isActive)
  }

  private func applyBlocks(_ config: MonitorBlockConfig) {
    guard config.isActive else {
      store.shield.applications = nil
      store.shield.applicationCategories = nil
      store.shield.webDomains = nil
      return
    }

    let validAppTokens = config.items.compactMap { $0.appToken }
    let validCategoryTokens = config.items.compactMap { $0.categoryToken }
    let validWebDomainTokens = config.items.compactMap { $0.webDomainToken }

    guard !validAppTokens.isEmpty || !validCategoryTokens.isEmpty || !validWebDomainTokens.isEmpty else {
      store.shield.applications = nil
      store.shield.applicationCategories = nil
      store.shield.webDomains = nil
      return
    }

    if !validAppTokens.isEmpty {
      store.shield.applications = Set(validAppTokens)
    } else {
      store.shield.applications = nil
    }

    if !validCategoryTokens.isEmpty {
      store.shield.applicationCategories = .specific(Set(validCategoryTokens))
    } else {
      store.shield.applicationCategories = nil
    }

    if !validWebDomainTokens.isEmpty {
      store.shield.webDomains = Set(validWebDomainTokens)
    } else {
      store.shield.webDomains = nil
    }
  }

  private func decodeApplicationToken(from encoded: String) -> ApplicationToken? {
    guard let data = Data(base64Encoded: encoded) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(ApplicationToken.self, from: data)
    } catch {
      return nil
    }
  }

  private func decodeCategoryToken(from encoded: String) -> ActivityCategoryToken? {
    guard let data = Data(base64Encoded: encoded) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(ActivityCategoryToken.self, from: data)
    } catch {
      return nil
    }
  }

  private func decodeWebDomainToken(from encoded: String) -> WebDomainToken? {
    guard let data = Data(base64Encoded: encoded) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(WebDomainToken.self, from: data)
    } catch {
      return nil
    }
  }
}

enum MonitorBlockedItemType: String {
  case app
  case category
  case webDomain
}

struct MonitorBlockedItemInfo {
  let type: MonitorBlockedItemType
  let tokenId: String
  let appToken: ApplicationToken?
  let categoryToken: ActivityCategoryToken?
  let webDomainToken: WebDomainToken?
}

struct MonitorBlockConfig {
  let items: [MonitorBlockedItemInfo]
  let isActive: Bool
}
