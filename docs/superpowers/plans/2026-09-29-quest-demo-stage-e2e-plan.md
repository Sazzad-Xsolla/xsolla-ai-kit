# Quest Demo Stage E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one fresh, unmocked stage run that connects a verified catalog SKU to an active quest, one real event, a completed reward execution, a blockchain transaction and a Backpack item.

**Architecture:** Keep the Publisher catalog project and Quest Platform project separate. Resolve the reward SKU from the stage catalog before creating the quest, then correlate one event ID through qp-data, the mint ledger, explorer and Backpack. Never retry an ambiguous reward event.

**Tech Stack:** Publisher Account UI, Codex terminal, stage QP APIs, stage event collector, qp-data, Web3 minting service, Backpack, curl, Python UUID generation.

**Spec:** `docs/superpowers/specs/2026-09-29-xsolla-quest-demo-design.md`

## Global Constraints

- Use QP merchant `940246`, project `316575` for the quest owner.
- Use Publisher catalog merchant `940463`, project `316665` for the reward item.
- The reward must use a SKU verified in the minting catalog and metadata endpoint.
- Send exactly one event with a fresh idempotency key.
- Do not use `load_test=true` for the event.
- Do not expose credentials, Authorization headers, wallet secrets or full user identifiers.
- Do not resend a reward event after a timeout; read first.
- Update `quest-skill-e2e/progress.md` with the final correlation evidence.

## Review Focus

- Catalog SKU missing from minting service: stop before quest creation and record the response.
- Quest reward points at the wrong catalog project: reject the readback before activation.
- Event timeout or duplicate acceptance: search by idempotency key and event ID before any action.
- qp-data execution is accepted but not completed: preserve evidence and do not claim success.
- Backpack item is absent after on-chain success: correlate wallet identity and token ID before proceeding.

### Task 1: Prepare a disposable run directory and read-only preflight

**Files:**
- Create outside Git: `$HOME/Movies/XsollaQuestDemo/$RUN_ID/stage/`
- Modify: `quest-skill-e2e/progress.md` by appending the run header only after the run ID is generated.

**Interfaces:**
- Produces: `RUN_ID`, `RUN_DIR`, the stage host variables and a clean evidence directory.

