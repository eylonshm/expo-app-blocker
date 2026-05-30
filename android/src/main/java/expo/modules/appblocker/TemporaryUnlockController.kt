package expo.modules.appblocker

import android.content.Context

/**
 * Single source of truth for the Android "earned time" budget.
 *
 * Unlock time is a *budget of seconds* that is consumed only while a blocked app
 * is actually in the foreground — see [AppBlockerService], which calls [consume]
 * on each poll tick spent inside a blocked app and leaves the budget untouched
 * otherwise. This gives pause/resume semantics: leaving the blocked app freezes
 * the remaining time; returning resumes it.
 *
 * The budget is persisted (see [Store]) so the JS module can read it without
 * holding a reference to the running service, mirroring the iOS approach.
 *
 * [consume] and [grant] do a read-modify-write on the persisted budget and are
 * NOT atomic; the service drives both from the main thread (the poll Handler and
 * onStartCommand share that thread), which serializes them. Don't call these from
 * another thread without adding synchronization.
 */
class TemporaryUnlockController(private val context: Context) {
  /** True while earned time remains (blocking should be suppressed inside blocked apps). */
  val hasTimeLeft: Boolean
    get() = Store.remainingMs(context) > 0

  /** Grant a fresh budget of [durationMinutes], replacing any existing balance. No-op if <= 0. */
  fun grant(durationMinutes: Int) {
    if (durationMinutes <= 0) return
    Store.setRemaining(context, durationMinutes * 60_000L)
  }

  /** Spend [elapsedMs] of the budget (clamped at 0). Called while inside a blocked app. */
  fun consume(elapsedMs: Long) {
    if (elapsedMs <= 0) return
    val remaining = Store.remainingMs(context)
    if (remaining <= 0) return
    Store.setRemaining(context, (remaining - elapsedMs).coerceAtLeast(0))
  }

  /** Drop the entire budget immediately, restoring blocking. */
  fun clear() {
    Store.setRemaining(context, 0)
  }

  /**
   * Stateless persistence for the remaining budget. Readable from anywhere with a
   * [Context] — the running service is not required.
   */
  companion object Store {
    private const val KEY_REMAINING_MS = "temporary_unlock_remaining_ms"

    private fun setRemaining(context: Context, remainingMs: Long) {
      AppBlockerPrefs.get(context).edit().putLong(KEY_REMAINING_MS, remainingMs).apply()
    }

    private fun remainingMs(context: Context): Long =
      AppBlockerPrefs.get(context).getLong(KEY_REMAINING_MS, 0L).coerceAtLeast(0L)

    /** Seconds of earned time remaining, or 0 if none. */
    fun remainingSeconds(context: Context): Int = (remainingMs(context) / 1000).toInt()
  }
}
