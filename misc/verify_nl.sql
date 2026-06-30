-- =====================================================================================
--  VOICE OF THE PATIENT — HCLS AI LAB (NATURAL-LANGUAGE version)  |  ACCEPTANCE VERIFY
-- =====================================================================================
--  Run AFTER all 8 prompts. PART 1 = structural assertions (every row must read PASS).
--  PART 2 = object existence (each SHOW returns >=1 row).
--  PART 3 = informational only (the AI's risk judgments — NOT pass/fail, since the
--           NL version lets the model decide tiers with no deterministic override).
-- =====================================================================================

-- ── PART 1: structural assertions (every row must read PASS) ─────────────────────────
SELECT * FROM (
  SELECT 1 AS seq, 'Setup: 16 MP3s in stage' AS check_name,
         IFF(COUNT(*)=16,'PASS','FAIL') AS result
  FROM DIRECTORY(@HCLS_DEMO_DB.DEMO.DEMO_STAGE) WHERE RELATIVE_PATH ILIKE 'audio/%.mp3'
  UNION ALL SELECT 2, 'Prompt 2: CLINICAL_VISITS = 16 rows',
         IFF(COUNT(*)=16,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS
  UNION ALL SELECT 3, 'Prompt 2: no empty transcripts',
         IFF(COUNT_IF(TRANSCRIPT IS NULL OR LENGTH(TRANSCRIPT)<50)=0,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS
  UNION ALL SELECT 4, 'Prompt 3: VISIT_ANALYSIS = 16 rows',
         IFF(COUNT(*)=16,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 5, 'Prompt 3: URGENCY always valid (EMERGENT/URGENT/ROUTINE, no null)',
         IFF(COUNT_IF(URGENCY IS NULL OR URGENCY NOT IN ('EMERGENT','URGENT','ROUTINE'))=0,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 6, 'Prompt 3: SUMMARY + RECOMMENDED_ACTION never null',
         IFF(COUNT_IF(SUMMARY IS NULL OR RECOMMENDED_ACTION IS NULL)=0,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 7, 'Prompt 3: at least one high-risk (URGENT/EMERGENT) visit exists',
         IFF(COUNT_IF(URGENCY IN ('EMERGENT','URGENT'))>=1,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 8, 'Prompt 5: TRIAL_SEARCH top match for lung profile = NCT05120000',
         IFF(PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW('HCLS_DEMO_DB.DEMO.TRIAL_SEARCH',
              '{"query":"never-smoker stage II lung adenocarcinoma EGFR targeted therapy trial","columns":["TRIAL_ID"],"limit":1}'))
              :results[0]:TRIAL_ID::STRING='NCT05120000','PASS','FAIL')
) t
ORDER BY seq;

-- ── PART 2: object existence (each SHOW should return at least one row) ───────────────
SHOW SEMANTIC VIEWS LIKE 'PATIENT_360' IN SCHEMA HCLS_DEMO_DB.DEMO;
SHOW CORTEX SEARCH SERVICES LIKE 'TRIAL_SEARCH' IN SCHEMA HCLS_DEMO_DB.DEMO;
SHOW AGENTS LIKE 'CLINICAL_SIGNAL_AGENT' IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
SHOW STREAMLITS LIKE 'CLINICAL_WORKLIST' IN SCHEMA HCLS_DEMO_DB.DEMO;

-- ── PART 3: informational — the AI's clinical judgments (NOT pass/fail) ───────────────
-- Inspect how the model triaged this run. Sarah Chen (P007) is expected to be flagged
-- high-risk (URGENT or EMERGENT) with a missed signal; the single EMERGENT label may go
-- to the most acutely decompensating patient. This is the model's call, by design.
SELECT v.VISIT_ID, c.PATIENT_NAME, v.URGENCY, v.MISSED_SIGNAL, v.TOPIC
FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS v
JOIN HCLS_DEMO_DB.DEMO.PATIENT_CONTACT c ON v.PATIENT_ID=c.PATIENT_ID
WHERE v.URGENCY IN ('EMERGENT','URGENT')
ORDER BY CASE v.URGENCY WHEN 'EMERGENT' THEN 0 WHEN 'URGENT' THEN 1 ELSE 2 END, c.PATIENT_NAME;
