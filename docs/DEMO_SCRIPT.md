# Cycl0ps — Demo Script (3 minutes)

The story: in the Odyssey, the Cyclops screams "Nobody is hurting me!" and nobody comes,
because nobody knows who is really in the cave. On a collapsed job site, the answer to
"who is inside?" is still "nobody knows". Cycl0ps makes sure there is always a real answer.

---

## Addresses

Laptop name: `EMPL-150327.local`. Wi-Fi number: run `ipconfig getifaddr en0` (it was
`10.133.199.93`; it changes when the Wi-Fi changes).

| What | On the laptop | From another laptop or phone browser |
| --- | --- | --- |
| Supervisor dashboard (web) | http://localhost:8000/app/#/dashboard | http://10.133.199.93:8000/app/#/dashboard |
| Rescuer page (web, no login) | http://localhost:8000/app/#/rescue | http://10.133.199.93:8000/app/#/rescue |
| Server address typed into the iPhone app | – | `http://EMPL-150327.local:8000` or `http://10.133.199.93:8000` |
| Server check | http://localhost:8000/health | – |

The supervisor on a phone uses the Cycl0ps app: first screen → **Supervisor**.

---

## Who does what

| Person | Holds | Job |
| --- | --- | --- |
| **Speaker** | nothing | Tells the story, points at the screen. Never touches a device. |
| **Driver** | laptop | Dashboard tab + rescuer tab. Holds the red button if needed. Types to Athena. |
| **Phone 1 (Sajid)** | iPhone 17 Pro Max (LiDAR) | Supervisor app, LiDAR scan, one of the dropped phones. |
| **Phone 2 (Bhaskar)** | iPhone 14 | Worker "Bhaskar". The fall demo phone. |
| **Phone 3 (spare)** | any iPhone with the app | Worker. Handed to a judge for "I need help". |

Only 2 phones? Skip the 3-phone drop and use the **red button** (it is in the script anyway).

---

## 10 minutes before the judges

1. Laptop and all phones on the **same Wi-Fi**. (Venue Wi-Fi blocks phones? Use an iPhone
   Personal Hotspot for everything.)
2. Start the server and keep the tab open:
   `cd ~/Documents/blackbox/server && source .venv/bin/activate && python run.py`
3. Browser tab 1: the dashboard. Tab 2: the rescuer page. Make the window wide (the Athena
   panel shows on the right at 1200 px or wider).
4. Each phone: **Server → Change** → `http://EMPL-150327.local:8000`.
5. Supervisor phone: long-press the logo → **Demo tools** → **Reset demo**.
6. Worker phones: **Worker** → join → **Allow** everything → **Start shift**. Check each
   name shows on the dashboard.
7. Ask Athena one test question on the dashboard ("How many workers are on site?").
   If it says "offline", check `GROQ_API_KEY` in `server/.env` and restart the server.
8. Volume up, Low Power Mode off, phones unlocked, Cycl0ps open on screen. Pillow on the table.

---

## The 3 minutes

| Time | Who | Do | Say |
| --- | --- | --- | --- |
| **0:00** | Speaker | Hold up a phone. | "In the Odyssey, the Cyclops screams 'Nobody is hurting me!' and nobody comes, because nobody knows who's really inside. Every year, after a collapse on a job site, rescuers face the same question: who is inside? The answer is still 'nobody knows'. We built **Cycl0ps** so there's always a real answer, using the phones workers already carry." |
| **0:25** | Phone 1 | Supervisor → Floor 3 → **Scan** → **Start LiDAR scan**, sweep, **Done**. (Slow? Tap **Use saved demo scan**.) | "Every morning the supervisor scans each floor with the iPhone's LiDAR. Cycl0ps compares it with yesterday's scan." |
| **0:45** | Driver | Point at the new hazard on the dashboard. | "A new opening in the floor. The supervisor and everyone on that floor get a text, with the OSHA rule." |
| **0:55** | Speaker | Point at the dashboard map, then at Phone 2's "What your phone shares" box. | "Each worker's phone sends a tiny ping: zone, floor, battery. No camera, no microphone, no messages. Only during the shift." |
| **1:10** | Phone 2 | Drop Phone 2 on the pillow. About 10 s later: "Did you fall?" Tap **I'm OK**. | "One phone falls. It asks first. If nobody answers, the supervisor is alerted." |
| **1:35** | Driver | Hold **Start Rescue Mode** for 2 seconds. (3+ phones: drop them on the pillow together instead.) | "If three phones feel a hard hit at once, or the supervisor holds the red button, Cycl0ps starts Rescue Mode." |
| **1:45** | – | Worker phones turn dark red: "Emergency on site". | "Every worker gets one question: are you OK? By app and by text." |
| **1:55** | Judge | Hand Phone 3 to a judge: **I need help**. The dot turns orange on the dashboard. | "One tap. Now the supervisor sees who's safe, who needs help, and who hasn't answered." |
| **2:10** | Driver | Switch to the rescuer tab. In the Athena panel tap **Who is missing?**, then type "Where was Bhaskar last seen, and the nearest stairs?" | "Firefighters arrive. One link, no app, no login. And they can just ask **Athena**: who is missing, where were they last seen, which stairs are closest. She only answers from live site data, and a worker's Athena never sees anyone else." |
| **2:35** | Speaker | – | "No internet in the building? The phones pass messages to each other until one gets out. And a rescuer's phone can find a buried worker's phone by its Bluetooth signal: hot and cold." |
| **2:45** | Speaker | Close. | "Today it runs on phones. Next, a hard-hat tag does this all day over long-range radio. Cycl0ps: so 'nobody' is never the answer." |

---

## If something goes wrong

| Problem | Do this |
| --- | --- |
| LiDAR scan slow or fails | **Use saved demo scan**, or Demo tools → **Fake a hazard on Floor 3** |
| "Did you fall?" doesn't appear | Say "it waits 10 seconds to be sure", move on to Rescue Mode |
| Pillow drop doesn't start Rescue Mode | Driver holds the red button (2 s), or Demo tools → **Fake a collapse** |
| Phone shows "No connection" | Check it's on the same Wi-Fi; type the number address instead of `.local` |
| Athena says "offline" | Skip it; read the missing list from the rescuer page instead |

## After each run
- Demo tools → **Stop Rescue Mode**, then **Reset demo**.
- Workers do not need to join again.

## If judges ask (be honest)
- Works only while Cycl0ps is open on screen (iOS limit). The hard-hat tag fixes this.
- Positions are by zone, not to the meter.
- Two scans of the same room can differ; "False alarm" clears a wrong hazard.
- The rescuer link has no login; the real version uses a secret link that expires.
- Texts are faked unless the Chert API key is set.
- Athena runs on Groq (`openai/gpt-oss-120b`). It can be wrong, so it always says to call 911 in an emergency.
- Built but not shown: a FaceTime safety agent (Chert) that checks protective gear and reads hazard labels on a video call.

---

## Offline add-on (only if judges ask, 1 minute)

Needs 3 phones that joined while online.

| Do | Say |
| --- | --- |
| 3 phones: Airplane Mode on, then Bluetooth and Wi-Fi back on. **Offline mesh** → **Offline mode** on. | "The building's internet is gone." |
| Phone A: **I need help**. Phone C shows it, with the path. | "The message hopped from phone to phone." |
| Hide a phone in a bag. Another phone: **Rescuer finder**, tap the name, walk toward the bag. | "No GPS indoors. The rescuer follows the signal: hot and cold." |
| Airplane Mode off on one phone. The dashboard shows the help request "via mesh". | "As soon as one phone gets a signal, everything reaches the dashboard." |
