# BUILD_PLAN.md — Black Box

Build in this order. Each phase ends with **checks** that must pass before moving on. Phases 0–6 are the **core demo**. Phases 7–9 are the **offline features**. Phase 10 is **demo polish**. If time runs short, cut from the bottom (see section "Cut list").

---

## Shared contracts (do not change without asking the user)

### Config values (`app/lib/config.dart` and `server/.env`)

| Name | Default | Meaning |
| --- | --- | --- |
| PING_NORMAL_SEC | 120 | normal ping interval (demo mode: 10) |
| PING_RESCUE_SEC | 60 | ping interval in Rescue Mode (demo mode: 5) |
| SHOCK_G | 3.0 | impact threshold in g (1 g = 9.81 m/s²) |
| FREEFALL_G | 0.3 | below this for 150 ms = free fall |
| FALL_STILL_SEC | 10 | stillness after impact to count as a fall |
| FALL_ANSWER_SEC | 30 | time to tap "I'm OK" before alerting (demo: 15) |
| NO_MOVE_MIN | 10 | no movement before "Are you OK?" (demo: 1) |
| COLLAPSE_PHONES | 3 | phones with shocks needed |
| COLLAPSE_WINDOW_SEC | 5 | window for those shocks |
| FLOOR_HEIGHT_M | 3.5 | meters per floor |
| HPA_PER_M | 0.12 | pressure drop per meter |
| DEMO_MODE | true | short timers + demo seed data |

### Data model (SQLite)

- **workers**: id, name, phone, site_code, joined_at, active (bool)
- **pings**: id, worker_id, zone, floor, battery, lat, lng, moving (bool), source ("internet" | "mesh"), ts
- **events**: id, worker_id, type ("shock" | "fall" | "fall_ok" | "fall_alert" | "no_move"), ts
- **rescue**: id, active, reason, started_at, ended_at
- **checkins**: rescue_id, worker_id, status ("none" | "safe" | "help"), note, ts
- **scans**: id, floor, model_file (.usdz), glb_file (nullable), json_file, walls, doors, windows, openings, objects, ts
- **hazards**: id, floor, text, osha_topic, status ("open" | "fixed" | "false_alarm"), scan_id, ts
- **messages**: id, direction ("out" | "in"), to_or_from, body, channel ("chert" | "fake" | "mesh"), ts
- **mesh_seen**: msg_id, ts (dedupe)

### REST API

