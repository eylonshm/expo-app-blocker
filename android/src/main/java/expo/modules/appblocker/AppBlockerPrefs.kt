package expo.modules.appblocker

import android.content.Context
import android.content.SharedPreferences

object AppBlockerPrefs {
  const val PREFS_NAME = "expo_app_blocker_prefs"
  const val KEY_BLOCKED_PACKAGES = "blocked_packages"

  fun get(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  fun getBlockedPackages(context: Context): Set<String> =
    get(context).getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()

  fun setBlockedPackages(context: Context, packages: Collection<String>) {
    get(context).edit()
      .putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet())
      .apply()
  }
}
