package expo.modules.appblocker

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

class OverlayManager(private val context: Context) {
  private val windowManager: WindowManager =
    context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

  private var overlayView: View? = null

  fun show(blockedPackageName: String? = null) {
    if (overlayView != null) {
      Log.d(TAG, "Overlay already visible")
      if (blockedPackageName != null) {
        navigateToApp(blockedPackageName)
      } else {
        bringAppToFront()
      }
      return
    }

    val appName = blockedPackageName?.let { resolveAppName(it) } ?: ""
    val view = buildOverlayView(appName)
    try {
      windowManager.addView(view, buildLayoutParams())
      overlayView = view
      Log.d(TAG, "Overlay shown")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to add overlay view", e)
      return
    }

    if (blockedPackageName != null) {
      navigateToApp(blockedPackageName)
    } else {
      bringAppToFront()
    }
  }

  fun hide() {
    val view = overlayView ?: return
    try {
      windowManager.removeView(view)
      Log.d(TAG, "Overlay hidden")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to remove overlay view", e)
    }
    overlayView = null
  }

  private fun resolveAppName(packageName: String): String = try {
    val pm = context.packageManager
    val appInfo = pm.getApplicationInfo(packageName, 0)
    pm.getApplicationLabel(appInfo).toString()
  } catch (e: Exception) {
    packageName
  }

  private fun navigateToApp(blockedPackageName: String) {
    val appName = resolveAppName(blockedPackageName)

    // Use the app's own scheme for deep linking
    val scheme = getAppScheme()
    val deepLinkIntent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse("${scheme}://blocked?app=${Uri.encode(appName)}&package=${Uri.encode(blockedPackageName)}")
    ).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }

    try {
      context.startActivity(deepLinkIntent)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to deep link", e)
      bringAppToFront()
    }
  }

  private fun bringAppToFront() {
    val launchIntent = context.packageManager
      .getLaunchIntentForPackage(context.packageName)
      ?.apply {
        addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        )
      }

    if (launchIntent == null) {
      Log.w(TAG, "No launch intent for package ${context.packageName}")
      return
    }

    context.startActivity(launchIntent)
  }

  private fun getAppScheme(): String {
    val resId = context.resources.getIdentifier("expo_app_blocker_scheme", "string", context.packageName)
    if (resId != 0) return context.getString(resId)
    return context.packageName.replace(".", "-")
  }

  private fun buildOverlayView(appName: String): View {
    val density = context.resources.displayMetrics.density
    fun dp(value: Int) = (value * density).toInt()

    val overlayTitle = AppBlockerPrefs.getOverlayTitle(context)
      .replace("{appName}", appName)
    val overlayText = AppBlockerPrefs.getOverlayText(context)
      .replace("{appName}", appName)
    val backgroundColor = parseColorOrDefault(
      AppBlockerPrefs.getOverlayBackgroundColor(context),
      Color.WHITE,
    )
    val titleColor = parseColorOrDefault(
      AppBlockerPrefs.getOverlayTitleColor(context),
      Color.parseColor("#111111"),
    )
    val textColor = parseColorOrDefault(
      AppBlockerPrefs.getOverlayTextColor(context),
      Color.parseColor("#737373"),
    )

    return LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setBackgroundColor(backgroundColor)
      setPadding(dp(32), dp(32), dp(32), dp(32))

      // Optional brand icon — drawable named `expo_app_blocker_overlay_icon`
      // is copied by the config plugin from `pluginConfig.android.overlay.icon`.
      // Skip silently if missing so apps that don't ship one still get a clean overlay.
      val iconResId = context.resources.getIdentifier(
        "expo_app_blocker_overlay_icon",
        "drawable",
        context.packageName,
      )
      if (iconResId != 0) {
        addView(ImageView(context).apply {
          val bitmap = BitmapFactory.decodeResource(context.resources, iconResId)
          if (bitmap != null) setImageBitmap(bitmap)
          val size = dp(96)
          layoutParams = LinearLayout.LayoutParams(size, size).apply {
            bottomMargin = dp(20)
          }
        })
      }

      addView(TextView(context).apply {
        text = overlayTitle
        setTextColor(titleColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTypeface(typeface, Typeface.BOLD)
        gravity = Gravity.CENTER
        setPadding(0, 0, 0, dp(12))
      })

      addView(TextView(context).apply {
        text = overlayText
        setTextColor(textColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        gravity = Gravity.CENTER
      })
    }
  }

  private fun parseColorOrDefault(hex: String, fallback: Int): Int = try {
    Color.parseColor(hex)
  } catch (_: IllegalArgumentException) {
    fallback
  }

  private fun buildLayoutParams(): WindowManager.LayoutParams {
    @Suppress("DEPRECATION")
    val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    } else {
      WindowManager.LayoutParams.TYPE_PHONE
    }

    return WindowManager.LayoutParams(
      WindowManager.LayoutParams.MATCH_PARENT,
      WindowManager.LayoutParams.MATCH_PARENT,
      type,
      WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
      PixelFormat.TRANSLUCENT
    ).apply {
      gravity = Gravity.TOP or Gravity.START
    }
  }

  companion object {
    private const val TAG = "ExpoAppBlocker"
  }
}
