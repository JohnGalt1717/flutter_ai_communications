# Screen source is not a Camera Endpoint

Screen capture has different permission, region, and cursor metadata than a camera, and Zoom/Teams send camera and screen together as two streams. Screen source is its own catalog. A Session may send screen-only, camera-only, or both. An inbound presentation is an inbound video stream on a Video surface, not a local Screen source. Native implementation may trail cameras; the contract must not pretend a screen is a camera.
