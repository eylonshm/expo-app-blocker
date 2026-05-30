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
import android.widget.ProgressBar
import android.widget.TextView

class OverlayManager(private val context: Context) {
  private val windowManager: WindowManager =
    context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

  private var overlayView: View? = null

  fun show(blockedPackageName: String? = null, reason: BlockReason = BlockReason.OPENED) {
    if (overlayView != null) {
      Log.d(TAG, "Overlay already visible")
      if (blockedPackageName != null) {
        navigateToApp(blockedPackageName, reason)
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
      navigateToApp(blockedPackageName, reason)
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

  private fun navigateToApp(blockedPackageName: String, reason: BlockReason) {
    val appName = resolveAppName(blockedPackageName)

    // Use the app's own scheme for deep linking
    val scheme = getAppScheme()
    val deepLinkIntent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse(
        "${scheme}://blocked?app=${Uri.encode(appName)}" +
          "&package=${Uri.encode(blockedPackageName)}&reason=${reason.slug}"
      )
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
    fun dp(value: Float) = (value * density).toInt()

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
    val titleFontSize = AppBlockerPrefs.getOverlayTitleFontSize(context)
    val textFontSize = AppBlockerPrefs.getOverlayTextFontSize(context)
    val titleBold = AppBlockerPrefs.getOverlayTitleBold(context)
    val padding = AppBlockerPrefs.getOverlayPadding(context)
    val iconSize = AppBlockerPrefs.getOverlayIconSize(context)
    val iconGap = AppBlockerPrefs.getOverlayIconBottomMargin(context)
    val titleGap = AppBlockerPrefs.getOverlayTitleBottomMargin(context)

    return LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setBackgroundColor(backgroundColor)
      setPadding(dp(padding), dp(padding), dp(padding), dp(padding))

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
          val size = dp(iconSize)
          layoutParams = LinearLayout.LayoutParams(size, size).apply {
            bottomMargin = dp(iconGap)
          }
        })
      }

      addView(TextView(context).apply {
        text = overlayTitle
        setTextColor(titleColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, titleFontSize)
        if (titleBold) setTypeface(typeface, Typeface.BOLD)
        gravity = Gravity.CENTER
        setPadding(0, 0, 0, dp(titleGap))
      })

      addView(TextView(context).apply {
        text = overlayText
        setTextColor(textColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, textFontSize)
        gravity = Gravity.CENTER
      })

      // Optional indeterminate spinner — gives the user a visual cue that
      // the app is launching during the ~150–300ms gap between intercept
      // detection and the deep-link landing.
      if (AppBlockerPrefs.getOverlayShowSpinner(context)) {
        val spinnerSize = dp(AppBlockerPrefs.getOverlaySpinnerSize(context))
        val spinnerGap = dp(AppBlockerPrefs.getOverlaySpinnerTopMargin(context))
        addView(ProgressBar(context).apply {
          isIndeterminate = true
          val tint = AppBlockerPrefs.getOverlaySpinnerColor(context)
          if (tint != null) {
            val parsed = parseColorOrNull(tint)
            if (parsed != null) indeterminateTintList = android.content.res.ColorStateList.valueOf(parsed)
          }
          layoutParams = LinearLayout.LayoutParams(spinnerSize, spinnerSize).apply {
            topMargin = spinnerGap
          }
        })
      }
    }
  }

  private fun parseColorOrDefault(hex: String, fallback: Int): Int = try {
    Color.parseColor(hex)
  } catch (_: IllegalArgumentException) {
    fallback
  }

  private fun parseColorOrNull(hex: String): Int? = try {
    Color.parseColor(hex)
  } catch (_: IllegalArgumentException) {
    null
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
