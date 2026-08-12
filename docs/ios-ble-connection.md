# iOS BLE connection notes

This branch carries the smallest set of changes that made the Meshtastic iOS app
finish connecting to the Flipper app over BLE.

## Observed failure

The phone discovered the Meshtastic BLE service and characteristics, subscribed
to FromNum, sent both config nonces, and reached "Retrieving nodes 2 of 2".
The Flipper Phone diagnostics page showed the key symptom:

```text
Stage:nodes N:69421
Q:36 Dr:8 Now:28
```

That means BLE discovery and pairing were already working. The failure was in
the Meshtastic phone protocol stream. The Flipper app had queued the full
firmware-like stage-one response, but the FAP cannot answer FromRadio reads
synchronously. It has to publish queued values on a timer and ring FromNum as a
doorbell. With 36 stage-one messages, iOS timed out before the queue drained.

## Fast stage-one stream

The stage-one response is now compact:

1. MyNodeInfo
2. DeviceUI config
3. own NodeInfo
4. DeviceMetadata
5. primary Channel
6. LoRa Config
7. config_complete_id 69420

Stage two remains:

1. own NodeInfo
2. config_complete_id 69421

This is enough for iOS to identify the node, record metadata, learn the primary
channel and LoRa settings, and complete the initial database gate.

## Drain cadence

The FromRadio drain interval is 75 ms. The iOS app polls FromRadio at roughly
200 ms, so 75 ms keeps values fresh without creating an excessive notification
storm. With the compact stream, the queue now drains completely during connect:

```text
Stage:done N:69421
Q:16 Dr:16 Now:0
```

The cumulative count is higher than the nominal 9-message handshake because iOS
may retry or send follow-up writes during the same session.

## Firmware version claim

The metadata firmware string is set to `2.5.18`, matching the iOS app's current
hard minimum. Earlier builds reported `2.5.0`, which allowed the protocol stream
to run but then failed the iOS version gate after database retrieval.

Do not raise this casually. iOS uses firmware version checks to expose newer
feature paths. Claiming a modern `2.7.x` or `2.8.x` version should be paired
with explicit support for the commands those paths send.
