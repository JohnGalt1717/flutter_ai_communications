# Native reset must not replace the Session or its streams

iOS needs a full communications-channel teardown on Endpoint change, Isolation return, and resume unless an in-place native switch is proven. Scribe's SignalR hub dies if the capture Stream is replaced (`connectionId` is lost). Reset stays inside the same Session and the same broadcast streams; native teardown may emit silence frames so the Transport never sees an end. In-place switch is allowed only when native code can prove it.
