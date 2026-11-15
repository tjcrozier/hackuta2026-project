# Cycl0ps + Chert FaceTime — plan and setup

**Status (14 Nov 2026): kept as a feature, NOT part of the demo.** Chert onboarding is done
(line +1 913-282-1013, trial). The starter agent is in `agent/` (`blackbox-safety`); the
LiveKit and OpenAI keys are not filled in yet, and the safety/help/rescuer modes are not written.

Target prize: **Best Use of FaceTime** ("an AI agent that uses FaceTime video to see
what you show it, show you what you need, or both").

Source for every Chert fact below: https://app.trychert.com/skills.md (CLI version
`@trychert/facetime@0.1.0-beta.21`, read 14 Nov 2026). Chert is in beta; if a command
behaves differently, the CLI's own message wins.

---

## 1. How Chert works (what we learned)

- Chert gives us a **FaceTime line** (a real Apple number) answered by a Chert Mac.
- When someone FaceTimes that number, Chert puts the call into a **LiveKit room**.
  **Our agent** (a small Python program on the laptop) joins that room, sees the
  caller's video, hears them, and talks back. The agent can also send its own video.
- Two programs must stay running during the demo: **our agent** and **`chert dev`**
  (the connector). Ctrl+C on either one and calls stop reaching us.
- **Free trial:** 50 FaceTime minutes in total, **5 minutes per call max**, valid
  **48 hours** (because we start before 18 Nov 2026). Paid "Shared" plan: $25/month.
- **One call at a time** on a Shared/trial line.
- Only **phones verified for our project** can use the line (each phone texts a code
  over iMessage once).
- Outbound calls (Chert calls the worker) exist in the HTTP API, but need a project
  API key and are less certain on the trial. **Inbound calls (the phone calls the
  agent) are the safe path**, so the plan uses inbound first.

---

## 2. Rating

| Idea | Score | Why |
| --- | --- | --- |
| **Help Call** (worker in trouble FaceTimes the agent) | **9/10** | Fits our Rescue Mode story, very clear "it sees what you show it" moment, the dashboard fills in live. |
| **Safety supervisor: PPE check** (hard hat, vest, glasses, gloves, boots) | **9/10** | The easiest thing for a judge to try live: put on or take off a hard hat and the agent notices. Vision models do this well. |
| **Safety supervisor: "is this chemical dangerous?"** | **6/10 as asked, 8/10 reframed** | A camera **cannot** tell what an unlabeled liquid is. Claiming it can is risky in front of judges. Reframe: the agent **reads the label, GHS hazard symbols and NFPA diamond**, says what they mean, and treats anything unlabeled as dangerous until checked against the Safety Data Sheet. That is honest and still impressive. |
| **Rescuer FaceTime** | **6/10 voice only, 8/10 with map video** | Rescuers already have the web link, so a voice-only version adds little. If the agent **shows the floor map with the missing worker's last-seen spot as its own video**, it covers the "show you what you need" half of the prize, which most teams will skip. |
| **Overall** | **8/10** | Strong prize fit and it reuses our server data. Main risks: one call at a time, 5-minute cap, the trial expires in 48 h, it needs internet, and it adds new tools (Node, LiveKit, an AI model key). |

**Recommendation:** build **one agent, "Cycl0ps Safety"**, with three modes, in this
order (stop after any step and it still demos):

1. **Safety check** (PPE + label reading). No server change needed. ~1–2 h.
2. **Help Call.** The agent looks up the caller in our server, then writes a short
   summary that appears on the dashboard and rescuer page. ~1–2 h.
3. **Rescuer guide** with the floor map shown as the agent's video. Stretch. ~2 h.

How the agent picks the mode: it asks our server who is calling (by phone number).
A worker whose status is "help" → **Help Call**. Anyone during Rescue Mode who is not
a worker → **Rescuer guide**. Everyone else → **Safety check**. If it can't tell, it
simply asks: "Are you hurt, are you a rescuer, or do you want a safety check?"

