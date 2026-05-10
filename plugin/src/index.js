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
// Privacy manifest helper
// ──────────────────────────────────────────────────────────────────────────────

// Merges expo-app-blocker's required UserDefaults entry into config.ios.privacyManifests
// so Expo's built-in withPrivacyInfo plugin writes it to PrivacyInfo.xcprivacy on prebuild.
// Required for App Store submission: the blocker uses UserDefaults extensively for
// AppGroup state sharing between the main app and Shield/DeviceActivityMonitor extensions.
function mergeBlockerPrivacyManifest(config) {
  const ios = config.ios ?? {};
  const privacyManifests = ios.privacyManifests ?? {};
  const apiTypes = [...(privacyManifests.NSPrivacyAccessedAPITypes ?? [])];
  const TYPE = "NSPrivacyAccessedAPICategoryUserDefaults";
  const REASON = "CA92.1";
  const existing = apiTypes.find((t) => t.NSPrivacyAccessedAPIType === TYPE);
  if (!existing) {
    apiTypes.push({ NSPrivacyAccessedAPIType: TYPE, NSPrivacyAccessedAPITypeReasons: [REASON] });
  } else if (!existing.NSPrivacyAccessedAPITypeReasons.includes(REASON)) {
    existing.NSPrivacyAccessedAPITypeReasons = [...existing.NSPrivacyAccessedAPITypeReasons, REASON];
  }
  return {
    ...config,
    ios: { ...ios, privacyManifests: { ...privacyManifests, NSPrivacyAccessedAPITypes: apiTypes } },
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Android
// ──────────────────────────────────────────────────────────────────────────────

function getAndroidScheme(config, pluginConfig) {
  if (pluginConfig?.android?.scheme) return pluginConfig.android.scheme;
  const configScheme = Array.isArray(config.scheme) ? config.scheme[0] : config.scheme;
  if (configScheme) return configScheme;
  const pkg = config.android?.package;
  if (pkg) return pkg.replace(/\./g, "-");
  return null;
}

function withAppBlockerAndroid(config, pluginConfig) {
  const scheme = getAndroidScheme(config, pluginConfig);

  // Manifest: permissions, service, receiver, and deep-link intent filter
  config = withAndroidManifest(config, (config) => {
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

    // Add deep-link intent filter to MainActivity so notification taps route back to the app
    if (scheme) {
      const activities = mainApplication.activity || [];
      const mainActivity = activities.find(
        (a) => a.$?.["android:name"] === ".MainActivity" || a.$?.["android:name"]?.endsWith(".MainActivity")
      );
      if (mainActivity) {
        if (!mainActivity["intent-filter"]) mainActivity["intent-filter"] = [];
        const alreadyHasScheme = mainActivity["intent-filter"].some((f) =>
          (f.data || []).some((d) => d.$?.["android:scheme"] === scheme)
        );
        if (!alreadyHasScheme) {
          mainActivity["intent-filter"].push({
            action: [{ $: { "android:name": "android.intent.action.VIEW" } }],
            category: [
              { $: { "android:name": "android.intent.category.DEFAULT" } },
              { $: { "android:name": "android.intent.category.BROWSABLE" } },
            ],
            data: [{ $: { "android:scheme": scheme } }],
          });
        }
      }
    }

    return config;
  });

  // Write scheme to strings.xml so AppBlockerService can read it at runtime
  if (scheme) {
    config = withDangerousMod(config, [
      "android",
      (config) => {
        const platformRoot = config.modRequest.platformProjectRoot;
        const valuesDir = path.join(platformRoot, "app", "src", "main", "res", "values");
        const stringsPath = path.join(valuesDir, "strings.xml");

        if (!fs.existsSync(valuesDir)) {
          fs.mkdirSync(valuesDir, { recursive: true });
        }

        let xml = fs.existsSync(stringsPath)
          ? fs.readFileSync(stringsPath, "utf-8")
          : '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>';

        const tag = `<string name="expo_app_blocker_scheme">${scheme}</string>`;
        if (!xml.includes('name="expo_app_blocker_scheme"')) {
          xml = xml.replace("</resources>", `    ${tag}\n</resources>`);
        } else {
          xml = xml.replace(/<string name="expo_app_blocker_scheme">.*?<\/string>/, tag);
        }

        fs.writeFileSync(stringsPath, xml);
        return config;
      },
    ]);
  }

  // Copy the overlay icon (PNG) to `res/drawable/expo_app_blocker_overlay_icon.png`
  // so `OverlayManager.kt` can resolve it via Resources.getIdentifier(...).
  // The icon is rendered above the title in the SYSTEM_ALERT_WINDOW overlay.
  // Path is resolved relative to the project root for consistency with the
  // top-level `icon` config field.
  const overlayIconRel = pluginConfig?.android?.overlay?.icon;
  if (overlayIconRel) {
    config = withDangerousMod(config, [
      "android",
      (config) => {
        const platformRoot = config.modRequest.platformProjectRoot;
        const projectRoot = config.modRequest.projectRoot;
        const drawableDir = path.join(platformRoot, "app", "src", "main", "res", "drawable");
        const iconSrc = path.isAbsolute(overlayIconRel)
          ? overlayIconRel
          : path.join(projectRoot, overlayIconRel);

        if (!fs.existsSync(iconSrc)) {
          throw new Error(
            `[expo-app-blocker] android.overlay.icon points to a missing file: ${iconSrc}`,
          );
        }

        if (!fs.existsSync(drawableDir)) {
          fs.mkdirSync(drawableDir, { recursive: true });
        }

        fs.copyFileSync(iconSrc, path.join(drawableDir, "expo_app_blocker_overlay_icon.png"));
        return config;
      },
    ]);
  }

  return config;
}

// ──────────────────────────────────────────────────────────────────────────────
// iOS
// ──────────────────────────────────────────────────────────────────────────────

function withAppBlockerIOS(config, pluginConfig) {
  config = mergeBlockerPrivacyManifest(config);

  const bundleId = config.ios?.bundleIdentifier || "expo.app-blocker";
  const appGroup = pluginConfig?.ios?.appGroup || `group.${bundleId}`;

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

      // Copy fresh target templates from node_modules before replacing placeholders
      const targetsDir = path.join(path.dirname(platformRoot), "targets");
      const packageTargetsDir = path.resolve(__dirname, "..", "..", "targets");
      if (fs.existsSync(packageTargetsDir)) {
        function copyDirSync(src, dest) {
          if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
          for (const entry of fs.readdirSync(src)) {
            const srcPath = path.join(src, entry);
            const destPath = path.join(dest, entry);
            if (fs.statSync(srcPath).isDirectory()) {
              copyDirSync(srcPath, destPath);
            } else {
              fs.copyFileSync(srcPath, destPath);
            }
          }
        }
        // Only copy Swift files and config (preserve user's assets, generated entitlements, Info.plist)
        for (const dir of fs.readdirSync(packageTargetsDir)) {
          const srcDir = path.join(packageTargetsDir, dir);
          const destDir = path.join(targetsDir, dir);
          if (!fs.statSync(srcDir).isDirectory()) continue;
          if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
          for (const file of fs.readdirSync(srcDir)) {
            if (file.endsWith(".swift") || file === "expo-target.config.js") {
              fs.copyFileSync(path.join(srcDir, file), path.join(destDir, file));
            }
          }
        }
      }

      // Helper: hex to RGB floats
      function hexToRgb(hex) {
        const h = hex.replace("#", "");
        return {
          r: (parseInt(h.substring(0, 2), 16) / 255).toFixed(3),
          g: (parseInt(h.substring(2, 4), 16) / 255).toFixed(3),
          b: (parseInt(h.substring(4, 6), 16) / 255).toFixed(3),
        };
      }

      // Shield config defaults
      const shield = pluginConfig?.ios?.shield || {};
      const primaryColor = hexToRgb(shield.primaryButtonColor || "#fb6107");
      const titleColor = hexToRgb(shield.titleColor || "#111111");
      const subtitleColor = hexToRgb(shield.subtitleColor || "#737373");
      // Background color (solid) - separate from blur
      const bgColorHex = shield.backgroundColor || null;
      const bgColor = bgColorHex ? hexToRgb(bgColorHex) : null;

      // Blur style mapping
      const blurStyleMap = {
        "systemUltraThinMaterial": ".systemUltraThinMaterial",
        "systemThinMaterial": ".systemThinMaterial",
        "systemMaterial": ".systemMaterial",
        "systemThickMaterial": ".systemThickMaterial",
        "systemChromeMaterial": ".systemChromeMaterial",
        "systemUltraThinMaterialLight": ".systemUltraThinMaterialLight",
        "systemThinMaterialLight": ".systemThinMaterialLight",
        "systemMaterialLight": ".systemMaterialLight",
        "systemThickMaterialLight": ".systemThickMaterialLight",
        "systemChromeMaterialLight": ".systemChromeMaterialLight",
        "systemUltraThinMaterialDark": ".systemUltraThinMaterialDark",
        "systemThinMaterialDark": ".systemThinMaterialDark",
        "systemMaterialDark": ".systemMaterialDark",
        "systemThickMaterialDark": ".systemThickMaterialDark",
        "systemChromeMaterialDark": ".systemChromeMaterialDark",
        "regular": ".regular",
        "prominent": ".prominent",
        "light": ".light",
        "dark": ".dark",
        "extraLight": ".extraLight",
      };
      const blurRaw = shield.backgroundBlurStyle || (bgColorHex ? null : "systemThickMaterial");
      const blurSwift = blurRaw && blurStyleMap[blurRaw] ? blurStyleMap[blurRaw] : null;

      // Notification config (shown when the user taps the Shield primary button).
      // All copy is configurable so non-English apps can localize without forking.
      const notification = pluginConfig?.ios?.notification || {};
      const notificationTitle = notification.title || "App Blocker";
      const notificationBody = notification.body || "Tap to return to the app and complete the unlock challenge.";
      // attachIcon defaults to true to preserve current behavior; set to false
      // to drop the duplicate icon attachment so only the system app icon shows.
      const notificationAttachIcon = notification.attachIcon === false ? "false" : "true";

      // Temporary-unlock state copy (shown when the user has just earned time
      // and the Shield is briefly visible while ManagedSettings clears).
      const tempUnlockTitle = shield.tempUnlockTitle || "Almost there!";
      const tempUnlockSubtitle = shield.tempUnlockSubtitle || "Your free time is loading. Try again in a moment.";
      const tempUnlockButtonLabel = shield.tempUnlockButtonLabel || "OK";

      // "You have N apps blocked" suffix appended to the subtitle when more
      // than one app is blocked. Set countSuffix to "" to drop it entirely,
      // or to a localized template like " יש לך {count} אפליקציות חסומות.".
      // Defaults preserve the legacy English suffix.
      const countSuffixTemplate = shield.countSuffix !== undefined
        ? shield.countSuffix
        : " You have {count} apps blocked.";

      // Swift string-literal escaping. Plugin substitutions land inside `"..."`
      // literals so backslashes, quotes, and the Swift interpolation escape
      // `\(` MUST all be escaped or the extension fails to compile.
      function escapeSwiftString(s) {
        return String(s)
          .replace(/\\/g, "\\\\")
          .replace(/"/g, '\\"')
          .replace(/\n/g, "\\n")
          .replace(/\r/g, "\\r");
      }

      // Render the count suffix template into a Swift expression. We use
      // `\(count)` interpolation when the template includes `{count}` so the
      // runtime value is substituted. Empty template → empty literal.
      function renderCountSuffixSwift(template) {
        if (!template) return '""';
        const escaped = escapeSwiftString(template);
        return `"${escaped.replace(/\{count\}/g, "\\(count)")}"`;
      }

      // All placeholder replacements
      const replacements = {
        "APP_GROUP_PLACEHOLDER": appGroup,
        "SHIELD_TITLE_PLACEHOLDER": shield.title || "Hold on!",
        "SHIELD_SUBTITLE_PLACEHOLDER": shield.subtitle || "{appName} is blocked.",
        "SHIELD_PRIMARY_BUTTON_PLACEHOLDER": shield.primaryButtonLabel || "Earn Free Time",
        "SHIELD_SECONDARY_BUTTON_PLACEHOLDER": shield.secondaryButtonLabel === null ? "none" : (shield.secondaryButtonLabel || "Not now"),
        "SHIELD_TEMP_UNLOCK_TITLE_PLACEHOLDER": tempUnlockTitle,
        "SHIELD_TEMP_UNLOCK_SUBTITLE_PLACEHOLDER": tempUnlockSubtitle,
        "SHIELD_TEMP_UNLOCK_BUTTON_PLACEHOLDER": tempUnlockButtonLabel,
        "SHIELD_COUNT_SUFFIX_SWIFT_PLACEHOLDER": renderCountSuffixSwift(countSuffixTemplate),
        "NOTIFICATION_TITLE_PLACEHOLDER": notificationTitle,
        "NOTIFICATION_BODY_PLACEHOLDER": notificationBody,
        "NOTIFICATION_ATTACH_ICON_PLACEHOLDER": notificationAttachIcon,
        "SHIELD_PRIMARY_R_PLACEHOLDER": primaryColor.r,
        "SHIELD_PRIMARY_G_PLACEHOLDER": primaryColor.g,
        "SHIELD_PRIMARY_B_PLACEHOLDER": primaryColor.b,
        "SHIELD_TITLE_R_PLACEHOLDER": titleColor.r,
        "SHIELD_TITLE_G_PLACEHOLDER": titleColor.g,
        "SHIELD_TITLE_B_PLACEHOLDER": titleColor.b,
        "SHIELD_SUBTITLE_R_PLACEHOLDER": subtitleColor.r,
        "SHIELD_SUBTITLE_G_PLACEHOLDER": subtitleColor.g,
        "SHIELD_SUBTITLE_B_PLACEHOLDER": subtitleColor.b,
        "SHIELD_BG_COLOR_PLACEHOLDER": bgColor
          ? `UIColor(red: ${bgColor.r}, green: ${bgColor.g}, blue: ${bgColor.b}, alpha: 1.0)`
          : "nil",
        "SHIELD_BLUR_STYLE_PLACEHOLDER": blurSwift || "nil",
      };

      // Inject all placeholders into extension Swift files
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
            for (const [key, value] of Object.entries(replacements)) {
              content = content.replace(new RegExp(key, "g"), value);
            }
            fs.writeFileSync(filePath, content);
          }
        }
      }

      // Copy shield icon to ShieldConfiguration and ShieldAction target assets
      const shieldIcon = pluginConfig?.ios?.shield?.icon;
      if (shieldIcon) {
        const projectRoot = path.dirname(platformRoot);
        const iconSrc = path.resolve(projectRoot, shieldIcon);
        if (fs.existsSync(iconSrc)) {
          for (const target of ["ShieldConfiguration", "ShieldAction"]) {
            const assetsDir = path.join(targetsDir, target, "assets");
            if (!fs.existsSync(assetsDir)) {
              fs.mkdirSync(assetsDir, { recursive: true });
            }
            fs.copyFileSync(iconSrc, path.join(assetsDir, "shield-icon.png"));
          }
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
