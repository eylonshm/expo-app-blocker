import Foundation

// This file provides default configuration values.
// The actual values are injected by the config plugin at prebuild time
// into a generated file in the app's ios directory.
// If the generated file exists, its values override these defaults.

public struct ExpoAppBlockerConfig {
  // Override this in your app by creating a file with:
  // let expoAppBlockerAppGroup = "group.com.yourapp.blocker"
  public static var appGroupIdentifier: String {
    // Try to read from UserDefaults (set by config plugin)
    if let appGroup = UserDefaults.standard.string(forKey: "expo.appblocker.appGroup") {
      return appGroup
    }
    // Fallback - should be overridden
    return "group.expo.app-blocker"
  }
}
