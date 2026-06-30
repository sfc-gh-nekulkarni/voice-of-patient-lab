-- =====================================================================================
--  VOICE OF THE PATIENT — HCLS AI LAB  |  ACCEPTANCE VERIFICATION
-- =====================================================================================
--  Run AFTER all 5 prompts. PART 1 returns one row per check; every RESULT must be PASS.
--  PART 2 confirms the AI objects exist (SHOW returns >=1 row each).
-- =====================================================================================

-- ── PART 1: data assertions (every row must read PASS) ───────────────────────────────
SELECT * FROM (
  SELECT 1 AS seq, 'Setup: 16 MP3s in stage' AS check_name,
         IFF(COUNT(*)=16,'PASS','FAIL') AS result
  FROM DIRECTORY(@HCLS_DEMO_DB.DEMO.DEMO_STAGE) WHERE RELATIVE_PATH ILIKE 'audio/%.mp3'
  UNION ALL SELECT 2, 'Setup: VISIT_METADATA = 16 rows',
         IFF(COUNT(*)=16,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.VISIT_METADATA
  UNION ALL SELECT 3, 'Setup: TRIAL_DOCS = 4 rows',
         IFF(COUNT(*)=4,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.TRIAL_DOCS
  UNION ALL SELECT 4, 'Prompt 1: CLINICAL_VISITS = 16 rows',
         IFF(COUNT(*)=16,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS
  UNION ALL SELECT 5, 'Prompt 1: no empty transcripts',
         IFF(COUNT_IF(TRANSCRIPT IS NULL OR LENGTH(TRANSCRIPT)<50)=0,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.CLINICAL_VISITS
  UNION ALL SELECT 6, 'Prompt 2: VISIT_ANALYSIS = 16 rows',
         IFF(COUNT(*)=16,'PASS','FAIL') FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 7, 'Prompt 2: Sarah V001 = EMERGENT',
         IFF(MAX(IFF(VISIT_ID='V001',URGENCY,NULL))='EMERGENT','PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 8, 'Prompt 2: tiers 1 EMERGENT / 5 URGENT / 10 ROUTINE',
         IFF(COUNT_IF(URGENCY='EMERGENT')=1 AND COUNT_IF(URGENCY='URGENT')=5
             AND COUNT_IF(URGENCY='ROUTINE')=10,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 9, 'Prompt 2: model returned valid JSON for all 16 (AI_URGENCY not null)',
         IFF(COUNT_IF(AI_URGENCY IS NULL)=0,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 10, 'Prompt 2: P007 has 3 missed signals',
         IFF(COUNT_IF(PATIENT_ID='P007' AND MISSED_SIGNAL)=3,'PASS','FAIL')
         FROM HCLS_DEMO_DB.DEMO.VISIT_ANALYSIS
  UNION ALL SELECT 11, 'Prompt 4: TRIAL_SEARCH top match for P007 profile = NCT05120000',
         IFF(PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW('HCLS_DEMO_DB.DEMO.TRIAL_SEARCH',
              '{"query":"never-smoker stage II lung adenocarcinoma EGFR targeted therapy trial","columns":["TRIAL_ID"],"limit":1}'))
              :results[0]:TRIAL_ID::STRING='NCT05120000','PASS','FAIL')
) t
ORDER BY seq;

-- ── PART 2: object existence (each SHOW should return exactly one row) ────────────────
SHOW SEMANTIC VIEWS LIKE 'PATIENT_360' IN SCHEMA HCLS_DEMO_DB.DEMO;
SHOW CORTEX SEARCH SERVICES LIKE 'TRIAL_SEARCH' IN SCHEMA HCLS_DEMO_DB.DEMO;
SHOW AGENTS LIKE 'CLINICAL_SIGNAL_AGENT' IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
SHOW STREAMLITS LIKE 'CLINICAL_WORKLIST' IN SCHEMA HCLS_DEMO_DB.DEMO;
