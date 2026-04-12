import ManagedSettingsUI
import ManagedSettings
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

  private let appGroupIdentifier = "APP_GROUP_PLACEHOLDER"

  // ── Configurable values (injected by plugin at prebuild) ──────────────
  private let cfgTitle = "SHIELD_TITLE_PLACEHOLDER"                           // default: "Hold on!"
  private let cfgTitleColor = "SHIELD_TITLE_COLOR_PLACEHOLDER"                // default: "#111111"
  private let cfgSubtitle = "SHIELD_SUBTITLE_PLACEHOLDER"                     // default: "{appName} is blocked."
  private let cfgSubtitleColor = "SHIELD_SUBTITLE_COLOR_PLACEHOLDER"          // default: "#8c8c8c"
  private let cfgPrimaryLabel = "SHIELD_PRIMARY_LABEL_PLACEHOLDER"            // default: "Earn Free Time"
  private let cfgPrimaryLabelColor = "SHIELD_PRIMARY_LABEL_COLOR_PLACEHOLDER" // default: "#ffffff"
  private let cfgPrimaryBgColor = "SHIELD_PRIMARY_BG_COLOR_PLACEHOLDER"       // default: "#7cb518"
  private let cfgSecondaryLabel = "SHIELD_SECONDARY_LABEL_PLACEHOLDER"        // default: "Not now", "NONE" to hide
  private let cfgSecondaryLabelColor = "SHIELD_SECONDARY_LABEL_COLOR_PLACEHOLDER" // default: "#8c8c8c"
  private let cfgBgColor = "SHIELD_BG_COLOR_PLACEHOLDER"                      // default: "NONE" (no tint)
  private let cfgBlurStyle = "SHIELD_BLUR_STYLE_PLACEHOLDER"                  // default: "systemThickMaterial"

  // ── Helpers ───────────────────────────────────────────────────────────

  private func hexColor(_ hex: String) -> UIColor {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }

    var rgb: UInt64 = 0
    Scanner(string: h).scanHexInt64(&rgb)

    if h.count == 8 { // RRGGBBAA
      return UIColor(
        red: CGFloat((rgb >> 24) & 0xFF) / 255,
        green: CGFloat((rgb >> 16) & 0xFF) / 255,
        blue: CGFloat((rgb >> 8) & 0xFF) / 255,
        alpha: CGFloat(rgb & 0xFF) / 255
      )
    }
    return UIColor(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1.0
    )
  }

  private func resolveBlurStyle(_ name: String) -> UIBlurEffect.Style {
    switch name {
    case "extraLight": return .extraLight
    case "light": return .light
    case "dark": return .dark
    case "regular": return .regular
    case "prominent": return .prominent
    case "systemUltraThinMaterial": return .systemUltraThinMaterial
    case "systemThinMaterial": return .systemThinMaterial
    case "systemMaterial": return .systemMaterial
    case "systemThickMaterial": return .systemThickMaterial
    case "systemChromeMaterial": return .systemChromeMaterial
    case "systemUltraThinMaterialLight": return .systemUltraThinMaterialLight
    case "systemThinMaterialLight": return .systemThinMaterialLight
    case "systemMaterialLight": return .systemMaterialLight
    case "systemThickMaterialLight": return .systemThickMaterialLight
    case "systemChromeMaterialLight": return .systemChromeMaterialLight
    case "systemUltraThinMaterialDark": return .systemUltraThinMaterialDark
    case "systemThinMaterialDark": return .systemThinMaterialDark
    case "systemMaterialDark": return .systemMaterialDark
    case "systemThickMaterialDark": return .systemThickMaterialDark
    case "systemChromeMaterialDark": return .systemChromeMaterialDark
    default: return .systemThickMaterial
    }
  }

  private var mascotIcon: UIImage? {
    let bundle = Bundle(for: type(of: self))
    return UIImage(named: "shield-icon", in: bundle, compatibleWith: nil)
      ?? UIImage(contentsOfFile: bundle.path(forResource: "shield-icon", ofType: "png") ?? "")
  }

  private func getBlockedAppCount() -> Int {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }
    guard let config = defaults.dictionary(forKey: "appBlocker.blockConfiguration.v1") else { return 0 }
    if let items = config["blockedItems"] as? [[String: Any]] { return items.count }
    return 0
  }

  private func isTemporarilyUnlocked() -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return false }
    guard let exp = defaults.object(forKey: "appBlocker.temporaryUnlock.v1") as? Date else { return false }
    return Date() < exp
  }

  private func buildConfig(appName: String) -> ShieldConfiguration {
    if isTemporarilyUnlocked() {
      return ShieldConfiguration(
        backgroundBlurStyle: resolveBlurStyle(cfgBlurStyle),
        backgroundColor: cfgBgColor == "NONE" ? nil : hexColor(cfgBgColor),
        icon: mascotIcon,
        title: ShieldConfiguration.Label(text: "Almost there!", color: hexColor(cfgTitleColor)),
        subtitle: ShieldConfiguration.Label(text: "Your free time is loading. Try again in a moment.", color: hexColor(cfgSubtitleColor)),
        primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .white),
        primaryButtonBackgroundColor: hexColor(cfgPrimaryBgColor),
        secondaryButtonLabel: nil
      )
    }

    let title = cfgTitle.replacingOccurrences(of: "{appName}", with: appName)
    let subtitle = cfgSubtitle.replacingOccurrences(of: "{appName}", with: appName)
    let count = getBlockedAppCount()
    let fullSubtitle = count > 1
      ? "\(subtitle) You have \(count) apps blocked."
      : subtitle

    let secondaryLabel: ShieldConfiguration.Label? =
      cfgSecondaryLabel == "NONE" ? nil :
      ShieldConfiguration.Label(text: cfgSecondaryLabel, color: hexColor(cfgSecondaryLabelColor))

    return ShieldConfiguration(
      backgroundBlurStyle: resolveBlurStyle(cfgBlurStyle),
      backgroundColor: cfgBgColor == "NONE" ? nil : hexColor(cfgBgColor),
      icon: mascotIcon,
      title: ShieldConfiguration.Label(text: title, color: hexColor(cfgTitleColor)),
      subtitle: ShieldConfiguration.Label(text: fullSubtitle, color: hexColor(cfgSubtitleColor)),
      primaryButtonLabel: ShieldConfiguration.Label(text: cfgPrimaryLabel, color: hexColor(cfgPrimaryLabelColor)),
      primaryButtonBackgroundColor: hexColor(cfgPrimaryBgColor),
      secondaryButtonLabel: secondaryLabel
    )
  }

  // ── Overrides ─────────────────────────────────────────────────────────

  override func configuration(shielding application: Application) -> ShieldConfiguration {
    buildConfig(appName: application.localizedDisplayName ?? "This app")
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    buildConfig(appName: category.localizedDisplayName ?? "This category")
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    buildConfig(appName: webDomain.domain ?? "This website")
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    buildConfig(appName: webDomain.domain ?? "This website")
  }
}
