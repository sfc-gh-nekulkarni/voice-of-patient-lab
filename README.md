# Voice of the Patient: Developer Lab

A hands-on Snowflake lab where participants turn **raw clinical-visit audio** into an AI pipeline that catches a missed cancer signal: using `AI_TRANSCRIBE`, Cortex AISQL functions, a semantic view, Cortex Search, a Cortex Agent, and a Streamlit app. Participants build it by pasting prompts into **Cortex Code in Snowsight**.

**The story:** Sarah Chen (P007), 41, a never-smoker, reported coughing up blood, weight loss, and a worsening cough: attributed to asthma. Her lung cancer was diagnosed 208 days later. The lab shows AI reading every visit and flagging the signal a busy clinic missed.

---

## What's in this repo

| Path | What it is | What it does |
|------|-----------|--------------|
| **`audio/`** | 16 synthetic clinical-visit recordings (`.mp3`), named `V###_P###_Name.mp3` | The lab's raw input. `setup.sql` copies these from this repo into a Snowflake stage; participants transcribe them in Prompt/Challenge 2. |
| **`streamlit/streamlit_app.py`** | The clinician worklist Streamlit-in-Snowflake app | Deployed by the Streamlit prompt: risk-ranked worklist, Sarah Chen's timeline, and a follow-up write-back button. |
| **`setup.sql`** | One-time setup script (run as ACCOUNTADMIN) | Creates the warehouse, database, schema, and SSE stage; loads the 8 source tables; and pulls the 16 MP3s from this repo into the stage via a Git integration. Run once. |
| **`prompts.md`** | The **code version** — 5 prescriptive prompts containing exact SQL | For a scripted demo. Includes a deterministic safety net. |
| **`prompts.md`** | The **natural-language version** — 8 plain-English prompts | The primary participant track. Cortex Code authors the SQL from intent. |
| **`verify.sql`** | Acceptance checks for the **code version** | 11 data assertions (incl. Sarah = EMERGENT and the 1/5/10 tiers) + 4 object-existence checks. Every row should read `PASS`. |
| **`verify_nl.sql`** | Acceptance checks for the **natural-language version** | 8 structural assertions (row counts, valid `URGENCY` enum, no nulls, search match, objects exist) — does not pin risk tiers, so it is always green. Plus an informational view of the AI's tiering. |
| **`README.md`** | This file | Repo overview. |

---

## How to run the lab

1. **Setup (once, ACCOUNTADMIN):** open `setup.sql` in a Snowsight worksheet and Run All. Confirm the final check rows all read `OK`.
2. **Build (Cortex Code):** paste the prompts from `prompts_nl.md` (natural-language) **or** `prompts.md` (code) in order. Each prompt self-verifies.
3. **Explore:** open the `CLINICAL_WORKLIST` Streamlit app and the *Clinical Signal Intelligence* agent in Snowsight.
4. **Grade (optional):** run `verify_nl.sql` (or `verify.sql` for the code version).

> Prerequisites: each participant needs their **own Snowflake account**, **ACCOUNTADMIN**, and a region with Cortex AI functions (validated on **AWS us-west-2**; `AI_TRANSCRIBE` + the Claude models must be available).
