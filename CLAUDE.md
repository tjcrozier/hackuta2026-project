# CLAUDE.md — Cycl0ps

Read this file fully before doing anything. Then read `BUILD_PLAN.md`. Work through the plan **one phase at a time**.

---

## 1. What we are building

**Cycl0ps** (written with a zero; formerly "Black Box") tells you who is inside a job site. In the UI and texts it is always "Cycl0ps"; screen readers say "Cyclops". Folder names, the bundle id `com.sajid.blackbox` and the database file keep the old name on purpose.

- **Daily Mode:** a supervisor scans each floor with an iPhone LiDAR scan (Apple RoomPlan). The server compares today's scan with yesterday's and texts an alert when a new hazard appears (a new hole, a missing door, a removed wall).
- **Worker tracking:** each worker's iPhone sends a small ping every 2 minutes: zone, floor, battery. No camera, no audio.
- **Motion safety:** phones detect falls, hard impacts and no-movement.
- **Rescue Mode:** starts when 3+ phones feel a hard impact within 5 seconds, or when the supervisor holds the red button. Every worker gets a check-in text ("Reply 1 safe, 2 help"). Rescuers open one web link (no login) that shows the latest 3D map, who is missing, where they were last seen, and the nearest stairs.
- **Offline features (iPhone-only versions):**
  - **Finder:** a rescuer's phone finds a missing worker's phone with a Bluetooth signal-strength meter ("hot and cold"), and on iPhone 11+ with Apple Nearby Interaction (distance + direction arrow).
  - **Mesh:** when the internet is down, phones pass messages to each other using Apple Multipeer Connectivity until one phone reaches the server.

This is a **hackathon project**. The goal is a reliable, good-looking demo for judges, built in about 24–36 hours. Simple and working beats clever and broken.

**We have NO custom hardware.** Everything runs on iPhones, an iPad or spare iPhone used as a "zone beacon", and a laptop. Hardware (ESP32 hard-hat tags, LoRa mesh) is only mentioned in the pitch as the future version. Do not write ESP32 code unless the user asks.

---

## 2. Tech stack (fixed — do not change without asking)

| Part | Tech |
| --- | --- |
| Mobile app (Supervisor + Worker + Rescuer-finder modes) | Flutter (Dart), iOS only, minimum iOS 16 |
| Native iOS parts | Swift, called from Flutter with `MethodChannel` / `EventChannel` |
| LiDAR scan | Apple RoomPlan (Swift) |
| Offline mesh | Apple MultipeerConnectivity (Swift) |
| Precise finder | Apple NearbyInteraction (Swift), iPhone 11+ |
| Bluetooth finder + zone beacons | `flutter_blue_plus` (scan) + `flutter_ble_peripheral` (advertise) |
| Web dashboard + rescuer page | Same Flutter project built for web |
| Server | Python 3.11, FastAPI, Uvicorn, SQLite (via `sqlite3` or SQLModel), WebSockets |
| Texts / check-ins | Chert API (iMessage/SMS) behind a `MessageSender` interface, with a `FakeSender` fallback |
| Athena chat assistant | Groq (`openai/gpt-oss-120b`) called by the server with `httpx`; key in `server/.env` |
| FaceTime agent (built, NOT demoed) | Chert FaceTime line + LiveKit Agents (Node.js) in `agent/`; see `docs/CHERT_SETUP.md` |
| Hosting | Rocky Linux (CIQ) VM or laptop; public HTTPS via `cloudflared` tunnel |

Flutter packages to use: `http`, `web_socket_channel`, `flutter_blue_plus`, `flutter_ble_peripheral`, `sensors_plus`, `battery_plus`, `geolocator`, `shared_preferences`, `model_viewer_plus`, `provider`, `go_router`, `audioplayers` (finder beep), `uuid`.

If a package fails to build or is unmaintained, **stop and tell the user** with 1–2 alternatives. Do not silently swap.

---

## 3. Repo structure

```
blackbox/
  CLAUDE.md
  BUILD_PLAN.md
  PROGRESS.md            <- you keep this updated after every phase
  app/                   <- Flutter project
    lib/
      main.dart
      config.dart        <- server URL, feature flags, thresholds
      models/            <- Worker, Ping, Hazard, MeshMessage, Scan
      services/
        api.dart
        live_socket.dart
        roomplan.dart
        zone_beacon.dart   <- scan for zone beacons / advertise as one
        floor.dart         <- barometer
        motion.dart        <- fall, shock, no-movement
        rescue_beacon.dart <- worker phone advertises in Rescue Mode
        finder.dart        <- rescuer scans + RSSI smoothing
        nearby.dart        <- NearbyInteraction bridge
        mesh.dart          <- Multipeer bridge
      screens/
        role_picker.dart
        join_screen.dart
        worker_home.dart
        worker_rescue.dart
        fall_check.dart
        supervisor_home.dart
        scan_screen.dart
        hazard_detail.dart
        finder_screen.dart
        mesh_screen.dart
        beacon_mode_screen.dart
        web/
          dashboard_screen.dart
          rescuer_screen.dart
      widgets/
        floor_map.dart
        status_pill.dart
        big_button.dart
    ios/Runner/
      AppDelegate.swift
      RoomScanViewController.swift
      MeshService.swift
      NearbyService.swift
  server/
    main.py
    db.py
    models.py
    senders.py           <- MessageSender, FakeSender, ChertSender
    compare.py           <- scan compare logic
    demo.py              <- seed + reset demo data
    tests/
    requirements.txt
    .env.example
  docs/
    DEMO_SCRIPT.md
```

