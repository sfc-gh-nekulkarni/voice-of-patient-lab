# Voice of the Patient — Dev Day HCLS AI Lab

A hands-on Snowflake lab where participants turn **raw clinical-visit audio** into an AI pipeline that catches a missed cancer signal — using `AI_TRANSCRIBE`, Cortex AISQL functions, a semantic view, Cortex Search, a Cortex Agent, and a Streamlit app. Participants build it by pasting prompts into **Cortex Code in Snowsight**.

**The story:** Sarah Chen (P007), 41, a never-smoker, reported coughing up blood, weight loss, and a worsening cough — attributed to asthma. Her lung cancer was diagnosed 208 days later. The lab shows AI reading every visit and flagging the signal a busy clinic missed.

---

## What's in this repo

| Path | What it is | What it does |
|------|-----------|--------------|
| **`audio/`** | 16 synthetic clinical-visit recordings (`.mp3`), named `V###_P###_Name.mp3` | The lab's raw input. `setup.sql` copies these from this repo into a Snowflake stage; participants transcribe them in Prompt/Challenge 2. **Path-critical — do not rename or move.** |
| **`streamlit/streamlit_app.py`** | The clinician worklist Streamlit-in-Snowflake app | Deployed by the Streamlit prompt: risk-ranked worklist, Sarah Chen's timeline, and a follow-up write-back button. **Path-critical — do not rename or move.** |
| **`setup.sql`** | One-time setup script (run as ACCOUNTADMIN) | Creates the warehouse, database, schema, and SSE stage; loads the 8 source tables; and pulls the 16 MP3s from this repo into the stage via a Git integration. Run once, top to bottom. Builds **only the foundation** — not the AI objects. |
| **`prompts.md`** | The **code version** — 5 prescriptive prompts containing exact SQL | For a scripted demo. Includes a deterministic safety net so the story always lands (Sarah = **EMERGENT**, fixed risk tiers). Model: `claude-sonnet-4-5`. |
| **`prompts_nl.md`** | The **natural-language version** — 8 plain-English prompts | The primary participant track. Cortex Code authors the SQL from intent; the AI judges risk freely (no override, so Sarah typically lands **URGENT + missed signal**). Model: `claude-opus-4-8`. |
| **`verify.sql`** | Acceptance checks for the **code version** | 11 data assertions (incl. Sarah = EMERGENT and the 1/5/10 tiers) + 4 object-existence checks. Every row should read `PASS`. |
| **`verify_nl.sql`** | Acceptance checks for the **natural-language version** | 8 structural assertions (row counts, valid `URGENCY` enum, no nulls, search match, objects exist) — does not pin risk tiers, so it is always green. Plus an informational view of the AI's tiering. |
| **`lab_guide.md`** | Instructor + participant guide | Run order, prerequisites, architecture diagram, the two-version comparison, the reliability design, and teardown. |
| **`README.md`** | This file | Repo overview. |

---

## How to run the lab

1. **Setup (once, ACCOUNTADMIN):** open `setup.sql` in a Snowsight worksheet and Run All. Confirm the final check rows all read `OK`.
2. **Build (Cortex Code):** paste the prompts from `prompts_nl.md` (natural-language) **or** `prompts.md` (code) in order. Each prompt self-verifies.
3. **Explore:** open the `CLINICAL_WORKLIST` Streamlit app and the *Clinical Signal Intelligence* agent in Snowsight.
4. **Grade (optional):** run `verify_nl.sql` (or `verify.sql` for the code version).

> Prerequisites: each participant needs their **own Snowflake account**, **ACCOUNTADMIN**, and a region with Cortex AI functions (validated on **AWS us-west-2**; `AI_TRANSCRIBE` + the Claude models must be available).

---

## Two prompt versions

| | `prompts.md` (code) | `prompts_nl.md` (natural language) |
|---|---|---|
| Prompts | 5, exact SQL | 8, plain English |
| Model | `claude-sonnet-4-5` | `claude-opus-4-8` |
| Risk engine | Model + deterministic safety-net floor | Model decides, no override |
| Sarah Chen | Always **EMERGENT** | Typically **URGENT + missed signal** |
| Best for | A scripted demo where the EMERGENT beat must land | Showcasing Cortex Code authoring from intent |

Both versions share `setup.sql` and produce the same object names, so an account can run either.

---

## If you move or fork this repo

Three things in `setup.sql` are wired to this repo's location, plus one path in the Streamlit prompt. Update them if the owner/name/branch changes:

- `API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-nekulkarni')`
- `ORIGIN = 'https://github.com/sfc-gh-nekulkarni/voice-of-patient-lab.git'`
- the `COPY FILES ... FROM @...LAB_REPO/branches/main/audio/` path (and the matching `streamlit/` path in the Streamlit prompt)

**Path-critical folders:** `audio/` and `streamlit/` must keep their names and locations. All `.md` and `verify*.sql` files are documentation and can be reorganized freely.
