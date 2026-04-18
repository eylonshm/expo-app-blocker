package expo.modules.appblocker

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

private const val TAG = "ExpoAppBlocker"
private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 9003

class ExpoAppBlockerModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  override fun definition() = ModuleDefinition {
    Name("ExpoAppBlocker")

    OnCreate {
      requestNotificationPermissionIfNeeded()
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
      AppBlockerPrefs.setAndroidConfig(
        context,
        overlayText = config["overlayText"] as? String,
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

    AsyncFunction("getInstalledApps") {
      val pm = context.packageManager
      val intent = Intent(Intent.ACTION_MAIN).apply {
        addCategory(Intent.CATEGORY_LAUNCHER)
      }
      val apps = pm.queryIntentActivities(intent, 0)
      apps.mapNotNull { resolveInfo ->
        val appInfo = resolveInfo.activityInfo.applicationInfo
        if (appInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0) return@mapNotNull null
        if (appInfo.packageName == context.packageName) return@mapNotNull null

        mapOf(
          "packageName" to appInfo.packageName,
          "name" to (pm.getApplicationLabel(appInfo)?.toString() ?: appInfo.packageName)
        )
      }.sortedBy { it["name"]?.lowercase() }
    }
  }

  private fun requestNotificationPermissionIfNeeded() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val granted = ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED
    if (granted) return
    val activity = appContext.currentActivity ?: return
    ActivityCompat.requestPermissions(
      activity,
      arrayOf(Manifest.permission.POST_NOTIFICATIONS),
      NOTIFICATION_PERMISSION_REQUEST_CODE
    )
  }
}
