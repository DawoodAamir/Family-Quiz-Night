# Verification

October 3, 2026. Verification in progress.

- Native iPhone/iPad and Apple TV simulator app builds passed with Swift 6 complete concurrency.
- Both native UI test targets compile against the OS 27 SDKs.
- Unsigned iOS and tvOS Release device builds passed.
- All three core tests passed locally in Debug and Release, including timed scoring/reconnect rules, bounded messages and rooms, and an actual framed TCP loopback exchange. The transport test waits for listener readiness before connecting.
- Hosted Debug/Release tests, remote-play UI verification, and screenshots are pending.

Physical-device checks remain necessary for Bonjour discovery on a real LAN, Local Network denial, phone sleep/wake, controller reconnect, host termination, Siri Remote navigation, VoiceOver, and text-size changes. A transport loopback test alone does not verify cross-device discovery.
