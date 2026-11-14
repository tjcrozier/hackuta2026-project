# Black Box — Demo Script

3 minutes for the main demo, plus a 1-minute offline add-on.

## Before the judges arrive (10 minutes)

**Laptop**
1. Start the server (keep this terminal open):
   `cd ~/Documents/blackbox/server && source .venv/bin/activate && python run.py`
   (`run.py` listens on IPv4 and IPv6, so phones can use the laptop's `.local` name.)
2. Open the dashboard in a browser: `http://localhost:8000/app/#/dashboard`
3. In a second tab, open the rescuer page: `http://localhost:8000/app/#/rescue`

**Phones** (all on the same Wi-Fi as the laptop, or the laptop's hotspot)
| Phone | Role | Notes |
| --- | --- | --- |
| Phone 1 (LiDAR iPhone) | Supervisor | Does the scan and holds the red button |
| Phone 2 | Worker "Sajid" | Gets dropped; is the phone hidden in the bag |
| Phone 3 | Worker | A judge taps "I need help" |
| Phone 4 (optional) | Rescuer finder | Finds Phone 2 |
| Spare iPhone / iPad | Zone beacon | Zone A, screen on |

4. On every phone: first screen → **Server → Change** → `http://<laptop-name>.local:8000`
   (the laptop name is shown by `scutil --get LocalHostName`), or the laptop's Wi-Fi number.
5. **Reset:** on the supervisor phone, long-press the logo → **Demo tools** → **Reset demo**.
6. Workers: tap **Worker**, join, tap every **Allow**, start the shift. Check that each name
   appears on the dashboard.
7. Turn the phone volume up. Turn Low Power Mode off. Keep Black Box open on screen on all phones.
8. Put a pillow on the table.

## Main demo (3 minutes)

| Time | Who | Do | Say |
| --- | --- | --- | --- |
| 0:00 | You | Hold up a phone. | "Planes have black boxes. Buildings don't. On a job site, when something goes wrong, nobody knows who was where. Black Box fixes that with the phones workers already carry." |
| 0:15 | Supervisor | Supervisor → Floor 3 → **Scan** → **Start LiDAR scan**, sweep the room, tap **Done**. | "Every morning the supervisor scans each floor with the iPhone's LiDAR." |
| 0:40 | Supervisor | Show the "New opening on Floor 3" result. Point at the dashboard: the hazard shows up. | "The server compares today's scan with yesterday's. A new hole in the floor: the supervisor and every worker on that floor get a text, with the OSHA topic." |
| 1:00 | You | Point at the dashboard map. | "Each worker's phone sends a tiny ping: zone, floor, battery. Location only. No camera, no microphone, no messages." |
| 1:15 | You | Drop Phone 2 onto the pillow from about 40 cm. Wait about 10 s. | "One phone falls..." |
| 1:30 | You | "Did you fall?" appears with a beep. Tap **I'm OK**. | "...it asks first. One hit is not a disaster. If nobody answers, the supervisor gets a text." |
| 1:45 | You | Drop Phones 2 and 3 and the supervisor's phone on the pillow together. (Backup: hold the red button on the dashboard for 2 seconds.) | "But three phones feeling a hard impact at the same moment means something big happened." |
| 1:55 | — | Every worker phone turns dark red: "Emergency on site". | "Rescue Mode. Every worker gets one question: are you OK?" |
| 2:05 | Judge | Hand Phone 3 to a judge: tap **I need help**. Dashboard dot turns orange. | "One tap. The supervisor sees who is safe, who needs help, and who hasn't answered." |
| 2:25 | You | Switch to the rescuer tab. | "Firefighters arrive. They open one link. No app, no login: who is missing, where they were last seen, and the nearest stairs." |
| 2:45 | You | Close. | "Today it runs on phones. On a real site, a hard-hat tag does this all day over long-range LoRa radio. Black Box: know who's inside." |

**If the LiDAR scan fails or takes too long:** tap **Use saved demo scan** on the same screen
(or Demo tools → **Fake a hazard on Floor 3**). The result is the same new-opening hazard.

**If the pillow drop does not start Rescue Mode:** Demo tools → **Fake a collapse (3 phones)**,
or hold the red button on the dashboard.

## Offline add-on (1 minute)

Needs 3 phones that joined while online (so they know each other's names).

| Time | Do | Say |
| --- | --- | --- |
| 0:00 | On 3 phones: Airplane Mode on, then Bluetooth and Wi-Fi back on. Open **Offline mesh**, turn on **Offline mode**. | "The building's internet is gone. The phones talk to each other directly." |
| 0:15 | Phone A: **I need help**. Phone C (across the room or behind a wall) shows it with the path "Sajid → Maria → You". | "The message hopped from phone to phone until it found someone." |
| 0:30 | Hide Phone 2 in a bag. On Phone 4 open **Rescuer finder**, tap the name, walk toward the bag. | "No GPS indoors, no internet. The rescuer follows the signal: hot and cold, and on newer iPhones a distance and an arrow." |
| 0:50 | Turn Airplane Mode off on one phone. The dashboard shows the help request with "via mesh". | "As soon as one phone gets a signal, everything it collected reaches the dashboard." |

## After each run
- Demo tools → **Stop Rescue Mode**, then **Reset demo**.
- Workers do not need to join again: phones join again by themselves after a reset.

## Known limits (be honest if a judge asks)
- Everything works only while Black Box is open on screen (iOS limit). The hard-hat tag fixes this.
- Positions are by zone, not to the meter.
- Two scans of the same room can differ; "False alarm" clears a wrong hazard.
- The rescuer link has no login; the real version uses a secret link that expires.
- Texts are faked unless the Chert API key is set in `server/.env`.
