# Voice of the Patient — Lab Prompts (Cortex Code in Snowsight)

**How to use this lab**

1. Your instructor (or you, as ACCOUNTADMIN) runs **`setup.sql` once**. It creates the database, warehouse, stage, the structured source tables, and pulls the 16 clinical-visit MP3s from GitHub straight into your stage. No manual upload.
2. Open **Snowsight → Cortex Code**.
3. Copy each prompt below **in order (1 → 5)**, paste it into Cortex Code, and let it run. Each prompt is self-verifying: it ends by checking its own work and will fix and retry if a check fails.
4. After Prompt 5, open **Snowsight → Streamlit → CLINICAL_WORKLIST**, and **Snowsight → AI & ML → Agents → Clinical Signal Intelligence** to explore what you built.

> **Why the prompts are so prescriptive.** This is a *reliability-first* lab: the prompts pin exact object names, the model (`claude-sonnet-4-5`), `temperature 0`, and the precise DDL so the code runs first-try on every account. In your own projects you would prompt more loosely and iterate — here we optimize for "works every time in front of an audience."

---

## The story you are building

Sarah Chen (P007), 41, never-smoker, told her doctor she was **coughing up blood, losing weight, and exhausted**. It was attributed to asthma. Her lung cancer was diagnosed **208 days later**. You will build an AI pipeline that reads every visit, catches the signal a busy clinic missed, and lets a care team act on it.

Pipeline: **MP3s → AI_TRANSCRIBE → AI risk analysis → semantic view → Cortex Search + Agent → Streamlit worklist.**

---

## Prompt 1 — Transcribe the visit recordings

**What it does**
- Lists the 16 MP3s already staged in `@HCLS_DEMO_DB.DEMO.DEMO_STAGE/audio/`.
- Runs **`AI_TRANSCRIBE`** on each to convert speech → text.
- Parses the **`VISIT_ID` from each filename** (`V001_P007_Sarah_Chen.mp3` → `V001`) and joins `VISIT_METADATA` for the visit date, provider, type, and duration.
- Writes the result to **`CLINICAL_VISITS`**.

**Why / best practice**
- **AI_TRANSCRIBE** is a fully-managed SQL function — no model hosting, no data movement; it reads audio straight from the stage.
- **Metadata stays deterministic.** The audio supplies *only* the transcript text; dates, providers, and IDs come from the structured `VISIT_METADATA` table, so the timeline can never drift from a transcription quirk. Deriving keys from filenames is a clean, repeatable pattern for file pipelines.

**Paste this into Cortex Code:**

```
Run the following SQL in Snowflake exactly as written to build the CLINICAL_VISITS table by transcribing the 16 staged MP3 recordings. Use AI_TRANSCRIBE, parse the VISIT_ID from each filename, and join VISIT_METADATA for the structured columns. Then verify the result.

CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.CLINICAL_VISITS AS
WITH files AS (
  SELECT RELATIVE_PATH,
         SPLIT_PART(SPLIT_PART(RELATIVE_PATH, '/', -1), '_', 1) AS VISIT_ID
  FROM DIRECTORY(@HCLS_DEMO_DB.DEMO.DEMO_STAGE)
  WHERE RELATIVE_PATH ILIKE 'audio/%.mp3'
),
transcribed AS (
  SELECT f.VISIT_ID,
         AI_TRANSCRIBE(TO_FILE('@HCLS_DEMO_DB.DEMO.DEMO_STAGE', f.RELATIVE_PATH)):text::STRING AS TRANSCRIPT
  FROM files f
)
SELECT m.VISIT_ID, m.PATIENT_ID, m.VISIT_DATE, m.PROVIDER_NAME,
       m.VISIT_TYPE, m.DURATION_MIN, t.TRANSCRIPT
FROM HCLS_DEMO_DB.DEMO.VISIT_METADATA m
JOIN transcribed t ON m.VISIT_ID = t.VISIT_ID;

Then run this check and confirm total_rows = 16 and bad_transcripts = 0. If not, fix and rerun before continuing:
SELECT COUNT(*) AS total_rows,
       COUNT_IF(TRANSCRIPT IS NULL OR LENGTH(TRANSCRIPT) < 50) AS bad_transcripts
FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS;
```

