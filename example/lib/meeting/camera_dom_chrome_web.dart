import 'package:web/web.dart' as web;

const _id = 'fac-camera-chrome';

/// Body-pinned caption/mute badge above the web camera overlay.
void setCameraDomChrome({String? caption, bool muted = false}) {
  var el = web.document.getElementById(_id) as web.HTMLElement?;
  if ((caption == null || caption.isEmpty) && !muted) {
    el?.remove();
    return;
  }
  if (el == null) {
    el = web.HTMLDivElement()..id = _id;
    el.style
      ..setProperty('position', 'fixed')
      ..setProperty('z-index', '10')
      ..setProperty('pointer-events', 'none')
      ..setProperty('color', '#E8E8F0')
      ..setProperty('font-size', '12px')
      ..setProperty('font-family', 'sans-serif')
      ..setProperty('text-shadow', '0 1px 2px #000');
    web.document.body!.append(el);
  }
  el.textContent = [
    if (caption != null && caption.isNotEmpty) caption,
    if (muted) 'mic off',
  ].join('  ');
}
