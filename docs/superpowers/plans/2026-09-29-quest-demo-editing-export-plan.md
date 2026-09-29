# Quest Demo Editing and Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble the approved Screen Studio chapters, VoiceStudio narration and reference-style slides into a readable, captioned 5:30–6:00 demo and export validated delivery files.

**Architecture:** Use a DaVinci Resolve project outside Git with reusable ivory and dark slide templates. Keep screen recordings, voiceover and overlays on separate timeline tracks so any chapter can be replaced without re-recording the live stage flow.

**Tech Stack:** DaVinci Resolve Free, WAV, SRT, H.264, ProRes 422, FFmpeg/ffprobe.

**Spec:** `docs/superpowers/specs/2026-09-29-xsolla-quest-demo-design.md`

## Global Constraints

- Final video is English, 16:9, 1920x1080, 60 fps and under 10 minutes.
- Target duration is approximately 5:30–6:00.
- Visual language uses ivory explanation slides, charcoal technical slides and cyan accents.
- Raw JSON and credentials are not primary visual content.
- The opening hook shows the Backpack result before setup.
- Voiceover explains why actions matter, not every click.
- Source audio, raw recordings, Resolve projects and environment files remain outside Git.
- Export MP4, ProRes master and SRT subtitles.

## Review Focus

- Opening result is not understandable in five seconds: hold the Backpack item and use a clear caption.
- Terminal or browser text is unreadable at 1080p: increase zoom or crop before export.
- Voiceover drifts from live timing: align narration after the screen cut is locked.
- Sensitive data appears in a raw frame: replace or crop the source clip before rendering.
- Chapter transitions lose causality: retain the same run ID, event ID and proof chain across summary cards.

### Task 1: Create the Resolve project and templates

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/recording/project/xsolla-quest-demo.drp`
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/recording/project/templates/`

**Interfaces:**
- Produces: 1920x1080/60 timeline, reusable title cards and chapter labels.

- [ ] **Step 1: Create the timeline**

Set timeline resolution to 1920x1080, frame rate to 60 fps and audio sample rate to 48 kHz before importing media.

- [ ] **Step 2: Create the visual templates**

Create reusable templates for:

```text
dark title card
ivory two-column explanation
ivory three-column setup
chapter label
quest summary
proof chain
resources card
lower-third identity
```

Use warm ivory, charcoal and cyan. Keep margins generous and headings large.

- [ ] **Step 3: Create the timeline tracks**

```text
V1  screen recordings
V2  slides and overlays
A1  voiceover
A2  optional music
A3  interface sounds
```

### Task 2: Assemble the visual sequence

**Files:**
- Modify outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/recording/project/xsolla-quest-demo.drp`

- [ ] **Step 1: Place the opening Backpack hook**

Use the cleanest Backpack item shot for 00:00–00:05. Add:

```text
The reward is already in Backpack
```

- [ ] **Step 2: Add the title and identity lower third**

Use:

```text
From Prompt to Backpack
A real Web3 quest with Xsolla AI Toolkit

Rauf Aliyev
Middle Backend Developer
```

- [ ] **Step 3: Add the flow slide and chapter labels**

Use the approved flow and chapter names:

```text
Publisher Account → Catalog Item → Toolkit → Quest → Event → Backpack
1. Setup
2. Install
3. Create Quest
4. Trigger Event
5. Verify Reward
```

- [ ] **Step 4: Insert the live chapter recordings**

Place setup, install, quest creation and trigger/verification chapters in the approved order. Use window framing and short cursor zooms, not full-screen raw terminal for long periods.

- [ ] **Step 5: Add summary and proof cards**

Show only readable fields:

```text
Quest created
Trigger: `EVENT_NAME` from `$RUN_DIR/stage/quest.md`
Reward: item name from `$RUN_DIR/stage/catalog.md`
SKU: shortened `CATALOG_SKU` from `$RUN_DIR/stage/catalog.md`
Quantity: 1
Status: Active
```

Use the actual evidence values from the stage run, shortened where sensitive.

- [ ] **Step 6: Add the manual JSON contrast**

Show a brief card describing handwritten JSON as many fields and guessing risk, then replace it with `One natural-language prompt`. Do not expose a real credential-bearing payload.

### Task 3: Add narration, captions and pacing

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/exports/xsolla-quest-demo.srt`

- [ ] **Step 1: Import narration clips**

Place the seven VoiceStudio clips on A1 after the visual cut is locked. Trim silence and leave natural pauses between sentences.

- [ ] **Step 2: Mix the voiceover**

Target approximately −14 LUFS integrated and true peak below −1 dBTP. Keep music at least 20 dB below voice or omit it.

- [ ] **Step 3: Create English subtitles**

Use the approved narration transcript to create an SRT matching the final clip boundaries. Verify that captions never cover the key catalog, qp-data or Backpack proof fields.

- [ ] **Step 4: Label accelerated waits**

Speed up cache and transaction waits to 8x or 16x and add a short `90 seconds later` card. The narration must acknowledge the cut honestly.

- [ ] **Step 5: Check pronunciation and timing**

Review `Xsolla`, `Web3`, `API`, `idempotency`, `qp-data`, `transaction` and `Backpack` at normal speed.

### Task 4: Security and visual quality review

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/exports/security-review.txt`

- [ ] **Step 1: Review the timeline frame-by-frame**

Search every source and rendered chapter for full API keys, Authorization headers, cookies, clipboard contents, emails, complete wallet addresses and full user IDs.

- [ ] **Step 2: Review 1080p readability**

Watch the final timeline full-screen and confirm terminal text, browser item names, status labels, event ID and Backpack item are readable without pausing.

- [ ] **Step 3: Review causality**

Confirm that the same evidence chain appears as:

```text
event ID
→ qp-data COMPLETED
→ transaction hash
→ token transfer
→ Backpack item
```

- [ ] **Step 4: Record the review result**

Write pass/fail results and any redactions to `security-review.txt`.

### Task 5: Export and validate delivery files

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/exports/xsolla-quest-demo-final.mp4`
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/exports/xsolla-quest-demo-master.mov`
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$MEDIA_RUN_ID/exports/xsolla-quest-demo.srt`

- [ ] **Step 1: Export the MP4**

Use H.264, 1920x1080, 60 fps, 16–20 Mbps video and AAC 320 kbps at 48 kHz.

- [ ] **Step 2: Export the ProRes master**

Use ProRes 422 at 1920x1080 and 60 fps.

- [ ] **Step 3: Validate duration and streams**

```bash
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate,sample_rate,channels -of default=noprint_wrappers=1 "$EXPORT_DIR/xsolla-quest-demo-final.mp4"
```

Expected: duration 330–360 seconds, video 1920x1080 at 60 fps, audio 48 kHz.

- [ ] **Step 4: Validate audio loudness**

```bash
ffmpeg -hide_banner -i "$EXPORT_DIR/xsolla-quest-demo-final.mp4" -af ebur128=framelog=verbose -f null - 2>&1 | tail -n 30
```

Expected: voice mix near −14 LUFS integrated with no true peak above −1 dBTP.

- [ ] **Step 5: Watch the complete MP4 once**

Confirm opening Backpack hook, quest prompt, active status, one event, `COMPLETED`, explorer proof, Backpack proof, captions and resources.