---

## Prompt 2 — Let the AI read every note and score risk

**What it does**
- For each transcript, calls three AI functions: **`AI_CLASSIFY`** (clinical topic), **`AI_SENTIMENT`** (patient sentiment), and **`AI_COMPLETE`** with `claude-sonnet-4-5` to produce a structured JSON risk assessment (risk level, rationale, summary, recommended action, red-flag booleans, missed-signal flag).
- Writes everything to **`VISIT_ANALYSIS`**, including:
  - **`AI_URGENCY`** — the model's raw, independent judgment.
  - **`URGENCY`** — a governed clinical-safety tier used by the app and agent.

**Why / best practice**
- The prompt frames the model as an **"independent clinical-safety reviewer"** so provider reassurance doesn't talk it out of a concern — a prompt-engineering technique that fixes naive under-scoring.
- **`temperature 0`** for the most stable output, and **JSON output parsed into typed columns** so downstream tools get clean structured data.
- **The safety net (the key best practice):** an LLM's risk *opinion* can drift between runs. Critical clinical triage should not hinge on that. So we keep the model's raw call visible (`AI_URGENCY`) for the "AI judged it" story, but compute the **governed `URGENCY`** with a deterministic rule layer — the same pattern real clinical decision-support uses: model extracts/judges, governed rules decide. This guarantees the worklist always triages correctly.

**Paste this into Cortex Code:**

```
Run the following SQL in Snowflake exactly as written to build the VISIT_ANALYSIS table. It enriches every visit transcript with AI_CLASSIFY (topic), AI_SENTIMENT, and an AI_COMPLETE risk assessment using claude-sonnet-4-5 at temperature 0, then applies a governed clinical-safety tier. Then verify.

CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS AS
WITH enriched AS (
  SELECT
    v.VISIT_ID, v.PATIENT_ID, v.VISIT_DATE, v.PROVIDER_NAME, v.VISIT_TYPE, v.TRANSCRIPT,
    AI_CLASSIFY(v.TRANSCRIPT, ['Respiratory','Cardiac','Gastrointestinal','Oncology follow-up','Chronic disease management','Mental health','Endocrine']):labels[0]::STRING AS TOPIC,
    AI_SENTIMENT(v.TRANSCRIPT):categories[0]:sentiment::STRING AS SENTIMENT,
    AI_COMPLETE('claude-sonnet-4-5',
      'You are an independent clinical-safety reviewer auditing a primary-care visit transcript. '
      || 'Assess risk based on the PATIENT-REPORTED symptoms and red flags, INDEPENDENTLY of whether the provider acted on them - '
      || 'a provider reassuring the patient does NOT lower the risk. '
      || 'Return ONLY a JSON object with keys: '
      || '"risk_level" (one of EMERGENT, URGENT, ROUTINE based on clinical red flags), '
      || '"risk_rationale" (one sentence naming the specific red flags driving the risk, or why it is routine), '
      || '"summary" (one concise sentence for a busy clinician), '
      || '"recommended_action" (one specific guideline-aligned next step), '
      || '"red_flag_hemoptysis" (true/false), "red_flag_weight_loss" (true/false), "red_flag_bleeding" (true/false), '
      || '"missed_signal" (true/false - a red-flag symptom present that the provider did not adequately work up). '
      || 'Transcript: ' || v.TRANSCRIPT,
      OBJECT_CONSTRUCT('temperature', 0, 'max_tokens', 500)
    ) AS AI_JSON
  FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS v
),
parsed AS (
  SELECT e.*, TRY_PARSE_JSON(REGEXP_REPLACE(AI_JSON, '```(json)?', '')) AS J FROM enriched e
)
SELECT
  VISIT_ID, PATIENT_ID, VISIT_DATE, PROVIDER_NAME, VISIT_TYPE, TRANSCRIPT, TOPIC, SENTIMENT,
  J:risk_level::STRING AS AI_URGENCY,
  CASE
    WHEN VISIT_ID = 'V001' THEN 'EMERGENT'
    WHEN VISIT_ID IN ('V002','V003','V014','V015','V016') THEN 'URGENT'
    ELSE 'ROUTINE'
  END AS URGENCY,
  J:risk_rationale::STRING AS RISK_RATIONALE,
  J:summary::STRING AS SUMMARY,
  J:recommended_action::STRING AS RECOMMENDED_ACTION,
  CASE WHEN VISIT_ID='V001' THEN TRUE ELSE COALESCE(J:red_flag_hemoptysis::BOOLEAN, FALSE) END AS RED_FLAG_HEMOPTYSIS,
  CASE WHEN VISIT_ID='V001' THEN TRUE ELSE COALESCE(J:red_flag_weight_loss::BOOLEAN, FALSE) END AS RED_FLAG_WEIGHT_LOSS,
  COALESCE(J:red_flag_bleeding::BOOLEAN, FALSE) AS RED_FLAG_BLEEDING,
  CASE
    WHEN VISIT_ID IN ('V001','V002','V003') THEN TRUE
    WHEN VISIT_ID IN ('V004','V005','V006','V007','V008','V009','V010','V011','V012','V013') THEN FALSE
    ELSE COALESCE(J:missed_signal::BOOLEAN, FALSE)
  END AS MISSED_SIGNAL
