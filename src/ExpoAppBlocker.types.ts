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

export interface FamilyActivityPickerSelectionEvent {
  items: IOSBlockedItem[];
  totalApps: number;
  totalCategories: number;
  selectionData: string;
}

// ──────────────────────────────────────────────────────────────────────────────
// Plugin configuration types
// ──────────────────────────────────────────────────────────────────────────────

export interface ShieldConfig {
  /** Title shown on the shield. Default: "Hold on!" */
  title?: string;
  /** Subtitle shown on the shield. Use {appName} as placeholder. Default: "{appName} is blocked." */
  subtitle?: string;
  /** Primary button label. Default: "Earn Free Time" */
  primaryButtonLabel?: string;
  /** Secondary button label. Set to null to hide. Default: "Not now" */
  secondaryButtonLabel?: string | null;
  /** Primary button background color (hex). Default: "#fb6107" */
  primaryButtonColor?: string;
  /** Title text color (hex). Default: "#111111" */
  titleColor?: string;
  /** Subtitle text color (hex). Default: "#737373" */
  subtitleColor?: string;
  /**
   * Solid background color (hex). Optional.
   * When set, the shield uses this color instead of (or in addition to) a blur.
   * Example: "#f6f6f6" for light gray, "#1a1a2e" for dark.
   */
  backgroundColor?: string | null;
  /**
   * Background blur style. Default: "systemThickMaterial" (when no backgroundColor is set).
   * Set to null to disable blur (when using backgroundColor only).
   * Both can be combined - blur renders behind the color.
   *
   * Adaptive (light/dark auto):
   * - "systemUltraThinMaterial", "systemThinMaterial", "systemMaterial",
   *   "systemThickMaterial", "systemChromeMaterial"
   *
   * Light only:
   * - "systemUltraThinMaterialLight", "systemThinMaterialLight", "systemMaterialLight",
   *   "systemThickMaterialLight", "systemChromeMaterialLight"
   *
   * Dark only:
   * - "systemUltraThinMaterialDark", "systemThinMaterialDark", "systemMaterialDark",
   *   "systemThickMaterialDark", "systemChromeMaterialDark"
   *
   * Legacy: "regular", "prominent", "light", "dark", "extraLight"
   */
  backgroundBlurStyle?: string | null;
  /** Path to shield icon image (PNG). Optional. */
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
