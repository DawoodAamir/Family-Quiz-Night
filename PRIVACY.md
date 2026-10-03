# Privacy

Family Quiz Night has no accounts, telemetry, advertising, tracking SDKs, or Internet matchmaking.

Local Network access is requested only when you open a room or search for rooms. Bonjour advertises the local host and the generic room name. Controllers exchange their chosen team nickname, an ephemeral random session token, answers, and scores with the selected host. The protocol uses unencrypted local TCP; use a trusted Wi-Fi network and avoid sensitive team names.

Games and controller identity stay in memory. The app does not persist game history or transmit data to a cloud service. Reconnect retains the token only while the controller process remains open; leaving resets it. Closing the host ends its game.

No microphone, camera, contacts, location, photo-library, or Health permissions are requested. The app does not accept a local-network system prompt on your behalf. Its privacy manifest declares no tracking, collected data, or required-reason API use.
