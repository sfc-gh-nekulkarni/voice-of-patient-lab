# Voice of the Patient — Lab Prompts (NATURAL-LANGUAGE version, Cortex Code in Snowsight)

**How to use this lab**

1. Your instructor (or you, as ACCOUNTADMIN) runs **`setup.sql` once**. It creates the database, warehouse, stage, the structured source tables, and pulls the 16 clinical-visit MP3s from GitHub straight into your stage. No manual upload.
2. Open **Snowsight → Cortex Code**.
3. Copy each prompt below **in order (1 → 8)**, paste it into Cortex Code, and let it work. These are **plain-English prompts** — Cortex Code writes and runs the SQL for you. Every prompt ends by telling Cortex Code to **test its own work and fix any error before stopping**.
4. After Prompt 8, explore your worklist app and your agent in Snowsight.

> **How this version differs from the code version.** Here you describe *what you want in plain English* and let Cortex Code author the SQL. The prompts are deliberately **explicit** (they name exact databases, schemas, tables, columns, the model, and temperature) and each one **self-verifies**, so the generated code runs without errors. The AI makes its own clinical risk judgments — there is **no hardcoded override** — so the exact risk tiers reflect the model's reasoning on the day.

---

## The story you are building

Sarah Chen (P007), 41, a never-smoker, told her doctor she was **coughing up blood, losing weight, and exhausted**. It was attributed to asthma. Her lung cancer was diagnosed **208 days later**. You will build an AI pipeline that reads every visit transcript, flags the dangerous ones a busy clinic can miss, answers questions in plain English, and surfaces it all in a clinician worklist.

Pipeline: **MP3s → AI_TRANSCRIBE → AI risk analysis → semantic view → Cortex Search + Agent → Streamlit worklist.**

> **A note on what "high risk" means.** The AI weighs every visit independently. It tends to reserve the single **EMERGENT** label for the most acutely life-threatening visit (an actively decompensating patient), and flags Sarah Chen's lung-cancer warning signs as **URGENT with a "missed signal"**. Either way, the AI catches the visit the clinic dismissed — that is the point.

---

## Prompt 1 — Orient: confirm the foundation is ready

**What it does**
- Has Cortex Code look at your `HCLS_DEMO_DB.DEMO` schema and the staged audio so it understands the data it will work with.

**Why / best practice**
- Giving the assistant a quick **tour of the real schema first** grounds every later prompt in the actual table and column names, which dramatically reduces hallucinated SQL.
- It also confirms `setup.sql` succeeded before you build anything on top of it.

**Paste this into Cortex Code:**

```
I'm working in the Snowflake database HCLS_DEMO_DB, schema DEMO. Please orient yourself before we build a healthcare AI lab:
1. List all tables in HCLS_DEMO_DB.DEMO and, for each, show its columns and a few sample rows.
2. List the files in the stage HCLS_DEMO_DB.DEMO.DEMO_STAGE under the audio/ folder.
Then confirm in plain language that you can see: the 16 patient-visit MP3 files in the stage, and these tables — PATIENT_DEMOGRAPHICS, PATIENT_CONDITIONS, PROVIDERS, DIAGNOSES, PATIENT_CONTACT, VISIT_METADATA, TRIAL_DOCS, and FOLLOW_UP_ACTIONS. If any of these are missing, stop and tell me exactly what is missing rather than continuing.
```

---

## Prompt 2 — Transcribe the visit recordings

**What it does**
- Turns the 16 staged MP3 recordings into text using Snowflake's `AI_TRANSCRIBE`, and assembles a `CLINICAL_VISITS` table that pairs each transcript with its visit details.

**Why / best practice**
- `AI_TRANSCRIBE` is a fully-managed function that reads audio straight from the stage — no model hosting, no data movement.
- **Keep the structured columns deterministic:** the audio supplies only the transcript text; the visit's date, provider, type, and duration come from the existing `VISIT_METADATA` table, joined on a visit ID that you parse from the file name. Deriving the key from the file name (`V001_P007_Sarah_Chen.mp3` → `V001`) is a clean, repeatable file-pipeline pattern.

**Paste this into Cortex Code:**