| Method + path | Body | Returns |
| --- | --- | --- |
| POST `/workers/join` | `{name, phone, site_code}` | `{worker_id}` |
| POST `/ping` | `{worker_id, zone, floor, battery, lat?, lng?, moving, source}` | `{rescue_active, rescue_id?}` |
| POST `/workers/{id}/end_shift` | – | `{ok}` (hides the worker until their next ping; added after Phase 10 at the user's request) |
| POST `/event` | `{worker_id, type}` | `{rescue_active}` |
| POST `/rescue/start` | `{reason}` | rescue object |
| POST `/rescue/stop` | – | rescue object |
| POST `/checkin` | `{worker_id, status, note?}` (from app buttons) | `{ok}` |
| POST `/chert/webhook` | Chert's format | `{ok}` (parses "1" / "2" replies) |
| POST `/scan` | multipart: `floor`, `model` (.usdz), `room_json` | `{scan_id, parts, hazards: [...]}` |
| POST `/hazards/{id}` | `{status}` | hazard |
| POST `/hazards/{id}/warn` | – | `{ok, sent}` (texts workers on the hazard's floor; added in Phase 5, approved by the user) |
| POST `/mesh/upload` | `{messages: [MeshMessage]}` | `{accepted, duplicates}` |
| GET `/state` | – | full snapshot (same as WebSocket payload) |
| POST `/demo/reset` | – | resets DB to demo seed (only if DEMO_MODE) |
| WS `/live` | – | pushes snapshot on every change |
| GET `/files/...` | – | static scan files |
| GET `/app/...` | – | built Flutter web (dashboard at `/app/#/dashboard`, rescuer at `/app/#/rescue`) |

**Snapshot shape** (WebSocket + `/state`):

```json
{
  "site": {"name": "Arlington Site", "code": "ARL-0412"},
  "rescue": {"active": false, "reason": null, "started_at": null},
  "workers": [{"id": "w1", "name": "Sajid H.", "zone": "B", "floor": 3, "battery": 64,
               "last_ping": 1763060000, "moving": true, "source": "internet",
               "status": "none", "phone_lost": false}],
  "hazards": [{"id": 1, "floor": 3, "text": "New opening on Floor 3, east side",
               "osha_topic": "Fall protection: holes and openings", "status": "open", "ts": 0,
               "before": {"walls": 6, "doors": 2, "windows": 1, "openings": 0, "objects": 4},
               "after": {"walls": 6, "doors": 2, "windows": 1, "openings": 1, "objects": 4}}],
  "scans": {"3": {"model": "floor3-1763.glb", "ts": 0, "parts": {"walls": 6, "doors": 2, "windows": 1, "openings": 1}}},
  "messages": [{"direction": "out", "to_or_from": "all", "body": "...", "ts": 0}]
}
```

### Mesh message format

```json
{"msg_id": "uuid", "origin_worker_id": "w1", "type": "help" | "safe" | "ping" | "text",
 "body": "I need help", "zone": "B", "floor": 3, "battery": 61,
 "created_at": 1763060000, "ttl": 5, "path": ["w1", "w2"]}
```

Rules: drop if `msg_id` already seen; drop if `ttl == 0`; otherwise store, show, append own id to `path`, `ttl - 1`, forward to all connected peers except the one it came from. Any phone with internet uploads stored messages to `/mesh/upload`.

---

## Phase 0 — Setup (about 1 hour)

**Tasks**
1. Create the repo structure from CLAUDE.md. Add `.gitignore` (Flutter, Python, `.env`, `server/scans/*`).
2. `flutter create app --platforms=ios,web --org com.blackbox`.
3. Set iOS minimum to 16.0 in `ios/Podfile` and give the user Xcode steps for the deployment target and signing.
4. Add all packages from CLAUDE.md. Run `flutter pub get` and `flutter analyze`.
5. Create `server/` with `requirements.txt` (fastapi, uvicorn[standard], python-multipart, httpx, python-dotenv, pytest, ruff), `.env.example`, and an empty FastAPI app with `/health`.
6. Create `PROGRESS.md` with a checklist of all phases.

**Info.plist keys** (give the user exact steps or edit the file):
- NSCameraUsageDescription: "Black Box uses the camera and LiDAR to scan the site."
- NSMotionUsageDescription: "Black Box uses motion sensors to find your floor and detect falls."
- NSBluetoothAlwaysUsageDescription: "Black Box uses Bluetooth to find your zone and help rescuers find you."
- NSLocationWhenInUseUsageDescription: "Black Box uses your location only while you are on site."
- NSLocalNetworkUsageDescription: "Black Box connects to nearby phones to send messages when the internet is down."
- NSBonjourServices: `_bb-mesh._tcp`, `_bb-mesh._udp`
- NSNearbyInteractionUsageDescription: "Black Box measures distance to a teammate's phone to help find them."

**Checks**
- [ ] `flutter run` shows the default app on the user's iPhone.
- [ ] `uvicorn main:app` returns `{"ok": true}` at `/health`.

---

## Phase 1 — Server core (about 3 hours)

**Tasks**
1. `db.py`: create tables from the data model; helper functions.
2. Endpoints: `/workers/join`, `/ping`, `/event`, `/rescue/start`, `/rescue/stop`, `/checkin`, `/state`, WS `/live`.
3. Broadcast the snapshot on every change.
4. **Collapse logic:** on each `shock` event, count distinct workers with a shock in the last COLLAPSE_WINDOW_SEC. If ≥ COLLAPSE_PHONES and no rescue active → start rescue with reason "impact on N phones".
5. **Fall alert:** on `fall_alert` event → send text to supervisor: "Possible fall: {name}, Floor {f}, Zone {z}."
6. `senders.py`: `MessageSender` interface with `send(to, body)`. `FakeSender` logs and stores in `messages`. `ChertSender` reads `CHERT_API_KEY` and base URL from `.env`. **The exact Chert endpoint and webhook fields are unknown:** leave clearly marked TODOs and ask the user to paste them from docs.trychert.com or the Chert booth. Use FakeSender when no key is set.
7. On rescue start: set every active worker's check-in to "none" and send each: "BLACK BOX EMERGENCY. {name}, are you OK? Reply 1 if safe, 2 if you need help."
8. `/chert/webhook`: match sender phone → worker; "1" → safe, "2" → help, other text → help + save as note.
9. `demo.py` + `/demo/reset`: seed 14 workers across 3 floors (names and positions like the live demo page), one site, yesterday's scans for floors 1–3.
10. Tests: collapse trigger (2 phones = no, 3 phones = yes, 3 phones over 6 s = no), reply parsing, check-in counts.

**Checks**
- [ ] `pytest` passes.
- [ ] Using `/docs`: join 3 workers, ping, send 3 shocks → rescue starts, fake messages appear.

---

## Phase 2 — App shell, join, worker pings (about 4 hours)

**Tasks**
1. `config.dart` with server URL + all config values + feature flags.
2. `api.dart` and `live_socket.dart` (auto-reconnect every 3 s).
3. Theme from CLAUDE.md design rules. Reusable `BigButton`, `StatusPill`.
4. `role_picker.dart`: Worker / Supervisor / Rescuer finder / Zone beacon.
5. `join_screen.dart` (matches mockup W1): name, phone, site code, permission rows with Allow buttons. Save to `shared_preferences`.
6. **Zones without hardware** (`zone_beacon.dart`):
   - **Beacon mode:** a spare iPhone/iPad runs "Zone beacon" and advertises BLE local name `BB-ZONE-A` (choose A/B/C on screen). Screen stays on (keep awake) and shows a big zone letter.
   - **Worker side:** scan 4 seconds, pick the strongest `BB-ZONE-*`.
   - **Fallback:** if no beacon found, the worker home shows "Zone unknown — tap to pick" with A/B/C buttons.
7. `floor.dart`: barometer → floor using HPA_PER_M and FLOOR_HEIGHT_M, "I'm on the ground floor" calibration.
8. `worker_home.dart` (mockup W2): floor + zone big, last ping time, battery, hazard banner for the worker's floor/zone, "What your phone shares" box, reset-floor button, I need help, End shift.
9. Ping loop: every PING_NORMAL_SEC; switch to PING_RESCUE_SEC when the server says rescue is active. Keep the screen awake during a shift (`wakelock_plus`; ask the user before adding it).

**Checks**
- [ ] Two iPhones join and show up in `/state`.
- [ ] Zone changes when walking from beacon A to beacon B.
- [ ] Floor number changes when walking one floor up (test on stairs).

---

## Phase 3 — Motion safety (about 3 hours)

**Tasks** (`motion.dart`)
1. **Shock:** accelerometer magnitude > SHOCK_G → POST `/event` type `shock` (max once per 10 s).
2. **Fall:** free fall (< FREEFALL_G for ≥ 150 ms) → impact (> SHOCK_G within 1 s) → stillness (low variance for FALL_STILL_SEC). Then show `fall_check.dart`: big "Did you fall?" with countdown FALL_ANSWER_SEC and huge "I'm OK" button + vibration and sound. OK → event `fall_ok`. Timeout → event `fall_alert`.
3. **No-movement:** if no meaningful movement for NO_MOVE_MIN during a shift → ask "Are you OK?" the same way. Send `moving` in each ping.
4. Unit-test the detection logic in Dart with fake sensor streams (pure functions, no plugins).

**Checks**
- [ ] Dropping a phone onto a pillow shows "Did you fall?".
- [ ] Ignoring it sends the supervisor a fake text.
- [ ] Three phones dropped together start Rescue Mode.

---

## Phase 4 — Rescue Mode in the app (about 3 hours)

**Tasks**
1. `worker_rescue.dart` (mockup W3): dark red screen, "Emergency on site", I'm safe / I need help (POST `/checkin`), last spot, nearest exit, location interval, battery-saver note. After answering: "Marked safe" or "Help is coming".
2. `supervisor_home.dart` (mockup S1): today's scans per floor, open hazards, crew per floor, **hold-2-seconds** red button with a progress ring.
3. When rescue is active, the supervisor home switches to a rescue summary (counts no answer / help / safe + list).
4. Stop rescue: supervisor only, with a confirm step.

**Checks**
- [ ] Red button hold starts rescue; every worker phone switches screens within 5 s (demo mode).
- [ ] Tapping I need help changes the count on the supervisor phone.

---

## Phase 5 — LiDAR scan + hazard compare (about 4 hours)

**Tasks**
1. Swift `RoomScanViewController.swift` + MethodChannel `blackbox/roomplan` (`startScan` → `{model, json}` paths). Check `RoomCaptureSession.isSupported`; non-LiDAR phones show "This iPhone has no LiDAR" and offer "Use saved demo scan".
2. `scan_screen.dart` (mockup S2) launches the native scan; after Done, upload to `/scan` with the current floor.
3. `compare.py`: count walls, doors, windows, openings, objects from RoomPlan JSON; compare with the last scan of the same floor. Rules:
   - openings up → "New opening on Floor {f}. Check guardrails." (OSHA topic: Fall protection: holes and openings)
   - doors down → "A door is missing or blocked on Floor {f}. Check exits." (Exit routes)
   - walls down → "A wall was removed on Floor {f}. Check the structure." (Structural stability)
4. New hazard → text supervisor + text workers whose last ping is on that floor.
5. `hazard_detail.dart` (mockup S3): before/after part counts (simple drawings are fine), OSHA topic, workers nearby, buttons: Warn workers on this floor, Mark fixed, False alarm.
6. **3D for web:** RoomPlan gives `.usdz`. Web needs `.glb`. Add `server/convert.sh` that uses Blender headless if installed (`blender -b -P usd_to_glb.py -- in.usdz out.glb`). If Blender isn't available, document the manual step and keep 3 pre-converted demo `.glb` files in `server/demo_assets/`.
7. Tests for `compare.py` with two sample JSON files.

**Checks**
- [ ] Real scan on the LiDAR iPhone uploads and appears on the server.
- [ ] Scanning a room again after opening a door or moving a big box produces the expected alert (or use the sample JSON test).

---

## Phase 6 — Web dashboard + rescuer link (about 4 hours)

**Tasks**
1. `go_router` routes: `/dashboard`, `/rescue`. Web build starts at `/dashboard`.
2. `dashboard_screen.dart` (mockup D1): top bar (site, status pill, Start Rescue Mode button), floor tabs, 3D model (`model_viewer_plus`, `.glb`), **2D floor map** (`floor_map.dart`) with worker dots on top, tiles (on site, open hazards, floors scanned), hazard list with Mark fixed, crew list for the floor.
3. **Worker dot positions:** there's no exact indoor position. Place each worker at their zone's center on the 2D map, spread out slightly so dots don't overlap. Zone centers per floor are defined in config.
4. `rescuer_screen.dart` (mockup D2): red header with start time, counts (no answer / help / safe), floor tabs showing missing count, map with status colors and pulsing halo on "no answer", "People to find first" list sorted: no answer → help, highest floor first, with last ping time, battery, nearest stairs, "via mesh" tag when the last info came through mesh.
5. No login on `/rescue` (it's view-only). Note for the pitch: real version uses a secret link that expires.
6. Responsive: works on a tablet and a phone.
7. Server serves the web build at `/app`.

**Checks**
- [ ] Dashboard updates live when a worker phone pings.
- [ ] Rescuer page shows the correct people and counts during a rescue.

---

## Phase 7 — Bluetooth finder (about 4 hours)

**Tasks**
1. `rescue_beacon.dart`: in Rescue Mode, a worker phone that hasn't answered "safe" **advertises** BLE with local name `BB-W-{worker_id}`. Show a small "Rescuers can find this phone" line on the rescue screen. (iOS limit: only reliable while the app is open; tell the user.)
2. `finder.dart`: scan continuously for `BB-W-*`; keep RSSI per worker; smooth with the average of the last 5 readings (or an exponential moving average, alpha 0.3).
3. `finder_screen.dart`: list of nearby missing workers by name (matched with `/state` or mesh data); tap one → full screen meter:
   - big ring that fills as signal grows
   - label: "Far" (< -85 dBm), "Getting closer" (-85 to -70), "Close" (-70 to -60), "Very close" (> -60)
   - rough distance estimate shown as a range ("about 5–10 m"), never a single exact number
   - beep that speeds up as signal grows (`audioplayers`), with a mute button
4. Label in the UI: "Signal strength, not exact distance."

**Checks**
- [ ] Hide a worker phone in a bag; the finder phone's meter rises while walking toward it.

---

## Phase 8 — Offline mesh (about 6 hours)

**Tasks**
1. Swift `MeshService.swift` using MultipeerConnectivity:
   - service type `bb-mesh`
   - `MCNearbyServiceAdvertiser` + `MCNearbyServiceBrowser` running at the same time; auto-invite and auto-accept peers with the same site code (send it in discovery info)
   - send/receive `Data` (JSON-encoded MeshMessage)
   - EventChannel `blackbox/mesh/events` for: peer connected, peer lost, message received
   - MethodChannel `blackbox/mesh` for: `start(siteCode, workerId)`, `stop()`, `send(json)`
2. `mesh.dart`: dedupe by `msg_id`, TTL, path, forwarding rules from the contract. Store messages locally (shared_preferences or a small JSON file).
3. Start the mesh automatically in Rescue Mode, and on a manual "Offline mode" switch for the demo.
4. When a phone has internet → POST `/mesh/upload` with stored messages; server dedupes with `mesh_seen`, applies `help` / `safe` / `ping` as check-ins and pings with `source: "mesh"`.
5. **Offline rescue start:** if a phone detects the collapse locally (its own shock + shock messages from 2 peers within 5 s) while offline, it starts Rescue Mode locally and broadcasts a `rescue` message.
6. `mesh_screen.dart`: peers connected, recent messages with their path ("Sajid → Maria → Rescuer"), and a text box to send a short message.
7. Server tests for mesh upload dedupe.

**Checks**
- [ ] Three iPhones with internet off (Airplane Mode, then Bluetooth + Wi-Fi turned back on): phone A sends "I need help", phone C across the room shows it with path A → B → C.
- [ ] Turning internet back on uploads the messages and the dashboard shows "via mesh".

---

## Phase 9 — Nearby Interaction arrow (stretch, about 4 hours)

**Tasks**
1. Swift `NearbyService.swift`: `NISession`; check `NISession.deviceCapabilities.supportsPreciseDistanceMeasurement` (iOS 16+).
2. Swap discovery tokens through the mesh (`type: "ni_token"` messages, sent directly, not forwarded).
3. EventChannel streams `{peerId, distanceM, directionX, directionY}`.
4. In `finder_screen.dart`, when available, show an arrow + distance in meters above the Bluetooth meter. If not supported, hide it and keep the Bluetooth meter.

**Checks**
- [ ] Two iPhone 11+ phones show distance and an arrow that turns as you walk around.

---

## Phase 10 — Demo polish (about 3 hours)

**Tasks**
1. `DEMO_MODE` short timers everywhere.
2. Supervisor "Demo tools" screen (hidden behind long-press on the logo): reset demo, load saved scans, fake a collapse, fake a hazard.
3. Make sure every screen works with no internet and shows a calm offline banner instead of errors.
4. `docs/DEMO_SCRIPT.md` with the 3-minute script below and a 1-minute offline add-on.
5. Run through the full script 3 times; fix anything that takes more than 5 seconds to update.

**Demo script (summary)**
1. Hook: "Planes have black boxes. Buildings don't."
2. Supervisor scans Floor 3 → new opening alert → texts arrive.
3. Dashboard: worker dots by zone and floor; "location only, no camera".
4. Drop one phone → "Did you fall?" → tap I'm OK. One hit ≠ disaster.
5. Drop three phones on a pillow → Rescue Mode on every phone.
6. A judge taps "I need help" on one phone → dot turns orange.
7. Airplane Mode on → message hops across phones via mesh.
8. Hide a phone in a bag → judge finds it with the finder meter/arrow.
9. Open rescuer link → "No app, no login: who's missing and where."
10. Pitch close: "On a real site, a hard-hat tag does this 24/7 over long-range LoRa radio."

---

## Cut list (if time runs short, cut from the top)

1. Phase 9 (Nearby Interaction arrow)
2. Offline rescue start (Phase 8, task 5)
3. Real Blender conversion (use pre-converted demo files)
4. No-movement detection (keep fall + shock)
5. Mesh forwarding beyond one hop (direct peer-to-peer only)

**Never cut:** join + pings, Rescue Mode with check-ins, the red button, the rescuer page, and one real LiDAR scan.
