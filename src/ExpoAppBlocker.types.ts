// ──────────────────────────────────────────────────────────────────────────────
// Permission types
// ──────────────────────────────────────────────────────────────────────────────

export interface PermissionStatus {
  allGranted: boolean;
  details: AndroidPermissions | IOSPermissions;
}

export interface AndroidPermissions {
  platform: "android";
  overlay: boolean;
  usageStats: boolean;
}

export interface IOSPermissions {
  platform: "ios";
  authorized: boolean;
  status: "notDetermined" | "denied" | "approved";
}

// ──────────────────────────────────────────────────────────────────────────────
// App selection types
// ──────────────────────────────────────────────────────────────────────────────

export interface AndroidBlockableApp {
  packageName: string;
  name: string;
}

export interface IOSBlockedItem {
  type: "app" | "category";
  token: string;
  bundleIdentifier?: string;
  displayName?: string;
  categoryName?: string;
  iconBase64?: string;
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS-specific types
// ──────────────────────────────────────────────────────────────────────────────

export interface IOSBlockConfiguration {
  blockedItems: IOSBlockedItem[];
  isActive: boolean;
  schedule?: {
    intervalStart: number;
    intervalEnd: number;
    repeats: boolean;
    warningTime: number;
  };
}

export interface TemporaryUnlockResult {
  unlocked: boolean;
  expiresAt: number;
}

export interface RelockResult {
  locked: boolean;
}

// ──────────────────────────────────────────────────────────────────────────────
// Plugin configuration types
// ──────────────────────────────────────────────────────────────────────────────

export interface ShieldConfig {
  /** Title shown on the shield. Use {appName} as placeholder. Default: "Hold on!" */
  title?: string;
  /** Subtitle shown on the shield. Use {appName} as placeholder. */
  subtitle?: string;
  /** Primary button label. Default: "Earn Free Time" */
  primaryButtonLabel?: string;
  /** Secondary button label. Set to null to hide. Default: "Not now" */
  secondaryButtonLabel?: string | null;
  /** Primary button background color (hex). Default: "#7cb518" */
  primaryButtonColor?: string;
  /** Background color (hex). Default: null (uses blur) */
  backgroundColor?: string | null;
  /** Background blur style. Default: "systemThickMaterial" */
  backgroundBlurStyle?: string;
  /** Path to shield icon image. Optional. */
  icon?: string;
}

export interface PluginConfig {
  ios?: {
    /** App Group identifier for shared data between app and extensions. Required. */
    appGroup: string;
    /** Shield overlay customization */
    shield?: ShieldConfig;
  };
  android?: {
    /** Notification title when app is blocked. Use {appName} as placeholder. */
    notificationTitle?: string;
    /** Notification text when app is blocked. Use {appName} as placeholder. */
    notificationText?: string;
    /** Text shown on the blocking overlay. Default: "" (empty) */
    overlayText?: string;
  };
}
