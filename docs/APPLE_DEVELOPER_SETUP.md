# Apple Developer Portal Setup

This guide walks you through the one-time setup required in the Apple Developer Portal for `expo-app-blocker` on iOS.

## Prerequisites

- A **paid Apple Developer account** ($99/year)
- Access to https://developer.apple.com/account

---

## Step 0: Request Family Controls Approval (Do This First)

> **Do this before anything else.** App Store and TestFlight distribution require explicit Apple approval for the Family Controls entitlement. Approval can take days to weeks — start the process immediately.

Because `expo-app-blocker` creates 4 bundle identifiers (main app + 3 extensions), **you must submit the request form once for each bundle ID**:

| Bundle ID | Submit for |
|---|---|
| `com.yourapp.id` | Main app |
| `com.yourapp.id.DeviceActivityMonitor` | DeviceActivityMonitor extension |
| `com.yourapp.id.ShieldAction` | ShieldAction extension |
| `com.yourapp.id.ShieldConfiguration` | ShieldConfiguration extension |

Submit each one at: https://developer.apple.com/contact/request/family-controls-distribution

**You can continue with local development builds without waiting for approval.** Approval is only required to distribute via TestFlight or the App Store.

> **Warning:** If you skip or partially complete the capability setup in Steps 2–6, you will run into cryptic provisioning errors during build. Make sure all 4 App IDs have both **Family Controls** and **App Groups** enabled before building.

---

## Step 1: Create the App Group

The App Group enables data sharing between your main app and the three iOS extensions.

1. Go to **Identifiers**: https://developer.apple.com/account/resources/identifiers/list
2. Change the dropdown from **"App IDs"** to **"App Groups"**
   - Or go directly to: https://developer.apple.com/account/resources/identifiers/list/applicationGroup
3. Click the **+** (blue plus) button
4. Select **App Groups** > **Continue**
5. Fill in:
   - **Description**: `Your App Name Shared` (e.g., "My App Blocker Shared")
   - **Identifier**: The value you set in `ios.appGroup` in your plugin config
     - Example: `group.com.yourapp.blocker`
6. Click **Continue** > **Register**

---

## Step 2: Register the Main App ID

1. Go to **Identifiers**: https://developer.apple.com/account/resources/identifiers/list
2. Make sure the dropdown shows **"App IDs"**
3. Click the **+** button
4. Select **App IDs** > **Continue**
5. Select **App** > **Continue**
6. Fill in:
   - **Description**: Your app name (e.g., "My App Blocker")
   - **Bundle ID**: Select **Explicit**, enter your `ios.bundleIdentifier` from `app.json`
     - Example: `com.yourapp.id`
7. Scroll down to **Capabilities** and enable:
   - **App Groups**
   - **Family Controls**
8. Click **Continue** > **Register**

> **Note on Family Controls**: If you don't see Family Controls in the capabilities list, you may need to request it. Look for a link to request additional capabilities, or check if it appears under "Additional Capabilities".

---

## Step 3: Register the DeviceActivityMonitor Extension App ID

1. Click the **+** button again
2. **App IDs** > **App** > **Continue**
3. Fill in:
   - **Description**: `Your App DeviceActivityMonitor`
   - **Bundle ID**: Explicit, enter `{your-bundle-id}.DeviceActivityMonitor`
     - Example: `com.yourapp.id.DeviceActivityMonitor`
4. Enable capabilities:
   - **App Groups**
   - **Family Controls**
5. Click **Continue** > **Register**

---

## Step 4: Register the ShieldAction Extension App ID

1. Click the **+** button
2. **App IDs** > **App** > **Continue**
3. Fill in:
   - **Description**: `Your App ShieldAction`
   - **Bundle ID**: Explicit, enter `{your-bundle-id}.ShieldAction`
     - Example: `com.yourapp.id.ShieldAction`
4. Enable capabilities:
   - **App Groups**
   - **Family Controls**
5. Click **Continue** > **Register**

---

## Step 5: Register the ShieldConfiguration Extension App ID

1. Click the **+** button
2. **App IDs** > **App** > **Continue**
3. Fill in:
   - **Description**: `Your App ShieldConfiguration`
   - **Bundle ID**: Explicit, enter `{your-bundle-id}.ShieldConfiguration`
     - Example: `com.yourapp.id.ShieldConfiguration`
4. Enable capabilities:
   - **App Groups**
   - **Family Controls**
5. Click **Continue** > **Register**

---

## Step 6: Assign the App Group to All App IDs

For **each of the 4 App IDs** you just created:

1. Click on the App ID in the list
2. Scroll to **App Groups**
3. Click **Configure** (or **Edit**)
4. Check your App Group (e.g., `group.com.yourapp.blocker`)
5. Click **Save**

Repeat for all 4:
- `com.yourapp.id`
- `com.yourapp.id.DeviceActivityMonitor`
- `com.yourapp.id.ShieldAction`
- `com.yourapp.id.ShieldConfiguration`

---

## Summary Checklist

When you're done, you should have:

- [ ] **1 App Group**: `group.com.yourapp.blocker`
- [ ] **4 App IDs**, each with Family Controls + App Groups:

| App ID | Description |
|---|---|
| `com.yourapp.id` | Main app |
| `com.yourapp.id.DeviceActivityMonitor` | Relock timer extension |
| `com.yourapp.id.ShieldAction` | Shield button handler extension |
| `com.yourapp.id.ShieldConfiguration` | Custom shield UI extension |

- [ ] App Group assigned to all 4 App IDs

---

## About Family Controls Approval

| Distribution method | Approval required? |
|---|---|
| Local dev build (Xcode / `expo run:ios`) | No |
| TestFlight | Yes |
| App Store | Yes |

See [Step 0](#step-0-request-family-controls-approval-do-this-first) for submission instructions. You must submit once per bundle ID (4 total).

---

## Troubleshooting

**"Family Controls" not visible in capabilities list**
- Make sure you're on a paid developer account (not free)
- Try searching for it in the capabilities search bar
- You may need to request access: https://developer.apple.com/contact/request/family-controls-distribution

**"An App ID with this identifier is not available"**
- The bundle ID might already be registered. Check your existing identifiers.

**App Group not showing when configuring an App ID**
- Make sure you created the App Group first (Step 1)
- Try refreshing the page

**Signing errors in Xcode after setup**
- In Xcode: select each target > Signing & Capabilities > set your Team
- Xcode should automatically create provisioning profiles using the registered App IDs