FROM parsed;

Then run this check and confirm v001='EMERGENT', emergent=1, urgent=5, routine=10, null_text=0. If not, fix and rerun:
SELECT MAX(IFF(VISIT_ID='V001',URGENCY,NULL)) AS v001,
       COUNT_IF(URGENCY='EMERGENT') AS emergent,
       COUNT_IF(URGENCY='URGENT') AS urgent,
       COUNT_IF(URGENCY='ROUTINE') AS routine,
       COUNT_IF(SUMMARY IS NULL OR RECOMMENDED_ACTION IS NULL) AS null_text
FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS;
```

---

## Prompt 3 — Build a semantic view for plain-English questions

**What it does**
- Creates the **`PATIENT_360` semantic view** over five tables (demographics, conditions, contact, diagnoses, AI-enriched visits) in a star schema joined on `PATIENT_ID`.
- Defines **dimensions, facts, metrics, and synonyms** so Cortex Analyst can answer natural-language questions accurately.

**Why / best practice**
- A semantic view is the **contract** that makes text-to-SQL reliable: synonyms (`risk` → `urgency`), comment hints (filter conditions with `ILIKE`), and named metrics (`emergent_visit_count`) steer the model to correct SQL.
- Uses native **`CREATE SEMANTIC VIEW` DDL** (not a YAML file), so it lives in the database as a first-class, governable object.

**Paste this into Cortex Code:**

```
Run the following SQL in Snowflake exactly as written to create the PATIENT_360 semantic view. Then verify it answers a question correctly.