---

## 4. Design rules (match the mockups)

The UI mockups exist on the user's Design canvas. Follow these rules so the app matches:

**Colors (and what they mean — never use them for anything else):**

| Token | Hex | Meaning |
| --- | --- | --- |
| ground | `#F5F4F0` | page background |
| ink | `#1C1F24` | text, dark cards, primary dark buttons |
| muted | `#4B5160` | secondary text |
| line | `#E2E3E6` | borders |
| accent / hazard | `#C2410C` | hazards, main action buttons |
| hazard-soft | `#FFF7ED` | hazard card background |
| safe | `#15803D` (soft `#DCFCE7`) | safe, OK, allowed |
| help | `#F97316` with dark text `#431407` | worker needs help |
| no answer | `#7F1D1D` | missing / no answer |
| danger | `#B91C1C` | Rescue Mode, red button |
| exit | `#1D4ED8` (soft `#DBEAFE`) | stairs and exits |

**Type:** Space Grotesk for headings and big numbers, Inter for body (use `google_fonts` or bundle the fonts).

**Rules:**
- Touch targets at least 48 px tall; main actions 56–84 px. Workers may wear gloves.
- Every color also has a word or icon (color-blind safe).
- Rescue Mode turns the whole screen dark red (`#7F1D1D`) with two huge buttons: "I'm safe" (white) and "I need help".
- Red emergency button needs a **2-second hold**, never a single tap.
- Worker home always shows "What your phone shares" (zone, floor, battery) and "Never tracked: camera, microphone, messages", plus one line saying the camera is on only during a video call with Athena that the worker starts.
- No emoji in the UI. Use simple line icons.

---

## 5. Working rules for you (Claude Code)

1. **One phase at a time.** Finish a phase, run its checks, update `PROGRESS.md`, then stop and give the user a short summary in simple English: what works, what they must do by hand (Xcode signing, testing on a device), and what's next. Wait for "go" before the next phase.
2. **Ask before:** changing the tech stack, adding a package not listed here, changing the API contract in `BUILD_PLAN.md`, or deleting files.
3. **The user tests on real iPhones.** You cannot. For anything that needs a device (LiDAR, Bluetooth, motion, Multipeer, UWB), write a clear "How to test on your iPhone" checklist.
4. **Xcode steps:** when a step needs Xcode (adding a Swift file to the Runner target, signing, Info.plist, capabilities), write exact click-by-click steps for the user. Prefer editing `Info.plist` and `project.pbxproj` yourself only if you are sure it's correct; otherwise give manual steps.
5. **Secrets:** never commit API keys. Use `server/.env` (git-ignored) and `.env.example` with placeholders.
6. **Fallbacks everywhere.** Every feature that depends on outside things (Chert, internet, LiDAR, UWB) must have a fallback that still demos: `FakeSender`, manual zone picker, pre-saved scans, the Bluetooth meter if UWB isn't supported.
7. **Feature flags** live in `app/lib/config.dart` and `server/.env` so the user can turn features off quickly during the demo.
8. **Code style:** simple, readable, commented where logic isn't obvious. Small files. No over-engineering. Python: type hints, `ruff` clean. Dart: `flutter analyze` clean.
9. **Tests:** server logic (rescue trigger, scan compare, mesh dedupe, reply parsing) gets `pytest` tests. Run them after every server change.
10. **Explain in plain English.** The user prefers simple words and full file contents over partial diffs when he asks to see code.

---

## 6. Privacy rules (also part of the pitch)

- Phones send only: worker id, name, phone number (once at join), zone, floor, battery, timestamps, and events (fall, shock, no-movement).
- Raw sensor data stays on the phone.
- Camera only for: the supervisor's LiDAR scan, the rescuer's camera assist in the Finder, and a FaceTime call with the Cycl0ps Safety agent that the person starts (or accepts) themselves. Never in the background.
- Microphone only during that FaceTime call, or a voice note the worker chooses to send in Rescue Mode (stretch goal).
- FaceTime calls are live only: Cycl0ps never records or stores video or audio, only the agent's short text summary. During a call, video and audio pass through Chert, LiveKit and OpenAI.
- Athena (chat): questions go to our server, which adds live site data and asks Groq. A worker's Athena sees only that worker, their floor's hazards and Rescue Mode, never other workers. Supervisor and rescuer chats send workers' names, floors, zones, status and battery to Groq. Chats are not stored on the server.
- Athena Live (video call): the video button in the Athena chat opens a call screen in the app. The person starts it; the camera stops when they tap End or leave the screen. The microphone is never used. When they ask a question, the app takes ONE picture and sends it with the question to our server, which asks Groq (`GROQ_VISION_MODEL`). The picture is not stored or recorded. Athena Live gets no site data.
- Tracking only between "Start shift" and "End shift".

---

## 7. Commands

```
# server
cd server && python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pytest

# public URL for phones + Chert webhook
cloudflared tunnel --url http://localhost:8000

# app
cd app && flutter pub get
flutter run                 # on a connected iPhone
flutter run -d chrome       # web dashboard
flutter build web           # then serve from server/static/app
flutter analyze
```
