# Mute-video is black frames; Camera-off stops hardware

Hosts need Teams/Zoom parity on the in-call controls. Mute-video keeps the camera graph running and substitutes black frames so the remote track stays alive and the encoder stays warm. Camera-off stops hardware capture and stops feeding sinks; preview goes dark; enable-video later restarts capture on the same Session without replacing audio streams. Pause still parks audio and video together.
