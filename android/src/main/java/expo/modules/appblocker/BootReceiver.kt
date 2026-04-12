package expo.modules.appblocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
      Log.d(TAG, "BootReceiver: BOOT_COMPLETED received, starting service")
      AppBlockerService.start(context.applicationContext)
    }
  }

  companion object {
    private const val TAG = "ExpoAppBlocker"
  }
}
