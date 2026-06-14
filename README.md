# beammp auth bridge

Standalone player account system for BeamMP servers, bridging the gap while official authentication is unavailable.

Guest players are prompted to register or sign in with a username and password. Authenticated players receive a persistent display name across sessions.

![](https://raw.githubusercontent.com/5DROR5/beammp-auth-bridge/main/png.png)

---

## Features

- Register and sign in with username and password
- Persistent display name across sessions via hashed credentials stored locally
- Auto-login on reconnect
- Display names reflected on vehicles, player list, and launcher server list in real time
- Server-side account storage in JSON
- Autosave every 30 seconds
- Translations support via `lang/en.json`

---

## Installation

**Server**

Copy the `Server/PIT_Auth` folder into your server's `Resources/Server/`.

```
PIT_Auth/
├── main.lua
├── modules/
│   └── DescUpdater.lua
├── data/          ← created automatically
└── lang/
    └── en.json
```

**Client**

Copy `Client/Accounts.zip` into your server's `Resources/Client/`.

---

## Server Description

The launcher server list displays authenticated player names automatically.  
To add a fixed header above the player list (server name, rules, Discord link, etc.), edit `FIXED_DESC` at the top of `modules/DescUpdater.lua`:

```lua
local FIXED_DESC = "My Server — discord.gg/example\n\n"
```

---

## How It Works

1. Guest players are detected on join and shown a login/register dialog.
2. Credentials are hashed client-side using SHA-256 before being sent to the server.
3. On successful auth, the player receives a display name that is broadcast to all connected clients.
4. Credentials are saved locally in the browser for auto-login on reconnect.

---

## License

MIT
