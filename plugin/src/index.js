// Resolve from the app's node_modules, not the package's
const resolve = (mod) => {
  try { return require(mod); } catch {}
  try { return require(require.resolve(mod, { paths: [process.cwd()] })); } catch {}
  throw new Error(`Cannot find module '${mod}'. Make sure 'expo' is installed.`);
};
const {
  withAndroidManifest,
  withEntitlementsPlist,
  withInfoPlist,
  withDangerousMod,
  createRunOncePlugin,
} = resolve("expo/config-plugins");
const fs = require("fs");
const path = require("path");

// ──────────────────────────────────────────────────────────────────────────────
// Android
// ──────────────────────────────────────────────────────────────────────────────

function withAppBlockerAndroid(config, pluginConfig) {
  return withAndroidManifest(config, (config) => {
    const manifest = config.modResults;
    const mainApplication = manifest.manifest.application?.[0];
    if (!mainApplication) return config;

    if (!manifest.manifest["uses-permission"]) {
      manifest.manifest["uses-permission"] = [];
    }
    const permissions = manifest.manifest["uses-permission"];

    const requiredPermissions = [
      "android.permission.SYSTEM_ALERT_WINDOW",
      "android.permission.FOREGROUND_SERVICE",
      "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
      "android.permission.RECEIVE_BOOT_COMPLETED",
      "android.permission.POST_NOTIFICATIONS",
    ];

    // PACKAGE_USAGE_STATS needs tools:ignore
    if (!permissions.some((p) => p.$?.["android:name"] === "android.permission.PACKAGE_USAGE_STATS")) {
      permissions.push({
        $: { "android:name": "android.permission.PACKAGE_USAGE_STATS", "tools:ignore": "ProtectedPermissions" },
      });
    }

    for (const perm of requiredPermissions) {
      if (!permissions.some((p) => p.$?.["android:name"] === perm)) {
        permissions.push({ $: { "android:name": perm } });
      }
    }

    if (!manifest.manifest.$) manifest.manifest.$ = {};
    manifest.manifest.$["xmlns:tools"] = "http://schemas.android.com/tools";

    // Add AppBlockerService
    if (!mainApplication.service) mainApplication.service = [];
    if (!mainApplication.service.some((s) => s.$?.["android:name"] === "expo.modules.appblocker.AppBlockerService")) {
      mainApplication.service.push({
        $: {
          "android:name": "expo.modules.appblocker.AppBlockerService",
          "android:enabled": "true",
          "android:exported": "false",
          "android:foregroundServiceType": "specialUse",
        },
      });
    }

    // Add BootReceiver
    if (!mainApplication.receiver) mainApplication.receiver = [];
    if (!mainApplication.receiver.some((r) => r.$?.["android:name"] === "expo.modules.appblocker.BootReceiver")) {
      mainApplication.receiver.push({
        $: { "android:name": "expo.modules.appblocker.BootReceiver", "android:enabled": "true", "android:exported": "true" },
        "intent-filter": [{ action: [{ $: { "android:name": "android.intent.action.BOOT_COMPLETED" } }] }],
      });
    }

    return config;
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS
// ──────────────────────────────────────────────────────────────────────────────

function withAppBlockerIOS(config, pluginConfig) {
  const appGroup = pluginConfig?.ios?.appGroup || "group.expo.app-blocker";

  config = withEntitlementsPlist(config, (config) => {
    config.modResults["com.apple.developer.family-controls"] = true;
    config.modResults["com.apple.security.application-groups"] = [appGroup];
    return config;
  });

  config = withInfoPlist(config, (config) => {
    config.modResults.BGTaskSchedulerPermittedIdentifiers = [
      `${config.ios?.bundleIdentifier || "expo.app-blocker"}.relock`,
    ];
    return config;
  });

  config = withDangerousMod(config, [
    "ios",
    (config) => {
      const platformRoot = config.modRequest.platformProjectRoot;
      const projectName = config.modRequest.projectName;

      // Patch Podfile deployment target (pod itself is auto-linked via expo-module.config.json)
      const podfilePath = path.join(platformRoot, "Podfile");
      if (fs.existsSync(podfilePath)) {
        let podfile = fs.readFileSync(podfilePath, "utf-8");

        podfile = podfile.replace(
          /platform :ios, podfile_properties\['ios\.deploymentTarget'\] \|\| '[\d.]+'/,
          "platform :ios, podfile_properties['ios.deploymentTarget'] || '16.0'"
        );

        fs.writeFileSync(podfilePath, podfile);
      }

      // Patch deployment target in pbxproj
      const pbxprojPath = path.join(platformRoot, `${projectName}.xcodeproj`, "project.pbxproj");
      if (fs.existsSync(pbxprojPath)) {
        let pbxproj = fs.readFileSync(pbxprojPath, "utf-8");
        pbxproj = pbxproj.replace(/IPHONEOS_DEPLOYMENT_TARGET = \d+\.\d+;/g, "IPHONEOS_DEPLOYMENT_TARGET = 16.0;");
        fs.writeFileSync(pbxprojPath, pbxproj);
      }

      // Patch AppDelegate with localhost fallback
      const appDelegatePath = path.join(platformRoot, projectName, "AppDelegate.swift");
      if (fs.existsSync(appDelegatePath)) {
        let appDelegate = fs.readFileSync(appDelegatePath, "utf-8");
        const original = 'return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry")';
        const replacement = `if let url = RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry") {
      return url
    }
    return URL(string: "http://localhost:8081/.expo/.virtual-metro-entry.bundle?platform=ios&dev=true&lazy=true&minify=false")`;
        if (appDelegate.includes(original)) {
          appDelegate = appDelegate.replace(original, replacement);
          fs.writeFileSync(appDelegatePath, appDelegate);
        }
      }

      // Inject config values into extension Swift files
      const shield = pluginConfig?.ios?.shield || {};
      const replacements = {
        "APP_GROUP_PLACEHOLDER": appGroup,
        "SHIELD_TITLE_PLACEHOLDER": shield.title || "Hold on!",
        "SHIELD_TITLE_COLOR_PLACEHOLDER": shield.titleColor || "#111111",
        "SHIELD_SUBTITLE_PLACEHOLDER": shield.subtitle || "{appName} is blocked.",
        "SHIELD_SUBTITLE_COLOR_PLACEHOLDER": shield.subtitleColor || "#8c8c8c",
        "SHIELD_PRIMARY_LABEL_PLACEHOLDER": shield.primaryButtonLabel || "Earn Free Time",
        "SHIELD_PRIMARY_LABEL_COLOR_PLACEHOLDER": shield.primaryButtonLabelColor || "#ffffff",
        "SHIELD_PRIMARY_BG_COLOR_PLACEHOLDER": shield.primaryButtonBackgroundColor || shield.primaryButtonColor || "#7cb518",
        "SHIELD_SECONDARY_LABEL_PLACEHOLDER": shield.secondaryButtonLabel === null ? "NONE" : (shield.secondaryButtonLabel || "Not now"),
        "SHIELD_SECONDARY_LABEL_COLOR_PLACEHOLDER": shield.secondaryButtonLabelColor || "#8c8c8c",
        "SHIELD_BG_COLOR_PLACEHOLDER": shield.backgroundColor || "NONE",
        "SHIELD_BLUR_STYLE_PLACEHOLDER": shield.backgroundBlurStyle || "systemThickMaterial",
      };

      const targetsDir = path.join(path.dirname(platformRoot), "targets");
      if (fs.existsSync(targetsDir)) {
        const dirs = fs.readdirSync(targetsDir);
        for (const dir of dirs) {
          const dirPath = path.join(targetsDir, dir);
          if (!fs.statSync(dirPath).isDirectory()) continue;
          const files = fs.readdirSync(dirPath);
          for (const file of files) {
            if (!file.endsWith(".swift")) continue;
            const filePath = path.join(dirPath, file);
            let content = fs.readFileSync(filePath, "utf-8");
            let changed = false;
            for (const [placeholder, value] of Object.entries(replacements)) {
              if (content.includes(placeholder)) {
                content = content.replace(new RegExp(placeholder, "g"), value);
                changed = true;
              }
            }
            if (changed) fs.writeFileSync(filePath, content);
          }
        }
      }

      // Copy shield icon to ShieldConfiguration target assets
      const shieldIcon = shield.icon;
      if (shieldIcon) {
        const projectRoot = path.dirname(platformRoot);
        const iconSrc = path.resolve(projectRoot, shieldIcon);
        const assetsDir = path.join(targetsDir, "ShieldConfiguration", "assets");
        if (fs.existsSync(iconSrc)) {
          if (!fs.existsSync(assetsDir)) {
            fs.mkdirSync(assetsDir, { recursive: true });
          }
          const iconDest = path.join(assetsDir, "shield-icon.png");
          fs.copyFileSync(iconSrc, iconDest);
        }
      }

      return config;
    },
  ]);

  return config;
}

// ──────────────────────────────────────────────────────────────────────────────
// Combined
// ──────────────────────────────────────────────────────────────────────────────

function withAppBlocker(config, pluginConfig = {}) {
  config = withAppBlockerAndroid(config, pluginConfig);
  config = withAppBlockerIOS(config, pluginConfig);
  return config;
}

module.exports = createRunOncePlugin(withAppBlocker, "expo-app-blocker", "0.1.0");
