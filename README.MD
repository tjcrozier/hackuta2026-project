# Cycl0ps

**One eye that never closes on a job site.** Cycl0ps is a phone-based system that knows who is inside a job site, where they are, and whether they're OK. It runs on the iPhones workers already carry.

Built by **Team Nostos**.

## Contents

- [Why we built it](#why-we-built-it)
- [Features](#features)
- [Tech stack](#tech-stack)
- [How it works](#how-it-works)
- [Fallbacks](#fallbacks)
- [Getting started](#getting-started)
- [Tests](#tests)
- [Challenges](#challenges)
- [What we learned](#what-we-learned)
- [What's next](#whats-next)
- [Tracks](#tracks)

## Why we built it

In the *Odyssey*, Odysseus tells the Cyclops his name is "Nobody." So when the Cyclops is attacked and screams for help, he shouts: *"Nobody is hurting me!"* Help never comes, because no one knows who is really in the cave.

Three thousand years later, that still happens. When a job site collapses, rescuers ask "Who's inside?" and the answer is: **nobody knows.** Rescuers go in blind. They don't know who is inside, where those people are, or what conditions they'll face. Every minute spent digging in the wrong place could cost a life.

The story gave us a second idea. The Cyclops blocks the cave door and counts his sheep by touch as they leave, and Odysseus's men slip out hidden under the sheep. A headcount by hand misses people. We wanted a headcount that doesn't.

In ancient Greek literature, *nostos* is the hero's journey home. That's our goal: making sure every worker comes home safely.

## Features

| Feature | What it does |
| --- | --- |
| **Daily hazard scan** | Every morning a supervisor scans each floor with the iPhone's LiDAR (Apple RoomPlan). Cycl0ps compares the scan with yesterday's and warns about new dangers, like a hole in the floor, a missing door or a removed wall. The supervisor and everyone on that floor get a text with the matching OSHA rule. |
| **Live worker map** | Each worker's phone sends a small ping with only three things: **zone, floor and battery.** No camera, no microphone, no messages, and only between "Start shift" and "End shift". The zone comes from Bluetooth beacons (a spare iPhone or iPad) and the floor from the barometer. |
| **Motion safety** | The phone detects falls, hard impacts and long periods with no movement. It asks the worker first ("Did you fall?"). If nobody answers, the supervisor is alerted. |
| **Automatic Rescue Mode** | When three or more phones feel a hard impact within five seconds, Rescue Mode starts by itself. The supervisor can also start it by holding the red button for 2 seconds (never a single tap). Every worker's screen turns dark red with two huge buttons, "I'm safe" and "I need help", and every worker gets a text: *"Reply 1 if safe, 2 if you need help."* |
| **Rescuer page** | No app and no login. The fire department opens one link and sees the latest 3D map of the floor, who is safe, who needs help and who hasn't answered, each person's last-seen spot, and the nearest stairs. |
| **Athena, the site assistant** | A chat assistant on the worker app, the supervisor dashboard and the rescuer page. A rescuer can ask "Who is missing, and where was Bhaskar last seen?" and Athena answers from live site data. A worker's Athena only knows about that worker, their floor's hazards and Rescue Mode, never other workers. |
| **Athena Live** | A worker can video-call Athena, in the app or over **FaceTime through Chert**, and show her what's around them. She checks for a hard hat, vest and glasses, reads chemical labels and GHS hazard symbols, and sends a short text summary to the supervisor. Calls are live only: nothing is recorded or stored. |
| **Works without internet** | If the building's internet is down, phones pass messages to each other (Apple Multipeer Connectivity) until one of them reaches the server. |
| **Finder** | A rescuer's phone can find a missing worker's phone by its Bluetooth signal, playing "hot and cold" as it gets stronger with every step. On iPhone 11 and newer it also uses Apple's Nearby Interaction (UWB) to show a distance and a direction arrow. |

## Tech stack

| Part | Built with |
| --- | --- |
| Mobile app | Flutter (Dart), iOS only. One app with Worker, Supervisor, Rescuer-finder and Beacon modes. |
| Native iOS | Swift, called from Flutter through `MethodChannel` and `EventChannel`: **RoomPlan** (LiDAR scan), **MultipeerConnectivity** (offline mesh), **NearbyInteraction** (precise finder) |
| Bluetooth and motion | `flutter_blue_plus`, `flutter_ble_peripheral`, `sensors_plus` |
| Web dashboard and rescuer page | The same Flutter project built for the web and served by our own server, so it still works on a router with no internet. 3D floor map with `model_viewer_plus`. RoomPlan scans are converted to GLB on the server. |
| Server | Python 3.11, FastAPI, WebSockets for live dashboard updates |
| Time-series data | **Tiger Data** (Postgres + TimescaleDB) |
| Document data | **MongoDB Atlas** |
| Offline data | **SQLite** |
| Messages | Chert (iMessage/SMS) |
| AI | Gemini API and Gemini Live, with Groq as the backup model |
| Video calls | Chert FaceTime bridge, LiveKit, Node.js LiveKit Agents worker |
| Hosting | A laptop or a Rocky Linux VM, with a public HTTPS link through a `cloudflared` tunnel |

## How it works

### Where the data goes

Each kind of data goes where it fits.

- **Tiger Data** stores worker pings and motion events as a time series, so "where was this worker last seen?" and "which phones felt a shock in the last 5 seconds?" are fast time-window queries.
- **MongoDB Atlas** stores each floor's LiDAR scans and hazards as documents, because a RoomPlan scan is nested JSON.
- **SQLite** is the offline fallback behind the same interface, so the system still runs on a laptop if the internet goes down.

### Scan comparison

The server counts walls, doors, windows and openings per floor and flags what changed since yesterday. Two scans of the same room are never identical, so we compare counts instead of raw geometry. There is also a "False alarm" button.

### Rescue Mode trigger

Rescue Mode starts when enough *different* phones report a hard hit inside a short window:

```math
\Big|\{\, p \;:\; \text{phone } p \text{ felt a shock in } [t-5\text{ s},\, t] \,\}\Big| \;\ge\; 3
```

One phone hitting the floor is normal on a job site. Requiring three different phones inside five seconds, and asking "Did you fall?" before alerting anyone, cut false alarms without missing real events.

### Finder signal smoothing

Bluetooth signal strength jumps around a lot, so the finder smooths it before showing "Far", "Getting closer", "Close" or "Very close":

```math
\hat{s}_t = 0.7\,\hat{s}_{t-1} + 0.3\,s_t
```

Here $s_t$ is the newest reading in dBm. We always show distance as a range, because signal strength is not an exact distance.

### Messages

Texts go through Chert (iMessage/SMS) behind a `MessageSender` interface. A `FakeSender` fallback means the demo never depends on it.

### Athena chat

Our server adds live site data to each question, filtered by role, then asks Gemini. A worker's chat never contains other workers' data. Groq is the backup model.

### Athena Live

A worker FaceTimes the Cycl0ps line. Chert bridges the call into our LiveKit room, where a Node.js LiveKit Agents worker running Gemini Live sees the caller's video and talks back. It writes its findings (gear check, label reading, help summary) to the dashboard.

### Privacy

- Phones send only three fields: zone, floor and battery.
- No camera or microphone in the background.
- Tracking only runs during a shift.
- Site data is filtered by role on the server before anything reaches the AI model.
- Athena Live calls are not recorded or stored.

## Fallbacks

Every outside dependency has a backup. All features can be turned off with flags during a demo.

| If this fails | This takes over |
| --- | --- |
| LiDAR scan is slow | Saved demo scan |
| Bluetooth beacons | Manual zone picker |
| Texts through Chert | `FakeSender` |
| UWB not supported | Bluetooth signal meter |
| Phone-drop trigger doesn't fire | Red button (hold 2 seconds) |
| Gemini | Groq |
| MongoDB Atlas or Tiger Data | SQLite |
| Building internet | Phone-to-phone mesh |

## Getting started

<!-- TODO: fill in the real commands and env variable names from the repo -->

1. Clone the repo.
2. Start the server (Python 3.11, FastAPI).
3. Run the Flutter app on an iPhone. LiDAR scanning needs a Pro model.
4. Open the dashboard in a browser.

## Tests

Every safety-critical rule has automated tests: the rescue trigger, scan comparison, mesh message deduplication and text-reply parsing. 68 server tests and 49 app tests pass.

## Challenges

- **No custom hardware.** Our real vision is a hard-hat tag, but we had one weekend and no parts. So everything had to run on iPhones: a spare iPhone became a zone beacon, and the barometer became our floor sensor.
- **iOS limits.** iOS doesn't let an app scan Bluetooth or read sensors freely in the background, so tracking only works while Cycl0ps is open. The hard-hat tag fixes this.
- **Indoor location is hard.** There's no GPS inside a concrete building, so we use zones and floors instead of exact points. Being honest about that was better than drawing a fake precise dot.
- **Networking at a hackathon.** Venue Wi-Fi blocked phone-to-laptop traffic, and `.local` names resolved to IPv6 while our server only listened on IPv4. We made the server listen on both and used a phone hotspot as a backup.
- **FaceTime's hard limits.** A Chert trial line takes one call at a time, with a 5-minute cap, and our first hosted test call timed out. We kept calls short and made sure the rest of the demo never depends on the call.
- **Cloud databases versus a dead network.** A collapsed building may have no internet, so we kept SQLite as an offline fallback behind the same interface as MongoDB and Tiger Data.

## What we learned

- **Simple and working beats clever and broken.** Zones and floors are less impressive than exact coordinates, but they're honest and they work.
- **Plan the fallback first.** LiDAR, Bluetooth, Wi-Fi and outside APIs all failed at least once. Because every feature had a backup, the demo still ran.
- **Native iOS from Flutter.** We learned to bridge Swift frameworks (RoomPlan, Multipeer, Nearby Interaction) into one cross-platform app.
- **Privacy shapes the data model.** Deciding early that phones send only zone, floor and battery made the server simpler and the pitch stronger.
- **AI needs guardrails, not just prompts.** Filtering data by role on the server is safer than asking the model not to share it.

## What's next

- **A rugged hard-hat tag** with long-range radio (LoRa mesh), built from Mouser parts, so it keeps working even when every phone is gone or the battery is dead.
- **Better maps:** dedicated sensors for more detailed 3D maps and faster access for rescuers.
- **Secure rescuer links** that expire after the incident.
- **Outbound FaceTime from Athena:** she calls a worker who pressed "I need help" or hasn't answered, instead of waiting for them to call.
- **Pilots** with construction companies and fire departments.

## Tracks

| Track | How we use it |
| --- | --- |
| **Dev** | A full-stack system: Flutter iOS and web app, native Swift (RoomPlan, Multipeer Connectivity, Nearby Interaction), a FastAPI server, an offline phone mesh, and automated tests. |
| **Chert** | Athena Live over FaceTime sees what the worker shows her (protective gear, chemical labels) and reports to the supervisor. |
| **Gemini API** | Powers Athena chat and Athena Live (Gemini Live for real-time video over FaceTime). |
| **MongoDB Atlas** | Stores LiDAR scans and hazards as documents. |
| **Tiger Data** | Stores worker pings and motion events as a time series for last-seen lookups and collapse detection. |
