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

## Firmware version claim and heartbeat

The metadata firmware string is set to `2.7.4`. Earlier builds reported
`2.5.0`, which allowed the protocol stream to run but then failed the iOS
version gate after database retrieval. `2.5.18` satisfies the hard minimum, and
`2.6.0` clears the iOS security warning.

The next important gate is `2.7.4`: iOS documents heartbeat writes as liveness
checks and expects a definite `FromRadio.queueStatus` response. BLE does not use
the repeating idle heartbeat timer, but the connection flow still sends
heartbeats before the config and database requests. This branch decodes
`ToRadio.heartbeat.nonce` and replies with `queueStatus`, echoing the nonce as
`mesh_packet_id`.

Do not raise this casually past `2.7.4`. iOS uses firmware version checks to
expose newer feature paths. Claiming a modern `2.8.x` version should be paired
with explicit support for the commands those paths send, including the
`FromRadio.region_presets` map and the newer TAK/status/discovery paths.
