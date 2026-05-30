package expo.modules.appblocker

import android.os.Handler

/**
 * Owns the "temporary unlock" state for Android blocking.
 *
 * While unlocked, the monitor should not block — see [isUnlocked]. An unlock
 * auto-expires after the requested duration; [relock] ends it early. All timer
 * bookkeeping is hidden here so the service only asks a single yes/no question.
 *
 * Not thread-safe beyond the [isUnlocked] read: drive [unlock] / [relock] from
 * the same (main) thread the [Handler] is bound to.
 */
class TemporaryUnlockController(private val handler: Handler) {
  @Volatile private var unlocked = false

  private val expireRunnable = Runnable { unlocked = false }

  /** True while a temporary unlock is in effect (blocking should be suppressed). */
  val isUnlocked: Boolean
    get() = unlocked

  /** Suppress blocking for [durationMinutes], replacing any pending expiry. No-op if <= 0. */
  fun unlock(durationMinutes: Int) {
    if (durationMinutes <= 0) return
    handler.removeCallbacks(expireRunnable)
    unlocked = true
    handler.postDelayed(expireRunnable, durationMinutes * 60_000L)
  }

  /** End any active unlock immediately, restoring blocking. */
  fun relock() {
    handler.removeCallbacks(expireRunnable)
    unlocked = false
  }
}
