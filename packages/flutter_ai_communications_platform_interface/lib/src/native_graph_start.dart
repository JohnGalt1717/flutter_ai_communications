/// Outcome of starting the native capture/render graph.
enum NativeGraphStart {
  /// The graph is running.
  started,

  /// No usable capture Endpoint.
  unavailable,

  /// The graph could not start.
  failed,
}
