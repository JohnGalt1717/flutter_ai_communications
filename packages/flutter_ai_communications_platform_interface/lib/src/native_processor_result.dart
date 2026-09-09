/// Outcome of applying a Video processor on the Production video path.
enum NativeProcessorResult {
  /// The processor is running on the Production video path.
  ready,

  /// The still or intensity was invalid. The previous processor stays.
  invalid,

  /// Native segmentation is unavailable. Caller falls back to none.
  unavailable,
}
