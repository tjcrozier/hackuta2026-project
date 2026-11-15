# PROGRESS.md — Cycl0ps (formerly Black Box)

Updated after every phase.

## Phases

- [x] **Phase 0 — Setup** (done, all checks passed)
- [x] **Phase 1 — Server core** (done, all checks passed)
- [ ] **Phase 2 — App shell, join, worker pings** (code done; the 3 device checks are for the user)
- [ ] **Phase 3 — Motion safety** (code done; the 3 device checks are for the user)
- [ ] **Phase 4 — Rescue Mode in the app** (code done; the 2 device checks are for the user)
- [ ] **Phase 5 — LiDAR scan + hazard compare** (code done; the real LiDAR scan check is for the user)
- [ ] **Phase 6 — Web dashboard + rescuer link** (code done; the live check with a real phone is for the user)
- [ ] **Phase 7 — Bluetooth finder** (code done; needs two phones to check)
- [ ] **Phase 8 — Offline mesh** (code done; needs three phones to check)
- [ ] **Phase 9 — Nearby Interaction arrow (stretch)** (code done; needs two phones to check)
- [x] **Phase 10 — Demo polish** (done; full rehearsal on real phones is for the user)

## Phase 0 — Setup

**Checks**
- [x] `flutter run` shows the default app on the user's iPhone. (Ran on iPhone 17 Pro Max.)
- [x] `uvicorn main:app` returns `{"ok": true}` at `/health`.

**Also checked**
- `flutter analyze`: no issues.
- `flutter build ios --debug --no-codesign`: builds.
- `pytest`: 1 passed. `ruff check`: clean.

