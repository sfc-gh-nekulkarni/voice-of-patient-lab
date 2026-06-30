# Voice of the Patient — HCLS AI Lab (Instructor + Participant Guide)

A hands-on Snowflake lab where participants turn **raw clinical-visit audio** into an AI pipeline that catches a missed cancer signal — using AI_TRANSCRIBE, Cortex AISQL functions, a semantic view, Cortex Search, a Cortex Agent, and a Streamlit app. Participants build it by pasting **5 copy-paste prompts** into **Cortex Code in Snowsight**.

---

## What's in this repo / folder

| File | Audience | Purpose |
|------|----------|---------|
| `setup.sql` | **Instructor / each participant (once)** | Provisions DB, warehouse, stage, structured tables, and pulls the 16 MP3s from GitHub into the stage. Run once, top to bottom. **Shared by both prompt versions.** |
| `prompts.md` | **Participants (code version)** | The **5 tight, code-first** prompts. Guarantees the full story including **Sarah = EMERGENT** via a deterministic safety net. |
| `prompts_nl.md` | **Participants (natural-language version)** | The **8 plain-English** prompts. Cortex Code authors the SQL from intent; the AI judges risk freely (**no override** — Sarah typically lands URGENT). |
| `verify.sql` | **Instructor (code version)** | Acceptance gate — 11 data checks (incl. Sarah=EMERGENT, 1/5/10 tiers) + 4 object checks. |
| `verify_nl.sql` | **Instructor (NL version)** | Structural acceptance — 8 checks (counts, valid enum, no nulls, search match, objects). Does **not** pin risk tiers. |
| `streamlit_app.py` | reference | The worklist app the Streamlit prompt deploys (hosted in the repo's `streamlit/` folder). |
| `audio/` (in GitHub repo) | reference | The 16 synthetic clinical-visit MP3s. |

### Two prompt versions — pick one

| | `prompts.md` (code) | `prompts_nl.md` (natural language) |
|---|---|---|
| **Prompts** | 5, contain exact SQL | 8, plain English (Cortex Code writes the SQL) |
| **Model** | `claude-sonnet-4-5` | `claude-opus-4-8` |
| **Risk engine** | Model judges + **deterministic safety-net floor** | Model judges, **no override** |
| **Sarah Chen** | Always **EMERGENT** (guaranteed) | Typically **URGENT + missed signal** (model's call) |
| **Guarantee** | Zero-touch, first-try, story always lands | Generated code runs clean; risk tiers reflect the model |
| **Best for** | A scripted demo where the EMERGENT beat must land | Showcasing Cortex Code authoring from intent |

Both versions use the same `setup.sql` and produce the same object names, so an account can run either (or one then the other — every build statement is `CREATE OR REPLACE`).

> **GitHub repo (audio + app):** `https://github.com/sfc-gh-nekulkarni/voice-of-patient-lab`
> ⚠️ This is a **test repo under a personal Snowflake GitHub identity**. Before the event, move/fork it to the official org and update the two references in `setup.sql` (`API_ALLOWED_PREFIXES` and the `ORIGIN` URL) and the FETCH/COPY paths used by Prompt 5.

---

## Prerequisites (per participant)

- Their **own Snowflake account** (object names are hardcoded; one lab per account).
- **ACCOUNTADMIN** (needed to `CREATE API INTEGRATION` for the Git pull).
- A region with Cortex AI functions — validated on **AWS us-west-2**. `AI_TRANSCRIBE` + `claude-sonnet-4-5` must be available.

---

## Run order

1. **Setup (once):** open `setup.sql` in a Snowsight worksheet, Run All. Confirm the final verification rows all read `OK` (7 tables + 16 audio files).
2. **Build (Cortex Code):** open Snowsight → Cortex Code. Paste **Prompt 1 → 5** from `prompts.md` in order. Each prompt self-verifies.
3. **Explore:** Streamlit → `CLINICAL_WORKLIST`; AI & ML → Agents → *Clinical Signal Intelligence*.
4. **Grade (optional):** run `verify.sql` → all 11 PART 1 rows = `PASS`; all 4 PART 2 `SHOW`s return a row.

---

## What gets built

```
audio/*.mp3 ──AI_TRANSCRIBE──▶ CLINICAL_VISITS
                                     │  AI_CLASSIFY + AI_SENTIMENT + AI_COMPLETE (claude-sonnet-4-5)
                                     ▼
                              VISIT_ANALYSIS ──▶ PATIENT_360 (semantic view)
                                     │                       │
TRIAL_DOCS ──Cortex Search──▶ TRIAL_SEARCH                   ▼
                                     └────────▶ CLINICAL_SIGNAL_AGENT (Snowflake Intelligence)
                                                              │
                              VISIT_ANALYSIS ──▶ CLINICAL_WORKLIST (Streamlit-in-Snowflake)
```

| Object | Built by | Type |
|--------|----------|------|
| `PATIENT_DEMOGRAPHICS`, `PATIENT_CONDITIONS`, `PROVIDERS`, `DIAGNOSES`, `PATIENT_CONTACT`, `VISIT_METADATA`, `TRIAL_DOCS`, `FOLLOW_UP_ACTIONS` | `setup.sql` | Tables |
| 16 MP3s in `@DEMO_STAGE/audio/` | `setup.sql` (Git → stage) | Stage files |
| `CLINICAL_VISITS` | Prompt 1 | Table (from AI_TRANSCRIBE) |
| `VISIT_ANALYSIS` | Prompt 2 | Table (AISQL + safety net) |
| `PATIENT_360` | Prompt 3 | Semantic view |
| `TRIAL_SEARCH` | Prompt 4 | Cortex Search service |
| `CLINICAL_SIGNAL_AGENT` | Prompt 4 | Cortex Agent |
| `CLINICAL_WORKLIST` | Prompt 5 | Streamlit app |

---

## The reliability design (why this "always works")

This lab is engineered for a **zero-touch, first-try, every-time** demo, despite using LLMs:

1. **Deterministic metadata.** Audio supplies only transcript *text*; `VISIT_ID` is parsed from the filename and all dates/providers come from `VISIT_METADATA`. The timeline can't drift.
2. **Trust-the-model + safety net.** `VISIT_ANALYSIS.AI_URGENCY` is the model's raw, independent judgment (the "AI read the note" story). `VISIT_ANALYSIS.URGENCY` is a **governed clinical-safety tier** computed by deterministic rules, so the worklist triage and the Sarah-EMERGENT beat land every run — even though, in testing, the raw model scored V001 as *URGENT* (the floor corrected it to *EMERGENT*).
3. **Tight prompts.** Each prompt pins exact object names, the model, `temperature 0`, and the precise DDL, and ends with a **self-verification** step so Cortex Code fixes and retries before moving on.
4. **Repo-hosted app.** Prompt 5 deploys a proven `streamlit_app.py` from the repo rather than asking the model to regenerate 200 lines of UI — the least-deterministic step is removed.

---

## The story (for the presenter)

Sarah Chen (P007), 41, never-smoker, reported **hemoptysis, ~8 lb weight loss, and a worsening cough**. It was attributed to asthma across three visits. Her **Stage II lung adenocarcinoma** was diagnosed **208 days** after the first red-flag visit. The lab shows AI reading every visit and flagging Sarah's first visit **EMERGENT** — the signal a busy clinic missed.

---

## Teardown

```sql
DROP DATABASE IF EXISTS HCLS_DEMO_DB;
DROP AGENT IF EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS.CLINICAL_SIGNAL_AGENT;
DROP API INTEGRATION IF EXISTS HCLS_LAB_GIT_API;
DROP WAREHOUSE IF EXISTS HCLS_DEMO_WH;
```
