package expo.modules.appblocker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class AppBlockerService : Service() {
  private val handler = Handler(Looper.getMainLooper())
  private var lastForegroundPackage: String? = null
  private lateinit var overlayManager: OverlayManager
  @Volatile private var paused = false

  private val resumeRunnable = Runnable {
    Log.d(TAG, "Temporary unlock expired, resuming blocking")
    paused = false
  }

  private val pollRunnable = object : Runnable {
    override fun run() {
      if (!paused) {
        val foregroundPackage = getCurrentForegroundPackage()
        if (foregroundPackage != null && foregroundPackage != lastForegroundPackage) {
          Log.d(TAG, "Foreground changed: $foregroundPackage")
          lastForegroundPackage = foregroundPackage
          handleForegroundChange(foregroundPackage)
        }
      }
      handler.postDelayed(this, POLL_INTERVAL_MS)
    }
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    Log.d(TAG, "AppBlockerService onCreate")
    overlayManager = OverlayManager(this)
    createChannelsIfNeeded()
    startForeground(NOTIFICATION_ID, buildNotification())
    handler.post(pollRunnable)
  }

  private fun handleForegroundChange(foregroundPackage: String) {
    val blocked = AppBlockerPrefs.getBlockedPackages(this)
    if (foregroundPackage in blocked) {
      Log.d(TAG, "Blocked app in foreground: $foregroundPackage")
      overlayManager.show(foregroundPackage)
      showBlockedNotification(foregroundPackage)
    } else {
      overlayManager.hide()
    }
  }

  private fun showBlockedNotification(packageName: String) {
    val appName = try {
      val pm = this.packageManager
      val appInfo = pm.getApplicationInfo(packageName, 0)
      pm.getApplicationLabel(appInfo).toString()
    } catch (e: Exception) {
      packageName
    }

    val title = AppBlockerPrefs.getNotificationTitle(this).replace("{appName}", appName)
    val text = AppBlockerPrefs.getNotificationText(this).replace("{appName}", appName)

    val scheme = getAppScheme()
    val deepLinkIntent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse("${scheme}://blocked?app=${Uri.encode(appName)}&package=${Uri.encode(packageName)}")
    ).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }

    val launchIntent = packageManager.getLaunchIntentForPackage(this.packageName)
      ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP) }

    val resolvedIntent = try {
      deepLinkIntent.resolveActivity(packageManager)?.let { deepLinkIntent } ?: launchIntent
    } catch (e: Exception) {
      launchIntent
    } ?: deepLinkIntent

    val pendingIntent = PendingIntent.getActivity(
      this, packageName.hashCode(), resolvedIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val notification = NotificationCompat.Builder(this, BLOCKED_CHANNEL_ID)
      .setContentTitle(title)
      .setContentText(text)
      .setSmallIcon(applicationInfo.icon)
      .setAutoCancel(true)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setContentIntent(pendingIntent)
      .build()

    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(BLOCKED_NOTIFICATION_ID, notification)
  }

  private fun getAppScheme(): String {
    val resId = resources.getIdentifier("expo_app_blocker_scheme", "string", packageName)
    if (resId != 0) return getString(resId)
    return try {
      packageManager.getLaunchIntentForPackage(packageName)?.data?.scheme
        ?: packageName.replace(".", "-")
    } catch (e: Exception) {
      packageName.replace(".", "-")
    }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val action = intent?.action
    if (action == ACTION_TEMPORARY_UNLOCK) {
      val minutes = intent.getIntExtra(EXTRA_DURATION_MINUTES, 0)
      if (minutes > 0) {
        Log.d(TAG, "Temporary unlock for $minutes minutes")
        handler.removeCallbacks(resumeRunnable)
        paused = true
        overlayManager.hide()
        handler.postDelayed(resumeRunnable, minutes * 60_000L)
      }
    }
    return START_STICKY
  }

  override fun onDestroy() {
    Log.d(TAG, "AppBlockerService onDestroy")
    handler.removeCallbacks(pollRunnable)
    overlayManager.hide()
    super.onDestroy()
  }

  private fun getCurrentForegroundPackage(): String? {
    val usageStatsManager =
      getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val endTime = System.currentTimeMillis()
    val beginTime = endTime - LOOKBACK_WINDOW_MS
    val events = usageStatsManager.queryEvents(beginTime, endTime)
    val event = UsageEvents.Event()
    var latestForeground: String? = null
    while (events.hasNextEvent()) {
      events.getNextEvent(event)
      if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
        latestForeground = event.packageName
      }
    }
    return latestForeground
  }

  private fun createChannelsIfNeeded() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

      val serviceChannel = NotificationChannel(
        CHANNEL_ID, "App Blocker", NotificationManager.IMPORTANCE_LOW
      ).apply {
        description = "Keeps the app blocker running"
        setShowBadge(false)
      }
      manager.createNotificationChannel(serviceChannel)

      val blockedChannel = NotificationChannel(
        BLOCKED_CHANNEL_ID, "Blocked App Alerts", NotificationManager.IMPORTANCE_HIGH
      ).apply {
        description = "Notifications when a blocked app is detected"
      }
      manager.createNotificationChannel(blockedChannel)
    }
  }

  private fun buildNotification(): Notification =
    NotificationCompat.Builder(this, CHANNEL_ID)
      .setContentTitle("App Blocker")
      .setContentText("Monitoring blocked apps")
      .setSmallIcon(applicationInfo.icon)
      .setOngoing(true)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .build()

  companion object {
    private const val TAG = "ExpoAppBlocker"
    private const val CHANNEL_ID = "expo_app_blocker_channel"
    private const val BLOCKED_CHANNEL_ID = "expo_app_blocker_blocked"
    private const val NOTIFICATION_ID = 9001
    private const val BLOCKED_NOTIFICATION_ID = 9002
    private const val POLL_INTERVAL_MS = 500L
    private const val LOOKBACK_WINDOW_MS = 10_000L
    private const val ACTION_TEMPORARY_UNLOCK = "expo.modules.appblocker.TEMPORARY_UNLOCK"
    private const val EXTRA_DURATION_MINUTES = "duration_minutes"

    fun start(context: Context) {
      val intent = Intent(context, AppBlockerService::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      val intent = Intent(context, AppBlockerService::class.java)
      context.stopService(intent)
    }

    fun temporaryUnlock(context: Context, durationMinutes: Int) {
      val intent = Intent(context, AppBlockerService::class.java).apply {
        action = ACTION_TEMPORARY_UNLOCK
        putExtra(EXTRA_DURATION_MINUTES, durationMinutes)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }
  }
}
