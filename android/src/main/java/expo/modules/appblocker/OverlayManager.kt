package expo.modules.appblocker

import android.content.Context
import android.content.Intent
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

    val overlayText = AppBlockerPrefs.getOverlayText(context)
      .replace("{appName}", appName)

    return LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setBackgroundColor(Color.WHITE)
      setPadding(dp(32), dp(32), dp(32), dp(32))

      addView(TextView(context).apply {
        text = "App Blocked"
        setTextColor(Color.parseColor("#111111"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTypeface(typeface, Typeface.BOLD)
        gravity = Gravity.CENTER
        setPadding(0, 0, 0, dp(12))
      })

      addView(TextView(context).apply {
        text = overlayText
        setTextColor(Color.parseColor("#737373"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        gravity = Gravity.CENTER
      })
    }
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
