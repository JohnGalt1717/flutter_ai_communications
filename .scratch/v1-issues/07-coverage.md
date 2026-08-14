# Coverage port and audio-focus pause

## Parent

See the v1 spec issue.

## What to build

A `CoverageSource` port: `Stream<Coverage>` with `ok` / `degraded` / `lost` plus a reason (`airplane`, `pathDead`, `hostReported`, `unknown`) and optional latency. Default implementation reports airplane / audio-route death immediately and does not use `connectivity_plus` RTT. Hosts plug in a realtime source (Scribe hub ping). `lost` parks the Session like pause without disposing it or replacing streams; `ok` resumes if the Session was live.

## Acceptance criteria

- [ ] Fake host Coverage `lost` parks capture/play; `ok` resumes the same Session
- [ ] Default source can report `pathDead` when the fake platform kills the route
- [ ] No `connectivity_plus` dependency for RTT
- [ ] Phone-call / audio-focus interruption auto-pauses and is resumable

## Blocked by

The Audio manager + fake platform ticket.
