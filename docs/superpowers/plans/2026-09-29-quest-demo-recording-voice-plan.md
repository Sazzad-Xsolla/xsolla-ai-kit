# Quest Demo Recording and Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the local voice profile, clean browser and terminal surfaces, and independent Screen Studio chapter recordings for the approved quest demo.

**Architecture:** VoiceStudio produces independent narration clips from the supplied reference WAV. Screen Studio records browser and terminal chapters with secrets excluded before capture. The raw media and project files stay outside Git and are later consumed by the DaVinci Resolve plan.

**Tech Stack:** VoiceStudio local app, Screen Studio, Chrome Demo profile, macOS Focus mode, terminal, WAV/FFmpeg inspection.

**Spec:** `docs/superpowers/specs/2026-09-29-xsolla-quest-demo-design.md`

## Global Constraints

- Use the supplied WAV at `/Users/raufaliyev/Downloads/recording-20260929T090045.wav` as the reference.
- Do not upload source audio or generated voice to GitHub, Slack or a public service.
- Use English voiceover with the profile name `Rauf Aliyev`.
- Record 16:9, 1920x1080, 60 fps.
- API keys, Authorization headers, cookies, wallet secrets and complete user identifiers must never enter raw media.
- The operator performs all browser, terminal and editor actions.

## Review Focus

- VoiceStudio rejects a 19.98-second reference window: select a 10–15 second speech-heavy crop in the UI without modifying the source.
- Clipped reference peaks are reproduced in the clone: listen to the test phrase before generating all clips.
- Screen Studio captures an API key for one frame: rehearse the key scene with the field outside the capture region.
- MacBook 16:10 capture is letterboxed incorrectly: record the application window and configure a 16:9 canvas.
- Notifications or personal tabs enter the raw recording: use a clean Chrome profile and Focus mode before every chapter.

### Task 1: Prepare local media workspace

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/voice/`
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/recording/raw/`
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/recording/project/`

**Interfaces:**
- Produces: `MEDIA_DIR`, source reference path, chapter output paths and a local-only workspace.

- [ ] **Step 1: Create the media workspace**

```bash
MEDIA_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
MEDIA_DIR="$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID"
mkdir -p "$MEDIA_DIR/voice" "$MEDIA_DIR/voiceover/drafts" "$MEDIA_DIR/voiceover/final" "$MEDIA_DIR/recording/raw" "$MEDIA_DIR/recording/project" "$MEDIA_DIR/exports"
```

- [ ] **Step 2: Inspect the source without modifying it**

```bash
ffprobe -v error -show_entries format=duration:stream=codec_name,sample_rate,channels,bits_per_sample -of default=noprint_wrappers=1 /Users/raufaliyev/Downloads/recording-20260929T090045.wav
```

Expected: WAV PCM 16-bit, mono, 24 kHz, approximately 20 seconds.

- [ ] **Step 3: Keep the source outside Git**

Do not copy the WAV into the repository. Store only a local path note in the media workspace.

### Task 2: Install and configure VoiceStudio

**Files:**
- Create outside Git: `$MEDIA_DIR/voice/profile-notes.txt`
- Create outside Git: `$MEDIA_DIR/voiceover/drafts/`

**Interfaces:**
- Consumes: the supplied WAV and exact English transcript.
- Produces: local profile `Rauf Aliyev` and seven draft narration WAV clips.

- [ ] **Step 1: Install the official macOS VoiceStudio package**

Use the official local installation flow from `https://github.com/debpalash/VoiceStudio` and its macOS guide. Keep the app and model cache local.

- [ ] **Step 2: Create the voice profile**

Open `Voice cloning`, add the supplied WAV, name the profile `Rauf Aliyev`, and provide the exact transcript.

- [ ] **Step 3: Select a shorter speech window if required**

If the default engine rejects the 19.98-second boundary or transcript alignment, select a speech-heavy 10–15 second window inside the VoiceStudio waveform UI. Do not rewrite the original WAV.

- [ ] **Step 4: Generate and review a test phrase**

Generate a short test containing `Xsolla`, `Web3`, `API`, `idempotency` and `Backpack`. Stop if the cloned voice has audible clipping, metallic artifacts or incorrect pronunciation.

- [ ] **Step 5: Generate independent narration clips**

Create the following clips from the approved English script:

```text
01-intro.wav
02-setup.wav
03-install.wav
04-create-quest.wav
05-trigger-event.wav
06-verify-backpack.wav
07-close.wav
```

- [ ] **Step 6: Normalize working copies only**

Keep the VoiceStudio exports unchanged as drafts. Convert working copies to 48 kHz for the editor and target approximately −14 LUFS integrated with true peak below −1 dBTP.

### Task 3: Prepare Chrome, terminal and macOS capture state

**Files:**
- Create outside Git: `$MEDIA_DIR/recording/project/chrome-demo-profile-notes.txt`
- Create outside Git: `$MEDIA_DIR/recording/project/terminal-profile.txt`

- [ ] **Step 1: Create a clean Chrome Demo profile**

Use a profile without extensions, history, bookmarks, autofill or personal tabs. Set browser zoom to 125%. Pre-open only Publisher Account, QP readback, explorer and Backpack tabs.

- [ ] **Step 2: Configure macOS Focus**

Enable Do Not Disturb, hide Dock and desktop icons, and stop Slack, mail and Telegram notifications.

- [ ] **Step 3: Configure the terminal**

Use a dark high-contrast theme, 18–20 pt font and a short prompt:

```bash
export PS1='$ '
clear
```

Set shell history protection before entering any credential-bearing command. Never display secrets in command output.

- [ ] **Step 4: Configure Screen Studio**

Select the application window or display region, configure 16:9 1920x1080 capture at 60 fps, enable cursor smoothing and click effects, and leave enough background padding for framed browser and terminal shots.

- [ ] **Step 5: Run a ten-second readability test**

Record a short terminal and browser sample, open it full-screen at 1080p, and confirm that the smallest visible text is readable.

### Task 4: Record independent chapters

**Files:**
- Create outside Git: `$MEDIA_DIR/recording/raw/chapter-01-setup.*`
- Create outside Git: `$MEDIA_DIR/recording/raw/chapter-02-install.*`
- Create outside Git: `$MEDIA_DIR/recording/raw/chapter-03-create-quest.*`
- Create outside Git: `$MEDIA_DIR/recording/raw/chapter-04-trigger-and-verify.*`

- [ ] **Step 1: Record Chapter 1, Setup**

Show Publisher Account, the ordinary virtual item, availability, catalog verification and masked API key creation. Do not show the secret field.

- [ ] **Step 2: Record Chapter 2, Install**

Show the repository, installation command, successful toolkit setup and the `quest-setup` skill.

- [ ] **Step 3: Record Chapter 3, Create Quest**

Insert the approved prompt from a local note rather than typing it slowly. Zoom to `exact event name`, `catalog project` and `do not guess the SKU`. Show the concise quest summary.

- [ ] **Step 4: Record Chapter 4, Trigger and Verify**

Record one continuous flow from active quest through event acceptance, qp-data `COMPLETED`, explorer and Backpack. Do not repeat the event if any response is ambiguous.

- [ ] **Step 5: Save the rehearsal separately**

Keep rehearsal media in `$MEDIA_DIR/recording/raw/rehearsal/` and never use it as evidence unless the live run is independently correlated.
