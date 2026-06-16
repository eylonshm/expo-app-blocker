import ExpoModulesCore
import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftUI
import Foundation

public class ExpoAppBlockerModule: Module {
  private let appGroupIdentifier = ExpoAppBlockerConfig.appGroupIdentifier

  private let authCenter = AuthorizationCenter.shared
  private let store = ManagedSettingsStore()
  private let activityCenter = DeviceActivityCenter()
  private var sharedDefaults: UserDefaults?
  private let userDefaults = UserDefaults.standard
  private let blockConfigStorageKey = "appBlocker.blockConfiguration.v1"
  // Stores the grant's wall-clock expiration (Date). Presence + a future date means
  // a temporary unlock is active; the shield is re-applied once it passes.
  private let temporaryUnlockKey = "appBlocker.temporaryUnlock.v1"
  private let unlockActivityName = "appBlocker.temporaryUnlock"
  private let pendingUnlockKey = "appBlocker.pendingUnlock.v1"
  private let pendingInterceptsKey = "appBlocker.pendingIntercepts.v1"
  private let minimumTemporaryUnlockMinutes = 1
  private var didLoadPersistedConfig = false

  private var currentBlockConfig: BlockConfig?
  private let stateQueue = DispatchQueue(label: "expo.appblocker.state", qos: .userInitiated)
  private let scheduleLock = NSLock()
  private var isProcessingUnlockState = false

