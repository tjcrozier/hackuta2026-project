## Inspiration

In the *Odyssey*, Odysseus tells the Cyclops his name is "Nobody." So when the Cyclops is attacked and screams for help, he shouts: *"Nobody is hurting me!"* Help never comes, because no one knows who is really in the cave.

Three thousand years later, that still happens. When a job site collapses, rescuers ask "Who's inside?" and the answer is: **nobody knows.** Rescuers go in blind. They don't know who is inside, where those people are, or what conditions they'll face. Every minute spent digging in the wrong place could cost a life.

The story gave us a second idea. The Cyclops blocks the cave door and counts his sheep by touch as they leave, and Odysseus's men slip out hidden under the sheep. A headcount by hand misses people. We wanted a headcount that doesn't.

We're **Team Nostos**. In ancient Greek literature, *nostos* is the hero's journey home. That's our goal: making sure every worker comes home safely. So we built **Cycl0ps**, one eye that never closes on a job site, so that "nobody knows" is never the answer again.

## What it does

Cycl0ps is a phone-based system that knows who is inside a job site, where they are, and whether they're OK. It runs on the iPhones workers already carry.

* **Daily hazard scan.** Every morning a supervisor scans each floor with the iPhone's LiDAR (Apple RoomPlan). Cycl0ps compares the scan with yesterday's and warns about new dangers, like a hole in the floor that wasn't there before, a missing door or a removed wall. The supervisor and everyone on that floor get a text with the matching OSHA rule.

* **Live worker map.** Each worker's phone sends a small ping with only three things: **zone, floor and battery.** No camera, no microphone, no messages, and only between "Start shift" and "End shift". The zone comes from Bluetooth beacons (a spare iPhone or iPad) and the floor from the barometer.

* **Motion safety.** The phone detects falls, hard impacts and long periods with no movement. It asks the worker first ("Did you fall?"). If nobody answers, the supervisor is alerted.

* **Automatic Rescue Mode.** When three or more phones feel a hard impact within five seconds, Rescue Mode starts by itself. The supervisor can also start it by holding the red button for 2 seconds (never a single tap). Every worker's screen turns dark red with two huge buttons, "I'm safe" and "I need help", and every worker gets a text: *"Reply 1 if safe, 2 if you need help."*

* **A rescuer page with no app and no login.** The fire department opens one link and sees the latest 3D map of the floor, who is safe, who needs help and who hasn't answered, each person's last-seen spot, and the nearest stairs. Not "nobody": names, floors and places.

* **Athena, the site assistant.** A chat assistant on the worker app, the supervisor dashboard and the rescuer page. A rescuer can ask "Who is missing, and where was Bhaskar last seen?" and Athena answers from live site data. A worker's Athena only knows about that worker, their floor's hazards and Rescue Mode, never other workers.

* **Athena Live.** A worker can video-call Athena, in the app or over **FaceTime through Chert**, and show her what's around them. She checks for a hard hat, vest and glasses, reads chemical labels and GHS hazard symbols, and sends a short text summary to the supervisor. Calls are live only: nothing is recorded or stored.

* **Works without internet.** If the building's internet is down, phones pass messages to each other (Apple Multipeer Connectivity) until one of them reaches the server.

* **Finder.** A rescuer's phone can find a missing worker's phone by its Bluetooth signal, playing "hot and cold" as it gets stronger with every step. On iPhone 11 and newer it also uses Apple's Nearby Interaction (UWB) to show a distance and a direction arrow.

## How we built it

* **Mobile app:** Flutter (Dart), iOS only. One app with Worker, Supervisor, Rescuer-finder and Beacon modes.

* **Native iOS:** Swift code called from Flutter through `MethodChannel` and `EventChannel`: **RoomPlan** for the LiDAR scan, **MultipeerConnectivity** for the offline mesh, and **NearbyInteraction** for the precise finder. Bluetooth zone beacons and the rescue beacon use `flutter_blue_plus` and `flutter_ble_peripheral`. Motion uses `sensors_plus`.
* **Web dashboard and rescuer page:** the same Flutter project built for the web and served by our own server, so it still works on a router with no internet. The 3D floor map uses `model_viewer_plus`, and we convert RoomPlan scans to GLB on the server.
* **Server:** Python 3.11 and FastAPI, with WebSockets so the dashboard updates live. Each kind of data goes where it fits:
  * **Tiger Data** (Postgres + TimescaleDB) stores worker pings and motion events as a time series, so "where was this worker last seen?" and "which phones felt a shock in the last 5 seconds?" are fast time-window queries.
  * **MongoDB Atlas** stores each floor's LiDAR scans and hazards as documents, because a RoomPlan scan is nested JSON.
  * **SQLite** is the offline fallback, so the system still runs on a laptop if the internet goes down.


* **Scan comparison:** counts walls, doors, windows and openings per floor and flags what changed since yesterday.

* **Messages:** Chert (iMessage/SMS) behind a `MessageSender` interface, with a `FakeSender` fallback so the demo never depends on it.

* **Athena chat (Gemini API):** our server adds live site data to each question, filtered by role, so a worker's chat never contains other workers' data, then asks Gemini. Groq is the backup model.

* **Athena Live (Chert + Gemini Live):** a worker FaceTimes the Cycl0ps line. Chert bridges the call into our LiveKit room, where a Node.js LiveKit Agents worker running Gemini Live sees the caller's video and talks back. It writes its findings (gear check, label reading, help summary) to the dashboard.