```
Create a table HCLS_DEMO_DB.DEMO.CLINICAL_VISITS by transcribing the visit audio. Requirements:
- Read every .mp3 file in the audio/ folder of stage HCLS_DEMO_DB.DEMO.DEMO_STAGE.
- Use Snowflake's AI_TRANSCRIBE function (with TO_FILE) to transcribe each recording to text; take the "text" field of the result as the transcript.
- Each file is named like V001_P007_Sarah_Chen.mp3. Parse the visit id (the part before the first underscore, e.g. V001) from the file name.
- Join to the existing table HCLS_DEMO_DB.DEMO.VISIT_METADATA on that visit id to bring in PATIENT_ID, VISIT_DATE, PROVIDER_NAME, VISIT_TYPE, and DURATION_MIN. The audio should supply ONLY the transcript text; all other columns come from VISIT_METADATA.
- Final columns: VISIT_ID, PATIENT_ID, VISIT_DATE, PROVIDER_NAME, VISIT_TYPE, DURATION_MIN, TRANSCRIPT.
After creating it, TEST your work: confirm the table has exactly 16 rows and that no transcript is null or shorter than 50 characters. If the test fails or any statement errors, correct your SQL and re-run until it passes. Then show me 2 sample transcripts.
```

---

## Prompt 3 — Let the AI read every note and score risk

**What it does**
- For each transcript, classifies the clinical topic, scores patient sentiment, and asks a Claude model to return a structured risk assessment (risk level, rationale, summary, recommended action, red-flag flags, missed-signal flag). Writes it all to `VISIT_ANALYSIS`.

**Why / best practice**
- Uses three Cortex AISQL functions together: **`AI_CLASSIFY`** (topic), **`AI_SENTIMENT`** (sentiment), and **`AI_COMPLETE`** (the structured risk read).
- Framing the model as an **"independent clinical-safety reviewer"** and telling it that provider reassurance does **not** lower risk is a prompt-engineering technique that prevents the AI from being "talked out of" a concern.
- Asking for **JSON output at `temperature 0`** and parsing it into typed columns gives clean, structured data for the semantic view, agent, and app downstream.

**Paste this into Cortex Code:**

```
Create a table HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS that enriches every row of HCLS_DEMO_DB.DEMO.CLINICAL_VISITS with AI. For each visit:
- TOPIC: use AI_CLASSIFY on the transcript to pick the best single clinical topic from this list: Respiratory, Cardiac, Gastrointestinal, Oncology follow-up, Chronic disease management, Mental health, Endocrine.
- SENTIMENT: use AI_SENTIMENT on the transcript and take the overall sentiment.
- Use AI_COMPLETE with the model 'claude-opus-4-8' at temperature 0 to return ONLY a JSON object with these keys: risk_level (one of EMERGENT, URGENT, ROUTINE), risk_rationale (one sentence), summary (one concise sentence for a busy clinician), recommended_action (one specific guideline-aligned next step), red_flag_hemoptysis (true/false), red_flag_weight_loss (true/false), red_flag_bleeding (true/false), missed_signal (true/false — a red-flag symptom the provider did not adequately work up). In the prompt, instruct the model to act as an independent clinical-safety reviewer assessing risk from the PATIENT-REPORTED symptoms regardless of whether the provider acted on them, because provider reassurance does not lower risk.
- Parse the JSON safely (strip any markdown code fences first, then use TRY_PARSE_JSON) into these typed columns: URGENCY (string, from risk_level), RISK_RATIONALE, SUMMARY, RECOMMENDED_ACTION (strings), RED_FLAG_HEMOPTYSIS, RED_FLAG_WEIGHT_LOSS, RED_FLAG_BLEEDING, MISSED_SIGNAL (booleans, default false if missing).
- Keep these passthrough columns from CLINICAL_VISITS: VISIT_ID, PATIENT_ID, VISIT_DATE, PROVIDER_NAME, VISIT_TYPE, TRANSCRIPT, plus TOPIC and SENTIMENT.
After creating it, TEST your work: confirm 16 rows, that URGENCY is never null and is always one of EMERGENT/URGENT/ROUTINE, and that SUMMARY and RECOMMENDED_ACTION are never null. If anything fails or errors, fix your SQL and re-run until it passes. Then show me the visit id, patient, urgency, and one-line summary for every row, highest risk first.
```

---

## Prompt 4 — Build a semantic view for plain-English questions

**What it does**
- Creates the `PATIENT_360` semantic view over five tables (demographics, conditions, contact, diagnoses, AI-enriched visits) so an agent can answer natural-language questions accurately.

**Why / best practice**
- A semantic view is the **contract** that makes text-to-SQL reliable: it defines how the tables join (a star schema on `PATIENT_ID`), adds **synonyms** (so "risk" maps to urgency), and names **metrics** the agent can reference directly.
- It is a native, governable database object — not a config file floating outside the database.

