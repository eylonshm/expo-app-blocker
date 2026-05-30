# expo-app-blocker

Cross-platform app blocking module for Expo. Block other apps and redirect users to your app.

**Android**: UsageStatsManager + Foreground Service + System Overlay
**iOS**: Screen Time API (FamilyControls + ManagedSettings + DeviceActivity)

## Demo

https://github.com/user-attachments/assets/37f34797-6b92-40d5-911a-90c40e9ffaaa


> **iOS requires Apple Developer Portal setup before building.** See [Prerequisites](#prerequisites) for details.

> [!IMPORTANT]
> **Submit your Family Controls distribution approval request now.** App Store distribution requires Apple approval per bundle ID — it can take days to weeks and you can't ship without it. [Request here](https://developer.apple.com/contact/request/family-controls-distribution) (you'll need to submit once per bundle ID — 4 total).
>
> **While waiting for approval**, use the **Family Controls (Development)** capability in Xcode instead of the standard "Family Controls" — it's marked "Development only" in Xcode's Signing & Capabilities tab and works without Apple's approval. Development builds with this entitlement are fully functional on device but cannot be submitted to TestFlight or the App Store.

<details>
<summary><strong>Table of Contents</strong></summary>

- [Features](#features)
- [Build Compatibility](#build-compatibility)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Plugin Options](#plugin-options)
  - [Blur Styles](#blur-styles)
  - [EAS Build](#eas-build)
- [API Reference](#api-reference)
  - [Permissions](#permissions)
  - [Android: Permission Settings](#android-permission-settings)
  - [Android: App Blocking](#android-app-blocking)
  - [Android: Monitoring](#android-monitoring)
  - [iOS: App Selection (Inline Picker)](#inline-picker-recommended)
  - [iOS: App Selection (Modal Picker)](#modal-picker)
  - [iOS: Block Configuration](#ios-block-configuration)
  - [iOS: Temporary Unlock](#ios-temporary-unlock)
  - [iOS: Shield Button Events](#ios-shield-button-events)
  - [iOS: Blocked Apps List](#ios-blocked-apps-list)
- [Full Example: iOS App Blocker](#full-example-ios-app-blocker)
- [Platform Notes](#platform-notes)
- [How It Works](#how-it-works)
- [Contributing](CONTRIBUTING.md)

</details>

## Features

- Block specific apps from being used
- Inline app picker - embed the iOS system app picker directly in your UI (like Duolingo)
- Modal app picker - present the system picker as a sheet
- Customizable iOS shield overlay (icon, title, subtitle, button text, colors, blur style)
- Native view for rendering blocked app names/icons (Apple's opaque tokens)
- Temporary unlock with timer
- Auto-relock when unlock period expires (iOS DeviceActivityMonitor extension)
- Notification when blocked app is detected
- Persist blocked apps across app restarts
- Automatic iOS extension target creation via `@bacons/apple-targets`
- Full Expo Config Plugin - no manual native setup required

## Build Compatibility

| Build type | Supported | Notes |
|---|---|---|
| **Expo Go** | ❌ | Requires custom native modules — not available in Expo Go |
| **Development build** (`expo-dev-client`) | ✅ | Fully supported — same setup as production |
| **Local build** (`expo run:ios` / `expo run:android`) | ✅ | Fully supported |
| **EAS Build** | ✅ | Fully supported — see [EAS Build config](#eas-build) |
| **Production / App Store** | ✅ | Fully supported — iOS requires Apple approval first |

**This plugin requires a development build or a production build.** If you're using Expo Go, you'll need to [create a development build](https://docs.expo.dev/develop/development-builds/introduction/) first:

```bash
npx expo install expo-dev-client
npx expo run:ios --device    # or: eas build --profile development
```

## Quick Start

### 1. Install

```bash
npx expo install expo-app-blocker
```

### 2. Configure `app.json`

> **Two things are required on iOS** and skipping either produces a cryptic build failure:
> 1. `ios.appleTeamId` — `@bacons/apple-targets` (auto-registered by this plugin) refuses to add the extension targets without it.
> 2. `ios.entitlements` with **Family Controls + the App Group** — the extension `expo-target.config.js` files read `ios.entitlements['com.apple.security.application-groups'][0]` to learn which App Group to embed. If it's missing they fall back to `group.expo.app-blocker` and the build fails with `An Application Group with Identifier 'group.expo.app-blocker' is not available`.

```json
{
  "expo": {
    "scheme": "myapp",
    "ios": {
      "bundleIdentifier": "com.yourapp.id",
      "appleTeamId": "YOUR_TEAM_ID",
      "entitlements": {
        "com.apple.developer.family-controls": true,
        "com.apple.security.application-groups": ["group.com.yourapp.blocker"]
      }
    },
    "plugins": [
      ["expo-app-blocker", {
        "ios": {
          "appGroup": "group.com.yourapp.blocker",
          "shield": {
            "title": "Hold on!",
            "subtitle": "{appName} is blocked.",
            "primaryButtonLabel": "Earn Free Time",
            "primaryButtonColor": "#fb6107",
            "backgroundColor": "#f6f6f6",
            "backgroundBlurStyle": "systemThickMaterialLight"
          }
        }
      }]
    ]
  }
}
```

> The App Group identifier in `ios.entitlements` and `expo-app-blocker.ios.appGroup` **must match** — they describe the same shared-storage container for the main app and the three extensions.

> **Monorepo note (pnpm / yarn workspaces):** `@bacons/apple-targets` is declared as a direct dependency of `expo-app-blocker` and is auto-registered by this plugin, so most monorepo setups work out of the box. If you ever see `Failed to load '@bacons/apple-targets'` during prebuild, add it as a direct dependency of your app (`pnpm add @bacons/apple-targets`) to defeat the workspace's resolver isolation.

### 3. Use in your app

```tsx
import {
  requestPermissions,
  setBlockConfiguration,
  clearAllBlocks,
  temporaryUnlock,
  FamilyActivityPickerView,
  type FamilyActivityPickerSelectionEvent,
} from 'expo-app-blocker';

function AppBlockerScreen() {
  const [selectionData, setSelectionData] = useState('');

  // 1. Request Screen Time permission (call once)
  const handleAuth = async () => {
    const { allGranted } = await requestPermissions();
    if (!allGranted) console.log('User denied Screen Time access');
  };

  // 2. Handle selection changes from the inline picker
  const handleSelectionChange = async (event: FamilyActivityPickerSelectionEvent) => {
    setSelectionData(event.selectionData);

    if (event.items.length > 0) {
      // Apply blocks — shields appear immediately on selected apps
      await setBlockConfiguration({ blockedItems: event.items, isActive: true });
    } else {
      clearAllBlocks();
    }
  };

  return (
    <View>
      {/* Inline app picker — renders the iOS system picker in your UI */}
      <FamilyActivityPickerView
        initialSelection={selectionData}
        onSelectionChange={handleSelectionChange}
        theme="light"
        style={{ height: 500 }}
      />

      {/* Unlock apps temporarily (e.g. after completing a quiz) */}
      <Button
        title="Unlock for 15 minutes"
        onPress={() => temporaryUnlock(15)}
      />
    </View>
  );
}
```

### 4. Build and run

```bash
npx expo prebuild --clean
npx expo run:ios --device    # physical device required for Screen Time APIs
npx expo run:android         # Android works on emulator
```

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

4. Request **Family Controls** capability approval (required for App Store/TestFlight distribution)
   - Submit the form **once per bundle ID** (4 total): [developer.apple.com/contact/request/family-controls-distribution](https://developer.apple.com/contact/request/family-controls-distribution)
   - **While waiting for approval**: use **Family Controls (Development)** in Xcode's Signing & Capabilities tab — fully functional in dev builds, just not distributable
   - Incomplete capability setup causes cryptic provisioning errors — make sure all 4 App IDs have Family Controls + App Groups enabled

### Android

No special setup required beyond what the config plugin handles automatically.

## Plugin Options

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
| `ios.shield.backgroundBlurStyle` | `string\|null` | `"systemThickMaterial"` | Blur style. See [Blur Styles](#blur-styles) for all options |
| `ios.shield.icon` | `string` | SF Symbol | Path to custom shield icon PNG (e.g. `"./assets/shield-icon.png"`) |
| `ios.shield.tempUnlockTitle` | `string` | `"Almost there!"` | Title shown briefly while ManagedSettings clears after a successful unlock |
| `ios.shield.tempUnlockSubtitle` | `string` | `"Your free time is loading. Try again in a moment."` | Subtitle for the temporary-unlock state |
| `ios.shield.tempUnlockButtonLabel` | `string` | `"OK"` | Button label for the temporary-unlock state |
| `ios.shield.countSuffix` | `string` | `" You have {count} apps blocked."` | Appended to the subtitle when more than one app is blocked. `{count}` is replaced with the integer at runtime. Set to `""` to drop the suffix entirely. |
| `ios.notification.title` | `string` | `"App Blocker"` | Title of the local notification fired when the user taps the Shield primary button. Set to a Hebrew/Arabic/etc. string to localize. |
| `ios.notification.body` | `string` | `"Tap to return to the app and complete the unlock challenge."` | Body of the unlock notification |
| `ios.notification.attachIcon` | `boolean` | `true` | Whether to attach the shield icon as a notification image. Set to `false` to avoid the duplicate-icon look on iOS notification banners (the system app icon is always shown either way). |
| `android.notificationTitle` | `string` | `"App Blocked"` | Notification title |
| `android.notificationText` | `string` | `"{appName} is blocked."` | Notification text |
| `android.overlay.icon` | `string` | — | Path to the brand icon shown above the title in the `SYSTEM_ALERT_WINDOW` overlay. Resolved relative to the project root. PNG with transparent background recommended. Build-time only — not adjustable at runtime. |

### Android Overlay (runtime configurable via `setAndroidConfig`)

The `SYSTEM_ALERT_WINDOW` overlay flashed on top of a blocked app is fully themeable. All fields below are optional — defaults preserve the previous "App Blocked" + grey-on-white look. Pass them as a single object to `ExpoAppBlocker.setAndroidConfig({ ... })` once at app boot:

| Field | Type | Default | Description |
|---|---|---|---|
| `overlayTitle` | `string` | `"App Blocked"` | Bold heading. `{appName}` is replaced with the localized app name (e.g. `"Instagram is blocked"`). |
| `overlayText` | `string` | `"{appName} is blocked."` | Body line under the title. `{appName}` placeholder supported. |
| `overlayBackgroundColor` | `string` (hex) | `"#FFFFFF"` | Solid background color for the full-screen overlay. |
| `overlayTitleColor` | `string` (hex) | `"#111111"` | Title text color. |
| `overlayTextColor` | `string` (hex) | `"#737373"` | Body text color. |
| `overlayTitleFontSize` | `number` (sp) | `24` | Title font size. Android `sp` units — scales with system font setting. |
| `overlayTextFontSize` | `number` (sp) | `16` | Body font size. |
| `overlayTitleBold` | `boolean` | `true` | Render the title with `Typeface.BOLD`. Set to `false` for a regular weight. |
| `overlayPadding` | `number` (dp) | `32` | Inner padding on all four sides of the overlay's `LinearLayout`. |
| `overlayIconSize` | `number` (dp) | `96` | Square icon edge length. Only renders when `android.overlay.icon` was declared in the plugin config (build-time). |
| `overlayIconBottomMargin` | `number` (dp) | `20` | Vertical gap between the icon and the title. |
| `overlayTitleBottomMargin` | `number` (dp) | `12` | Vertical gap between the title and the body text. |
| `overlayShowSpinner` | `boolean` | `false` | Render an indeterminate Material circular spinner below the body text — same shape RN's `<ActivityIndicator>` produces. Useful as a "launching…" cue during the brief gap between intercept and the deep-link landing. |
| `overlaySpinnerSize` | `number` (dp) | `32` | Spinner edge length (square). Only used when `overlayShowSpinner` is true. |
| `overlaySpinnerTopMargin` | `number` (dp) | `24` | Vertical gap between the body text and the spinner. |
| `overlaySpinnerColor` | `string` (hex) | system primary | Tints the spinner. Useful to match your brand color. |
| `notificationTitle` | `string` | `"App Blocked"` | Foreground-service notification title. |
| `notificationText` | `string` | `"{appName} is blocked. Tap to manage."` | Foreground-service notification body. |

Example (matches a Hebrew RTL app with brand colors + a logo above the title):

```ts
import * as ExpoAppBlocker from 'expo-app-blocker';

ExpoAppBlocker.setAndroidConfig({
  overlayTitle: 'האפליקציה חסומה',
  overlayText: 'ענה על כמה שאלות כדי להשתמש בה',
  overlayBackgroundColor: '#f6f6f6',
  overlayTitleColor: '#111111',
  overlayTextColor: '#888888',
  overlayTitleFontSize: 26,
  overlayTextFontSize: 16,
  overlayTitleBold: true,
  overlayPadding: 32,
  overlayIconSize: 112,
  overlayIconBottomMargin: 20,
  overlayTitleBottomMargin: 12,
  notificationTitle: 'גרנדמייזר',
  notificationText: 'ענה על השאלות כדי לפתוח את האפליקציה',
});
```

**Why two layers?** `android.overlay.icon` is build-time because Android resolves drawable resources by ID, which requires the bitmap to be packed into the APK. Everything else (text, colors, sizes) lives in `SharedPreferences` and can be updated by your JS at any time — no rebuild required.

### Blur Styles

| Category | Values |
|---|---|
| Adaptive (auto light/dark) | `systemUltraThinMaterial`, `systemThinMaterial`, `systemMaterial`, `systemThickMaterial`, `systemChromeMaterial` |
| Light only | `systemUltraThinMaterialLight`, `systemThinMaterialLight`, `systemMaterialLight`, `systemThickMaterialLight`, `systemChromeMaterialLight` |
| Dark only | `systemUltraThinMaterialDark`, `systemThinMaterialDark`, `systemMaterialDark`, `systemThickMaterialDark`, `systemChromeMaterialDark` |
| Legacy | `regular`, `prominent`, `light`, `dark`, `extraLight` |

Both `backgroundColor` and `backgroundBlurStyle` can be combined — the blur renders behind the color.

### EAS Build

For EAS Build, declare extensions in `app.json` for credential management:

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

## API Reference

### Permissions

```typescript
import { getPermissionStatus, requestPermissions } from 'expo-app-blocker';

// Check current status
const status = await getPermissionStatus();
// { allGranted: boolean, details: AndroidPermissions | IOSPermissions }

// Request permissions (iOS: Screen Time authorization, Android: no-op)
const result = await requestPermissions();
```

### Android: Permission Settings

```typescript
import { openOverlaySettings, openUsageStatsSettings } from 'expo-app-blocker';

openOverlaySettings();     // "Display over other apps"
openUsageStatsSettings();  // "Usage access"
```

### Android: App Blocking

```typescript
import { setBlockedApps, getBlockedApps, getInstalledApps } from 'expo-app-blocker';

const apps = await getInstalledApps();
// [{ packageName: 'com.instagram.android', name: 'Instagram' }, ...]

setBlockedApps(['com.instagram.android', 'com.google.android.youtube']);
const blocked = getBlockedApps(); // ['com.instagram.android', ...]
```

### Android: Monitoring

```typescript
import { startMonitoring, stopMonitoring } from 'expo-app-blocker';

startMonitoring();   // Start foreground service (auto-started on init)
stopMonitoring();    // Stop monitoring
```

#### Deep-link contract (how your app is launched)

When the foreground service detects a blocked app, it brings **your** app to the
front via a deep link using your app's own URL scheme:

```
<yourScheme>://blocked?app=<AppName>&package=<package.name>&reason=<reason>
```

| Param | Description |
|---|---|
| `app` | Human-readable label of the blocked app (URL-encoded), e.g. `Instagram` |
| `package` | Android package name of the blocked app, e.g. `com.instagram.android` |
| `reason` | Why the block fired — see below. Lets you branch your UI |

`reason` values:

| Value | Meaning |
|---|---|
| `opened` | A blocked app was freshly brought to the foreground. |
| `expired` | A [temporary unlock](#android-temporary-unlock) expired while the user was still **inside** the blocked app. Handle this if you want a softer "time's up" interstitial instead of jumping straight into your gate. |

Handle the deep link with `expo-linking` / `expo-router` like any other route.
Your scheme is auto-detected from the app config; no extra setup required.

### iOS: App Selection

Two ways to let users pick which apps to block:

#### Inline Picker (Recommended)

Embeds Apple's `FamilyActivityPicker` directly in your UI — the same approach Duolingo and other Screen Time apps use. The picker renders as a searchable native view with app and category lists.

```tsx
import { FamilyActivityPickerView, setBlockConfiguration } from 'expo-app-blocker';

<FamilyActivityPickerView
  initialSelection={selectionData}
  onSelectionChange={async (event) => {
    setSelectionData(event.selectionData); // save for next mount
    await setBlockConfiguration({ blockedItems: event.items, isActive: true });
  }}
  theme="light"
  style={{ height: 500 }}
/>
```

**Props:**

| Prop | Type | Default | Description |
|---|---|---|---|
| `initialSelection` | `string` | — | Base64-encoded selection from a previous `selectionData`. Restores prior selection on mount |
| `onSelectionChange` | `(event) => void` | — | Fires each time the user toggles an app or category |
| `theme` | `"light" \| "dark" \| "system"` | `"system"` | Forces the picker's color scheme |
| `style` | `ViewStyle` | `{ minHeight: 400 }` | Set an explicit `height` for best results |

**`onSelectionChange` event:**

| Field | Type | Description |
|---|---|---|
| `items` | `IOSBlockedItem[]` | Selected apps/categories — pass directly to `setBlockConfiguration()` |
| `totalApps` | `number` | Number of individual apps selected |
| `totalCategories` | `number` | Number of categories selected |
| `selectionData` | `string` | Base64 string — save and pass back as `initialSelection` |

#### Modal Picker

Opens the system picker as a modal sheet. Returns items on "Done", rejects on cancel.

```typescript
import { presentFamilyActivityPicker } from 'expo-app-blocker';

try {
  const items = await presentFamilyActivityPicker();
  await setBlockConfiguration({ blockedItems: items, isActive: true });
} catch (e) {
  // User cancelled
}
```

### iOS: Block Configuration

```typescript
import { setBlockConfiguration, getBlockConfiguration, clearAllBlocks } from 'expo-app-blocker';

// Apply blocks (shields appear on selected apps)
await setBlockConfiguration({
  blockedItems: items, // from picker
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
// { unlocked: boolean, expiresAt: number }

const unlocked = isTemporarilyUnlocked(); // boolean
const seconds = getRemainingUnlockTime(); // seconds remaining
await relockApps();                        // re-lock immediately
```

### Android: Temporary Unlock

The same temporary-unlock API works on Android. The foreground service pauses
blocking for the requested duration and auto-resumes when it expires — the timer
lives in the service, so it survives your app being backgrounded.

```typescript
import {
  temporaryUnlock,
  getRemainingUnlockTime,
  relockApps,
} from 'expo-app-blocker';

// Suppress blocking for N minutes; auto-resumes on expiry
await temporaryUnlock(15);
// { unlocked: true, expiresAt: number }

const seconds = getRemainingUnlockTime(); // seconds remaining, 0 if none
await relockApps();                        // end the unlock now, re-block immediately
```

| Function | Android behavior |
|---|---|
| `temporaryUnlock(minutes)` | Suppresses blocking for `minutes` (min 1, rounded). Replaces any active unlock. |
| `getRemainingUnlockTime()` | Seconds left on the active unlock, or `0`. Backed by a persisted expiry, so it's accurate without the app holding service state. |
| `relockApps()` | Ends the unlock immediately and re-blocks the foreground app on the next poll. |
| `isTemporarilyUnlocked()` | iOS only — returns `false` on Android. Use `getRemainingUnlockTime() > 0` instead. |

> When an unlock expires while the user is still inside a blocked app, the
> deep link fires with `reason=expired` (see [Deep-link contract](#deep-link-contract-how-your-app-is-launched)).

### iOS: Shield Button Events

When a user taps the primary button on the shield overlay, your app receives an event:

```typescript
import { addPendingUnlockListener, checkAndClearPendingUnlock } from 'expo-app-blocker';

// Check if button was tapped while app was closed
const hasPending = checkAndClearPendingUnlock();

// Listen for real-time taps
const subscription = addPendingUnlockListener(() => {
  // Navigate to your unlock/quiz screen
  router.push('/unlock');
});

// Clean up
subscription?.remove();
```

### iOS: Blocked Apps List

Renders blocked app tokens with their real names and icons using Apple's native `Label` view. Since iOS tokens are opaque, this is the only way to display app names/icons outside the picker.

```tsx
import { BlockedAppsNativeList } from 'expo-app-blocker';

<BlockedAppsNativeList
  items={blockedItems}
  selectionData={selectionBase64}
  style={{ minHeight: 200 }}
/>
```

**Props:**

| Prop | Type | Default | Description |
|---|---|---|---|
| `items` | `IOSBlockedItem[]` | Required | Blocked items from picker |
| `selectionData` | `string` | — | Base64 selection for accurate rendering |
| `style` | `ViewStyle` | `{ minHeight: 50 }` | Standard style |

## Full Example: iOS App Blocker

A complete example showing permissions, inline picker, blocking, and temporary unlock:

```tsx
import { useState, useEffect, useCallback } from 'react';
import { View, Text, TouchableOpacity, Platform, StyleSheet } from 'react-native';
import {
  getPermissionStatus,
  requestPermissions,
  setBlockConfiguration,
  getBlockConfiguration,
  clearAllBlocks,
  temporaryUnlock,
  isTemporarilyUnlocked,
  getRemainingUnlockTime,
  relockApps,
  addPendingUnlockListener,
  checkAndClearPendingUnlock,
  FamilyActivityPickerView,
  type PermissionStatus,
  type IOSBlockedItem,
  type FamilyActivityPickerSelectionEvent,
} from 'expo-app-blocker';

export default function BlockerScreen() {
  const [permissions, setPermissions] = useState<PermissionStatus | null>(null);
  const [blockedApps, setBlockedApps] = useState<IOSBlockedItem[]>([]);
  const [selectionData, setSelectionData] = useState('');
  const [unlocked, setUnlocked] = useState(false);

  // Load permissions and existing blocks on mount
  useEffect(() => {
    getPermissionStatus().then(setPermissions);
    const config = getBlockConfiguration();
    if (config?.blockedItems?.length) {
      setBlockedApps(config.blockedItems);
    }
  }, []);

  // Listen for shield button taps
  useEffect(() => {
    if (checkAndClearPendingUnlock()) {
      // User tapped shield button while app was closed
    }
    const sub = addPendingUnlockListener(() => {
      // User tapped shield button — show your unlock UI
    });
    return () => sub?.remove();
  }, []);

  // Handle inline picker selection
  const handleSelectionChange = async (event: FamilyActivityPickerSelectionEvent) => {
    const items = event.items.filter(i => i.type !== 'summary');
    setBlockedApps(items);
    setSelectionData(event.selectionData);

    if (items.length > 0) {
      await setBlockConfiguration({ blockedItems: items, isActive: true });
    } else {
      clearAllBlocks();
    }
  };

  if (Platform.OS !== 'ios') return null;

  return (
    <View style={styles.container}>
      {/* Permission request */}
      {!permissions?.allGranted && (
        <TouchableOpacity
          style={styles.button}
          onPress={async () => {
            const result = await requestPermissions();
            setPermissions(result);
          }}
        >
          <Text style={styles.buttonText}>Enable Screen Time</Text>
        </TouchableOpacity>
      )}

      {/* Inline app picker */}
      {permissions?.allGranted && (
        <View style={styles.pickerContainer}>
          <FamilyActivityPickerView
            initialSelection={selectionData}
            onSelectionChange={handleSelectionChange}
            theme="light"
            style={{ height: 500 }}
          />
        </View>
      )}

      {/* Actions */}
      {blockedApps.length > 0 && (
        <View style={styles.actions}>
          <Text>{blockedApps.length} apps blocked</Text>

          <TouchableOpacity
            style={styles.button}
            onPress={async () => {
              await temporaryUnlock(15);
              setUnlocked(true);
            }}
          >
            <Text style={styles.buttonText}>Unlock 15 min</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.button}
            onPress={() => { clearAllBlocks(); setBlockedApps([]); }}
          >
            <Text style={styles.buttonText}>Clear All</Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  pickerContainer: { borderRadius: 16, overflow: 'hidden', borderWidth: 1, borderColor: '#e8e8e8' },
  actions: { marginTop: 16, gap: 12 },
  button: { backgroundColor: '#fb6107', padding: 16, borderRadius: 12, alignItems: 'center' },
  buttonText: { color: '#fff', fontWeight: '700', fontSize: 16 },
});
```

## Platform Notes

### iOS Limitations

- **Physical device required** - Screen Time APIs don't work in the simulator
- **App tokens are opaque** - You cannot extract app names/bundle IDs from tokens. Use `BlockedAppsNativeList` or `FamilyActivityPickerView` to display them
- **FamilyActivityPicker is required** - No API to enumerate installed apps on iOS
- **Shield customization is limited** - Only icon, title, subtitle, button labels, and colors can be changed. No custom views, fonts, or animations
- **Cannot open apps from shield** - Use notifications as a workaround to redirect users to your app
- **Permission status may lag** - After a user grants or revokes Screen Time access outside your app, the status may not update until the app is restarted. Re-check on app foreground
- **Picker may crash on large categories** - The native `FamilyActivityPicker` can crash when scrolling through very large app categories. Consider providing fallback UI (e.g. a retry button) if this affects your users

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
2. User selects apps to block — inline via `<FamilyActivityPickerView>` or modal via `presentFamilyActivityPicker()`
3. `setBlockConfiguration()` applies shields via `ManagedSettingsStore`
4. When a blocked app is opened, iOS shows the shield overlay (customized via config plugin)
5. When the user taps the shield button, `ShieldActionExtension` sends a notification
6. Your app receives the event via `addPendingUnlockListener()` and can navigate to an unlock flow
7. `temporaryUnlock()` removes shields for a duration
8. `DeviceActivityMonitor` extension re-applies shields when the unlock period expires

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, project structure, and guidelines.

## License

MIT