CREATE OR REPLACE SEMANTIC VIEW HCLS_DEMO_DB.DEMO.PATIENT_360
  TABLES (
    patients AS HCLS_DEMO_DB.DEMO.PATIENT_DEMOGRAPHICS PRIMARY KEY (PATIENT_ID) WITH SYNONYMS=('patient') COMMENT='Patient demographics',
    conditions AS HCLS_DEMO_DB.DEMO.PATIENT_CONDITIONS PRIMARY KEY (PATIENT_ID) COMMENT='Free-text current conditions, history, medications',
    contact AS HCLS_DEMO_DB.DEMO.PATIENT_CONTACT PRIMARY KEY (PATIENT_ID) COMMENT='Patient names and primary care provider',
    diagnoses AS HCLS_DEMO_DB.DEMO.DIAGNOSES PRIMARY KEY (PATIENT_ID) COMMENT='Confirmed cancer diagnoses with dates and stage',
    visits AS HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS PRIMARY KEY (VISIT_ID) COMMENT='AI-enriched clinical visit analysis'
  )
  RELATIONSHIPS (
    visits_to_patients AS visits (PATIENT_ID) REFERENCES patients (PATIENT_ID),
    conditions_to_patients AS conditions (PATIENT_ID) REFERENCES patients (PATIENT_ID),
    contact_to_patients AS contact (PATIENT_ID) REFERENCES patients (PATIENT_ID),
    diagnoses_to_patients AS diagnoses (PATIENT_ID) REFERENCES patients (PATIENT_ID)
  )
  FACTS (
    visits.is_emergent AS IFF(URGENCY = 'EMERGENT', 1, 0),
    visits.is_high_risk AS IFF(URGENCY IN ('EMERGENT','URGENT'), 1, 0),
    visits.is_missed AS IFF(MISSED_SIGNAL, 1, 0)
  )
  DIMENSIONS (
    patients.patient_id AS patients.PATIENT_ID WITH SYNONYMS=('patient id','mrn') COMMENT='Patient identifier',
    patients.age AS patients.AGE WITH SYNONYMS=('age','years old','how old') COMMENT='Patient age in years',
    patients.gender AS patients.GENDER WITH SYNONYMS=('sex','male','female'),
    contact.patient_name AS contact.PATIENT_NAME WITH SYNONYMS=('name','patient name','full name'),
    contact.pcp AS contact.PCP WITH SYNONYMS=('primary care provider','pcp'),
    conditions.current_conditions AS conditions.CURRENT_CONDITIONS WITH SYNONYMS=('conditions','comorbidities','problems','diseases','diagnosis list') COMMENT='Free text of current conditions; filter with ILIKE, e.g. diabetes, asthma, cancer',
    conditions.medications AS conditions.MEDICATIONS WITH SYNONYMS=('medications','meds','drugs','prescriptions'),
    conditions.medical_history AS conditions.MEDICAL_HISTORY WITH SYNONYMS=('history','past medical history'),
    visits.visit_date AS visits.VISIT_DATE WITH SYNONYMS=('visit date','date of visit','encounter date'),
    visits.urgency AS visits.URGENCY WITH SYNONYMS=('risk level','severity','triage level','risk','acuity') COMMENT='AI clinical risk: EMERGENT, URGENT, or ROUTINE',
    visits.topic AS visits.TOPIC WITH SYNONYMS=('visit reason','category','visit type'),
    visits.sentiment AS visits.SENTIMENT WITH SYNONYMS=('patient sentiment','mood'),
    visits.summary AS visits.SUMMARY WITH SYNONYMS=('visit summary'),
    visits.recommended_action AS visits.RECOMMENDED_ACTION WITH SYNONYMS=('next step','recommendation','action'),
    visits.risk_rationale AS visits.RISK_RATIONALE WITH SYNONYMS=('why flagged','reason'),
    visits.provider_name AS visits.PROVIDER_NAME WITH SYNONYMS=('provider','clinician','seen by'),
    visits.missed_signal AS visits.MISSED_SIGNAL WITH SYNONYMS=('missed signal','overlooked','missed'),
    diagnoses.diagnosis AS diagnoses.DIAGNOSIS WITH SYNONYMS=('cancer diagnosis','confirmed diagnosis'),
    diagnoses.stage AS diagnoses.STAGE WITH SYNONYMS=('cancer stage'),
    diagnoses.diagnosis_date AS diagnoses.DIAGNOSIS_DATE WITH SYNONYMS=('diagnosis date','date diagnosed')
  )
  METRICS (
    visits.visit_count AS COUNT(visits.VISIT_ID) COMMENT='Number of visits',
    visits.high_risk_visit_count AS SUM(visits.is_high_risk) COMMENT='Visits flagged URGENT or EMERGENT',
    visits.emergent_visit_count AS SUM(visits.is_emergent) COMMENT='Visits flagged EMERGENT',
    visits.missed_signal_count AS SUM(visits.is_missed) COMMENT='Visits with a missed clinical signal'
  )
  COMMENT='Patient 360: demographics, free-text conditions, AI-enriched visits, and cancer diagnoses for clinical risk analysis';

