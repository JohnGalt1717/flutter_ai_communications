/// Outcome of `AudioQueueSetProperty(kAudioQueueProperty_CurrentDevice)`.
final class MacQueueBind {
  /// Creates a bind outcome.
  const MacQueueBind({required this.setStatus, this.boundUid});

  /// `OSStatus` from SetProperty.
  final int setStatus;

  /// UID Core Audio reports after the set, if GetProperty succeeded.
  final String? boundUid;

  /// Set succeeded and GetProperty confirms the requested UID.
  bool applied(String requestedUid) =>
      setStatus == 0 && boundUid != null && boundUid == requestedUid;
}

/// Observed UID after a CurrentDevice set.
///
/// Always the GetProperty result. Never the requested UID as a fallback —
/// a failed set, a failed get, or an OS that ignored the set must not
/// rewrite Desired or lie that the queue is on the requested Endpoint.
String? observedQueueUid({required String? boundUid}) => boundUid;