  public func definition() -> ModuleDefinition {
    Name("ExpoAppBlocker")

    Events("onPendingUnlockRequest")

    // Native view that renders blocked app tokens with real names and icons
    View(BlockedAppsView.self) {
      Prop("selectionData") { (view: BlockedAppsView, selectionBase64: String) in
        guard !selectionBase64.isEmpty,
              let data = Data(base64Encoded: selectionBase64),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        view.viewModel.selection = selection
      }

      Prop("tokens") { (view: BlockedAppsView, tokens: [[String: String]]) in
        var appTokens: Set<ApplicationToken> = []
        var categoryTokens: Set<ActivityCategoryToken> = []

        for tokenInfo in tokens {
          guard let tokenString = tokenInfo["token"], let type = tokenInfo["type"] else { continue }
          if type == "app" {
            if let token = Self.decodeApplicationTokenStatic(from: tokenString) {
              appTokens.insert(token)
            }
          } else if type == "category" {
            if let token = Self.decodeCategoryTokenStatic(from: tokenString) {
              categoryTokens.insert(token)
            }
          }
        }

        var selection = FamilyActivitySelection()
        selection.applicationTokens = appTokens
        selection.categoryTokens = categoryTokens
        view.viewModel.selection = selection
      }
    }

    OnCreate {
      self.sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier)
      self.setupUnlockNotificationObserver()

      self.stateQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.checkAndApplyUnlockState()
      }
    }

    AsyncFunction("requestAuthorization") { (promise: Promise) in
      Task {
        do {
          try await self.authCenter.requestAuthorization(for: .individual)
          let status = self.getAuthStatus()
          promise.resolve([
            "authorized": status.authorized,
            "status": status.statusString
          ])
        } catch {
          promise.resolve([
            "authorized": false,
            "status": "denied"
          ])
        }
      }
    }

    Function("getAuthorizationStatus") {
      let status = self.getAuthStatus()
      return [
        "authorized": status.authorized,
        "status": status.statusString
      ]
    }

    AsyncFunction("presentFamilyActivityPicker") { (promise: Promise) in
      DispatchQueue.main.async {
        self.ensureLoadedPersistedConfig()

        guard self.authCenter.authorizationStatus == .approved else {
          promise.reject("NOT_AUTHORIZED", "Family Controls authorization not granted")
          return
        }

        let initialAppTokens = Set(self.currentBlockConfig?.items.compactMap { $0.appToken } ?? [])
        let initialCategoryTokens = Set(self.currentBlockConfig?.items.compactMap { $0.categoryToken } ?? [])
        let pickerView = FamilyActivityPickerView(
          initialApplicationTokens: initialAppTokens,
          initialCategoryTokens: initialCategoryTokens,
          promise: promise
        )
        let hostingController = UIHostingController(rootView: pickerView)

        if let rootVC = self.getRootViewController() {
          hostingController.modalPresentationStyle = .formSheet
          rootVC.present(hostingController, animated: true)
        } else {
          promise.reject("NO_ROOT_VC", "Could not find root view controller")
        }
      }
    }

    AsyncFunction("setBlockConfiguration") { (config: [String: Any], promise: Promise) in
      self.stateQueue.async {
        do {
          self.ensureLoadedPersistedConfig()
          let blockConfig = try self.parseBlockConfig(config)
          self.currentBlockConfig = blockConfig
          try self.applyBlocks(blockConfig)
          self.persistBlockConfiguration(config)

          DispatchQueue.main.async {
            promise.resolve(nil)
          }
        } catch {
          DispatchQueue.main.async {
            promise.reject("CONFIG_ERROR", "Failed to set block configuration: \(error.localizedDescription)")
          }
        }
      }
    }

    Function("getBlockConfiguration") { () -> [String: Any]? in
      self.ensureLoadedPersistedConfig()

      guard let config = self.currentBlockConfig else {
        return nil
      }
      return self.serializeBlockConfig(config)
    }

    Function("clearAllBlocks") {
      self.stateQueue.async {
        self.ensureLoadedPersistedConfig()
        self.cancelRelockActivity()
        self.store.shield.applications = nil
        self.store.shield.applicationCategories = nil
        self.store.shield.webDomains = nil
        self.currentBlockConfig = nil
        self.userDefaults.removeObject(forKey: self.blockConfigStorageKey)
        self.sharedDefaults?.removeObject(forKey: self.blockConfigStorageKey)
        self.clearUnlockState()
      }
    }

    Function("checkAndClearPendingUnlock") { () -> Bool in
      guard let defaults = self.sharedDefaults else { return false }
      let hasPending = defaults.bool(forKey: self.pendingUnlockKey)
      if hasPending {
        defaults.removeObject(forKey: self.pendingUnlockKey)
        defaults.synchronize()
      }
      return hasPending
    }

    Function("drainPendingIntercepts") { () -> [[String: Any]] in
      guard let defaults = self.sharedDefaults else { return [] }
      // Refresh the cached suite so writes made by the (separate) shield
      // extension process are visible to this long-lived app process.
      defaults.synchronize()
      var queue: [[String: Any]] = []
      if let json = defaults.string(forKey: self.pendingInterceptsKey),
         let data = json.data(using: .utf8),
         let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        queue = parsed
      }
      if defaults.string(forKey: self.pendingInterceptsKey) != nil {
        defaults.removeObject(forKey: self.pendingInterceptsKey)
        defaults.synchronize()
      }
      return queue
    }

    Function("isAppBlocked") { (bundleIdentifier: String) -> Bool in
      self.ensureLoadedPersistedConfig()
      guard let config = self.currentBlockConfig else {
        return false
      }
      return config.items.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    AsyncFunction("temporaryUnlock") { (durationMinutes: Int, promise: Promise) in
      self.stateQueue.async {
        self.ensureLoadedPersistedConfig()
        let sanitizedDurationMinutes = max(self.minimumTemporaryUnlockMinutes, durationMinutes)

        guard let config = self.currentBlockConfig, config.isActive else {
          DispatchQueue.main.async {
            promise.reject("NO_ACTIVE_BLOCKS", "No active blocks to unlock")
          }
          return
        }

        // Wall-clock expiry is the source of truth. (Usage-based relock was
        // removed: Apple won't fire DeviceActivity usage thresholds under ~15 min,
        // so short earned-time budgets never re-blocked and the countdown froze.)
        let expirationDate = Date().addingTimeInterval(TimeInterval(sanitizedDurationMinutes * 60))
        self.sharedDefaults?.set(expirationDate, forKey: self.temporaryUnlockKey)

        DispatchQueue.main.async {
          self.store.shield.applications = nil
          self.store.shield.applicationCategories = nil
          self.store.shield.webDomains = nil
        }

        // Best-effort schedule: only fires for grants ≥ ~15 min (Apple's minimum).
        // Shorter grants throw here and are re-blocked by the host instead —
        // getRemainingUnlockTime and the foreground checkAndApplyUnlockState relock
        // once the expiration passes.
        do {
          try self.scheduleRelockActivity(expirationDate: expirationDate)
        } catch {
          print("[AppBlocker] Schedule relock failed (duration may be too short): \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
          promise.resolve([
            "unlocked": true,
            "expiresAt": expirationDate.timeIntervalSince1970
          ])
        }
      }
    }

    Function("isTemporarilyUnlocked") { () -> Bool in
      guard let expirationDate = self.sharedDefaults?.object(forKey: self.temporaryUnlockKey) as? Date else {
        return false
      }
      if Date() < expirationDate {
        return true
      }
      self.relockApps()
      return false
    }

    // Wall-clock remaining seconds, counting down in real time. When the host app
    // polls this (e.g. the blocking-status banner, every second) and the grant has
    // expired, it re-applies the shield — the primary relock path for grants under
    // ~15 min, which Apple's DeviceActivity cannot enforce on its own.
    Function("getRemainingUnlockTime") { () -> Int in
      guard let expirationDate = self.sharedDefaults?.object(forKey: self.temporaryUnlockKey) as? Date else {
        return 0
      }
      let remaining = expirationDate.timeIntervalSince(Date())
      if remaining > 0 {
        return Int(remaining)
      }
      self.relockApps()
      return 0
    }

    AsyncFunction("relockApps") { (promise: Promise) in
      self.stateQueue.async {
        self.relockApps()

        DispatchQueue.main.async {
          promise.resolve(["locked": true])
        }
      }
    }
  }

  // MARK: - Authorization

  private func getAuthStatus() -> (authorized: Bool, statusString: String) {
    let status = authCenter.authorizationStatus
    switch status {
    case .notDetermined:
      return (false, "notDetermined")
    case .denied:
      return (false, "denied")
    case .approved:
      return (true, "approved")
    @unknown default:
      return (false, "denied")
    }
  }

  private func getRootViewController() -> UIViewController? {
    if let currentVC = appContext?.utilities?.currentViewController() {
      return currentVC
    }

    let scenes = UIApplication.shared.connectedScenes
    let windowScene = scenes.first as? UIWindowScene
    let window = windowScene?.windows.first
    return window?.rootViewController
  }

  // MARK: - Darwin Notification Observer

  private func setupUnlockNotificationObserver() {
    let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()

    let legacyName = "expo.appblocker.temporaryUnlock" as CFString
    CFNotificationCenterAddObserver(
      notificationCenter,
      observer,
      { (_, observer, _, _, _) in
        guard let observer else { return }
        let module = Unmanaged<ExpoAppBlockerModule>.fromOpaque(observer).takeUnretainedValue()
        module.stateQueue.async {
          module.checkAndApplyUnlockState()
        }
      },
      legacyName,
      nil,
      .deliverImmediately
    )

    let pendingName = "expo.appblocker.pendingUnlock" as CFString
    CFNotificationCenterAddObserver(
      notificationCenter,
      observer,
      { (_, observer, _, _, _) in
        guard let observer else { return }
        let module = Unmanaged<ExpoAppBlockerModule>.fromOpaque(observer).takeUnretainedValue()
        module.handlePendingUnlockRequest()
      },
      pendingName,
      nil,
      .deliverImmediately
    )
  }

  private func handlePendingUnlockRequest() {
    DispatchQueue.main.async {
      self.sendEvent("onPendingUnlockRequest", [:])
    }
  }

  // MARK: - Unlock State

  private func checkAndApplyUnlockState() {
    guard !isProcessingUnlockState else {
      return
    }

    isProcessingUnlockState = true
    defer { isProcessingUnlockState = false }

    ensureLoadedPersistedConfig()

    if let expirationDate = sharedDefaults?.object(forKey: temporaryUnlockKey) as? Date {
      let remaining = expirationDate.timeIntervalSince(Date())

      if remaining > 0 {
        // Unlock still active — keep the shield off and (re-)arm the schedule so a
        // grant ≥ ~15 min re-blocks even while the user stays in a blocked app.
        DispatchQueue.main.async {
          self.store.shield.applications = nil
          self.store.shield.applicationCategories = nil
          self.store.shield.webDomains = nil
        }

        do {
          try scheduleRelockActivity(expirationDate: expirationDate)
        } catch {
          relockApps()
        }
      } else {
        relockApps()
      }
    } else if let config = currentBlockConfig {
      do {
        try applyBlocks(config)
      } catch {
      }
    }
  }

  // MARK: - Block Configuration

  private func parseBlockConfig(_ dict: [String: Any]) throws -> BlockConfig {
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
      throw NSError(domain: "AppBlocker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing blockedItems"])
    }

    let items: [BlockedItemInfo] = rawItems.compactMap { selection -> BlockedItemInfo? in
      guard let tokenString = selection["token"] as? String else {
        return nil
      }

      let itemTypeRaw = (selection["type"] as? String ?? "app").lowercased()
      let itemType: BlockedItemType
      switch itemTypeRaw {
      case "category":
        itemType = .category
      case "webdomain":
        itemType = .webDomain
      default:
        itemType = .app
      }

      return BlockedItemInfo(
        type: itemType,
        tokenId: tokenString,
        appToken: itemType == .app ? self.decodeApplicationToken(from: tokenString) : nil,
        categoryToken: itemType == .category ? self.decodeCategoryToken(from: tokenString) : nil,
        webDomainToken: itemType == .webDomain ? self.decodeWebDomainToken(from: tokenString) : nil,
        bundleIdentifier: selection["bundleIdentifier"] as? String,
        displayName: selection["displayName"] as? String,
        categoryName: selection["categoryName"] as? String,
        domain: selection["domain"] as? String,
        iconBase64: selection["iconBase64"] as? String
      )
    }

    let isActive = dict["isActive"] as? Bool ?? true

    var schedule: ScheduleInfo?
    if let scheduleDict = dict["schedule"] as? [String: Any] {
      schedule = ScheduleInfo(
        intervalStart: scheduleDict["intervalStart"] as? Int ?? 0,
        intervalEnd: scheduleDict["intervalEnd"] as? Int ?? 24,
        repeats: scheduleDict["repeats"] as? Bool ?? true,
        warningTime: scheduleDict["warningTime"] as? Int ?? 5
      )
    }

    return BlockConfig(items: items, isActive: isActive, schedule: schedule)
  }

  private func applyBlocks(_ config: BlockConfig) throws {
    guard config.isActive else {
      store.shield.applications = nil
      store.shield.applicationCategories = nil
      store.shield.webDomains = nil
      return
    }

    if isTemporarilyUnlockedInternal() {
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

  private func relockApps() {
    clearUnlockState()
    cancelRelockActivity()
    ensureLoadedPersistedConfig()

    guard let config = currentBlockConfig else {
      return
    }

    do {
      try applyBlocks(config)
    } catch {
    }
  }

  // MARK: - Activity Scheduling

  /// Arm a time-based re-block: a `DeviceActivitySchedule` whose interval ends at
  /// `expirationDate`. The DeviceActivityMonitor's `intervalDidEnd` re-applies the
  /// shield at that wall-clock moment, so a grant re-blocks even while the user
  /// stays in a blocked app.
  ///
  /// Apple requires the interval to span at least ~15 minutes, so grants shorter
  /// than that make `startMonitoring` throw — the caller treats that as non-fatal
  /// and relies on the host-side relock (getRemainingUnlockTime poll /
  /// checkAndApplyUnlockState on foreground) once the expiration passes.
  private func scheduleRelockActivity(expirationDate: Date) throws {
    scheduleLock.lock()
    defer { scheduleLock.unlock() }

    cancelRelockActivityLocked()

    let activityName = DeviceActivityName(unlockActivityName)
    let calendar = Calendar.current
    let now = Date()
    let startComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
    let endComponents = calendar.dateComponents([.hour, .minute, .second], from: expirationDate)
    let nowDay = calendar.startOfDay(for: now)
    let expirationDay = calendar.startOfDay(for: expirationDate)

    let schedule: DeviceActivitySchedule
    if nowDay == expirationDay {
      schedule = DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: endComponents,
        repeats: false
      )
    } else {
      // Expiration crosses midnight — cap the interval at end-of-day; the host
      // relock handles the remainder on next foreground.
      schedule = DeviceActivitySchedule(
        intervalStart: startComponents,
        intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
        repeats: false
      )
    }

    try activityCenter.startMonitoring(activityName, during: schedule)
  }

  private func cancelRelockActivity() {
    scheduleLock.lock()
    defer { scheduleLock.unlock() }
    cancelRelockActivityLocked()
  }

  private func cancelRelockActivityLocked() {
    let activityName = DeviceActivityName(unlockActivityName)
    activityCenter.stopMonitoring([activityName])
  }

  private func isTemporarilyUnlockedInternal() -> Bool {
    return remainingUnlockSeconds() > 0
  }

  /// Clear all persisted unlock state (budget + consumed counter).
  private func clearUnlockState() {
    sharedDefaults?.removeObject(forKey: temporaryUnlockKey)
  }

  /// Seconds of earned time still available: wall-clock time until the grant's
  /// expiration. 0 if no active unlock or it has already expired. Clamped at 0.
  private func remainingUnlockSeconds() -> Int {
    guard let expirationDate = sharedDefaults?.object(forKey: temporaryUnlockKey) as? Date else {
      return 0
    }
    return max(0, Int(expirationDate.timeIntervalSince(Date())))
  }


  // MARK: - Serialization

  private func serializeBlockConfig(_ config: BlockConfig) -> [String: Any] {
    let blockedItems: [[String: Any]] = config.items.compactMap { tokenInfo in
      var tokenId = tokenInfo.tokenId
      if tokenId.isEmpty {
        switch tokenInfo.type {
        case .app:
          if let token = tokenInfo.appToken, let encoded = self.encodeApplicationToken(token) {
            tokenId = encoded
          }
        case .category:
          if let token = tokenInfo.categoryToken, let encoded = self.encodeCategoryToken(token) {
            tokenId = encoded
          }
        case .webDomain:
          if let token = tokenInfo.webDomainToken, let encoded = self.encodeWebDomainToken(token) {
            tokenId = encoded
          }
        }
      }

      guard !tokenId.isEmpty else {
        return nil
      }

      var dict: [String: Any] = [
        "type": tokenInfo.type.rawValue,
        "token": tokenId
      ]

      if let bundleId = tokenInfo.bundleIdentifier {
        dict["bundleIdentifier"] = bundleId
      }
      if let displayName = tokenInfo.displayName {
        dict["displayName"] = displayName
      }
      if let categoryName = tokenInfo.categoryName {
        dict["categoryName"] = categoryName
      }
      if let domain = tokenInfo.domain {
        dict["domain"] = domain
      }
      if let iconBase64 = tokenInfo.iconBase64 {
        dict["iconBase64"] = iconBase64
      }

      return dict
    }

    let appSelections = blockedItems.filter { ($0["type"] as? String) == BlockedItemType.app.rawValue }

    var result: [String: Any] = [
      "blockedItems": blockedItems,
      "appSelections": appSelections,
      "isActive": config.isActive
    ]

    if let schedule = config.schedule {
      result["schedule"] = [
        "intervalStart": schedule.intervalStart,
        "intervalEnd": schedule.intervalEnd,
        "repeats": schedule.repeats,
        "warningTime": schedule.warningTime
      ]
    }

    return result
  }

  // MARK: - Persistence

  private func ensureLoadedPersistedConfig() {
    if didLoadPersistedConfig {
      return
    }
    didLoadPersistedConfig = true

    guard let savedConfig = userDefaults.dictionary(forKey: blockConfigStorageKey) else {
      return
    }

    do {
      let config = try parseBlockConfig(savedConfig)
      currentBlockConfig = config
      try applyBlocks(config)
    } catch {
      currentBlockConfig = nil
      userDefaults.removeObject(forKey: blockConfigStorageKey)
    }
  }

  private func persistBlockConfiguration(_ config: [String: Any]) {
    userDefaults.set(config, forKey: blockConfigStorageKey)
    sharedDefaults?.set(config, forKey: blockConfigStorageKey)
  }

  // MARK: - Token Encoding/Decoding

  private func encodeApplicationToken(_ token: ApplicationToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
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

  private func encodeCategoryToken(_ token: ActivityCategoryToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  private func decodeCategoryToken(from encoded: String) -> ActivityCategoryToken? {
    return Self.decodeCategoryTokenStatic(from: encoded)
  }

  private func encodeWebDomainToken(_ token: WebDomainToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  private func decodeWebDomainToken(from encoded: String) -> WebDomainToken? {
    guard let data = Data(base64Encoded: encoded) else {
      return nil
    }
    return try? JSONDecoder().decode(WebDomainToken.self, from: data)
  }

  // Static versions for use in View prop closures
  static func decodeApplicationTokenStatic(from encoded: String) -> ApplicationToken? {
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return try? JSONDecoder().decode(ApplicationToken.self, from: data)
  }

  static func decodeCategoryTokenStatic(from encoded: String) -> ActivityCategoryToken? {
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return try? JSONDecoder().decode(ActivityCategoryToken.self, from: data)
  }
}

// MARK: - Native View for rendering blocked app tokens with real names/icons

class BlockedAppsViewModel: ObservableObject {
  @Published var selection = FamilyActivitySelection()
}

class BlockedAppsView: ExpoView {
  let viewModel = BlockedAppsViewModel()
  private var hostingController: UIHostingController<BlockedAppsContentView>?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    let contentView = BlockedAppsContentView(viewModel: viewModel)
    let hc = UIHostingController(rootView: contentView)
    hc.view.backgroundColor = .clear
    addSubview(hc.view)
    hostingController = hc
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hostingController?.view.frame = bounds
  }
}

struct BlockedAppsContentView: View {
  @ObservedObject var viewModel: BlockedAppsViewModel

  // Grandmizer design system colors
  private let cardBg = Color(red: 1.0, green: 1.0, blue: 1.0)           // #ffffff
  private let borderColor = Color(red: 0.91, green: 0.91, blue: 0.91)   // #e8e8e8
  private let labelColor = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
  private let subtitleColor = Color(red: 0.73, green: 0.73, blue: 0.73) // #bbbbbb
  private let greenBadgeBg = Color(red: 0.94, green: 0.96, blue: 0.91)  // #f0f6e8
  private let greenText = Color(red: 0.24, green: 0.31, blue: 0.0)      // #3d5000

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(viewModel.selection.applicationTokens), id: \.self) { token in
        HStack(spacing: 12) {
          Label(token)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 16, weight: .semibold))
            .tint(labelColor)
            .foregroundStyle(labelColor)
          Spacer()
          Text("App")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(greenText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(greenBadgeBg)
            .cornerRadius(100)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(cardBg)
        .cornerRadius(16)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(borderColor, lineWidth: 1)
        )
      }

      ForEach(Array(viewModel.selection.categoryTokens), id: \.self) { token in
        HStack(spacing: 12) {
          Label(token)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 16, weight: .semibold))
            .tint(labelColor)
            .foregroundStyle(labelColor)
          Spacer()
          Text("Category")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(greenText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(greenBadgeBg)
            .cornerRadius(100)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(cardBg)
        .cornerRadius(16)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(borderColor, lineWidth: 1)
        )
      }

      if viewModel.selection.applicationTokens.isEmpty && viewModel.selection.categoryTokens.isEmpty {
        Text("No apps blocked")
          .foregroundColor(subtitleColor)
          .font(.system(size: 14))
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 16)
      }
    }
    .environment(\.colorScheme, .light)
  }
}

