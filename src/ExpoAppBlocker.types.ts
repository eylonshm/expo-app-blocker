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
  /** Title text. Use {appName} as placeholder for the blocked app name. Default: "Hold on!" */
  title?: string;
  /** Title text color (hex). Default: "#111111" */
  titleColor?: string;
  /** Subtitle text. Use {appName} as placeholder. Default: "{appName} is blocked." */
  subtitle?: string;
  /** Subtitle text color (hex). Default: "#8c8c8c" */
  subtitleColor?: string;
  /** Primary button label text. Default: "Earn Free Time" */
  primaryButtonLabel?: string;
  /** Primary button label text color (hex). Default: "#ffffff" */
  primaryButtonLabelColor?: string;
  /** Primary button background color (hex). Default: "#7cb518" */
  primaryButtonBackgroundColor?: string;
  /** Secondary button label text. Set to null to hide the button. Default: "Not now" */
  secondaryButtonLabel?: string | null;
  /** Secondary button label text color (hex). Default: "#8c8c8c" */
  secondaryButtonLabelColor?: string;
  /**
   * Background tint color (hex, supports alpha e.g. "#FF000033").
   * Applied as overlay on top of the blur. Default: null (no tint)
   */
  backgroundColor?: string | null;
  /**
   * Background blur style. Default: "systemThickMaterial"
   *
   * Options: "extraLight", "light", "dark", "regular", "prominent",
   * "systemUltraThinMaterial", "systemThinMaterial", "systemMaterial",
   * "systemThickMaterial", "systemChromeMaterial",
   * and light/dark forced variants (e.g. "systemMaterialDark")
   */
  backgroundBlurStyle?: string;
  /** Path to custom shield icon PNG (relative to project root). Optional. */
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
