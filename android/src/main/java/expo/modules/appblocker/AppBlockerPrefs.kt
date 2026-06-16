package expo.modules.appblocker

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object AppBlockerPrefs {
  const val PREFS_NAME = "expo_app_blocker_prefs"
  private const val KEY_PENDING_INTERCEPTS = "pending_intercepts"
  private const val KEY_LAST_INTERCEPT_TS = "last_intercept_ts"
  private const val INTERCEPT_DEBOUNCE_MS = 2_000L
  private const val MAX_PENDING_INTERCEPTS = 200
  const val KEY_BLOCKED_PACKAGES = "blocked_packages"
  private const val KEY_OVERLAY_TITLE = "overlay_title"
  private const val KEY_OVERLAY_TEXT = "overlay_text"
  private const val KEY_OVERLAY_BG_COLOR = "overlay_bg_color"
  private const val KEY_OVERLAY_TITLE_COLOR = "overlay_title_color"
  private const val KEY_OVERLAY_TEXT_COLOR = "overlay_text_color"
  private const val KEY_OVERLAY_TITLE_FONT_SIZE = "overlay_title_font_size"
  private const val KEY_OVERLAY_TEXT_FONT_SIZE = "overlay_text_font_size"
  private const val KEY_OVERLAY_TITLE_BOLD = "overlay_title_bold"
  private const val KEY_OVERLAY_PADDING = "overlay_padding"
  private const val KEY_OVERLAY_ICON_SIZE = "overlay_icon_size"
  private const val KEY_OVERLAY_ICON_GAP = "overlay_icon_gap"
  private const val KEY_OVERLAY_TITLE_GAP = "overlay_title_gap"
  private const val KEY_OVERLAY_SHOW_SPINNER = "overlay_show_spinner"
  private const val KEY_OVERLAY_SPINNER_SIZE = "overlay_spinner_size"
  private const val KEY_OVERLAY_SPINNER_GAP = "overlay_spinner_gap"
  private const val KEY_OVERLAY_SPINNER_COLOR = "overlay_spinner_color"
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

  /**
   * Push the overlay + notification config from JS into native prefs.
   *
   * Numeric `Float?` knobs (font sizes, paddings, icon size) are stored as
   * floats and read back through [getOverlayFloat]. Pass `null` to keep the
   * baked-in default; pass an explicit value (e.g. `28f`) to override.
   */
  fun setAndroidConfig(
    context: Context,
    overlayTitle: String?,
    overlayText: String?,
    overlayBackgroundColor: String?,
    overlayTitleColor: String?,
    overlayTextColor: String?,
    overlayTitleFontSize: Float?,
    overlayTextFontSize: Float?,
    overlayTitleBold: Boolean?,
    overlayPadding: Float?,
    overlayIconSize: Float?,
    overlayIconBottomMargin: Float?,
    overlayTitleBottomMargin: Float?,
    overlayShowSpinner: Boolean?,
    overlaySpinnerSize: Float?,
    overlaySpinnerTopMargin: Float?,
    overlaySpinnerColor: String?,
    notificationTitle: String?,
    notificationText: String?,
  ) {
    val editor = get(context).edit()
      .putString(KEY_OVERLAY_TITLE, overlayTitle)
      .putString(KEY_OVERLAY_TEXT, overlayText)
      .putString(KEY_OVERLAY_BG_COLOR, overlayBackgroundColor)
      .putString(KEY_OVERLAY_TITLE_COLOR, overlayTitleColor)
      .putString(KEY_OVERLAY_TEXT_COLOR, overlayTextColor)
      .putString(KEY_OVERLAY_SPINNER_COLOR, overlaySpinnerColor)
      .putString(KEY_NOTIFICATION_TITLE, notificationTitle)
      .putString(KEY_NOTIFICATION_TEXT, notificationText)
    putNullableFloat(editor, KEY_OVERLAY_TITLE_FONT_SIZE, overlayTitleFontSize)
    putNullableFloat(editor, KEY_OVERLAY_TEXT_FONT_SIZE, overlayTextFontSize)
    putNullableFloat(editor, KEY_OVERLAY_PADDING, overlayPadding)
    putNullableFloat(editor, KEY_OVERLAY_ICON_SIZE, overlayIconSize)
    putNullableFloat(editor, KEY_OVERLAY_ICON_GAP, overlayIconBottomMargin)
    putNullableFloat(editor, KEY_OVERLAY_TITLE_GAP, overlayTitleBottomMargin)
    putNullableFloat(editor, KEY_OVERLAY_SPINNER_SIZE, overlaySpinnerSize)
    putNullableFloat(editor, KEY_OVERLAY_SPINNER_GAP, overlaySpinnerTopMargin)
    if (overlayTitleBold != null) {
      editor.putBoolean(KEY_OVERLAY_TITLE_BOLD, overlayTitleBold)
    } else {
      editor.remove(KEY_OVERLAY_TITLE_BOLD)
    }
    if (overlayShowSpinner != null) {
      editor.putBoolean(KEY_OVERLAY_SHOW_SPINNER, overlayShowSpinner)
    } else {
      editor.remove(KEY_OVERLAY_SHOW_SPINNER)
    }
    editor.apply()
  }

  fun getOverlayTitle(context: Context): String =
    get(context).getString(KEY_OVERLAY_TITLE, null) ?: "App Blocked"

  fun getOverlayText(context: Context): String =
    get(context).getString(KEY_OVERLAY_TEXT, null) ?: "{appName} is blocked."

  fun getOverlayBackgroundColor(context: Context): String =
    get(context).getString(KEY_OVERLAY_BG_COLOR, null) ?: "#FFFFFF"

  fun getOverlayTitleColor(context: Context): String =
    get(context).getString(KEY_OVERLAY_TITLE_COLOR, null) ?: "#111111"

  fun getOverlayTextColor(context: Context): String =
    get(context).getString(KEY_OVERLAY_TEXT_COLOR, null) ?: "#737373"

  fun getOverlayTitleFontSize(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_TITLE_FONT_SIZE, 24f)

  fun getOverlayTextFontSize(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_TEXT_FONT_SIZE, 16f)

  fun getOverlayTitleBold(context: Context): Boolean =
    get(context).getBoolean(KEY_OVERLAY_TITLE_BOLD, true)

  fun getOverlayPadding(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_PADDING, 32f)

  fun getOverlayIconSize(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_ICON_SIZE, 96f)

  fun getOverlayIconBottomMargin(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_ICON_GAP, 20f)

  fun getOverlayTitleBottomMargin(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_TITLE_GAP, 12f)

  fun getOverlayShowSpinner(context: Context): Boolean =
    get(context).getBoolean(KEY_OVERLAY_SHOW_SPINNER, false)

  fun getOverlaySpinnerSize(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_SPINNER_SIZE, 32f)

  fun getOverlaySpinnerTopMargin(context: Context): Float =
    getOverlayFloat(context, KEY_OVERLAY_SPINNER_GAP, 24f)

  fun getOverlaySpinnerColor(context: Context): String? =
    get(context).getString(KEY_OVERLAY_SPINNER_COLOR, null)

  fun getNotificationTitle(context: Context): String =
    get(context).getString(KEY_NOTIFICATION_TITLE, null) ?: "App Blocked"

  fun getNotificationText(context: Context): String =
    get(context).getString(KEY_NOTIFICATION_TEXT, null) ?: "{appName} is blocked. Tap to manage."

  /**
   * Queue one OS-level block event for the app to drain into
   * `blocker_intercepts`. Debounced globally so the poll loop can't emit
   * duplicates for a single block, and capped to bound storage.
   */
  fun appendIntercept(context: Context, appName: String, interceptedAtMs: Long) {
    val prefs = get(context)
    val lastTs = prefs.getLong(KEY_LAST_INTERCEPT_TS, 0L)
    if (lastTs > 0L && interceptedAtMs - lastTs < INTERCEPT_DEBOUNCE_MS) return

    val arr = try {
      JSONArray(prefs.getString(KEY_PENDING_INTERCEPTS, "[]"))
    } catch (e: Exception) {
      JSONArray()
    }
    arr.put(JSONObject().put("appName", appName).put("interceptedAt", interceptedAtMs))

    val trimmed = if (arr.length() > MAX_PENDING_INTERCEPTS) {
      JSONArray().also { t ->
        for (i in (arr.length() - MAX_PENDING_INTERCEPTS) until arr.length()) t.put(arr.get(i))
      }
    } else {
      arr
    }

    prefs.edit()
      .putString(KEY_PENDING_INTERCEPTS, trimmed.toString())
      .putLong(KEY_LAST_INTERCEPT_TS, interceptedAtMs)
      .apply()
  }

  /** Return and clear the queued block events. */
  fun drainIntercepts(context: Context): List<Map<String, Any>> {
    val prefs = get(context)
    val arr = try {
      JSONArray(prefs.getString(KEY_PENDING_INTERCEPTS, "[]"))
    } catch (e: Exception) {
      JSONArray()
    }
    val out = ArrayList<Map<String, Any>>(arr.length())
    for (i in 0 until arr.length()) {
      val o = arr.getJSONObject(i)
      out.add(
        mapOf(
          "appName" to o.optString("appName", ""),
          "interceptedAt" to o.optDouble("interceptedAt"),
        )
      )
    }
    if (arr.length() > 0) prefs.edit().remove(KEY_PENDING_INTERCEPTS).apply()
    return out
  }

  private fun putNullableFloat(editor: SharedPreferences.Editor, key: String, value: Float?) {
    if (value != null) editor.putFloat(key, value) else editor.remove(key)
  }

  private fun getOverlayFloat(context: Context, key: String, fallback: Float): Float =
    if (get(context).contains(key)) get(context).getFloat(key, fallback) else fallback
}
