# The hub: MRRadar's local API

The hub lets another program on the Mac read MRRadar. Remote Code uses it to bring MRRadar to the phone. Whoever runs the engine runs the hub: the app does, and without the app `Contents/MacOS/mrradar-hub hub --attached` does, ending with its parent. When the app opens it asks a running hub to end and takes over.

The hub listens on 127.0.0.1 only. While it runs, `~/Library/Application Support/MRRadar/control.json` (mode 0600) holds `{ version, port, token, pid }`. Every request sends `Authorization: Bearer <token>`.

| Request | What it does |
|---|---|
| `GET /v1/status` | `{ api, version, state, demo }`. `state` is `ready`, `setup`, `missingCLI` or `signedOut` |
| `GET /v1/portfolio` | Totals per currency and each app, without its long series |
| `GET /v1/projects/<id>` | One app's full report |
| `GET /v1/alerts` | Recent alerts, newest first |
| `POST /v1/refresh` | `{ project? }` reads again now |
| `POST /v1/yield` | Ends a `mrradar-hub` so the app can take over |
| `GET /v1/events` | Server-sent events: `portfolio` (read it again) and `alert` (the alert as JSON) |

Bump `Hub.api` when a change breaks a client.
