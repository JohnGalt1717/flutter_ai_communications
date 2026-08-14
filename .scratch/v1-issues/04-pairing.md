# Endpoint pairing and route classes

## Parent

See the v1 spec issue.

## What to build

Given a catalog of Endpoints, the Session pairs capture and render by hardware identity. Selecting one side of a Pair selects the other unless that side has an ephemeral override. If the override’s Endpoint disappears, the override clears. When a Pair disappears (AirPods out), fall back to speakerphone. OS-forced route changes apply and are broadcast. Handset and speakerphone exist as distinct catalog Endpoints on iOS/Android.

## Acceptance criteria

- [ ] Unit tests cover AirPods-in follow, render override, AirPods-out → speakerphone, and OS-forced re-pair
- [ ] Handset and speakerphone are selectable Endpoints in the catalog model
- [ ] No device-order preference list is stored

## Blocked by

The Audio manager + fake platform ticket.
