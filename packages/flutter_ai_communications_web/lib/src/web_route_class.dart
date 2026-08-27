import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

/// Maps a browser `MediaDeviceInfo` label to a [RouteClass].
///
/// Chrome does not expose transport. Labels after getUserMedia are the
/// signal. Built-in speakers/mics are speakerphone. There is no handset.
RouteClass webRouteClass({required String name, required bool isCapture}) {
  var lower = name.toLowerCase();
  for (final prefix in ['default - ', 'communications - ']) {
    if (lower.startsWith(prefix)) {
      lower = lower.substring(prefix.length);
      break;
    }
  }
  if (lower.contains('bluetooth') ||
      lower.contains('airpods') ||
      lower.contains('a2dp') ||
      lower.contains('hfp') ||
      lower.contains('tesla') ||
      lower.contains('carplay') ||
      lower.contains('android auto')) {
    return RouteClass.bluetooth;
  }
  if (lower.contains('headset') ||
      lower.contains('headphone') ||
      lower.contains('earphone') ||
      lower.contains('usb')) {
    return RouteClass.wired;
  }
  if (lower.contains('speaker') ||
      lower.contains('microphone') ||
      lower.contains('built-in') ||
      lower.contains('macbook') ||
      lower.contains('default')) {
    return RouteClass.speakerphone;
  }
  return isCapture ? RouteClass.wired : RouteClass.speakerphone;
}