// MARK: - Data Types

enum BlockedItemType: String {
  case app
  case category
  case webDomain
}

struct BlockedItemInfo {
  let type: BlockedItemType
  let tokenId: String
  let appToken: ApplicationToken?
  let categoryToken: ActivityCategoryToken?
  let webDomainToken: WebDomainToken?
  let bundleIdentifier: String?
  let displayName: String?
  let categoryName: String?
  let domain: String?
  let iconBase64: String?
}

struct BlockConfig {
  let items: [BlockedItemInfo]
  let isActive: Bool
  let schedule: ScheduleInfo?
}

struct ScheduleInfo {
  let intervalStart: Int
  let intervalEnd: Int
  let repeats: Bool
  let warningTime: Int
}

// MARK: - FamilyActivityPicker SwiftUI View

struct FamilyActivityPickerView: View {
  @State private var selection: FamilyActivitySelection
  @State private var didAppear = false
  @State private var didFinish = false
  let promise: Promise

  init(
    initialApplicationTokens: Set<ApplicationToken>,
    initialCategoryTokens: Set<ActivityCategoryToken>,
    promise: Promise
  ) {
    self.promise = promise

    var initialSelection = FamilyActivitySelection()
    initialSelection.applicationTokens = initialApplicationTokens
    initialSelection.categoryTokens = initialCategoryTokens
    self._selection = State(initialValue: initialSelection)
  }