* **Hosting:** a laptop or a Rocky Linux VM, with a public HTTPS link through a `cloudflared` tunnel.

**The math behind two features:**

Rescue Mode starts when enough *different* phones report a hard hit inside a short window:

$$
\Big|\{\, p \;:\; \text{phone } p \text{ felt a shock in } [t-5\text{ s},\, t] \,\}\Big| \;\ge\; 3
$$

Bluetooth signal strength jumps around a lot, so the finder smooths it before showing "Far", "Getting closer", "Close" or "Very close":

$$
\hat{s}_t = 0.7\,\hat{s}_{t-1} + 0.3\,s_t
$$

where $s_t$ is the newest reading in dBm. We always show distance as a range, because signal strength is not an exact distance.

**Fallbacks everywhere:** every outside dependency has a backup. There's a saved demo scan if LiDAR is slow, a manual zone picker if beacons fail, `FakeSender` if texts fail, the Bluetooth meter if UWB isn't supported, and the red button if the phone-drop trigger doesn't fire. All features can be turned off with flags during a demo.

## Challenges we ran into

* **No custom hardware.** Our real vision is a hard-hat tag, but we had one weekend and no parts. So everything had to run on iPhones: a spare iPhone became a zone beacon, and the barometer became our floor sensor.

* **iOS limits.** iOS doesn't let an app scan Bluetooth or read sensors freely in the background, so tracking only works while Cycl0ps is open. The hard-hat tag fixes this.

* **Telling a real collapse from a dropped phone.** One phone hitting the floor is normal on a job site. Requiring three different phones inside five seconds, and asking "Did you fall?" before alerting anyone, cut false alarms without missing real events.

* **LiDAR scans are noisy.** Two scans of the same room are never identical, so we compare counts of walls, doors and openings instead of raw geometry, and added a "False alarm" button.

* **Indoor location is hard.** There's no GPS inside a concrete building, so we use zones and floors instead of exact points. Being honest about that was better than drawing a fake precise dot.

* **Networking at a hackathon.** Venue Wi-Fi blocked phone-to-laptop traffic, and `.local` names resolved to IPv6 while our server only listened on IPv4. We made the server listen on both and used a phone hotspot as a backup.

* **Privacy versus usefulness.** An AI assistant that knows everything about the site is useful for a supervisor but dangerous on a worker's phone. We filter site data on the server by role before anything reaches the model.

* **FaceTime's hard limits.** A Chert trial line takes one call at a time, with a 5-minute cap, and our first hosted test call timed out. We kept calls short and made sure the rest of the demo never depends on the call.

* **Cloud databases versus a dead network.** A collapsed building may have no internet, so we kept SQLite as an offline fallback behind the same interface as MongoDB and Tiger Data.

## Accomplishments that we're proud of

* The full loop works end to end: a LiDAR scan finds a new hazard, phones trigger Rescue Mode, workers answer, and the rescuer page shows who is missing and where they were last seen.

* Every safety-critical rule has automated tests: the rescue trigger, scan comparison, mesh message deduplication and text-reply parsing. 68 server tests and 49 app tests pass.

* Athena answers from live site data, and on a worker's phone she refuses to share where other workers are.

* Athena Live over FaceTime: call a phone number and an AI safety officer looks at your gear and your surroundings.

* Rescuers need no app and no account, just one link.

* Privacy is built into the design, not added later: three data fields, no camera or microphone in the background, and tracking only during a shift.

* It runs on hardware every site already has: workers' phones.

## What we learned

* **Simple and working beats clever and broken.** Zones and floors are less impressive than exact coordinates, but they're honest and they work.

* **Plan the fallback first.** LiDAR, Bluetooth, Wi-Fi and outside APIs all failed at least once. Because every feature had a backup, the demo still ran.

* **Native iOS from Flutter.** We learned to bridge Swift frameworks (RoomPlan, Multipeer, Nearby Interaction) into one cross-platform app.

* **Privacy shapes the data model.** Deciding early that phones send only zone, floor and battery made the server simpler and the pitch stronger.

* **AI needs guardrails, not just prompts.** Filtering data by role on the server is safer than asking the model not to share it.

## What's next for Cycl0ps

* **A rugged hard-hat tag** with long-range radio (LoRa mesh), built from Mouser parts, so it keeps working even when every phone is gone or the battery is dead.

* **Better maps:** dedicated sensors for more detailed 3D maps and faster access for rescuers.

* **Secure rescuer links** that expire after the incident.

* **Outbound FaceTime from Athena:** she calls a worker who pressed "I need help" or hasn't answered, instead of waiting for them to call.

* **Pilots** with construction companies and fire departments.

## Tracks

* **Dev:** a full-stack system: Flutter iOS and web app, native Swift (RoomPlan, Multipeer Connectivity, Nearby Interaction), a FastAPI server, an offline phone mesh, and automated tests.

* **Chert:** Athena Live over FaceTime sees what the worker shows her (protective gear, chemical labels) and reports to the supervisor.

* **Gemini API:** powers Athena chat and Athena Live (Gemini Live for real-time video over FaceTime).

* **MongoDB Atlas:** stores LiDAR scans and hazards as documents.

* **Tiger Data:** stores worker pings and motion events as a time series for last-seen lookups and collapse detection.