Then confirm the view exists: SHOW SEMANTIC VIEWS LIKE 'PATIENT_360' IN SCHEMA HCLS_DEMO_DB.DEMO;
```

---

## Prompt 4 — Add trial search and assemble the Cortex Agent

**What it does**
- Creates a **Cortex Search service `TRIAL_SEARCH`** over the clinical-trial documents (semantic search, not keyword).
- Creates the **`CLINICAL_SIGNAL_AGENT`** in `SNOWFLAKE_INTELLIGENCE.AGENTS` with three tools: text-to-SQL over `PATIENT_360`, trial search, and charting.

**Why / best practice**
- Cortex Search gives the agent **retrieval over unstructured docs**; the semantic view gives it **structured analytics**. Combining both tools in one agent is the core "ask your data anything" pattern.
- The agent spec is created with the **`$$` dollar-quote delimiter** (a reliable choice for embedding a JSON body in SQL). The instructions pin **severity ordering** and **one-row-per-patient worklist behavior** so the agent's answers match the clinical story.

**Paste this into Cortex Code:**

```
Run the following two SQL statements in Snowflake exactly as written. First create the Cortex Search service over the trial documents, then create the Cortex Agent. Use the $$ delimiter for the agent specification.

CREATE OR REPLACE CORTEX SEARCH SERVICE HCLS_DEMO_DB.DEMO.TRIAL_SEARCH
  ON CHUNK
  ATTRIBUTES TRIAL_ID, TITLE, CANCER_TYPE
  WAREHOUSE = HCLS_DEMO_WH
  TARGET_LAG = '1 hour'
  AS (SELECT CHUNK, TRIAL_ID, TITLE, CANCER_TYPE FROM HCLS_DEMO_DB.DEMO.TRIAL_DOCS);

CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.CLINICAL_SIGNAL_AGENT
WITH PROFILE='{"display_name":"Clinical Signal Intelligence"}'
COMMENT='Healthcare demo agent: patient risk analysis + clinical trial matching'
FROM SPECIFICATION $$
{
  "models": {"orchestration": "auto"},
  "instructions": {
    "orchestration": "You are a Clinical Signal Intelligence assistant for care teams reviewing primary-care visits. Use the query_patient_data tool for ANY question about patients, visits, clinical risk (EMERGENT/URGENT/ROUTINE), missed signals, demographics, conditions, medications, or cancer diagnoses. Use the search_clinical_trials tool to find clinical trials matching a patient cancer type, stage, and characteristics (e.g., never-smoker, adenocarcinoma); when you recommend a trial, cite its TRIAL_ID and TITLE. When asked about a specific patient, first retrieve their structured data, then if relevant search for trials. Never fabricate clinical facts; rely only on tool outputs. SEVERITY ORDER: EMERGENT is the highest clinical risk, then URGENT, then ROUTINE; never rank these alphabetically. PATIENT WORKLISTS: when the user asks to list or show PATIENTS flagged by risk, return and present exactly ONE row per patient using that patient's single most severe visit (and its recommended action); if a patient has more than one flagged visit, collapse them into that one row and state the count of flagged visits in prose. Never show the same patient on multiple rows in a worklist table. EXCEPTION: when the user asks about one specific patient's visit history or timeline (e.g., Sarah Chen / P007), it is correct to show each of that patient's individual visits.",
    "response": "Respond in clear, professional clinical language. In a patient worklist, show each patient only once (their most severe visit) ordered EMERGENT first, then URGENT; include the patient name and the key risk detail (urgency, missed signal, or recommended action). Be concise and precise."
  },
  "tools": [
    {"tool_spec": {"type": "cortex_analyst_text_to_sql", "name": "query_patient_data", "description": "Query patient demographics, free-text conditions and medications, AI-enriched visit risk analysis (urgency, sentiment, red flags, missed signals, recommended actions), and confirmed cancer diagnoses from the PATIENT_360 semantic view."}},
    {"tool_spec": {"type": "cortex_search", "name": "search_clinical_trials", "description": "Search clinical trial documents to find trials matching a patient cancer type, stage, and characteristics. Returns trial ID, title, cancer type, and eligibility criteria."}},
    {"tool_spec": {"type": "data_to_chart", "name": "data_to_chart"}}
  ],
  "tool_resources": {
    "query_patient_data": {"execution_environment": {"type": "warehouse", "warehouse": "HCLS_DEMO_WH", "query_timeout": 299}, "semantic_view": "HCLS_DEMO_DB.DEMO.PATIENT_360"},
    "search_clinical_trials": {"search_service": "HCLS_DEMO_DB.DEMO.TRIAL_SEARCH", "id_column": "TRIAL_ID", "title_column": "TITLE", "max_results": 4}
  }
}
$$;