  var body: some View {
    NavigationView {
      VStack {
        familyActivityPicker
          .onChange(of: selection) { newSelection in
            _ = newSelection
          }
      }
      .onAppear {
        didAppear = true
      }
      .onDisappear {
        handleInteractiveDismissIfNeeded()
      }
      .navigationBarItems(
        leading: Button("Cancel") {
          dismissWithCancel()
        },
        trailing: Button("Done") {
          dismissWithSelection()
        }
      )
    }
  }

  @ViewBuilder
  private var familyActivityPicker: some View {
    FamilyActivityPicker(selection: $selection)
  }

  private func dismissWithSelection() {
    let appItems: [[String: Any]] = selection.applications.compactMap { selectedApp in
      guard let token = selectedApp.token,
            let tokenId = encodeSelectionToken(token) else {
        return nil
      }

      let bundleIdentifier = selectedApp.bundleIdentifier ?? ""
      let displayName = selectedApp.localizedDisplayName ?? ""
      // String(describing:) on Application sometimes contains the app name
      let descriptionString = String(describing: selectedApp)

      // Log everything for debugging
      print("[AppBlocker] Application: displayName='\(displayName)' bundleId='\(bundleIdentifier)' description='\(descriptionString)'")

      // Try multiple strategies to get a meaningful name
      let resolvedName: String
      if !displayName.isEmpty {
        resolvedName = displayName
      } else if !bundleIdentifier.isEmpty {
        // Try to make a readable name from bundle ID
        // e.g. "com.instagram.android" -> "Instagram"
        let parts = bundleIdentifier.split(separator: ".")
        if let lastPart = parts.last {
          let name = String(lastPart)
          // Capitalize and clean up
          resolvedName = name.prefix(1).uppercased() + name.dropFirst()
        } else {
          resolvedName = bundleIdentifier
        }
      } else if !descriptionString.isEmpty && descriptionString != "Application()" {
        // Try to parse something useful from description
        let cleaned = descriptionString
          .replacingOccurrences(of: "Application(", with: "")
          .replacingOccurrences(of: ")", with: "")
          .trimmingCharacters(in: .whitespaces)
        resolvedName = cleaned.isEmpty ? "Blocked App" : cleaned
      } else {
        resolvedName = "Blocked App"
      }

      return [
        "type": "app",
        "token": tokenId,
        "bundleIdentifier": bundleIdentifier,
        "displayName": resolvedName,
        "description": descriptionString
      ]
    }

    let categoryItems: [[String: Any]] = selection.categoryTokens.compactMap { categoryToken in
      guard let tokenId = encodeSelectionCategoryToken(categoryToken) else {
        return nil
      }

      let descriptionString = String(describing: categoryToken)
      let name = resolveCategoryName(categoryToken)
      print("[AppBlocker] Category: name='\(name)' description='\(descriptionString)'")

      return [
        "type": "category",
        "token": tokenId,
        "categoryName": name.isEmpty ? "Category" : name
      ]
    }

    let webDomainItems: [[String: Any]] = selection.webDomainTokens.compactMap { webDomainToken in
      guard let tokenId = encodeSelectionWebDomainToken(webDomainToken) else {
        return nil
      }
      let domain = String(describing: webDomainToken)
      return [
        "type": "webDomain",
        "token": tokenId,
        "domain": domain
      ]
    }

    // Serialize the full FamilyActivitySelection for the native view
    var selectionBase64 = ""
    if let selectionData = try? JSONEncoder().encode(selection) {
      selectionBase64 = selectionData.base64EncodedString()
    }

    var result: [[String: Any]] = appItems + categoryItems + webDomainItems
    result.append([
      "type": "summary",
      "totalApps": selection.applications.count,
      "totalCategories": selection.categoryTokens.count,
      "totalWebDomains": selection.webDomainTokens.count,
      "selectionData": selectionBase64
    ])

    dismissWithResult(result)
  }

