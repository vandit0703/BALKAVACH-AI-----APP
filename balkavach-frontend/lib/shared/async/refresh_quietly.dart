/// Waits for a pull-to-refresh to finish.
///
/// Failures are already rendered by the provider's error state, so they must
/// not escape the `RefreshIndicator` callback.
Future<void> refreshQuietly(Future<Object?> refresh) async {
  try {
    await refresh;
  } on Object {
    // Rendered by the watching widget.
  }
}