**What was done**
- `app/`: Flutter project (iOS + web), bundle id `com.sajid.blackbox` (`com.blackbox.app` was already taken on Apple's side), display name "Black Box".
- All packages from CLAUDE.md added, plus `google_fonts` (for Space Grotesk and Inter).
- iOS deployment target set to 16.0 in `project.pbxproj`.
- `Info.plist`: all 7 keys from BUILD_PLAN.md, plus `NSAllowsLocalNetworking`
  so the app can reach `http://<laptop-ip>:8000` on the same Wi-Fi.
- `server/`: `main.py` with `/health`, `requirements.txt`, `.env.example`, `pyproject.toml`, one test.
- `.gitignore`, empty folders from the repo structure.

**Notes about this Mac**
- Flutter 3.47.9 is at `~/development/flutter/bin` but is not on the PATH.
- There is no Podfile. This Flutter version links plugins with Swift Package Manager,
  so CocoaPods is not needed (and is not installed). The iOS build works without it.
- Python 3.11 was not installed. A conda env `py311` (Python 3.11.18) was created,
  and `server/.venv` was made from it.
- `cloudflared` is not installed (needed later for the public URL).
- The folder is not a git repository yet.

## Phase 1 — Server core

**Checks**
- [x] `pytest` passes (31 tests). `ruff check` is clean.
- [x] Live run: joined 3 workers, pinged, sent 3 shocks -> rescue started with reason
  "impact on 3 phones" and 17 fake texts were logged (14 demo workers + 3 test workers).

**What was done**
- `config.py`: settings from `server/.env`.
- `db.py`: all tables from the data model, helpers, and the snapshot.
- `models.py`: request bodies. `rules.py`: collapse rule, reply parsing, webhook field lookup.
- `senders.py`: `MessageSender`, `FakeSender`, `ChertSender` (falls back to fake on any error).
- `demo.py`: 14 workers on 3 floors + yesterday's scans for floors 1-3.
- `main.py`: `/workers/join`, `/ping`, `/event`, `/rescue/start`, `/rescue/stop`, `/checkin`,
  `/chert/webhook`, `/state`, `/demo/reset`, WS `/live`. Snapshot is pushed on every change.

**Open items**
- Chert: the send endpoint, auth header, body fields and webhook fields are guesses,
  marked `TODO(Chert)` in `senders.py` and `rules.py`. Needs the real docs.
- Demo worker names and positions are made up (the live demo page was not available).
- Demo scan files (`demo-floor1.glb` etc.) are only names for now; the files come in Phase 5.

**Choices made (tell Claude if you want them changed)**
- Joining again with the same phone number returns the same worker.
- A wrong site code is rejected (400).
- "I need help" outside Rescue Mode is saved and texts the supervisor.
- `phone_lost` turns true after `PHONE_LOST_SEC` (600 s) with no ping. The 14 demo workers
  have no real phone, so they show as lost 10 minutes after a reset. Use `/demo/reset` before a demo.

## Phase 2 — App shell, join, worker pings

**Checks (need real iPhones)**
- [ ] Two iPhones join and show up in `/state`.
- [ ] Zone changes when walking from beacon A to beacon B.
- [ ] Floor number changes when walking one floor up (test on stairs).

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 9 passed.
- `flutter build ios --debug` (signed) and `flutter build web`: both build.
- In a browser against the local server: join works, the worker shows in `/state` with
  the picked zone, pings arrive, and the Rescue Mode banner appears through the live socket.

**What was done**
- `config.dart`, `theme.dart`, `models/snapshot.dart`.
- Services: `api.dart`, `live_socket.dart` (reconnects every 3 s), `zone_beacon.dart`,
  `floor.dart`, `shift.dart` (the ping loop; not in the original file list).
- Screens: `role_picker.dart`, `join_screen.dart`, `worker_home.dart`,
  `beacon_mode_screen.dart`, `coming_soon.dart` (placeholder for Supervisor and Finder).
- Widgets: `big_button.dart`, `status_pill.dart`, `shares_box.dart`.
- Added package `wakelock_plus` (keeps the screen on during a shift and in beacon mode).

**Choices made (tell Claude if you want them changed)**
- The server address can be changed inside the app (role picker, "Server"), and is saved.
- The zone is sent in the Bluetooth service UUID as well as in the name `BB-ZONE-A`,
  because iOS can cut the advertised name short.
- Ground floor is floor 1. The floor can be fixed by hand with - and + (this is also the
  fallback when a device has no pressure sensor).
- If the server forgets a worker (for example after `/demo/reset`), the phone joins again quietly.
- "End shift" stops pings on the phone only. The API has no "leave" call, so the worker
  stays on the dashboard until a demo reset.
- Screens were built from the design rules in CLAUDE.md; the mockups were not available to Claude.
- Fonts come from `google_fonts`, which downloads them the first time. With no internet on
  first launch the app uses the system font.

## Phase 3 — Motion safety

**Checks (need real iPhones)**
- [ ] Dropping a phone onto a pillow shows "Did you fall?".
- [ ] Ignoring it sends the supervisor a fake text.
- [ ] Three phones dropped together start Rescue Mode.

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 22 passed (13 new motion tests with fake samples).
- Server `pytest`: 33 passed. `ruff`: clean.
- Release iOS build and web build both succeed.

**What was done**
- `services/motion.dart`: `MotionDetector` (pure logic) and `MotionService` (accelerometer).
  - Shock: above 3.0 g, sent at most once per 10 s.
  - Fall: free fall (below 0.3 g for 150 ms), then an impact within 1 s, then 10 s lying still.
  - No movement: 1 minute in demo mode (10 minutes otherwise).
- `screens/fall_check.dart`: full-screen question, countdown (15 s in demo mode), huge
  "I'm OK" button, vibration every second, looping beep (`assets/alarm.wav`).
- `shift.dart`: sends `shock`, `fall`, `fall_ok`, `fall_alert`, `no_move`; pings now carry real `moving`.
- Server: a `no_move` event now texts the supervisor ("No movement and no answer: ...").

**Choices made (tell Claude if you want them changed)**
- The phone sends `no_move` only after the worker did not answer "Are you OK?" in time.
- After the countdown ends the screen stays up ("Your supervisor was alerted") until "I'm OK" is tapped.
- Events are retried up to 3 times if the server cannot be reached.
- Motion detection runs only while the app is open on screen (iOS stops it in the background).

**Tuning (all in `app/lib/config.dart`)**
- If a pillow drop does not trigger: lower `shockG` (try 2.5) or drop from higher (free fall
  must last 150 ms, about 15 cm or more).
- `fallStillSec` is 10 s, so the "Did you fall?" screen appears 10 s after the drop.

## Phase 4 — Rescue Mode in the app

**Checks (need real iPhones)**
- [ ] Red button hold starts rescue; every worker phone switches screens within 5 s (demo mode).
- [ ] Tapping I need help changes the count on the supervisor phone.

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 24 passed. Release iOS build and web build succeed.
- In a browser against the local server: a single tap on the red button does nothing;
  the rescue summary shows the right counts (12 no answer / 1 help / 1 safe); a worker on
  shift switches to the dark red screen; "I need help" reaches the server and the screen
  shows "Help is coming"; stopping the rescue returns the worker to the normal home.
- NOT checked: the 2-second hold itself (the browser tool cannot hold a press). Test on the phone.

**What was done**
- `screens/worker_rescue.dart`: dark red screen, "I'm safe" / "I need help", last spot,
  nearest exit, location interval, battery note, and "Marked safe" / "Help is coming".
- `screens/supervisor_home.dart`: tiles, open hazards, today's scans per floor, crew per floor.
- `screens/supervisor_rescue.dart`: counts and the list (no answer, then help, then safe).
- `widgets/hold_button.dart`: red button with a ring that fills over 2 seconds.
- Stop Rescue Mode asks for confirmation first.

**Choices made (tell Claude if you want them changed)**
- Nearest exits per zone are placeholders in `config.dart` (`zoneExits`).
- If "I'm safe" / "I need help" cannot reach the server, the phone keeps trying with every ping.
- The worker can change the answer after tapping.
- The "Scan" buttons open a placeholder until Phase 5.
- There is no supervisor login; anyone who picks the Supervisor role can start or stop a rescue.

## Phase 5 — LiDAR scan + hazard compare

**Checks**
- [ ] Real scan on the LiDAR iPhone uploads and appears on the server. (User must do this.)
- [x] Scanning again produces the expected alert: checked with the sample JSON tests and with
  "Use saved demo scan" in a browser (Floor 3 -> "New opening on Floor 3. Check guardrails.").

**Checked by Claude**
- Server `pytest`: 44 passed (11 new). `ruff`: clean.
- `flutter analyze`: no issues. `flutter test`: 24 passed. Release iOS build (with the new
  Swift file) and web build succeed.
- In a browser: demo scan upload, hazard created, 1 supervisor text + 5 worker texts,
  before/after counts, "Warn workers" (5 more texts), "Mark fixed".
- NOT checked: the native RoomPlan scanner on a real device. It compiles, but it has never run.

**What was done**
- `ios/Runner/RoomScanViewController.swift`: RoomPlan scanner + channel `blackbox/roomplan`
  (`isSupported`, `startScan`). Added to the Runner target in `project.pbxproj` and registered
  in `AppDelegate.swift`. No manual Xcode steps needed.
- `services/roomplan.dart`, `screens/scan_screen.dart`, `screens/hazard_detail.dart`,
  `widgets/parts_compare.dart`.
- Server: `compare.py`, `scans.py`, `room_to_glb.py`, `POST /scan`, `POST /hazards/{id}`,
  `POST /hazards/{id}/warn`, `GET /files/{name}`.
- `demo.py` now builds real demo scan files (JSON + .glb) for floors 1-3 on seed/reset.
- `app/assets/demo/floor1-3.json`: saved "today" scans with one new opening each.

**API contract additions (approved by the user, recorded in BUILD_PLAN.md)**
- `POST /hazards/{id}/warn`.
- Each hazard in the snapshot has `before` and `after` part counts.

**Choices made (tell Claude if you want them changed)**
- 3D for the web: the server builds the `.glb` itself from the RoomPlan JSON
  (`room_to_glb.py`), so Blender is not needed. Openings are drawn in the hazard color.
  `convert.sh` + `usd_to_glb.py` are there as the optional Blender path (Blender is not installed).
- "Use saved demo scan" is always available on the scan screen, also on LiDAR phones, as a demo fallback.
- A floor's first scan never raises a hazard (nothing to compare with).
- Real scans of the same room can differ by a wall or door between scans. That can cause
  a false "wall removed" or "door missing" alert; use "False alarm" for those.

## Phase 6 — Web dashboard + rescuer link

**Checks**
- [ ] Dashboard updates live when a worker phone pings. (Needs a real phone; the live socket
  itself was checked in a browser.)
- [x] Rescuer page shows the correct people and counts during a rescue (checked in a browser:
  4 no answer / 2 help / 8 safe, sorted no answer first, highest floor first).

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 27 passed. Server `pytest`: 44 passed.
- In a browser, served by the server at `/app`: the dashboard shows the rotating 3D model,
  tiles, floor tabs, the 2D map with dots, hazards and crew; the rescuer page shows the red
  header, counts, missing count per floor, status colors, and the list.
- NOT checked: the layout on a real phone or tablet browser, and the hold button on the dashboard.

**What was done**
- `screens/web/dashboard_screen.dart`, `screens/web/rescuer_screen.dart`.
- `widgets/floor_map.dart` (2D map, dots at zone centers, pulsing halo for "no answer"),
  `widgets/floor_tabs.dart`, `widgets/live_builder.dart`.
- Routes `/dashboard` and `/rescue`. In a browser the app opens on the dashboard; the role
  picker is at `/roles`.
- Server serves the web build at `/app` and `/` redirects there.
- `build_web.sh` (repo root): builds the web app and copies it to `server/static/app`.

**URLs**
- Dashboard: `http://<server>:8000/app/#/dashboard`
- Rescuer link (no login, view-only): `http://<server>:8000/app/#/rescue`

**Choices made (tell Claude if you want them changed)**
- Zone centers and stairs positions on the map are in `config.dart` (`zoneCenters`, `stairs`).
  Every floor uses the same layout unless listed in `floorZoneCenters`.
- "Start Rescue Mode" on the dashboard is also a 2-second hold.
- The dashboard has no Stop button; stopping is done from the supervisor phone.
- For the pitch: the real version would use a secret rescuer link that expires.

## Phase 7 — Bluetooth finder

**Checks (need two real iPhones)**
- [ ] Hide a worker phone in a bag; the finder phone's meter rises while walking toward it.

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 32 passed (5 new: labels, distance ranges,
  ring, beep speed, smoothing, beacon id format).
- NOT checked: anything over real Bluetooth. Advertising and scanning have never run on a device.

**What was done**
- `services/rescue_beacon.dart`: in Rescue Mode a worker phone that has not answered "safe"
  advertises `BB-W-{worker_id}`. It stops when the worker taps "I'm safe" or the rescue ends.
- `services/finder.dart`: scans all the time, smooths the signal (70% old + 30% new).
- `screens/finder_screen.dart`: list of phones nearby (strongest first) plus "Missing, not in
  range yet"; tap a name for the full-screen meter: ring, label, distance range, beep, mute.
- Worker rescue screen shows "Rescuers can find this phone" while the signal is on.
- `assets/beep.wav`.

**Choices made (tell Claude if you want them changed)**
- The worker id is sent in the Bluetooth service UUID as well as the name, because iOS can
  cut the name short.
- Names in the finder come from the server. With no internet the list shows "Worker w15"
  until the mesh (Phase 8) can supply names.
- A phone not heard for 6 seconds shows "Signal lost".
- iOS limit: the worker phone only advertises reliably while Black Box is open on screen.
- `screens/coming_soon.dart` is no longer used by any route (left in place; not deleted).

## Phase 8 — Offline mesh

**Checks (need three real iPhones)**
- [ ] Three iPhones with internet off: phone A sends "I need help", phone C across the room
  shows it with path A -> B -> C.
- [ ] Turning internet back on uploads the messages and the dashboard shows "via mesh".

**Checked by Claude**
- Server `pytest`: 52 passed (8 new mesh tests: dedupe, help/safe/ping/text/rescue, ordering).
- `flutter analyze`: no issues. `flutter test`: 44 passed (12 new: dedupe, hops, path,
  forwarding, offline collapse).
- Release iOS build with `MeshService.swift` succeeds.
- NOT checked: anything over real Multipeer Connectivity. It has never run on a device.

**What was done**
- `ios/Runner/MeshService.swift`: Multipeer service `bb-mesh`, advertises and browses at the
  same time, auto-invites and auto-accepts phones with the same site code. Channels
  `blackbox/mesh` (start, stop, send) and `blackbox/mesh/events`. Added to the Xcode project.
- `models/mesh_message.dart`, `services/mesh.dart` (rules, storage, upload).
- `screens/mesh_screen.dart`: phones connected, Offline mode switch, quick "I need help" /
  "I'm safe", text box, recent messages with their path.
- Server: `POST /mesh/upload` (dedupe with `mesh_seen`; applies help, safe, ping, text, rescue).
- The mesh turns on by itself in Rescue Mode and when pings stop reaching the server, and
  with the Offline mode switch.
- In Rescue Mode, "I'm safe" / "I need help" also go out over the mesh.
- Offline rescue start: own shock + shocks from 2 other phones within 5 s while offline
  starts Rescue Mode locally and tells the other phones.

**Choices made (tell Claude if you want them changed)**
- `send` on the native channel takes an optional `except` peer, needed for "forward to all
  peers except the one it came from".
- Extra message types used on the mesh: `shock` and `rescue` (the plan needs them for the
  offline rescue start). The server accepts unknown types and ignores them.
- Names on the mesh: learned from the server while online and from directly connected
  phones. A far-away phone never seen before shows as its id (for example "w7").
- A phone that is not a worker gets a mesh id like "r4821" and the name "Rescuer".
- Multipeer needs Bluetooth and Wi-Fi turned ON (they can be on in Airplane Mode).
  It only runs while the app is open on screen.
- The supervisor's red button does not work offline yet (it needs the server).

## Phase 9 — Nearby Interaction arrow (stretch)

**Checks (need two iPhone 11+ phones)**
- [ ] Two phones show distance and an arrow that turns as you walk around.
  With the current setting, iPhone 14 and newer show the distance but NO arrow (see below).

**Checked by Claude**
- `flutter analyze`: no issues. `flutter test`: 46 passed (2 new: arrow angle, distance text).
- Release iOS build with `NearbyService.swift` succeeds and is installed on the iPhone 17 Pro Max.
- NOT checked: anything over real UWB. It has never run between two devices.

**What was done**
- `ios/Runner/NearbyService.swift`: one `NISession` per peer; channels `blackbox/nearby`
  (capabilities, myToken, setPeerToken, stop) and `blackbox/nearby/events`. Added to the Xcode project.
- `services/nearby.dart`: bridge + token swap with `ni_token` mesh messages (direct, one hop,
  never stored, forwarded or uploaded).
- `finder_screen.dart`: a dark card above the Bluetooth ring with the precise distance in
  meters and, when the phone gives a direction, an arrow. Hidden when not supported or not linked.
- Opening the finder turns the mesh on (the tokens travel over it) and off again on leaving.

**Open decision for the user: camera assist**
- iPhone 11-13 give a direction on their own. iPhone 14 and newer (including the 16 and
  17 Pro Max) only give a direction with "camera assistance", which runs the camera on the
  RESCUER's phone (nothing is recorded or sent).
- The user chose to turn it ON: `nearbyCameraAssist = true` in `app/lib/config.dart`.
  The camera permission text now mentions finding too. Set it to false to switch it off.
- This changes the privacy line: the camera is also used on the rescuer's phone while
  finding. Worker phones still never use the camera. CLAUDE.md section 6 not yet updated.

**Other notes**
- Both phones must have Black Box open on screen, and be connected on the mesh.
- The event also carries `directionZ` and `horizontalAngle` besides the plan's
  `directionX` / `directionY`; the arrow needs them.

## Phase 10 — Demo polish

**Checked by Claude**
- Server `pytest`: 53 passed. `ruff`: clean. `flutter analyze`: no issues. `flutter test`: 46 passed.
- The demo flow was run 3 times against a separate test server (join, ping, scan + hazard,
  fall alert, 3 shocks -> Rescue Mode, "I need help", mesh upload, stop, rescuer page).
  Every step reached the dashboard's live socket in under 30 ms. 0 steps over 5 seconds.
- In a browser: all 5 demo tools work; with the server stopped, the dashboard keeps the last
  saved data and shows a calm "No connection" note.
- NOT checked: the long-press on the logo (the browser tool cannot long-press), and a full
  rehearsal on real phones.

**What was done**
- Demo tools (`screens/demo_tools.dart`), opened by LONG-PRESSING THE LOGO on the role picker,
  the supervisor home, or the web dashboard: Reset demo (with confirm), Load saved scans,
  Fake a hazard on Floor 3, Fake a collapse (3 phones), Stop Rescue Mode. All use the normal API.
- Offline: `services/snapshot_cache.dart` saves the last snapshot on the phone/browser;
  supervisor home, dashboard, rescuer page and hazard screen show it with a calm grey
  `OfflineBanner` instead of an error. The worker home says what still works offline.
- Server, demo mode only: the 14 demo workers "ping" every 30 s from where they are, so they
  never show as "phone lost" during a demo. Real workers are not touched.
- `docs/DEMO_SCRIPT.md`: setup checklist, 3-minute script with times and lines, fallbacks,
  1-minute offline add-on, and known limits.
- `app/assets/demo/floor1-3-base.json`: saved scans with no changes (for the demo tools).

**Timers that are longer than 5 s on purpose**
- "Did you fall?" appears 10 s after the drop (`FALL_STILL_SEC`, no demo value in the plan).
- The fall countdown is 15 s in demo mode.

**Still open (for the user)**
- Rehearse the script 3 times on real phones.
- Chert API details (texts are still fake).
- `cloudflared` for a public link (not installed).
- CLAUDE.md privacy rule vs. camera assist on the rescuer phone.


---

## After Phase 10 — fixes, GitHub, Chert, Athena, rename (14 Nov 2026)

**Glitch fixes (from testing on the phones)**
- Phones could not always reach the server: the `.local` name also gives an IPv6 address and
  uvicorn only listened on IPv4. New `server/run.py` listens on both. Start the server with
  `python run.py` (not `uvicorn ...`).
- End shift now tells the server (`POST /workers/{id}/end_shift`), so the worker leaves the
  dashboard. Reopening the app during a shift goes straight back to the worker screen.
- "Still" pill renamed "Not moving". `DEMO_WORKERS=false` in `server/.env` hides the 14
  made-up workers (backup of the old database: `server/blackbox.db.backup`).
- Battery is shown in 5% steps: that is all iOS gives apps.

**GitHub**
- Pushed to https://github.com/tjcrozier/hackuta2026-project, branch `blackbox-app`, PR #1
  (main only accepts pull requests). Left open for the team to merge.

**Chert FaceTime (kept as a feature, NOT demoed)**
- Signed up, phone verified, line +1 913-282-1013 (free trial). The hosted demo call failed on
  Chert's side (`bridge_remote_audio_timeout`, call id b2088b14-a7cf-4772-9fec-3230ece50c01).
- Starter agent in `agent/` (`chert new agent --video`, Node.js, OpenAI `gpt-realtime`).
  LiveKit + OpenAI keys not filled in; modes not written. Plan: `docs/CHERT_SETUP.md`.
- Node.js 24 lives in `~/.local/node-v24.22.3` (use `export PATH="$HOME/.local/node-v24.22.3/bin:$PATH"`).

**Rename: Black Box -> Cycl0ps**
- App name on the iPhone, web title, logo (now one eye: `Icons.adjust`), headings, iOS
  permission texts, emergency/hazard texts ("CYCL0PS EMERGENCY. ..."), docs. Screen readers
  say "Cyclops". Bundle id, folders and the database file keep the old name on purpose.
- The pitch lines "Planes have black boxes. Buildings don't." in DEMO_SCRIPT.md / BUILD_PLAN.md
  were NOT changed: the opening needs a new line from the user.

**Athena chat assistant (Groq)**
- Server: `athena.py` + `POST /athena/chat`. The server adds the live site data and asks Groq
  (`GROQ_MODEL`, default `openai/gpt-oss-120b`). No key, feature off, or Groq down ->
  "Athena is offline right now..." (never an error). Flags: `FEATURE_ATHENA` (server/.env),
  `Config.featureAthena` (app).
- Privacy: a worker's Athena only sees that worker, their floor's hazards and Rescue Mode.
  Supervisor and rescuer see every worker. Chats are not stored.
- App: "Ask Athena" button on the supervisor home and worker home (full-screen chat,
  `/athena?role=`). Web dashboard + rescuer page: chat panel on the right when the window is
  1200 px or wider, otherwise an "Ask Athena" button that opens it from the bottom.
  Not on the worker Rescue Mode screen (two big buttons only).
- Checks: 62 server tests pass (7 new), ruff clean; 48 app tests pass (2 new), flutter analyze
  clean; web build checked in a browser at 1440 px (panel) and 820 px (button + sheet), with
  the offline reply. NOT checked: a real Groq answer (no key in `server/.env` yet) and the
  phone screens on a device.

**Still open (for the user)**
- Put a NEW Groq key in `server/.env` as `GROQ_API_KEY=...` (the one pasted in chat must be revoked).
- Restart the server (`python run.py`) and reinstall the app on the phones.
- A new opening line for the pitch.

**Athena Live (video call inside the app)**
- The video button next to the Athena text box (`Config.featureAthenaLive`) opens
  `screens/athena_live_screen.dart` (`/athena/live`). It no longer needs FaceAi or port 3000.
- Screen: the back camera fills the screen, Athena's name and call time on top, captions,
  the three quick questions always on screen ("What is this?", "Can I drink it?",
  "Can I touch it?"), a text box (the keyboard's dictation key works for voice), and
  Flip / End buttons. `camera` package added (`url_launcher` removed again).
- Each question: the app takes one picture (medium size) and sends it to the new server
  route `POST /athena/look`. The server asks Groq's vision model (`GROQ_VISION_MODEL`,
  default `qwen/qwen3.8-27b`, the only model on our key that reads pictures; it read a
  test BLEACH label correctly in under a second) with the Groq key from `server/.env`.
  The key never goes on the phone. Pictures are not stored. Microphone never used.
- Voice: Athena reads each answer out loud with Apple's built-in text-to-speech
  (`AVSpeechSynthesizer`), through `VoiceService` in `ios/Runner/AppDelegate.swift`
  (channel `blackbox/voice`) and `lib/services/voice.dart`. No package: `flutter_tts` was
  tried first but needs CocoaPods, which this Mac does not have; the user chose this way.
  It speaks even with the silent switch on, lowers music while talking, and stops on a new
  question or End. Replay and Mute buttons on the iPhone only; the web call is captions
  only. No audio leaves the phone. No site data is given to Athena Live.
- Privacy wording: worker box says "The camera is on only during a video call with
  Athena that you start. Nothing is recorded." CLAUDE.md / AGENTS.md section 6 updated.
- Checks: see the end of this section.
- Checks: flutter analyze clean, 49 app tests pass (1 new), 68 server tests pass (5 new),
  ruff clean. `/athena/look` answered a test BLEACH picture correctly through the real
  server and Groq (about 1 s). Web build done. Installed on Sajid's iPhone 17 Pro Max.
  NOT checked: opening the call on the iPhone (camera permission, picture quality).
