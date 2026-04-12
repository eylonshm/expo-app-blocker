import ManagedSettingsUI
import ManagedSettings
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"

  // Grandmizer design system colors
  private let primaryGreen = UIColor(red: 0.486, green: 0.710, blue: 0.094, alpha: 1.0) // #7cb518
  private let darkGreen = UIColor(red: 0.361, green: 0.502, blue: 0.004, alpha: 1.0)    // #5c8001
  private let accentOrange = UIColor(red: 0.984, green: 0.380, blue: 0.027, alpha: 1.0) // #fb6107
  private let darkText = UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0)     // #111111
  private let subtitleGray = UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)

  private var mascotIcon: UIImage? {
    // Load from the extension's own bundle
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

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    let appName = application.localizedDisplayName ?? "This app"

    // If temporarily unlocked, show a different message
    if isTemporarilyUnlocked() {
      return ShieldConfiguration(
        backgroundBlurStyle: .systemThickMaterial,
        backgroundColor: nil,
        icon: mascotIcon,
        title: ShieldConfiguration.Label(
          text: "Almost there!",
          color: darkText
        ),
        subtitle: ShieldConfiguration.Label(
          text: "Your free time is loading. Try again in a moment.",
          color: subtitleGray
        ),
        primaryButtonLabel: ShieldConfiguration.Label(
          text: "OK",
          color: .white
        ),
        primaryButtonBackgroundColor: primaryGreen,
        secondaryButtonLabel: nil
      )
    }

    let count = getBlockedAppCount()
    let contextLine = count > 1
      ? "You have \(count) apps blocked. Stay focused!"
      : "Stay focused! Take a quick quiz to earn free time."

    return ShieldConfiguration(
      backgroundBlurStyle: nil,
      backgroundColor: UIColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1.0),
      icon: mascotIcon,
      title: ShieldConfiguration.Label(
        text: "Hold on!",
        color: darkText
      ),
      subtitle: ShieldConfiguration.Label(
        text: "\(appName) is blocked. \(contextLine)",
        color: subtitleGray
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Earn Free Time",
        color: .white
      ),
      primaryButtonBackgroundColor: accentOrange,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "Not now",
        color: subtitleGray
      )
    )
  }

  override func configuration(shielding application: Application,
                               in category: ActivityCategory) -> ShieldConfiguration {
    let categoryName = category.localizedDisplayName ?? "This category"

    return ShieldConfiguration(
      backgroundBlurStyle: nil,
      backgroundColor: UIColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1.0),
      icon: mascotIcon,
      title: ShieldConfiguration.Label(
        text: "Hold on!",
        color: darkText
      ),
      subtitle: ShieldConfiguration.Label(
        text: "\(categoryName) is blocked. Take a quick quiz to earn free time!",
        color: subtitleGray
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Earn Free Time",
        color: .white
      ),
      primaryButtonBackgroundColor: accentOrange,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "Not now",
        color: subtitleGray
      )
    )
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    let domain = webDomain.domain ?? "This website"

    return ShieldConfiguration(
      backgroundBlurStyle: nil,
      backgroundColor: UIColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1.0),
      icon: mascotIcon,
      title: ShieldConfiguration.Label(
        text: "Hold on!",
        color: darkText
      ),
      subtitle: ShieldConfiguration.Label(
        text: "\(domain) is blocked. Take a quick quiz to earn free time!",
        color: subtitleGray
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: "Earn Free Time",
        color: .white
      ),
      primaryButtonBackgroundColor: accentOrange,
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: "Not now",
        color: subtitleGray
      )
    )
  }

  override func configuration(shielding webDomain: WebDomain,
                               in category: ActivityCategory) -> ShieldConfiguration {
    return configuration(shielding: webDomain)
  }
}
