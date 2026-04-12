# expo-app-blocker

Cross-platform app blocking module for Expo. Block other apps and redirect users to your app.

**Android**: UsageStatsManager + Foreground Service + System Overlay
**iOS**: Screen Time API (FamilyControls + ManagedSettings + DeviceActivity)

## Features

- Block specific apps from being used
- Detect when a blocked app is opened (Android: polling, iOS: system shield)
- Customizable iOS shield overlay (icon, title, subtitle, button text, colors)
- Temporary unlock with timer
- Auto-relock when unlock period expires (iOS DeviceActivityMonitor extension)
- Notification when blocked app is detected
- Persist blocked apps across app restarts
- Native view for rendering blocked app names/icons on iOS (Apple's opaque tokens)
- Automatic iOS extension target creation via `@bacons/apple-targets`
- Full Expo Config Plugin - no manual native setup required

## Prerequisites

### Apple Developer Portal (iOS)

> **Full step-by-step guide**: [docs/APPLE_DEVELOPER_SETUP.md](docs/APPLE_DEVELOPER_SETUP.md)

1. Register **4 App IDs** with **Family Controls** and **App Groups** capabilities:
   - `com.yourapp.id` (main app)
   - `com.yourapp.id.DeviceActivityMonitor`
   - `com.yourapp.id.ShieldAction`
   - `com.yourapp.id.ShieldConfiguration`

2. Create an **App Group**: `group.com.yourapp.blocker` (or your chosen identifier)

3. Assign the App Group to all 4 App IDs

4. Request **Family Controls** capability approval (works in dev builds without approval)

### Android

No special setup required beyond what the config plugin handles automatically.

## Installation

```bash
npx expo install expo-app-blocker
```

> `@bacons/apple-targets` is included as a dependency for automatic iOS extension target creation.

## Configuration

Add the plugin to your `app.json`:

```json
{
  "expo": {
    "scheme": "myapp",
    "ios": {
      "bundleIdentifier": "com.yourapp.id",
      "appleTeamId": "YOUR_TEAM_ID"
    },
    "android": {
      "package": "com.yourapp.id"
    },
    "plugins": [
      ["expo-app-blocker", {
        "ios": {
          "appGroup": "group.com.yourapp.blocker",
          "shield": {
            "title": "Hold on!",
            "subtitle": "{appName} is blocked.",
            "primaryButtonLabel": "Earn Free Time",
            "secondaryButtonLabel": "Not now",
            "primaryButtonColor": "#fb6107",
            "backgroundColor": "#f6f6f6",
            "backgroundBlurStyle": "systemThickMaterialLight",
            "icon": "./assets/shield-icon.png"
          }
        }
      }]
    ]
  }
}
```

### Plugin Options

| Option | Type | Default | Description |
|---|---|---|---|
| `ios.appGroup` | `string` | Required | App Group identifier for shared data |
| `ios.shield.title` | `string` | `"Hold on!"` | Shield overlay title |
| `ios.shield.subtitle` | `string` | `"{appName} is blocked."` | Shield subtitle. `{appName}` is replaced with the blocked app name |
| `ios.shield.primaryButtonLabel` | `string` | `"Earn Free Time"` | Primary button text |
| `ios.shield.secondaryButtonLabel` | `string\|null` | `"Not now"` | Secondary button text. Set to `null` to hide |
| `ios.shield.primaryButtonColor` | `string` | `"#fb6107"` | Primary button background color (hex) |
| `ios.shield.titleColor` | `string` | `"#111111"` | Title text color (hex) |
| `ios.shield.subtitleColor` | `string` | `"#737373"` | Subtitle text color (hex) |
| `ios.shield.backgroundColor` | `string\|null` | `null` | Solid background color (hex). e.g. `"#f6f6f6"` for light, `"#1a1a2e"` for dark |
| `ios.shield.backgroundBlurStyle` | `string\|null` | `"systemThickMaterial"` | Blur style. Auto-defaults when no backgroundColor. See below for all options |
| `ios.shield.icon` | `string` | SF Symbol | Path to custom shield icon PNG (relative to project root, e.g. `"./assets/shield-icon.png"`) |
| `android.notificationTitle` | `string` | `"App Blocked"` | Notification title |
| `android.notificationText` | `string` | `"{appName} is blocked."` | Notification text |

### EAS Build

For EAS Build, declare extensions for credential management:

```json
{
  "extra": {
    "eas": {
      "build": {
        "experimental": {
          "ios": {
            "appExtensions": [
              {
                "targetName": "DeviceActivityMonitor",
                "bundleIdentifier": "com.yourapp.id.DeviceActivityMonitor",
                "entitlements": {
                  "com.apple.developer.family-controls": true,
                  "com.apple.security.application-groups": ["group.com.yourapp.blocker"]
                }
              },
              {
                "targetName": "ShieldAction",
                "bundleIdentifier": "com.yourapp.id.ShieldAction",
                "entitlements": {
                  "com.apple.developer.family-controls": true,
                  "com.apple.security.application-groups": ["group.com.yourapp.blocker"]
                }
              },
              {
                "targetName": "ShieldConfiguration",
                "bundleIdentifier": "com.yourapp.id.ShieldConfiguration",
                "entitlements": {
                  "com.apple.developer.family-controls": true,
                  "com.apple.security.application-groups": ["group.com.yourapp.blocker"]
                }
              }
            ]
          }
        }
      }
    }
  }
}
```

## Build

```bash
# Generate native projects
npx expo prebuild --clean

# Run on Android
npx expo run:android

# Run on iOS (physical device required for Screen Time APIs)
npx expo run:ios --device
```

## API Reference

### Permissions

```typescript
import { getPermissionStatus, requestPermissions } from 'expo-app-blocker';

// Check current permission status
const status = await getPermissionStatus();
// Returns: { allGranted: boolean, details: AndroidPermissions | IOSPermissions }

// Request permissions (iOS: triggers Screen Time authorization)
const result = await requestPermissions();
```

### Android: Permission Settings

```typescript
import { openOverlaySettings, openUsageStatsSettings } from 'expo-app-blocker';

// Open system settings for overlay permission
openOverlaySettings();

// Open system settings for usage access
openUsageStatsSettings();
```

### Android: App Blocking

```typescript
import { setBlockedApps, getBlockedApps, getInstalledApps } from 'expo-app-blocker';

// Get list of installed apps
const apps = await getInstalledApps();
// Returns: [{ packageName: string, name: string }]

// Set which apps to block (by package name)
setBlockedApps(['com.instagram.android', 'com.google.android.youtube']);

// Get currently blocked apps
const blocked = getBlockedApps();
// Returns: ['com.instagram.android', 'com.google.android.youtube']
```

### Android: Monitoring Control

```typescript
import { startMonitoring, stopMonitoring } from 'expo-app-blocker';

// Start the foreground service (auto-started on module init)
startMonitoring();

// Stop monitoring
stopMonitoring();
```

### iOS: App Selection (Modal)

```typescript
import { presentFamilyActivityPicker } from 'expo-app-blocker';

// Opens the iOS system app/category picker as a modal sheet
const items = await presentFamilyActivityPicker();
// Returns: IOSBlockedItem[] - opaque tokens for selected apps/categories
```

### iOS: App Selection (Inline - Embedded in your UI)

Renders the system `FamilyActivityPicker` directly in your app's UI (like Duolingo), instead of a modal:

```typescript
import { FamilyActivityPickerView } from 'expo-app-blocker';

// In your component
<FamilyActivityPickerView
  initialSelection={selectionBase64}  // optional: restore previous selection
  onSelectionChange={(event) => {
    // event.items: IOSBlockedItem[] - selected apps/categories
    // event.totalApps: number
    // event.totalCategories: number
    // event.selectionData: string - base64 to pass back as initialSelection
    console.log(`Selected ${event.totalApps} apps`);
  }}
  style={{ height: 500 }}
/>
```

### iOS: Block Configuration

```typescript
import { setBlockConfiguration, getBlockConfiguration, clearAllBlocks } from 'expo-app-blocker';

// Apply blocks (shields appear on selected apps)
await setBlockConfiguration({
  blockedItems: items, // from presentFamilyActivityPicker()
  isActive: true,
});

// Get current configuration
const config = getBlockConfiguration();

// Remove all blocks
clearAllBlocks();
```

### iOS: Temporary Unlock

```typescript
import {
  temporaryUnlock,
  isTemporarilyUnlocked,
  getRemainingUnlockTime,
  relockApps,
} from 'expo-app-blocker';

// Unlock for N minutes (removes shields temporarily)
const result = await temporaryUnlock(15);
// Returns: { unlocked: boolean, expiresAt: number }

// Check if currently unlocked
const unlocked = isTemporarilyUnlocked();

// Get remaining seconds
const seconds = getRemainingUnlockTime();

// Re-lock immediately
await relockApps();
```

### iOS: Shield Button Events

```typescript
import { addPendingUnlockListener, checkAndClearPendingUnlock } from 'expo-app-blocker';

// Check if user tapped shield button while app was closed
const hasPending = checkAndClearPendingUnlock();

// Listen for real-time shield button taps
const subscription = addPendingUnlockListener(() => {
  // User tapped "Earn Free Time" on the shield
  // Navigate to your unlock/quiz screen
});

// Clean up
subscription?.remove();
```

### iOS: Native Blocked Apps List

Renders blocked app tokens with real names and icons using Apple's native Label view:

```typescript
import { BlockedAppsNativeList } from 'expo-app-blocker';

// In your component
<BlockedAppsNativeList
  items={blockedItems}
  selectionData={selectionBase64}
  style={{ minHeight: 200 }}
/>
```

## Platform Notes

### iOS Limitations

- **Physical device required** - Screen Time APIs don't work in the simulator
- **App tokens are opaque** - You cannot extract app names/bundle IDs from tokens. Use `BlockedAppsNativeList` to render them with Apple's native Label
- **FamilyActivityPicker is required** - No API to enumerate installed apps on iOS
- **Shield customization is limited** - Only icon, title, subtitle, button labels, and colors can be changed. No custom views, fonts, or animations
- **Cannot open apps from shield** - Use notifications as a workaround to redirect users to your app

### Android Limitations

- **~500ms detection delay** - The foreground polling interval means a blocked app is briefly visible before the overlay appears
- **Overlay permission requires manual grant** - Users must enable "Display over other apps" in system settings
- **Usage access permission requires manual grant** - Users must enable in system settings
- **OEM battery optimizations** - Some manufacturers (Xiaomi, Samsung, etc.) may kill the foreground service. Users may need to disable battery optimization for your app

### Android Permissions (auto-added by config plugin)

| Permission | Purpose |
|---|---|
| `SYSTEM_ALERT_WINDOW` | Display blocking overlay |
| `FOREGROUND_SERVICE` | Run monitoring service |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Required for Android 14+ |
| `PACKAGE_USAGE_STATS` | Detect foreground app |
| `RECEIVE_BOOT_COMPLETED` | Auto-start service on boot |
| `POST_NOTIFICATIONS` | Show blocked app notifications |

## How It Works

### Android Flow

1. `ExpoAppBlockerModule` starts `AppBlockerService` as a foreground service
2. Service polls `UsageStatsManager` every 500ms to detect the foreground app
3. If the foreground app is in the blocked list:
   - A full-screen overlay covers the screen
   - A notification is sent with a deep link to your app
   - Your app is brought to the foreground
4. Blocked apps are persisted in SharedPreferences

### iOS Flow

1. User authorizes Screen Time via `requestPermissions()`
2. User selects apps to block via `presentFamilyActivityPicker()`
3. `setBlockConfiguration()` applies shields via `ManagedSettingsStore`
4. When a blocked app is opened, iOS shows the shield overlay (customized via `ShieldConfigurationExtension`)
5. When the user taps the shield button, `ShieldActionExtension` sends a notification via Darwin notification center
6. Your app receives the event and can navigate to an unlock flow
7. `temporaryUnlock()` removes shields for a duration
8. `DeviceActivityMonitor` extension re-applies shields when the unlock period expires

## Contributing

Contributions are welcome! Please open an issue or PR.

## License

MIT