---

## 3. What changes in Cycl0ps

**New things to approve (CLAUDE.md says to ask first):**

| New | Why |
| --- | --- |
| **Node.js 24** on the laptop | Runs the Chert CLI (`npx @trychert/facetime`). |
| **`agent/` folder** (Node.js, made with `chert new agent --video`) | The FaceTime agent, named `blackbox-safety`. Packages: `@livekit/agents`, `@livekit/agents-plugin-openai`, `@livekit/rtc-node` (1.8.0 / 0.13.35). The starter does not look at the caller's camera; we add that by taking a frame from the caller's video when they finish speaking and sending it to the model as an image. |
| **LiveKit Cloud account** (free tier) | Carries the call's audio and video between Chert and our agent. Required on the trial (Chert-run rooms are a Shared-plan option). |
| **OpenAI API key** with Realtime access and credits | The agent's brain: model `gpt-realtime` (voice + images). Costs money per minute; set a monthly limit on the OpenAI billing page. |
| Server: `POST /agent/report` and `GET /agent/caller?phone=` | The agent reads who is calling and writes its findings (help summary, PPE result, chemical label) to the dashboard. Goes into the BUILD_PLAN.md API table. |
| App: **"FaceTime Cycl0ps Safety"** button | On "I need help" in Rescue Mode and on the worker home. Opens `facetime://<line number>`. No new Flutter package. |
| `config.dart` + `server/.env` flag `FEATURE_FACETIME` | So the button and agent reports can be turned off during the demo. |

**Fallback:** if Chert, LiveKit or the model fails, the button is hidden by the flag
and everything works exactly as today (help alert, texts, mesh, finder).

---

## 4. Privacy rule change (CLAUDE.md section 6)

Old rule: no camera except the LiDAR scan, no audio except an optional voice note.

New rule (proposed):

> - Camera and microphone are used only in a **FaceTime call the person starts
>   themselves** (or accepts), with the Cycl0ps Safety agent. Never in the background.
> - The call is live only. Cycl0ps **does not record or store** video or audio. It
>   stores only the agent's short **text summary** (for example "Hard hat: yes. Vest:
>   no.").
> - During the call, video and audio pass through Chert, LiveKit and the AI model
>   provider. Say this honestly if a judge asks.
> - The agent's advice is a safety aid, not a certified inspection. When unsure, it
>   tells the person to treat the situation as dangerous.

Pitch line: *"The phone never watches you. You choose to show it something."*

---

## 5. Setup — step by step

Who does what: **You** = Sajid at the laptop/phone. **Claude** = me, in this session.

### Step 0 — Before you start (5 min)

1. **Install Node.js 24** (the laptop has none right now):
   - Go to https://nodejs.org → download the **macOS Installer (.pkg)** for the
     current LTS version → open it → Continue → Install → enter your Mac password.
   - Open a **new** terminal tab and check: `node -v` (should print v24 or newer).
2. Have your iPhone with you, **signed in to iMessage and FaceTime** with your phone
   number (Settings → Apps → Messages / FaceTime → your number is ticked).
3. **Timing:** the free trial runs 48 hours from activation. Start this **no earlier
   than 48 hours before judging**.

### Step 1 — Sign up and verify (10 min)

1. Tell Claude: **"start Chert onboarding"**. Claude runs:
   ```
   npx --yes --prefer-online @trychert/facetime@0.1.0-beta.21 onboard --json --no-browser --plan trial --stack demo
   ```
2. Claude gives you a **link**. Open it, create a Chert account (or sign in), and type
   your **name and phone number**.
3. The page shows a **6-digit code** and a phone number. **From your iPhone, in
   Messages (blue bubble, iMessage — not SMS)**, text the code to that number.
   Chert replies "Verified".