- [ ] **Step 1: Generate a run ID and local evidence directory**

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$HOME/Movies/XsollaQuestDemo/$RUN_ID"
mkdir -p "$RUN_DIR/stage" "$RUN_DIR/screenshots"
printf '%s\n' "$RUN_ID" > "$RUN_DIR/stage/run_id.txt"
```

- [ ] **Step 2: Verify read-only project access**

Run the configured project readback with the local protected credential and confirm HTTP 200. Do not print the credential or full response body in the recording.

Expected: QP project `940246/316575` is reachable and active.

- [ ] **Step 3: Verify the target Backpack session and wallet**

Read the current target user identity and wallet mapping without creating a reward.

Expected: the wallet resolves for the same user that will be used in the event.

- [ ] **Step 4: Record preflight results**

Write only status, timestamps and redacted identifiers to `$RUN_DIR/stage/preflight.md`.

### Task 2: Create and verify the catalog item

**Files:**
- Create: `$RUN_DIR/stage/catalog.md`
- Create: `$RUN_DIR/stage/catalog-response-redacted.json`

**Interfaces:**
- Consumes: Publisher Account catalog session.
- Produces: `CATALOG_SKU`, catalog item name, availability, metadata confirmation.

- [ ] **Step 1: Create a free ordinary virtual item in Publisher Account**

Use a generated name containing `RUN_ID`, set quantity to one, and save it as available. Do not choose a special Web3 item type.

- [ ] **Step 2: Read back the item and store redacted fields**

Expected fields: item name, SKU, available status and catalog project `316665`.

- [ ] **Step 3: Verify the minting catalog**

```bash
curl -sk "https://web3-minting-service.gcp-k8s-web3-stage.srv.local/skus?project=316665&limit=100"
```

Expected: the new SKU is present. If absent, stop and do not create the quest.

- [ ] **Step 4: Verify metadata**

```bash
curl -sk "https://web3-minting-service.gcp-k8s-web3-stage.srv.local/metadata/sku/$CATALOG_SKU?project=316665"
```

Expected: HTTP 200 with the item name and attributes. Save a redacted response.

### Task 3: Create and activate the disposable quest

**Files:**
- Create: `$RUN_DIR/stage/quest.md`
- Create: `$RUN_DIR/stage/quest-readback-redacted.json`

**Interfaces:**
- Consumes: `CATALOG_SKU`, catalog project `316665`, QP project `316575`.
- Produces: `QUEST_ID`, exact `EVENT_NAME`, active quest readback.

- [ ] **Step 1: Generate unique quest and event names**

```bash
EVENT_NAME="demo.quest.completed.$RUN_ID"
QUEST_NAME="Backpack Quest Demo $RUN_ID"
```

- [ ] **Step 2: Invoke `quest-setup` with the approved natural-language prompt**

The prompt must require exact event name matching, explicit catalog project `316665`, metadata verification, no SKU guessing and quantity one. It must request a concise summary instead of raw JSON.

- [ ] **Step 3: Read back the quest**

Expected: reward node contains `web3_item`, `project: "316665"`, the verified SKU and `quantity: 1`.

- [ ] **Step 4: Activate and read back status**

Expected: status is active, the event condition matches `EVENT_NAME`, and the activity window includes the current time.

- [ ] **Step 5: Wait for configuration caches**

Wait 60–90 seconds before sending the event. Record the wait in `$RUN_DIR/stage/quest.md`.

### Task 4: Send one event and verify the reward

**Files:**
- Create: `$RUN_DIR/stage/event.md`
- Create: `$RUN_DIR/stage/qp-data-redacted.json`
- Create: `$RUN_DIR/stage/explorer.md`
- Create: `$RUN_DIR/stage/backpack.md`

**Interfaces:**
- Consumes: `QUEST_ID`, `EVENT_NAME`, target `xsolla_id`, `CATALOG_SKU`.
- Produces: `EVENT_ID`, `EXECUTION_ID`, `TX_HASH`, `TOKEN_ID`, Backpack item proof.

- [ ] **Step 1: Generate one idempotency key**

```bash
IDEMPOTENCY_KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
```

Store it locally without printing credentials.

- [ ] **Step 2: Send exactly one real event**

Use the configured stage Basic event credential, exact `EVENT_NAME`, the QP publisher/project context and required `xsolla_id`. Do not include `load_test=true`.

Expected: HTTP 200 and a returned `event_id`.

- [ ] **Step 3: Handle an ambiguous response safely**

If the request times out or the response is incomplete, do not resend it. Search qp-data and the event readback using the idempotency key first.

- [ ] **Step 4: Verify qp-data execution**

Expected: the matching event has an `issue_reward` action with status `COMPLETED`, the same SKU and quantity one, plus a transaction hash.

- [ ] **Step 5: Verify the blockchain transaction**

Open the explorer for the transaction and record status, token transfer and token ID. Store shortened identifiers only.

- [ ] **Step 6: Verify Backpack**

Open Backpack for the same user and record item name, verification label and collection visibility.

### Task 5: Write the evidence record

**Files:**
- Modify: `quest-skill-e2e/progress.md`

- [ ] **Step 1: Append the correlation table**

Record `RUN_ID`, item name, SKU, catalog project, quest ID, event name, event ID, execution ID, `issue_reward` status, shortened transaction hash, token ID and Backpack item name.

- [ ] **Step 2: Check the final evidence for secrets**

Run a local scan over the new evidence files and remove any full key, Authorization header, cookie, wallet secret, email or complete user identifier before committing or using the evidence in the video.

- [ ] **Step 3: Commit only the intended evidence update if required**

```bash
git add quest-skill-e2e/progress.md
git commit -m "docs: record quest demo stage evidence"
```
