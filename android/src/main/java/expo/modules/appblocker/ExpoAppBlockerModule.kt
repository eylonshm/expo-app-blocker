package expo.modules.appblocker

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Process
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.ByteArrayOutputStream

private const val TAG = "ExpoAppBlocker"

class ExpoAppBlockerModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  override fun definition() = ModuleDefinition {
    Name("ExpoAppBlocker")

    OnCreate {
      AppBlockerService.start(context)
      Log.d(TAG, "Module OnCreate: started AppBlockerService")
    }

    AsyncFunction("checkOverlayPermission") {
      Settings.canDrawOverlays(context)
    }

    AsyncFunction("checkUsageStatsPermission") {
      val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
      val mode = appOps.unsafeCheckOpNoThrow(
        AppOpsManager.OPSTR_GET_USAGE_STATS,
        Process.myUid(),
        context.packageName
      )
      mode == AppOpsManager.MODE_ALLOWED
    }

    AsyncFunction("checkNotificationPermission") {
      NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    Function("openOverlaySettings") {
      val intent = Intent(
        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
        Uri.parse("package:${context.packageName}")
      ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }

    Function("openUsageStatsSettings") {
      val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }

    Function("setAndroidConfig") { config: Map<String, Any?> ->
      // JS sends numbers as Double over the bridge — coerce to Float so prefs
      // keep a consistent type. Booleans are forwarded as-is.
      fun numberOrNull(key: String): Float? = (config[key] as? Number)?.toFloat()

      AppBlockerPrefs.setAndroidConfig(
        context,
        overlayTitle = config["overlayTitle"] as? String,
        overlayText = config["overlayText"] as? String,
        overlayBackgroundColor = config["overlayBackgroundColor"] as? String,
        overlayTitleColor = config["overlayTitleColor"] as? String,
        overlayTextColor = config["overlayTextColor"] as? String,
        overlayTitleFontSize = numberOrNull("overlayTitleFontSize"),
        overlayTextFontSize = numberOrNull("overlayTextFontSize"),
        overlayTitleBold = config["overlayTitleBold"] as? Boolean,
        overlayPadding = numberOrNull("overlayPadding"),
        overlayIconSize = numberOrNull("overlayIconSize"),
        overlayIconBottomMargin = numberOrNull("overlayIconBottomMargin"),
        overlayTitleBottomMargin = numberOrNull("overlayTitleBottomMargin"),
        overlayShowSpinner = config["overlayShowSpinner"] as? Boolean,
        overlaySpinnerSize = numberOrNull("overlaySpinnerSize"),
        overlaySpinnerTopMargin = numberOrNull("overlaySpinnerTopMargin"),
        overlaySpinnerColor = config["overlaySpinnerColor"] as? String,
        notificationTitle = config["notificationTitle"] as? String,
        notificationText = config["notificationText"] as? String,
      )
      Log.d(TAG, "setAndroidConfig: $config")
    }

    Function("setBlockedApps") { packageNames: List<String> ->
      AppBlockerPrefs.setBlockedPackages(context, packageNames)
      Log.d(TAG, "setBlockedApps: $packageNames")
    }

    Function("getBlockedApps") {
      AppBlockerPrefs.getBlockedPackages(context).toList()
    }

    Function("startMonitoring") {
      AppBlockerService.start(context)
      Log.d(TAG, "startMonitoring called")
    }

    Function("stopMonitoring") {
      AppBlockerService.stop(context)
      Log.d(TAG, "stopMonitoring called")
    }

    Function("temporaryUnlockAndroid") { durationMinutes: Int ->
      AppBlockerService.temporaryUnlock(context, durationMinutes)
      Log.d(TAG, "temporaryUnlockAndroid: $durationMinutes minutes")
    }

    Function("relockAndroid") {
      AppBlockerService.relock(context)
      Log.d(TAG, "relockAndroid")
    }

    AsyncFunction("getInstalledApps") {
      val pm = context.packageManager
      val intent = Intent(Intent.ACTION_MAIN).apply {
        addCategory(Intent.CATEGORY_LAUNCHER)
      }
      val resolved = pm.queryIntentActivities(intent, 0)
      val seen = HashSet<String>()
      resolved.mapNotNull { resolveInfo ->
        val appInfo = resolveInfo.activityInfo.applicationInfo
        if (appInfo.packageName == context.packageName) return@mapNotNull null
        if (!seen.add(appInfo.packageName)) return@mapNotNull null

        val iconBase64 = try {
          val drawable = pm.getApplicationIcon(appInfo)
          drawableToBase64Png(drawable)
        } catch (e: Exception) {
          Log.w(TAG, "Failed to load icon for ${appInfo.packageName}: ${e.message}")
          null
        }

        mapOf(
          "packageName" to appInfo.packageName,
          "name" to (pm.getApplicationLabel(appInfo)?.toString() ?: appInfo.packageName),
          "iconBase64" to iconBase64
        )
      }.sortedBy { it["name"]?.toString()?.lowercase() }
    }
  }

  private fun drawableToBase64Png(drawable: Drawable): String {
    val size = 96
    val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
      Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
    } else {
      val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
      val canvas = Canvas(bmp)
      drawable.setBounds(0, 0, canvas.width, canvas.height)
      drawable.draw(canvas)
      bmp
    }
    val stream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
  }
}
