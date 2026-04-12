# Contributing to expo-app-blocker

Thanks for your interest in contributing! This guide will help you get set up and familiar with the project structure.

## Project Structure

```
expo-app-blocker/
├── src/                        # TypeScript API (module bridge + types)
│   ├── index.ts                # Public API — all exports
│   └── ExpoAppBlocker.types.ts # Type definitions
├── ios/                        # iOS native module (Swift)
│   ├── ExpoAppBlockerModule.swift        # Main module (permissions, blocking, unlock)
│   ├── ExpoAppBlockerPickerModule.swift  # Inline FamilyActivityPicker view
│   ├── ExpoAppBlockerConfig.swift        # App group config
│   └── ExpoAppBlocker.podspec           # CocoaPods spec
├── android/                    # Android native module (Kotlin)
│   └── src/main/java/expo/modules/appblocker/
│       ├── ExpoAppBlockerModule.kt  # Main module
│       ├── AppBlockerService.kt     # Foreground service (polling)
│       ├── OverlayManager.kt        # Full-screen overlay
│       ├── AppBlockerPrefs.kt       # SharedPreferences wrapper
│       └── BootReceiver.kt          # Auto-start on boot
├── targets/                    # iOS extension templates (copied at prebuild)
│   ├── DeviceActivityMonitor/  # Re-applies shields when unlock expires
│   ├── ShieldAction/           # Handles shield button taps
│   └── ShieldConfiguration/    # Custom shield UI (title, colors, icon)
├── plugin/                     # Expo config plugin
│   └── src/index.js            # Android manifest + iOS entitlements/Podfile patches
├── app.plugin.js               # Plugin entry point
├── expo-module.config.json     # Expo module registration
└── docs/
    └── APPLE_DEVELOPER_SETUP.md
```

## Development Setup

### Prerequisites

- Node.js 18+
- A physical iOS device (Screen Time APIs don't work in the simulator)
- Xcode 15+ with iOS 16+ SDK
- Android Studio (for Android development)
- An [Apple Developer account](docs/APPLE_DEVELOPER_SETUP.md) with Family Controls capability

### Getting Started

1. **Clone the repo**

   ```bash
   git clone https://github.com/eylonshm/expo-app-blocker.git
   cd expo-app-blocker
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Set up a test app**

   The easiest way to test changes is with a local Expo app that references the package via file path:

   ```bash
   # In your test app's directory
   npm install ../expo-app-blocker
   ```

   Then in your test app's `app.json`:

   ```json
   {
     "plugins": [
       ["expo-app-blocker", {
         "ios": {
           "appGroup": "group.com.yourapp.test",
           "shield": { "title": "Test Shield" }
         }
       }]
     ]
   }
   ```

4. **Build and test**

   ```bash
   # In your test app
   npx expo prebuild --clean
   npx expo run:ios --device     # iOS (physical device only)
   npx expo run:android          # Android
   ```

## Making Changes

### TypeScript API (`src/`)

- `index.ts` is the public API surface. All functions and components are exported from here.
- `ExpoAppBlocker.types.ts` has all type definitions. Keep JSDoc comments up to date.
- Platform guards (`Platform.OS === "ios"`) are used throughout — iOS-only features return `null`/no-op on Android and vice versa.

### iOS Native (`ios/`)

- `ExpoAppBlockerModule.swift` — The main module. Handles FamilyControls authorization, ManagedSettingsStore for shields, DeviceActivityCenter for scheduled relock, token encoding/decoding, and the `BlockedAppsNativeList` view.
- `ExpoAppBlockerPickerModule.swift` — Separate module for the inline `FamilyActivityPickerView`. Registered as `ExpoAppBlockerPicker` in `expo-module.config.json`.
- iOS extensions in `targets/` use **placeholder injection** — Swift files contain `PLACEHOLDER` strings that the config plugin replaces at prebuild time with user-configured values.

### Android Native (`android/`)

- `ExpoAppBlockerModule.kt` — Expo module exposing functions to JS.
- `AppBlockerService.kt` — Foreground service that polls `UsageStatsManager` every 500ms.
- `OverlayManager.kt` — `TYPE_APPLICATION_OVERLAY` window that covers blocked apps.

### Config Plugin (`plugin/src/index.js`)

The config plugin patches native projects at prebuild time:
- **Android**: Adds permissions, service, and boot receiver to `AndroidManifest.xml`
- **iOS**: Adds entitlements, patches Podfile deployment target, copies extension templates from `targets/` and replaces placeholders with user config (shield text, colors, app group, etc.)

### Extension Templates (`targets/`)

iOS extension Swift files use placeholders like `APP_GROUP_PLACEHOLDER`, `SHIELD_TITLE_PLACEHOLDER`, etc. The config plugin copies these from `node_modules` (fresh copies each prebuild) and replaces placeholders with values from the user's `app.json` plugin config.

## Testing

Since this module depends on platform-specific APIs (Screen Time on iOS, UsageStats on Android), automated testing is limited. Test manually:

- **iOS**: Verify on a physical device that the picker shows apps, shields appear on blocked apps, unlock/relock works, and shield button events are received.
- **Android**: Verify on an emulator or device that the overlay appears when opening a blocked app, notifications are sent, and the service restarts on boot.
- **Config plugin**: Run `npx expo prebuild --clean` and inspect the generated native projects to verify manifest entries, entitlements, and placeholder replacements.

## Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Update the README if you add or change any public API, props, or config options
- Add JSDoc comments to new types and exported functions
- Test on both platforms when possible (or note which platform was tested)
- Follow the existing code style (no linter configured — just match what's there)

## Reporting Issues

When reporting a bug, please include:

- `expo-app-blocker` version
- Expo SDK version
- Platform (iOS/Android) and OS version
- Device model (physical vs simulator)
- Steps to reproduce
- Error messages or logs (Xcode console for iOS, `adb logcat` for Android)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
