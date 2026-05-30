package expo.modules.appblocker

/**
 * Why a blocked app is being intercepted right now. Carried into the deep link
 * so the JS side can branch (e.g. a softer "time's up" interstitial when an
 * earned-time window expires while the user is still inside the app).
 */
enum class BlockReason(val slug: String) {
  /** A blocked app was freshly brought to the foreground. */
  OPENED("opened"),

  /** A temporary unlock expired while a blocked app was already in the foreground. */
  EXPIRED("expired"),
}
