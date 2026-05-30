package expo.modules.appblocker

import android.content.Context
import android.os.Handler

/**
 * Single source of truth for the Android "temporary unlock" state.
 *
 * While unlocked, the monitor should not block — see [isUnlocked]. An unlock
 * auto-expires after the requested duration; [relock] ends it early. The expiry
 * timestamp is persisted (see [Store]) so the JS module can read the remaining
 * time without holding a reference to the running service, mirroring the iOS
 * shared-defaults approach.
 *
 * Drive [unlock] / [relock] from the same (main) thread the [Handler] is bound to.
 */
class TemporaryUnlockController(
  private val context: Context,
  private val handler: Handler,
) {
  private val expireRunnable = Runnable { Store.clear(context) }

  /** True while a temporary unlock is in effect (blocking should be suppressed). */
  val isUnlocked: Boolean
    get() = Store.remainingSeconds(context) > 0

  /** Suppress blocking for [durationMinutes], replacing any pending expiry. No-op if <= 0. */
  fun unlock(durationMinutes: Int) {
    if (durationMinutes <= 0) return
    val durationMs = durationMinutes * 60_000L
    handler.removeCallbacks(expireRunnable)
    Store.setExpiry(context, System.currentTimeMillis() + durationMs)
    handler.postDelayed(expireRunnable, durationMs)
  }

  /** End any active unlock immediately, restoring blocking. */
  fun relock() {
    handler.removeCallbacks(expireRunnable)
    Store.clear(context)
  }

  /**
   * Stateless persistence for the unlock expiry. Readable from anywhere with a
   * [Context] — the running service is not required.
   */
  companion object Store {
    private const val KEY_EXPIRES_AT = "temporary_unlock_expires_at"

    private fun setExpiry(context: Context, expiresAtMs: Long) {
      AppBlockerPrefs.get(context).edit().putLong(KEY_EXPIRES_AT, expiresAtMs).apply()
    }

    private fun clear(context: Context) {
      AppBlockerPrefs.get(context).edit().remove(KEY_EXPIRES_AT).apply()
    }

    /** Seconds remaining on the active unlock, or 0 if none / already expired. */
    fun remainingSeconds(context: Context): Int {
      val expiresAtMs = AppBlockerPrefs.get(context).getLong(KEY_EXPIRES_AT, 0L)
      val remainingMs = expiresAtMs - System.currentTimeMillis()
      return if (remainingMs > 0) (remainingMs / 1000).toInt() else 0
    }
  }
}
