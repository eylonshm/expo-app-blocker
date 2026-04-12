package expo.modules.appblocker

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
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

    val view = buildOverlayView()
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

  private fun navigateToApp(blockedPackageName: String) {
    val appName = try {
      val pm = context.packageManager
      val appInfo = pm.getApplicationInfo(blockedPackageName, 0)
      pm.getApplicationLabel(appInfo).toString()
    } catch (e: Exception) {
      blockedPackageName
    }

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
    return try {
      val pm = context.packageManager
      val intent = pm.getLaunchIntentForPackage(context.packageName)
      intent?.data?.scheme ?: context.packageName.replace(".", "-")
    } catch (e: Exception) {
      context.packageName.replace(".", "-")
    }
  }

  private fun buildOverlayView(): View {
    val textView = TextView(context).apply {
      text = ""
      setBackgroundColor(Color.parseColor("#F0000000"))
      gravity = Gravity.CENTER
    }
    return textView
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
