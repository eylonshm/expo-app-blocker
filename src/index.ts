import {
  requireNativeModule,
  requireNativeViewManager,
  EventEmitter,
} from "expo-modules-core";
import { Platform } from "react-native";
import React from "react";

import type {
  PermissionStatus,
  AndroidPermissions,
  IOSPermissions,
  AndroidBlockableApp,
  IOSBlockedItem,
  IOSBlockConfiguration,
  TemporaryUnlockResult,
  RelockResult,
} from "./ExpoAppBlocker.types";

export type {
  PermissionStatus,
  AndroidPermissions,
  IOSPermissions,
  AndroidBlockableApp,
  IOSBlockedItem,
  IOSBlockConfiguration,
  TemporaryUnlockResult,
  RelockResult,
  ShieldConfig,
  PluginConfig,
} from "./ExpoAppBlocker.types";

// ──────────────────────────────────────────────────────────────────────────────
// Native module bridge
// ──────────────────────────────────────────────────────────────────────────────

const NativeModule = requireNativeModule("ExpoAppBlocker");

// ──────────────────────────────────────────────────────────────────────────────
// Permissions
// ──────────────────────────────────────────────────────────────────────────────

export async function getPermissionStatus(): Promise<PermissionStatus> {
  if (Platform.OS === "android") {
    const overlay = await NativeModule.checkOverlayPermission();
    const usageStats = await NativeModule.checkUsageStatsPermission();
    const details: AndroidPermissions = { platform: "android", overlay, usageStats };
    return { allGranted: overlay && usageStats, details };
  }

  if (Platform.OS === "ios") {
    const result = NativeModule.getAuthorizationStatus();
    const details: IOSPermissions = {
      platform: "ios",
      authorized: result.authorized,
      status: result.status,
    };
    return { allGranted: result.authorized, details };
  }

  throw new Error("Unsupported platform");
}

export async function requestPermissions(): Promise<PermissionStatus> {
  if (Platform.OS === "ios") {
    const result = await NativeModule.requestAuthorization();
    const details: IOSPermissions = {
      platform: "ios",
      authorized: result.authorized,
      status: result.status,
    };
    return { allGranted: result.authorized, details };
  }
  return getPermissionStatus();
}

// ──────────────────────────────────────────────────────────────────────────────
// Android-specific: permission settings
// ──────────────────────────────────────────────────────────────────────────────

export function openOverlaySettings(): void {
  if (Platform.OS !== "android") return;
  NativeModule.openOverlaySettings();
}

export function openUsageStatsSettings(): void {
  if (Platform.OS !== "android") return;
  NativeModule.openUsageStatsSettings();
}

// ──────────────────────────────────────────────────────────────────────────────
// Android-specific: app list and blocking
// ──────────────────────────────────────────────────────────────────────────────

export async function getInstalledApps(): Promise<AndroidBlockableApp[]> {
  if (Platform.OS !== "android") return [];
  return NativeModule.getInstalledApps();
}

export function setBlockedApps(packageNames: string[]): void {
  if (Platform.OS !== "android") return;
  NativeModule.setBlockedApps(packageNames);
}

export function getBlockedApps(): string[] {
  if (Platform.OS !== "android") return [];
  return NativeModule.getBlockedApps();
}

export function startMonitoring(): void {
  if (Platform.OS !== "android") return;
  NativeModule.startMonitoring();
}

export function stopMonitoring(): void {
  if (Platform.OS !== "android") return;
  NativeModule.stopMonitoring();
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS-specific: Family Controls
// ──────────────────────────────────────────────────────────────────────────────

export async function presentFamilyActivityPicker(): Promise<IOSBlockedItem[]> {
  if (Platform.OS !== "ios") {
    throw new Error("Family Activity Picker is only available on iOS");
  }
  return NativeModule.presentFamilyActivityPicker();
}

export async function setBlockConfiguration(config: IOSBlockConfiguration): Promise<void> {
  if (Platform.OS !== "ios") {
    throw new Error("Block configuration is only available on iOS");
  }
  return NativeModule.setBlockConfiguration(config);
}

export function getBlockConfiguration(): IOSBlockConfiguration | null {
  if (Platform.OS !== "ios") return null;
  return NativeModule.getBlockConfiguration();
}

export function clearAllBlocks(): void {
  if (Platform.OS !== "ios") return;
  NativeModule.clearAllBlocks();
}

export function isAppBlocked(bundleIdentifier: string): boolean {
  if (Platform.OS !== "ios") return false;
  return NativeModule.isAppBlocked(bundleIdentifier);
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS-specific: Temporary unlock
// ──────────────────────────────────────────────────────────────────────────────

export async function temporaryUnlock(durationMinutes: number = 15): Promise<TemporaryUnlockResult> {
  if (Platform.OS !== "ios") {
    throw new Error("Temporary unlock is only available on iOS");
  }
  return NativeModule.temporaryUnlock(durationMinutes);
}

export function isTemporarilyUnlocked(): boolean {
  if (Platform.OS !== "ios") return false;
  return NativeModule.isTemporarilyUnlocked();
}

export function getRemainingUnlockTime(): number {
  if (Platform.OS !== "ios") return 0;
  return NativeModule.getRemainingUnlockTime();
}

export async function relockApps(): Promise<RelockResult> {
  if (Platform.OS !== "ios") {
    throw new Error("Relock is only available on iOS");
  }
  return NativeModule.relockApps();
}

export function checkAndClearPendingUnlock(): boolean {
  if (Platform.OS !== "ios") return false;
  return NativeModule.checkAndClearPendingUnlock();
}

export function addPendingUnlockListener(
  handler: () => void
): { remove: () => void } | null {
  if (Platform.OS !== "ios") return null;
  const emitter = new EventEmitter(NativeModule);
  return (emitter as any).addListener("onPendingUnlockRequest", handler);
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS Native View: renders blocked app tokens with real names and icons
// ──────────────────────────────────────────────────────────────────────────────

let NativeBlockedAppsView: any = null;
if (Platform.OS === "ios") {
  try {
    NativeBlockedAppsView = requireNativeViewManager("ExpoAppBlocker");
  } catch {}
}

export function BlockedAppsNativeList({
  items,
  selectionData,
  style,
}: {
  items: IOSBlockedItem[];
  selectionData?: string;
  style?: any;
}) {
  if (!NativeBlockedAppsView || Platform.OS !== "ios") return null;

  const tokens = items
    .filter((item) => (item.type as string) !== "summary")
    .map((item) => ({ token: item.token, type: item.type }));

  return React.createElement(NativeBlockedAppsView, {
    selectionData: selectionData || "",
    tokens,
    style: [{ minHeight: 50 }, style],
  });
}
