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
        title: ShieldConfiguration.Label(text: "Almost there!", color: shieldTitleColor),
        subtitle: ShieldConfiguration.Label(text: "Your free time is loading. Try again in a moment.", color: shieldSubtitleColor),
        primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .white),
        primaryButtonBackgroundColor: shieldPrimaryButtonColor,
        secondaryButtonLabel: nil
      )
    }

    let count = getBlockedAppCount()
    let context = count > 1 ? " You have \(count) apps blocked." : ""
    let subtitle = shieldSubtitle.replacingOccurrences(of: "{appName}", with: appName) + context

    let hasSecondary = !shieldSecondaryButtonLabel.isEmpty && shieldSecondaryButtonLabel != "none"

    return ShieldConfiguration(
      backgroundBlurStyle: shieldBackgroundColor == nil ? .systemThickMaterial : nil,
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
