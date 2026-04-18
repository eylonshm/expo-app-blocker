package expo.modules.appblocker

import android.content.Context
import android.content.SharedPreferences

object AppBlockerPrefs {
  const val PREFS_NAME = "expo_app_blocker_prefs"
  const val KEY_BLOCKED_PACKAGES = "blocked_packages"
  private const val KEY_OVERLAY_TEXT = "overlay_text"
  private const val KEY_NOTIFICATION_TITLE = "notification_title"
  private const val KEY_NOTIFICATION_TEXT = "notification_text"

  fun get(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  fun getBlockedPackages(context: Context): Set<String> =
    get(context).getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()

  fun setBlockedPackages(context: Context, packages: Collection<String>) {
    get(context).edit()
      .putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet())
      .apply()
  }

  fun setAndroidConfig(
    context: Context,
    overlayText: String?,
    notificationTitle: String?,
    notificationText: String?,
  ) {
    get(context).edit()
      .putString(KEY_OVERLAY_TEXT, overlayText)
      .putString(KEY_NOTIFICATION_TITLE, notificationTitle)
      .putString(KEY_NOTIFICATION_TEXT, notificationText)
      .apply()
  }

  fun getOverlayText(context: Context): String =
    get(context).getString(KEY_OVERLAY_TEXT, null) ?: "{appName} is blocked."

  fun getNotificationTitle(context: Context): String =
    get(context).getString(KEY_NOTIFICATION_TITLE, null) ?: "App Blocked"

  fun getNotificationText(context: Context): String =
    get(context).getString(KEY_NOTIFICATION_TEXT, null) ?: "{appName} is blocked. Tap to manage."
}
