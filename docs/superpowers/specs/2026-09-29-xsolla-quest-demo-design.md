# Xsolla Quest Demo Video Design

**Status:** Design approved

**Date:** 2026-09-29

## 1. Purpose

Create a polished English product demo that proves a complete, unmocked quest flow from a publisher catalog item to a Web3 reward visible in Backpack.

The viewer should understand that a publisher can describe the desired quest in natural language, let the `quest-setup` skill configure it, send one real event, and verify the reward across Quest Platform, the blockchain explorer, and Backpack.

The final video is a public-facing demo for YouTube. It is not a tutorial that exposes credentials or raw API responses.

## 2. Approved constraints

- Language: English.
- Presenter: no camera; use screen recording and voiceover.
- Identity: `Rauf Aliyev`, `Middle Backend Developer`.
- Format: 16:9, 1920x1080, 60 fps.
- Target duration: approximately 5:30 to 6:00, under 10 minutes.
- Capture: Screen Studio.
- Voice: VoiceStudio using the supplied WAV as the reference sample.
- Editing: DaVinci Resolve Free.
- New disposable catalog item, quest, reward, and event are allowed.
- The live reward flow must be real. Mocked stage responses and simulated success screens are prohibited.
- Full JSON and raw API output are not primary visual content.
- The user is not expected to perform manual preparation or recording actions. The operator performs the workflow autonomously.

## 3. Stage contexts

The demo uses two distinct project roles:

| Role | Merchant | Project | Use |
| --- | --- | --- | --- |
| Quest Platform | `940246` | `316575` | Quest owner, condition, event and execution |
| Publisher catalog | `940463` | `316665` | Catalog item, SKU and Web3 reward source |

The reward must contain the explicit catalog project and a SKU verified against the stage minting catalog and metadata endpoint. The SKU must never be guessed.

Secrets, Authorization headers and private wallet material remain in local protected configuration and never appear in the recording, logs, Git, or public description.

## 4. Production architecture

```text
Publisher Account
        |
        v
Chrome Demo Profile
        |
        v
Screen Studio chapter recordings
        |
        +--> VoiceStudio narration clips
        |
        v
DaVinci Resolve timeline
        |
        v
MP4 + ProRes master + SRT subtitles
```

### Responsibilities

The operator performs all setup and execution:

1. Install and configure missing applications.
2. Prepare a clean Chrome profile, terminal and Screen Studio settings.
3. Create and verify disposable stage objects.
4. Run the live quest flow and collect evidence.
5. Create the VoiceStudio profile and narration clips.
6. Record each chapter.
7. Assemble the final video, captions and subtitles.
8. Export and quality-check the final artifacts.
9. Update `quest-skill-e2e/progress.md` with the run evidence.

If macOS prevents an operation with a system permission dialog, the operator first tries available automation paths and records the exact blocker if the operating system cannot be controlled programmatically.

## 5. Story and timing

The video opens with the result. The viewer sees the item in Backpack before hearing the setup explanation.

| Time | Scene | Visual result |
| --- | --- | --- |
| 00:00–00:05 | Result hook | Backpack item visible with a short zoom |
| 00:05–00:15 | Hook narration | “Here is how one prompt got it there.” |
| 00:15–00:25 | Title and identity | Title card plus lower-third identity |
| 00:25–01:25 | Chapter 1, Setup | Publisher project, item, availability and catalog verification |
| 01:25–01:45 | Toolkit installation | Repository, install command and skills |
| 01:45–02:45 | Chapter 2, Create Quest | Natural-language prompt and Codex response |
| 02:45–03:15 | Quest summary | Reward, SKU, project, quantity and active status |
| 03:15–03:50 | Chapter 3, Trigger Event | Event fields and one real event |
| 03:50–04:30 | Chapter 4, Verify Reward | qp-data `COMPLETED` execution and transaction hash |
| 04:30–05:00 | Explorer proof | Successful transaction and token transfer |
| 05:00–05:30 | Backpack proof | Delivered item, verification and details |
| 05:30–05:55 | Resources | Toolkit, quest docs, Publisher, Explorer and Backpack |

Voiceover explains why each action matters. It should not narrate every click.

## 6. Slide and visual system

The visual language follows the supplied reference video:

- warm ivory explanation slides;
- charcoal or near-black technical slides;
- cyan or aqua accent lines;
- large modern sans-serif headings;
- short labels and generous whitespace;
- two-column or three-column layouts;
- browser and terminal frames at 75–85% of the canvas width;
- clean cuts, short fades and gentle cursor zooms;
- no dense paragraphs or unnecessary motion graphics.

Slides are created as reusable title, chapter, summary and resource templates in DaVinci Resolve. Keynote and HyperFrames are not required for the first version.

Required visual cards:

1. `From Prompt to Backpack` title card.
2. `Rauf Aliyev / Middle Backend Developer` lower third.
3. `Publisher Account → Catalog Item → Toolkit → Quest → Event → Backpack` flow.
4. Three-column preparation card: Publisher Account, Catalog Item, AI Toolkit.
5. Numbered skill list highlighting `quest-setup`.
6. Manual JSON versus one natural-language prompt contrast.
7. Quest summary card.
8. Event explanation card.
9. Proof chain from accepted event to Backpack.
10. Final resources card.

