/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = (config) => {
  const appGroup = config.ios?.entitlements?.["com.apple.security.application-groups"]?.[0]
    || "group.expo.app-blocker";

  return {
    type: "shield-action",
    name: "ShieldAction",
    deploymentTarget: "16.0",
    bundleIdentifier: ".ShieldAction",
    frameworks: ["ManagedSettings", "ManagedSettingsUI"],
    entitlements: {
      "com.apple.developer.family-controls": true,
      "com.apple.security.application-groups": [appGroup],
    },
  };
};
