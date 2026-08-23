/// Capture constraint for a web Endpoint.
final class WebCapturePlan {
  /// Creates a capture plan.
  const WebCapturePlan({this.deviceId, this.constrainDevice = false});

  /// Exact `deviceId` constraint, if any.
  final String? deviceId;

  /// Whether getUserMedia should constrain [deviceId].
  final bool constrainDevice;
}

/// Typed sink-selection failure. No user-facing copy.
final class WebSinkUnsupported {
  /// Creates a typed unsupported outcome.
  const WebSinkUnsupported({required this.path, required this.statusCode});

  /// Browser API path that is missing.
  final String path;

  /// Machine status, never a user string.
  final String statusCode;
}

/// Render sink plan for a web Endpoint.
final class WebRenderPlan {
  /// Creates a render plan.
  const WebRenderPlan({this.sinkId, this.unsupported});

  /// `sinkId` to apply when supported.
  final String? sinkId;

  /// Typed outcome when sink selection is unavailable.
  final WebSinkUnsupported? unsupported;
}

/// Testable web capture/render selection policy.
final class WebEndpointPolicy {
  /// Creates the policy.
  const WebEndpointPolicy();

  /// Builds getUserMedia constraints for [deviceId].
  WebCapturePlan capturePlan(String? deviceId) {
    final id = switch (deviceId) {
      null || '' => null,
      final value => value,
    };
    return WebCapturePlan(deviceId: id, constrainDevice: id != null);
  }

  /// Builds a sink plan, or a typed unsupported outcome.
  WebRenderPlan renderPlan(String? sinkId, {required bool sinkSupported}) {
    final id = switch (sinkId) {
      null || '' => null,
      final value => value,
    };
    if (id == null) {
      return const WebRenderPlan();
    }
    if (!sinkSupported) {
      return const WebRenderPlan(
        unsupported: WebSinkUnsupported(
          path: 'AudioContext.sinkId',
          statusCode: 'unsupported',
        ),
      );
    }
    return WebRenderPlan(sinkId: id);
  }
}
