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

/// Whether a post-start deviceID bind must fail start/select (issue #95).
///
/// A non-null selected Endpoint whose bind returned nil is a lie if the
/// graph reports started. A null or empty selected id is OS default and
/// is allowed to stay unbound.
bool postStartBindFailed({
  required String? selectedId,
  required String? boundUid,
}) {
  if (selectedId == null || selectedId.isEmpty) {
    return false;
  }
  return boundUid == null;
}

/// Window to wait for a Core Audio UID after graph or camera teardown.
///
/// USB composites (BRIO mic+camera) drop out of
/// `kAudioHardwarePropertyDevices` after `stopCameraNative`. Join stop+start
/// must wait or `deviceID(forUID:)` returns nil and #95 fails the start.
const macosUidLookupRetry = Duration(seconds: 2);

/// Pause between UID lookups while waiting for a USB composite to return.
const macosUidLookupRetryStep = Duration(milliseconds: 50);

/// Whether another Core Audio UID lookup should run.
bool macosUidLookupShouldRetry({
  required bool resolved,
  required Duration elapsed,
}) {
  if (resolved) {
    return false;
  }
  return elapsed < macosUidLookupRetry;
}