  private func dismissWithCancel() {
    didFinish = true

    DispatchQueue.main.async {
      if let rootVC = getRootViewController() {
        rootVC.dismiss(animated: true) {
          self.promise.reject("PICKER_CANCELLED", "User cancelled Family Activity Picker")
        }
      }
    }
  }

  private func encodeSelectionCategoryToken(_ token: ActivityCategoryToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  private func encodeSelectionWebDomainToken(_ token: WebDomainToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  private func resolveCategoryName(_ token: ActivityCategoryToken) -> String {
    let raw = String(describing: token)
    return raw.isEmpty ? "Category" : raw
  }

  private func encodeSelectionToken(_ token: ApplicationToken) -> String? {
    do {
      let data = try JSONEncoder().encode(token)
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  private func dismissWithResult(_ result: [[String: Any]]) {
    didFinish = true

    DispatchQueue.main.async {
      if let rootVC = getRootViewController() {
        rootVC.dismiss(animated: true) {
          self.promise.resolve(result)
        }
      }
    }
  }

  private func getRootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
    let windowScene = scenes.first as? UIWindowScene
    let window = windowScene?.windows.first
    return window?.rootViewController
  }

  private func handleInteractiveDismissIfNeeded() {
    guard didAppear, !didFinish else {
      return
    }

    didFinish = true
    promise.reject("PICKER_CANCELLED", "User dismissed Family Activity Picker")
  }
}