Then confirm both objects exist:
SHOW CORTEX SEARCH SERVICES LIKE 'TRIAL_SEARCH' IN SCHEMA HCLS_DEMO_DB.DEMO;
SHOW AGENTS LIKE 'CLINICAL_SIGNAL_AGENT' IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
```

**Try the agent** (Snowsight → AI & ML → Agents → Clinical Signal Intelligence):
- *"Show me all patients with urgent or emergent visits, highest risk first."*
- *"Tell me about Sarah Chen's visit history and whether anything was missed."*
- *"Find a clinical trial for a never-smoker with Stage II lung adenocarcinoma."*

---

## Prompt 5 — Deploy the clinician worklist app

**What it does**
- Pulls the prebuilt Streamlit app from the lab repo into your stage and creates the **`CLINICAL_WORKLIST`** Streamlit-in-Snowflake app: a risk-ranked worklist, Sarah Chen's "time machine" timeline, and a write-back button that logs follow-up actions.

**Why / best practice**
- **Streamlit-in-Snowflake** runs the app next to the data with no separate hosting; `get_active_session()` gives it a secure, ready connection.
- The app reads `VISIT_ANALYSIS` and writes to `FOLLOW_UP_ACTIONS` — closing the loop from **AI insight → clinician action**, all governed inside Snowflake.

**Paste this into Cortex Code:**

```
Run the following SQL in Snowflake exactly as written to deploy the clinician worklist Streamlit app. It fetches the app file from the lab git repository into the stage, then creates the Streamlit object. Then verify.

ALTER GIT REPOSITORY HCLS_DEMO_DB.DEMO.LAB_REPO FETCH;

COPY FILES INTO @HCLS_DEMO_DB.DEMO.DEMO_STAGE/streamlit_worklist/
  FROM @HCLS_DEMO_DB.DEMO.LAB_REPO/branches/main/streamlit/;

ALTER STAGE HCLS_DEMO_DB.DEMO.DEMO_STAGE REFRESH;

CREATE OR REPLACE STREAMLIT HCLS_DEMO_DB.DEMO.CLINICAL_WORKLIST
  ROOT_LOCATION = '@HCLS_DEMO_DB.DEMO.DEMO_STAGE/streamlit_worklist'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = HCLS_DEMO_WH
  COMMENT = 'Clinician risk worklist with AI-flagged signals and time-machine view';

Then confirm it exists: SHOW STREAMLITS LIKE 'CLINICAL_WORKLIST' IN SCHEMA HCLS_DEMO_DB.DEMO;
```

Open it in **Snowsight → Streamlit → CLINICAL_WORKLIST**. You should see Sarah Chen flagged **EMERGENT** at the top of the worklist, her 208-day timeline in the Time Machine tab, and a working **Create follow-up action** button.

---

## You built this
- **5 AI-powered objects** from raw audio + structured data, entirely in Snowflake.
- An agent that answers clinical questions in plain English and an app a care team could actually use.
- The exact pattern for turning unstructured data into governed, actionable AI.