**Paste this into Cortex Code:**

```
Create a Snowflake semantic view named HCLS_DEMO_DB.DEMO.PATIENT_360 for natural-language analytics over our patient data. Include these tables, all joined on PATIENT_ID in a star schema with PATIENT_DEMOGRAPHICS at the center:
- HCLS_DEMO_DB.DEMO.PATIENT_DEMOGRAPHICS (primary key PATIENT_ID) — dimensions: PATIENT_ID, AGE, GENDER.
- HCLS_DEMO_DB.DEMO.PATIENT_CONTACT (primary key PATIENT_ID) — dimensions: PATIENT_NAME (synonyms: name, patient name), PCP.
- HCLS_DEMO_DB.DEMO.PATIENT_CONDITIONS (primary key PATIENT_ID) — dimensions: CURRENT_CONDITIONS (synonyms: conditions, comorbidities; note in a comment that it is free text to filter with ILIKE), MEDICATIONS, MEDICAL_HISTORY.
- HCLS_DEMO_DB.DEMO.DIAGNOSES (primary key PATIENT_ID) — dimensions: DIAGNOSIS, STAGE, DIAGNOSIS_DATE.
- HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS (primary key VISIT_ID) — dimensions: VISIT_DATE, URGENCY (synonyms: risk level, severity, risk; comment that values are EMERGENT, URGENT, ROUTINE), TOPIC, SENTIMENT, SUMMARY, RECOMMENDED_ACTION, RISK_RATIONALE, PROVIDER_NAME, MISSED_SIGNAL.
Add metrics over the visits table: visit_count (count of VISIT_ID), high_risk_visit_count (count where URGENCY is EMERGENT or URGENT), emergent_visit_count (count where URGENCY = EMERGENT), and missed_signal_count (count where MISSED_SIGNAL is true).
After creating it, TEST your work: confirm the semantic view exists, and fix and re-run if the create statement errors. Then show me that it answers this question correctly by querying it: "How many visits are flagged urgent or emergent?"
```

---

## Prompt 5 — Add semantic search over clinical trials

**What it does**
- Creates a Cortex Search service, `TRIAL_SEARCH`, over the `TRIAL_DOCS` table so the agent can find relevant clinical trials by meaning, not keywords.

**Why / best practice**
- Cortex Search gives the agent **retrieval over unstructured documents** — the complement to the semantic view's structured analytics.
- Point the service at the warehouse `HCLS_DEMO_WH` and index the document text column so matches are semantic.

**Paste this into Cortex Code:**

```
Create a Cortex Search service named HCLS_DEMO_DB.DEMO.TRIAL_SEARCH over the table HCLS_DEMO_DB.DEMO.TRIAL_DOCS. Search on the CHUNK column (the trial document text). Include TRIAL_ID, TITLE, and CANCER_TYPE as returnable attributes. Use warehouse HCLS_DEMO_WH and a target lag of 1 hour.
After creating it, TEST it: wait a few seconds for indexing, then query the service for "never-smoker stage II lung adenocarcinoma EGFR targeted therapy trial" and confirm it returns a lung-cancer trial (trial id NCT05120000) as the top match. If the service errors or returns nothing on the first try, wait and retry once before reporting the result.
```

---

## Prompt 6 — Assemble the Cortex Agent

**What it does**
- Creates the `CLINICAL_SIGNAL_AGENT` in `SNOWFLAKE_INTELLIGENCE.AGENTS`, wiring in two tools: text-to-SQL over `PATIENT_360` and trial search over `TRIAL_SEARCH`.

**Why / best practice**
- Combining **structured analytics (semantic view)** and **document retrieval (search)** in one agent is the core "ask your data anything" pattern.
- Clear tool descriptions and instructions — e.g., severity ordering and "one row per patient in a worklist" — make the agent's answers match the clinical story.

**Paste this into Cortex Code:**

