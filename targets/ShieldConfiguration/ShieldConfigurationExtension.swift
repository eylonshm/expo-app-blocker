import ManagedSettingsUI
import ManagedSettings
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"

  // All values below are replaced by the config plugin at prebuild time
  private let shieldTitle = "SHIELD_TITLE_PLACEHOLDER"
  private let shieldSubtitle = "SHIELD_SUBTITLE_PLACEHOLDER"
  private let shieldPrimaryButtonLabel = "SHIELD_PRIMARY_BUTTON_PLACEHOLDER"
  private let shieldSecondaryButtonLabel = "SHIELD_SECONDARY_BUTTON_PLACEHOLDER"
  // Temporary-unlock state copy — shown briefly while ManagedSettings clears
  // after a successful unlock. Configurable via plugin options.
  private let shieldTempUnlockTitle = "SHIELD_TEMP_UNLOCK_TITLE_PLACEHOLDER"
  private let shieldTempUnlockSubtitle = "SHIELD_TEMP_UNLOCK_SUBTITLE_PLACEHOLDER"
  private let shieldTempUnlockButtonLabel = "SHIELD_TEMP_UNLOCK_BUTTON_PLACEHOLDER"
  private let shieldPrimaryButtonColor = UIColor(red: SHIELD_PRIMARY_R_PLACEHOLDER, green: SHIELD_PRIMARY_G_PLACEHOLDER, blue: SHIELD_PRIMARY_B_PLACEHOLDER, alpha: 1.0)
  private let shieldBackgroundColor: UIColor? = SHIELD_BG_COLOR_PLACEHOLDER
  private let shieldBlurStyle: UIBlurEffect.Style? = SHIELD_BLUR_STYLE_PLACEHOLDER
  private let shieldTitleColor = UIColor(red: SHIELD_TITLE_R_PLACEHOLDER, green: SHIELD_TITLE_G_PLACEHOLDER, blue: SHIELD_TITLE_B_PLACEHOLDER, alpha: 1.0)
  private let shieldSubtitleColor = UIColor(red: SHIELD_SUBTITLE_R_PLACEHOLDER, green: SHIELD_SUBTITLE_G_PLACEHOLDER, blue: SHIELD_SUBTITLE_B_PLACEHOLDER, alpha: 1.0)

  private var mascotIcon: UIImage? {
    let bundle = Bundle(for: type(of: self))
    return UIImage(named: "shield-icon", in: bundle, compatibleWith: nil)
      ?? UIImage(contentsOfFile: bundle.path(forResource: "shield-icon", ofType: "png") ?? "")
  }

  private func getBlockedAppCount() -> Int {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }
    guard let config = defaults.dictionary(forKey: "appBlocker.blockConfiguration.v1") else { return 0 }
    if let items = config["blockedItems"] as? [[String: Any]] {
      return items.count
    }
    return 0
  }

  private func isTemporarilyUnlocked() -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return false }
    guard let expiration = defaults.object(forKey: "appBlocker.temporaryUnlock.v1") as? Date else { return false }
    return Date() < expiration
  }

  private func makeConfig(appName: String) -> ShieldConfiguration {
    if isTemporarilyUnlocked() {
      return ShieldConfiguration(
        backgroundBlurStyle: shieldBlurStyle,
        backgroundColor: shieldBackgroundColor,
        icon: mascotIcon,
        title: ShieldConfiguration.Label(text: shieldTempUnlockTitle, color: shieldTitleColor),
        subtitle: ShieldConfiguration.Label(text: shieldTempUnlockSubtitle, color: shieldSubtitleColor),
        primaryButtonLabel: ShieldConfiguration.Label(text: shieldTempUnlockButtonLabel, color: .white),
        primaryButtonBackgroundColor: shieldPrimaryButtonColor,
        secondaryButtonLabel: nil
      )
    }

    let count = getBlockedAppCount()
    // The plugin replaces this placeholder with a Swift string literal
    // containing `\(count)` interpolation, or `""` when the user opted out.
    let context = count > 1 ? SHIELD_COUNT_SUFFIX_SWIFT_PLACEHOLDER : ""
    let subtitle = shieldSubtitle.replacingOccurrences(of: "{appName}", with: appName) + context

    let hasSecondary = !shieldSecondaryButtonLabel.isEmpty && shieldSecondaryButtonLabel != "none"

    return ShieldConfiguration(
      backgroundBlurStyle: shieldBlurStyle,
      backgroundColor: shieldBackgroundColor,
      icon: mascotIcon,
      title: ShieldConfiguration.Label(text: shieldTitle, color: shieldTitleColor),
      subtitle: ShieldConfiguration.Label(text: subtitle, color: shieldSubtitleColor),
      primaryButtonLabel: ShieldConfiguration.Label(text: shieldPrimaryButtonLabel, color: .white),
      primaryButtonBackgroundColor: shieldPrimaryButtonColor,
      secondaryButtonLabel: hasSecondary ? ShieldConfiguration.Label(text: shieldSecondaryButtonLabel, color: shieldSubtitleColor) : nil
    )
  }

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    makeConfig(appName: application.localizedDisplayName ?? "This app")
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    makeConfig(appName: category.localizedDisplayName ?? "This category")
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    makeConfig(appName: webDomain.domain ?? "This website")
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    makeConfig(appName: webDomain.domain ?? "This website")
  }
}
