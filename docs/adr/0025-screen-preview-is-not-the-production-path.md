# Screen preview and Share frame are pick chrome, not the Production video path

ADR-0013 forbids copying production frames through Dart. Picker thumbs and the Teams-style rectangle on the real window are not send. Screen previews exist only during Screen pick, at thumbnail size, and must not use a capture API that brands every window as “being shared” (Windows Graphics Capture yellow border). Share frame is library-owned native chrome via indicateScreenSource; the host draws the picker. OS-picker platforms have neither; the OS picker is the UI.