```
Create a Snowflake Cortex Agent named SNOWFLAKE_INTELLIGENCE.AGENTS.CLINICAL_SIGNAL_AGENT with the display name "Clinical Signal Intelligence". Give it two tools:
1. A Cortex Analyst (text-to-SQL) tool named query_patient_data backed by the semantic view HCLS_DEMO_DB.DEMO.PATIENT_360, running on warehouse HCLS_DEMO_WH. Describe it as querying patient demographics, conditions, medications, AI-enriched visit risk analysis, and cancer diagnoses.
2. A Cortex Search tool named search_clinical_trials backed by the search service HCLS_DEMO_DB.DEMO.TRIAL_SEARCH, using TRIAL_ID as the id column and TITLE as the title column. Describe it as finding clinical trials that match a patient's cancer type, stage, and characteristics.
Instructions for the agent: use query_patient_data for any question about patients, visits, clinical risk (EMERGENT/URGENT/ROUTINE), missed signals, conditions, medications, or diagnoses; use search_clinical_trials to find matching trials and cite the trial id and title. Tell it that severity order is EMERGENT (highest), then URGENT, then ROUTINE — never alphabetical — and that when listing a patient worklist it should show each patient only once using their most severe visit, except when asked about one patient's visit history, where each visit should be shown. Tell it never to fabricate clinical facts and to rely only on tool outputs.
After creating it, TEST your work: confirm the agent exists (and describe it without error). If the create statement errors, fix and re-run. Then tell me 3 example questions I can ask it.
```

---

## Prompt 7 — Deploy the clinician worklist app

**What it does**
- Deploys the prebuilt Streamlit worklist app (risk-ranked patients, Sarah Chen's timeline, a write-back button) from the lab's GitHub repository into a Streamlit-in-Snowflake object.

**Why / best practice**
- The app file already lives in the lab repository, so we **deploy a known-good app** rather than regenerating UI code — the most reliable path to an error-free app.
- Streamlit-in-Snowflake runs the app next to the data; the included app reads `VISIT_ANALYSIS` and writes follow-ups to `FOLLOW_UP_ACTIONS`, closing the loop from AI insight to clinician action.

**Paste this into Cortex Code:**

```
Deploy a Streamlit-in-Snowflake app from our lab's git repository. Steps:
1. Fetch the latest from the existing git repository object HCLS_DEMO_DB.DEMO.LAB_REPO.
2. Copy the files from the repo's main branch streamlit/ folder into the stage HCLS_DEMO_DB.DEMO.DEMO_STAGE under a streamlit_worklist/ folder, then refresh the stage directory.
3. Confirm the file streamlit_app.py is now present in the stage under streamlit_worklist/.
4. Create a Streamlit object named HCLS_DEMO_DB.DEMO.CLINICAL_WORKLIST with root location pointing at that streamlit_worklist/ folder in the stage, main file streamlit_app.py, and query warehouse HCLS_DEMO_WH.
After creating it, TEST your work: confirm the Streamlit object exists. If any step errors, fix it and re-run. Then give me the path in Snowsight to open the app.
```

---

## Prompt 8 — Verify everything and explore

**What it does**
- Runs a final set of checks confirming every object built correctly, then suggests questions to try against your agent.

**Why / best practice**
- A single **end-to-end verification** is the fastest way to confirm the whole lab is healthy before you present or explore.
- It separates structural success (objects exist, row counts right) from the AI's clinical judgments (which you will explore interactively).

**Paste this into Cortex Code:**

```
Run a final verification of the lab and report a simple pass/fail for each check:
1. HCLS_DEMO_DB.DEMO.CLINICAL_VISITS has 16 rows and no empty transcripts.
2. HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS has 16 rows, URGENCY is always EMERGENT/URGENT/ROUTINE, and SUMMARY is never null.
3. The semantic view HCLS_DEMO_DB.DEMO.PATIENT_360 exists.
4. The Cortex Search service HCLS_DEMO_DB.DEMO.TRIAL_SEARCH exists and returns NCT05120000 for a never-smoker stage II lung adenocarcinoma query.
5. The agent SNOWFLAKE_INTELLIGENCE.AGENTS.CLINICAL_SIGNAL_AGENT exists.
6. The Streamlit app HCLS_DEMO_DB.DEMO.CLINICAL_WORKLIST exists.
Present the results as a table. If any check fails, tell me exactly which one and what to re-run.

Then, so I can explore, list the patients flagged URGENT or EMERGENT (one row per patient, highest risk first) by querying HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS joined to patient names, and suggest that I open the Clinical Signal Intelligence agent and ask: "Tell me about Sarah Chen's visit history and whether anything was missed," and "Find a clinical trial for a never-smoker with stage II lung adenocarcinoma."
```

---

## You built this
- **8 plain-English prompts** turned raw audio + structured data into a working AI pipeline, entirely in Snowflake — without writing a line of SQL yourself.
- An agent that answers clinical questions and an app a care team could actually use.
- The exact pattern for turning unstructured data into governed, actionable AI with Cortex Code.
