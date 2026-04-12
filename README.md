# expo-app-blocker

Cross-platform app blocking module for Expo. Block other apps and redirect users to your app.

**Android**: UsageStatsManager + Foreground Service + System Overlay
**iOS**: Screen Time API (FamilyControls + ManagedSettings + DeviceActivity)

> **iOS requires Apple Developer Portal setup before building.** See [Prerequisites](#prerequisites) for details.

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

## Quick Start

### 1. Install

```bash
npx expo install expo-app-blocker
```

### 2. Configure `app.json`

```json
{
  "expo": {
    "scheme": "myapp",
    "ios": {
      "bundleIdentifier": "com.yourapp.id",
      "appleTeamId": "YOUR_TEAM_ID"
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

4. Request **Family Controls** capability approval (works in dev builds without approval)

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
| `android.notificationTitle` | `string` | `"App Blocked"` | Notification title |
| `android.notificationText` | `string` | `"{appName} is blocked."` | Notification text |

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

Contributions are welcome! Please open an issue or PR.

## License

MIT