The design should match the reference's colors, grid, density and editorial rhythm without copying third-party images pixel-for-pixel.

## 7. Live stage flow

The main live flow is recorded as one continuous chapter so that one event can be correlated through every proof surface.

1. Open the Publisher Account catalog project.
2. Create a free ordinary `virtual_item` with a unique name and SKU.
3. Confirm `Available` status.
4. Verify the SKU using the stage minting catalog and metadata endpoint.
5. Confirm the target Backpack identity and wallet resolution.
6. Create a disposable quest in QP project `316575` through `quest-setup`.
7. Add a `web3_item` reward with explicit catalog project `316665`, verified SKU and quantity `1`.
8. Activate the quest and read it back.
9. Wait for configuration caches before sending the event.
10. Send exactly one event with the exact trigger name, required `xsolla_id` and a fresh idempotency key.
11. Capture HTTP 200 and the returned `event_id`.
12. Find the matching qp-data execution and confirm `issue_reward = COMPLETED` with `txHash`.
13. Confirm the transaction and token transfer in the explorer.
14. Open Backpack and confirm the item is visible.

The chain of evidence is:

```text
SKU
→ Quest ID
→ Event name
→ Event ID
→ qp-data execution
→ txHash
→ Token ID
→ Backpack item
```

If a catalog SKU or metadata check fails, the quest and event steps do not start. If an event request times out, the operator checks read-only evidence before considering any further action and never blindly resends the reward event.

## 8. Voice and recording pipeline

Reference audio:

```text
/Users/raufaliyev/Downloads/recording-20260929T090045.wav
```

Create a local VoiceStudio profile named `Rauf Aliyev`. If the engine requires a shorter speech window, select a speech-heavy 10–15 second segment inside VoiceStudio without modifying the source file.

Generate independent clips:

```text
01-intro.wav
02-setup.wav
03-install.wav
04-create-quest.wav
05-trigger-event.wav
06-verify-backpack.wav
07-close.wav
```

Review pronunciation of `Xsolla`, `Web3`, `API`, `idempotency`, `qp-data` and `Backpack`. Keep source audio, profiles and generated clips outside Git.

Record these Screen Studio chapters:

1. `chapter-01-setup`
2. `chapter-02-install`
3. `chapter-03-create-quest`
4. `chapter-04-trigger-and-verify`

Use a clean Chrome Demo profile, 125–150% browser zoom, 18–20 pt terminal text, Focus mode, hidden Dock and no personal notifications. The API key field must be outside the captured frame or permanently masked before recording.

## 9. DaVinci Resolve timeline and export

Timeline tracks:

```text
V1  Screen recordings
V2  Slides and overlays
A1  Voiceover
A2  Optional low-volume music
A3  Interface sounds, if required
```

Build the timeline after the live capture so narration matches actual timing. Accelerate long waits to 8x or 16x and label them `90 seconds later` when needed.

Audio targets:

- convert working audio to 48 kHz;
- voice around −14 LUFS integrated;
- true peak no higher than −1 dBTP;
- music approximately 20 dB below voice or omitted;
- natural pauses between sentences.

Exports:

```text
xsolla-quest-demo-final.mp4   H.264, 1920x1080, 60 fps, 16–20 Mbps, AAC 320 kbps
xsolla-quest-demo-master.mov  ProRes 422, 1920x1080, 60 fps
xsolla-quest-demo.srt         English subtitles
```

## 10. Security and retention

- Never expose a complete API key, Authorization header, cookie, clipboard or private wallet secret.
- Mask full wallet addresses, email addresses and complete user IDs.
- Do not put source audio, VoiceStudio profiles, raw recordings, DaVinci projects, environment files or temporary screenshots in Git.
- Configure shell history before recording and clear old terminal output before each chapter.
- Revoke a demo-only API key after the run if one was created.
- Check VoiceStudio, model and tokenizer licenses before public release.
- If the voice clone is published, disclose that the voiceover uses a clone of the author's voice.

## 11. Evidence and acceptance criteria

Update `/Users/raufaliyev/GolandProjects/quest-skill-e2e/progress.md` with:

```text
run_id
catalog item name
catalog SKU
catalog project
quest ID
event name
event ID
qp-data execution
issue_reward status
transaction hash
token ID
Backpack item name
```

The demo is complete only when:

- the Backpack item appears in the opening hook and final proof;
- the catalog item and availability are visible;
- Toolkit installation and `quest-setup` are visible;
- the reward uses a verified SKU and explicit catalog project;
- the quest is active;
- the collector returns HTTP 200 and `event_id`;
- qp-data reports `issue_reward = COMPLETED`;
- the explorer confirms the transaction;
- Backpack confirms delivery;
- only one event was sent;
- no secret is visible in any frame or artifact;
- slides match the approved visual system;
- voiceover and subtitles are readable and synchronized;
- final MP4 plays from start to finish.

## 12. Out of scope

- Production service changes.
- Reusing an ambiguous reward event.
- Mocked stage responses.
- Publicly storing credentials, voice profiles or raw recordings.
- Building a reusable video editor or generalized automation framework.
- Adding Keynote or HyperFrames unless the first DaVinci pass proves they are necessary.