4. **Chert FaceTimes you** with its demo agent. Pick up, say hello, hang up.
5. Claude confirms onboarding finished and notes the **project ID** and the **line's
   FaceTime number** (not secret).

### Step 2 — LiveKit (10 min)

1. Go to https://cloud.livekit.io → sign up (free) → **Create project** → name it
   `blackbox`.
2. Go to **Settings → Keys** (or "API Keys") → **Create key**. You will see three
   values: **URL** (starts with `wss://`), **API Key**, **API Secret**.
3. **Do not paste them in chat.** Claude creates the file `agent/.env.local`; open it
   in a text editor and fill in:
   ```
   LIVEKIT_URL=wss://....livekit.cloud
   LIVEKIT_API_KEY=...
   LIVEKIT_API_SECRET=...
   ```
   All three must come from the same LiveKit project.

### Step 3 — Create the agent (Claude, ~1–2 h per mode)

1. Claude runs `chert new agent --video` inside `blackbox/` and reads which AI model
   the starter uses.
2. Claude tells you **which model key** is needed and roughly what 50 minutes of calls
   costs. You create that key on the provider's website and put it in
   `agent/.env.local` (again, never in chat).
3. Claude writes the three modes (safety check → help call → rescuer guide), the two
   server endpoints, the app button, the feature flag, and tests. Claude checks that
   `agent/.env.local` is git-ignored before anything is committed.

### Step 4 — Connect and test on the laptop (10 min)

In the `agent/` folder Claude starts the agent in one terminal tab, then in another:
```
chert setup --env-file .env.local --project <project-id>
chert doctor
chert doctor --agent <agent-name>     # runs a real test job
chert dev
```
Keep **both tabs open**. Claude tells you when it says the agent is ready.

### Step 5 — Phones (5 min per phone)

1. **Every phone that will call the agent must be verified** for the project (each one
   texts a code over iMessage, like Step 1). Do this for your phone, Bhaskar's, and
   any phone you will hand a judge. Claude will check in the Chert console how to add
   more phones and give you the exact clicks.
2. On each phone, save a contact: **"Cycl0ps Safety"** → the line's number.
3. Install the updated app (`flutter run --release -d <phone id>`).

### Step 6 — Test checklist (on your iPhone)

- [ ] **Safety check:** FaceTime **Video** "Cycl0ps Safety". Wear a hard hat → it says
      hard hat yes. Take it off → it warns you. The dashboard shows a "PPE check" line.
- [ ] **Label:** show a cleaning-product bottle with a warning symbol → it reads the
      symbol and says what it means. Show an unlabeled cup of water → it says it
      can't tell and to treat it as unknown.
- [ ] **Help Call:** start Rescue Mode (dashboard red button, hold 2 s) → tap
      **I need help** → tap **FaceTime Cycl0ps Safety** → the agent greets you by
      name and floor → describe a "hurt ankle" → the summary appears on the dashboard
      and rescuer page.
- [ ] **Rescuer** (stretch): from a phone that is not a worker, during Rescue Mode,
      FaceTime the agent → it shows the floor map and says where the missing worker
      was last seen.
- [ ] Call lasts under 5 minutes; a second phone calling at the same time gets
      "busy" (expected: one call at a time).

### Step 7 — Demo day

1. Start the server (`python run.py`), then the agent, then `chert dev`. Three tabs.
2. Run `chert doctor` once. Check minutes left on https://app.trychert.com/overview.
3. Keep calls short (under 1 minute each). Only one person calls at a time.
4. If anything fails: set `FEATURE_FACETIME=false` and do the normal demo.

---

## 6. Security

- Chert, LiveKit and model keys go **only** into `agent/.env.local` (git-ignored) or
  the Chert CLI's own store `~/.chert`. **Never in chat, never in git.**
- A Chert key is only ever sent to `app.trychert.com`.
- To revoke this laptop later: `chert logout`. API keys: https://app.trychert.com/developer
- Only call or text people who agreed to it.
