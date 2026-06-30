-- =====================================================================================
--  VOICE OF THE PATIENT — HCLS AI LAB  |  SETUP SCRIPT (run once, top to bottom)
-- =====================================================================================
--  WHAT THIS SCRIPT DOES
--    Provisions everything a lab participant needs BEFORE they start prompting:
--      * a dedicated warehouse, database, schema, and an SSE-encrypted stage
--      * the 5 structured "source of truth" tables (demographics, conditions,
--        providers, diagnoses, contact) + VISIT_METADATA + TRIAL_DOCS
--      * an empty FOLLOW_UP_ACTIONS table (write-back target for the Streamlit app)
--      * a GitHub Git integration that pulls the 16 clinical-visit MP3s straight
--        into the stage — NO manual upload required
--      * the SNOWFLAKE_INTELLIGENCE.AGENTS home schema (where the agent will live)
--
--  WHAT IT DOES *NOT* DO
--    It does not build CLINICAL_VISITS, VISIT_ANALYSIS, the semantic view, the
--    Cortex Search service, the agent, or the Streamlit app. Participants build
--    those by copy-pasting the 5 lab prompts into Cortex Code (Snowsight).
--
--  REQUIREMENTS
--    * Run as a role with ACCOUNTADMIN (needed to CREATE API INTEGRATION).
--    * Region with Cortex AI functions (e.g. AWS us-west-2). AI_TRANSCRIBE +
--      claude-sonnet-4-5 must be available.
--
--  IDEMPOTENT: every object uses CREATE [OR REPLACE | IF NOT EXISTS]; safe to re-run.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 0. COMPUTE + NAMESPACE
-- -------------------------------------------------------------------------------------
-- Dedicated XSMALL warehouse; auto-suspends after 60s so it costs nothing idle.
CREATE WAREHOUSE IF NOT EXISTS HCLS_DEMO_WH
  WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 AUTO_RESUME=TRUE INITIALLY_SUSPENDED=TRUE;
USE WAREHOUSE HCLS_DEMO_WH;

-- The lab database + schema. All lab objects live in HCLS_DEMO_DB.DEMO.
CREATE DATABASE IF NOT EXISTS HCLS_DEMO_DB;
CREATE SCHEMA   IF NOT EXISTS HCLS_DEMO_DB.DEMO;

-- Snowflake Intelligence requires agents to live in SNOWFLAKE_INTELLIGENCE.AGENTS.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;

-- SSE (server-side) encryption is REQUIRED for Cortex AI file functions like
-- AI_TRANSCRIBE to read staged audio. DIRECTORY=TRUE lets us list files in SQL.
CREATE STAGE IF NOT EXISTS HCLS_DEMO_DB.DEMO.DEMO_STAGE
  DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- -------------------------------------------------------------------------------------
-- 1. STRUCTURED SOURCE TABLES  (the deterministic "source of truth")
-- -------------------------------------------------------------------------------------
-- PATIENT_DEMOGRAPHICS — one row per patient (age, gender). 35 synthetic patients.
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.PATIENT_DEMOGRAPHICS (
  ROW_ID NUMBER, PATIENT_ID VARCHAR, AGE NUMBER, GENDER VARCHAR
);
INSERT INTO HCLS_DEMO_DB.DEMO.PATIENT_DEMOGRAPHICS VALUES
(0,'P001',45,'Female'),(1,'P002',62,'Male'),(2,'P003',34,'Female'),(3,'P004',71,'Male'),(4,'P005',28,'Female'),
(5,'P006',55,'Male'),(6,'P007',41,'Female'),(7,'P008',67,'Male'),(8,'P009',52,'Female'),(9,'P010',39,'Male'),
(10,'P011',58,'Female'),(11,'P012',44,'Male'),(12,'P013',63,'Female'),(13,'P014',29,'Male'),(14,'P015',76,'Female'),
(15,'P016',48,'Male'),(16,'P017',35,'Female'),(17,'P018',59,'Male'),(18,'P019',42,'Female'),(19,'P020',65,'Male'),
(20,'P021',33,'Female'),(21,'P022',54,'Male'),(22,'P023',47,'Female'),(23,'P024',69,'Male'),(24,'P025',31,'Female'),
(25,'P026',56,'Male'),(26,'P027',38,'Female'),(27,'P028',61,'Male'),(28,'P029',49,'Female'),(29,'P030',43,'Male'),
(30,'P031',37,'Female'),(31,'P032',72,'Male'),(32,'P033',26,'Female'),(33,'P034',58,'Male'),(34,'P035',64,'Female');

-- PATIENT_CONDITIONS — free-text history, current conditions, meds. $$-quoted (apostrophes).
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.PATIENT_CONDITIONS (
  ROW_ID NUMBER, PATIENT_ID VARCHAR, MEDICAL_HISTORY VARCHAR, CURRENT_CONDITIONS VARCHAR, MEDICATIONS VARCHAR
);
INSERT INTO HCLS_DEMO_DB.DEMO.PATIENT_CONDITIONS
SELECT 0,'P001',$$Hypertension diagnosed 2018, Type 2 diabetes since 2020, family history of heart disease$$,$$Type 2 diabetes mellitus, hypertension, mild depression$$,$$Metformin 500mg twice daily, Lisinopril 10mg daily, Sertraline 50mg daily$$
UNION ALL SELECT 1,'P002',$$Prostate cancer treated 2019, high cholesterol, previous smoker$$,$$Prostate cancer in remission, hyperlipidemia, chronic back pain$$,$$Atorvastatin 20mg daily, Ibuprofen 400mg as needed, Tamsulosin 0.4mg daily$$
UNION ALL SELECT 2,'P003',$$Breast cancer survivor, BRCA1 positive, anxiety disorder$$,$$Breast cancer in remission, generalized anxiety disorder, hypothyroidism$$,$$Levothyroxine 75mcg daily, Alprazolam 0.25mg as needed, Calcium supplement$$
UNION ALL SELECT 3,'P004',$$Alzheimer's disease early stage, hypertension, osteoarthritis$$,$$Alzheimer's disease mild cognitive impairment, hypertension, knee osteoarthritis$$,$$Donepezil 10mg daily, Amlodipine 5mg daily, Acetaminophen 500mg as needed$$
UNION ALL SELECT 4,'P005',$$Rheumatoid arthritis, no other significant history$$,$$Rheumatoid arthritis active, iron deficiency anemia$$,$$Methotrexate 15mg weekly, Folic acid 5mg daily, Iron sulfate 325mg daily$$
UNION ALL SELECT 5,'P006',$$Chronic kidney disease stage 3, diabetes type 2, hypertension$$,$$Chronic kidney disease stage 3, diabetic nephropathy, hypertension$$,$$Insulin glargine 20 units daily, Losartan 50mg daily, Sodium bicarbonate 650mg twice daily$$
UNION ALL SELECT 6,'P007',$$Lung cancer non-small cell, never smoker, asthma$$,$$Non-small cell lung cancer stage II, asthma$$,$$Carboplatin, Pemetrexed, Albuterol inhaler as needed, Prednisone 20mg daily$$
UNION ALL SELECT 7,'P008',$$Parkinson's disease, hypertension, previous stroke$$,$$Parkinson's disease with tremor, hypertension, history of ischemic stroke$$,$$Carbidopa-Levodopa 25/100mg three times daily, Metoprolol 50mg daily, Aspirin 81mg daily$$
UNION ALL SELECT 8,'P009',$$Multiple sclerosis relapsing-remitting, depression$$,$$Multiple sclerosis relapsing-remitting, major depressive disorder$$,$$Interferon beta-1a 30mcg weekly, Duloxetine 60mg daily, Vitamin D3 2000 IU daily$$
UNION ALL SELECT 9,'P010',$$Crohn's disease, no other conditions$$,$$Crohn's disease active moderate, vitamin B12 deficiency$$,$$Adalimumab 40mg every other week, Mesalamine 1g twice daily, Cyanocobalamin 1000mcg monthly$$
UNION ALL SELECT 10,'P011',$$Fibromyalgia, chronic fatigue syndrome, migraines$$,$$Fibromyalgia, chronic fatigue syndrome, migraine headaches$$,$$Pregabalin 150mg twice daily, Sumatriptan 50mg as needed, Magnesium supplement$$
UNION ALL SELECT 11,'P012',$$Psoriasis, psoriatic arthritis, no other conditions$$,$$Psoriasis moderate to severe, psoriatic arthritis$$,$$Etanercept 50mg weekly, Methotrexate 20mg weekly, Folic acid 5mg daily$$
UNION ALL SELECT 12,'P013',$$Ovarian cancer survivor, osteoporosis, hypothyroidism$$,$$Ovarian cancer in remission, osteoporosis, hypothyroidism$$,$$Alendronate 70mg weekly, Levothyroxine 100mcg daily, Calcium carbonate 1200mg daily$$
UNION ALL SELECT 13,'P014',$$Epilepsy, no other significant history$$,$$Epilepsy generalized tonic-clonic seizures, mild anxiety$$,$$Levetiracetam 1000mg twice daily, Lorazepam 0.5mg as needed$$
UNION ALL SELECT 14,'P015',$$Chronic obstructive pulmonary disease, former smoker, heart failure$$,$$COPD stage 3, heart failure with reduced ejection fraction$$,$$Tiotropium inhaler daily, Furosemide 40mg daily, Metoprolol 25mg twice daily$$
UNION ALL SELECT 15,'P016',$$Bipolar disorder, substance abuse history, liver disease$$,$$Bipolar disorder type I, alcohol use disorder in remission, fatty liver disease$$,$$Lithium 900mg daily, Naltrexone 50mg daily, Milk thistle supplement$$
UNION ALL SELECT 16,'P017',$$Endometriosis, polycystic ovary syndrome, insulin resistance$$,$$Endometriosis, polycystic ovary syndrome, prediabetes$$,$$Metformin 1000mg twice daily, Norethindrone 5mg daily, Inositol supplement$$
UNION ALL SELECT 17,'P018',$$Coronary artery disease, previous myocardial infarction, diabetes$$,$$Coronary artery disease with stents, type 2 diabetes, dyslipidemia$$,$$Clopidogrel 75mg daily, Atorvastatin 40mg daily, Insulin aspart with meals$$
UNION ALL SELECT 18,'P019',$$Systemic lupus erythematosus, kidney involvement, joint pain$$,$$Systemic lupus erythematosus, lupus nephritis, arthralgia$$,$$Hydroxychloroquine 400mg daily, Mycophenolate 1000mg twice daily, Prednisone 10mg daily$$
UNION ALL SELECT 19,'P020',$$Benign prostatic hyperplasia, sleep apnea, hypertension$$,$$Benign prostatic hyperplasia, obstructive sleep apnea, hypertension$$,$$Finasteride 5mg daily, CPAP therapy, Amlodipine 10mg daily$$
UNION ALL SELECT 20,'P021',$$Migraine headaches, anxiety disorder, no other conditions$$,$$Chronic migraine, generalized anxiety disorder, medication overuse headache$$,$$Topiramate 100mg twice daily, Escitalopram 10mg daily, Sumatriptan 50mg as needed$$
UNION ALL SELECT 21,'P022',$$Hypertension, high cholesterol, prediabetes$$,$$Hypertension, hyperlipidemia, prediabetes, sleep apnea$$,$$Losartan 100mg daily, Rosuvastatin 20mg daily, CPAP therapy$$
UNION ALL SELECT 22,'P023',$$Hypothyroidism, polycystic ovary syndrome, infertility$$,$$Hypothyroidism, polycystic ovary syndrome, insulin resistance$$,$$Levothyroxine 125mcg daily, Metformin 1000mg twice daily, Clomiphene citrate as needed$$
UNION ALL SELECT 23,'P024',$$Chronic kidney disease stage 4, diabetes, heart failure$$,$$Chronic kidney disease stage 4, diabetic nephropathy, heart failure with preserved ejection fraction$$,$$Insulin detemir 35 units daily, Furosemide 80mg daily, Losartan 25mg daily$$
UNION ALL SELECT 24,'P025',$$Juvenile idiopathic arthritis, uveitis, no other conditions$$,$$Juvenile idiopathic arthritis, chronic anterior uveitis, mild anemia$$,$$Methotrexate 25mg weekly, Prednisolone eye drops, Folic acid 5mg daily$$
UNION ALL SELECT 25,'P026',$$Atrial fibrillation, heart failure, chronic kidney disease$$,$$Atrial fibrillation, heart failure with reduced ejection fraction, chronic kidney disease stage 3$$,$$Warfarin 5mg daily, Metoprolol 100mg twice daily, Furosemide 40mg daily$$
UNION ALL SELECT 26,'P027',$$Asthma, allergic rhinitis, eczema$$,$$Asthma moderate persistent, allergic rhinitis, atopic dermatitis$$,$$Fluticasone inhaler twice daily, Montelukast 10mg daily, Cetirizine 10mg daily$$
UNION ALL SELECT 27,'P028',$$Prostate cancer, radiation therapy, urinary incontinence$$,$$Prostate cancer post-radiation, stress urinary incontinence, erectile dysfunction$$,$$Sildenafil 50mg as needed, Oxybutynin 5mg twice daily, Pelvic floor exercises$$
UNION ALL SELECT 28,'P029',$$Osteoporosis, vitamin D deficiency, hypothyroidism$$,$$Osteoporosis, vitamin D deficiency, hypothyroidism, chronic low back pain$$,$$Alendronate 70mg weekly, Vitamin D3 4000 IU daily, Levothyroxine 88mcg daily$$
UNION ALL SELECT 29,'P030',$$Gastroesophageal reflux disease, peptic ulcer disease, H. pylori$$,$$Gastroesophageal reflux disease, peptic ulcer disease treated, mild dyspepsia$$,$$Omeprazole 40mg daily, Sucralfate 1g four times daily, Probiotics$$
UNION ALL SELECT 30,'P031',$$Systemic sclerosis, Raynaud's phenomenon, pulmonary fibrosis$$,$$Systemic sclerosis limited cutaneous, Raynaud's phenomenon, interstitial lung disease$$,$$Mycophenolate 1000mg twice daily, Nifedipine 30mg daily, Sildenafil 20mg three times daily$$
UNION ALL SELECT 31,'P032',$$Benign prostatic hyperplasia, diabetes, neuropathy$$,$$Benign prostatic hyperplasia, type 2 diabetes, diabetic peripheral neuropathy$$,$$Tamsulosin 0.4mg daily, Metformin 1000mg twice daily, Gabapentin 300mg three times daily$$
UNION ALL SELECT 32,'P033',$$Celiac disease, iron deficiency anemia, osteopenia$$,$$Celiac disease, iron deficiency anemia, osteopenia, vitamin B12 deficiency$$,$$Iron sulfate 325mg daily, Cyanocobalamin 1000mcg monthly, Calcium carbonate 1200mg daily$$
UNION ALL SELECT 33,'P034',$$Chronic obstructive pulmonary disease, former smoker, anxiety$$,$$COPD stage 2, chronic bronchitis, generalized anxiety disorder$$,$$Tiotropium inhaler daily, Albuterol inhaler as needed, Buspirone 10mg twice daily$$
UNION ALL SELECT 34,'P035',$$Breast cancer, chemotherapy, neuropathy$$,$$Breast cancer stage IIIA, chemotherapy-induced peripheral neuropathy, lymphedema$$,$$Capecitabine 1000mg twice daily, Duloxetine 30mg daily, Compression garments$$;

-- PROVIDERS — clinicians + panel size (large panels = WHY signals get missed: volume).
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.PROVIDERS (
  PROVIDER_NAME VARCHAR, SPECIALTY VARCHAR, PANEL_SIZE NUMBER
);
INSERT INTO HCLS_DEMO_DB.DEMO.PROVIDERS VALUES
('Dr. James Okafor','Internal Medicine',2200),
('Dr. Robert Hayes','Family Medicine',2400),
('Dr. Emily Tran','Pulmonology',900),
('Dr. Lisa Park','Oncology',650),
('Dr. Mark Sullivan','Cardiology',1100),
('Dr. Anita Desai','Gastroenterology',850);

-- DIAGNOSES — confirmed cancers = "ground truth". P007 dx date is 208 days after V001.
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.DIAGNOSES (
  PATIENT_ID VARCHAR, DIAGNOSIS VARCHAR, DIAGNOSIS_DATE DATE, STAGE VARCHAR, DIAGNOSING_PROVIDER VARCHAR
);
INSERT INTO HCLS_DEMO_DB.DEMO.DIAGNOSES VALUES
('P007','Non-small cell lung cancer (adenocarcinoma)','2026-06-08','Stage II','Dr. Lisa Park'),
('P035','Breast cancer','2025-09-15','Stage IIIA','Dr. Lisa Park'),
('P013','Ovarian cancer','2021-03-22','Stage IC (in remission)','Dr. Lisa Park'),
('P003','Breast cancer','2020-07-10','Stage I (in remission)','Dr. Lisa Park'),
('P002','Prostate cancer','2019-05-30','Stage II (in remission)','Dr. Lisa Park'),
('P028','Prostate cancer','2022-11-02','Stage II (post-radiation)','Dr. Lisa Park');

-- PATIENT_CONTACT — names + PCP. Names let the worklist show real identities, not IDs.
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.PATIENT_CONTACT (
  PATIENT_ID VARCHAR, PATIENT_NAME VARCHAR, PHONE VARCHAR, EMAIL VARCHAR, PCP VARCHAR
);
INSERT INTO HCLS_DEMO_DB.DEMO.PATIENT_CONTACT (PATIENT_ID, PATIENT_NAME, PHONE, EMAIL, PCP) VALUES
('P001','Maria Alvarez','415-555-0101','maria.alvarez@example.com','Dr. James Okafor'),
('P002','Robert Feldman','415-555-0102','robert.feldman@example.com','Dr. Robert Hayes'),
('P003','Aisha Bennett','415-555-0103','aisha.bennett@example.com','Dr. James Okafor'),
('P004','Walter Greene','415-555-0104','walter.greene@example.com','Dr. Robert Hayes'),
('P005','Chloe Nguyen','415-555-0105','chloe.nguyen@example.com','Dr. James Okafor'),
('P006','Darnell Washington','415-555-0106','darnell.washington@example.com','Dr. Robert Hayes'),
('P007','Sarah Chen','415-555-0107','sarah.chen@example.com','Dr. James Okafor'),
('P008','Frank Russo','415-555-0108','frank.russo@example.com','Dr. Robert Hayes'),
('P009','Beatrice Lowe','415-555-0109','beatrice.lowe@example.com','Dr. James Okafor'),
('P010','Andre Silva','415-555-0110','andre.silva@example.com','Dr. Anita Desai'),
('P011','Diane Kowalski','415-555-0111','diane.kowalski@example.com','Dr. Robert Hayes'),
('P012','Marcus Tate','415-555-0112','marcus.tate@example.com','Dr. James Okafor'),
('P013','Eleanor Pratt','415-555-0113','eleanor.pratt@example.com','Dr. Lisa Park'),
('P014','Tyler Brooks','415-555-0114','tyler.brooks@example.com','Dr. Robert Hayes'),
('P015','Gloria Mendez','415-555-0115','gloria.mendez@example.com','Dr. Emily Tran'),
('P016','Sean Halloran','415-555-0116','sean.halloran@example.com','Dr. James Okafor'),
('P017','Priya Nair','415-555-0117','priya.nair@example.com','Dr. Robert Hayes'),
('P018','Victor Castillo','415-555-0118','victor.castillo@example.com','Dr. Mark Sullivan'),
('P019','Hannah Weiss','415-555-0119','hannah.weiss@example.com','Dr. James Okafor'),
('P020','Earl Jacobs','415-555-0120','earl.jacobs@example.com','Dr. Robert Hayes'),
('P021','Jasmine Cole','415-555-0121','jasmine.cole@example.com','Dr. James Okafor'),
('P022','Daniel Brooks','415-555-0122','daniel.brooks@example.com','Dr. Robert Hayes'),
('P023','Renee Park','415-555-0123','renee.park@example.com','Dr. James Okafor'),
('P024','Howard Klein','415-555-0124','howard.klein@example.com','Dr. Robert Hayes'),
('P025','Lucia Romano','415-555-0125','lucia.romano@example.com','Dr. James Okafor'),
('P026','Gerald Pierce','415-555-0126','gerald.pierce@example.com','Dr. Mark Sullivan'),
('P027','Tanya Robinson','415-555-0127','tanya.robinson@example.com','Dr. James Okafor'),
('P028','Calvin Ford','415-555-0128','calvin.ford@example.com','Dr. Lisa Park'),
('P029','Margaret Doyle','415-555-0129','margaret.doyle@example.com','Dr. Robert Hayes'),
('P030','Nathan Cole','415-555-0130','nathan.cole@example.com','Dr. Anita Desai'),
('P031','Olivia Marsh','415-555-0131','olivia.marsh@example.com','Dr. Emily Tran'),
('P032','Albert Ramsey','415-555-0132','albert.ramsey@example.com','Dr. Robert Hayes'),
('P033','Sophie Adler','415-555-0133','sophie.adler@example.com','Dr. Anita Desai'),
('P034','Raymond Brooks','415-555-0134','raymond.brooks@example.com','Dr. Emily Tran'),
('P035','Vivian Holt','415-555-0135','vivian.holt@example.com','Dr. Lisa Park');

-- VISIT_METADATA — the deterministic structured columns for each visit. The audio
-- supplies ONLY the transcript text; these 6 fields (date, provider, type, duration)
-- come from here so dates/IDs/timeline can never drift. Joined by VISIT_ID, which the
-- transcription prompt parses from each MP3 filename (V001_P007_Sarah_Chen.mp3 -> V001).
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.VISIT_METADATA (
  VISIT_ID VARCHAR, PATIENT_ID VARCHAR, VISIT_DATE DATE, PROVIDER_NAME VARCHAR,
  VISIT_TYPE VARCHAR, DURATION_MIN NUMBER
);
INSERT INTO HCLS_DEMO_DB.DEMO.VISIT_METADATA VALUES
('V001','P007','2025-11-12','Dr. James Okafor','Sick Visit',12),
('V002','P007','2025-12-18','Dr. James Okafor','Sick Visit',10),
('V003','P007','2026-02-20','Dr. James Okafor','Follow-up',11),
('V004','P001','2026-05-20','Dr. James Okafor','Routine',15),
('V005','P004','2026-05-21','Dr. Robert Hayes','Follow-up',15),
('V006','P011','2026-05-22','Dr. Robert Hayes','Follow-up',12),
('V007','P012','2026-05-26','Dr. James Okafor','Follow-up',10),
('V008','P017','2026-05-27','Dr. Robert Hayes','Routine',13),
('V009','P020','2026-05-28','Dr. Robert Hayes','Routine',12),
('V010','P027','2026-05-29','Dr. James Okafor','Routine',11),
('V011','P029','2026-06-01','Dr. Robert Hayes','Follow-up',12),
('V012','P032','2026-06-03','Dr. Robert Hayes','Follow-up',13),
('V013','P003','2026-06-05','Dr. James Okafor','Routine',14),
('V014','P022','2026-06-05','Dr. Robert Hayes','Sick Visit',13),
('V015','P026','2026-06-02','Dr. Mark Sullivan','Follow-up',14),
('V016','P010','2026-06-04','Dr. Anita Desai','Sick Visit',12);

-- TRIAL_DOCS — clinical-trial documents for the Cortex Search beat. The top match for
-- P007 (never-smoker, EGFR-likely adenocarcinoma, Stage II) is NCT05120000 (osimertinib).
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.TRIAL_DOCS (
  TRIAL_ID VARCHAR, TITLE VARCHAR, CANCER_TYPE VARCHAR, CHUNK VARCHAR
);
INSERT INTO HCLS_DEMO_DB.DEMO.TRIAL_DOCS (TRIAL_ID, TITLE, CANCER_TYPE, CHUNK)
SELECT 'NCT05120000', 'Phase III Trial of Osimertinib-Based Therapy in Resected Stage IB-IIIA EGFR-Mutated Non-Small Cell Lung Cancer (ADAURA-NEXT)', 'Lung (NSCLC adenocarcinoma)',
$$ADAURA-NEXT (NCT05120000) is a Phase III, randomized, double-blind trial evaluating adjuvant osimertinib, a third-generation EGFR tyrosine kinase inhibitor, in patients with completely resected Stage IB to IIIA non-small cell lung cancer (NSCLC) of adenocarcinoma histology harboring an EGFR exon 19 deletion or L858R mutation. ELIGIBILITY: adults 18 years or older; confirmed NSCLC adenocarcinoma, Stage IB-IIIA; EGFR-activating mutation; ECOG performance status 0-1; prior complete surgical resection permitted; never-smokers and former light smokers are eligible and represent the majority of EGFR-mutated cases. Patients on platinum-doublet adjuvant chemotherapy such as carboplatin plus pemetrexed may enroll after completion. INTERVENTION: oral osimertinib 80 mg once daily for up to 3 years versus placebo. PRIMARY ENDPOINT: disease-free survival. This trial is particularly relevant for younger never-smoker women with adenocarcinoma, a population enriched for EGFR mutations. Participating sites include UCSF Helen Diller Comprehensive Cancer Center (San Francisco, CA), Stanford Cancer Institute, and Memorial Sloan Kettering.$$
UNION ALL SELECT 'NCT05240111', 'Phase II Study of Pembrolizumab Plus Chemotherapy in PD-L1 Positive Stage II-III Non-Small Cell Lung Cancer', 'Lung (NSCLC)',
$$NCT05240111 is a Phase II open-label study of pembrolizumab combined with platinum-based chemotherapy in patients with Stage II-III non-small cell lung cancer expressing PD-L1 (TPS >= 1%). ELIGIBILITY: adults with histologically confirmed NSCLC (adenocarcinoma or squamous), Stage II-IIIA, measurable disease, ECOG 0-1, no prior immunotherapy. Smokers and never-smokers eligible. INTERVENTION: pembrolizumab 200 mg IV every 3 weeks plus carboplatin and pemetrexed for 4 cycles, followed by pembrolizumab maintenance. PRIMARY ENDPOINT: objective response rate and progression-free survival. Sites: UCSF, Kaiser Permanente Northern California, City of Hope.$$
UNION ALL SELECT 'NCT05330222', 'Phase III Adjuvant Therapy Trial in Stage III Colon Cancer (COLON-FORWARD)', 'Colorectal',
$$COLON-FORWARD (NCT05330222) is a Phase III randomized trial of adjuvant FOLFOX chemotherapy with or without a novel checkpoint inhibitor in patients with resected Stage III colon cancer. ELIGIBILITY: adults 18+, pathologically confirmed Stage III colon adenocarcinoma after curative-intent resection, ECOG 0-1. INTERVENTION: standard FOLFOX versus FOLFOX plus investigational agent. PRIMARY ENDPOINT: 3-year disease-free survival. Sites: UCSF, Stanford, Sutter Health.$$
UNION ALL SELECT 'NCT05410333', 'Phase III Trial of CDK4/6 Inhibitor in HR-Positive HER2-Negative Early Breast Cancer', 'Breast',
$$NCT05410333 is a Phase III trial evaluating adjuvant CDK4/6 inhibitor abemaciclib plus endocrine therapy in hormone-receptor-positive, HER2-negative early-stage breast cancer at high risk of recurrence (including Stage IIIA). ELIGIBILITY: adults with HR+/HER2- breast cancer, node-positive or high-risk, ECOG 0-1, completed primary surgery. INTERVENTION: abemaciclib 150 mg twice daily plus standard endocrine therapy for 2 years. PRIMARY ENDPOINT: invasive disease-free survival. Sites: UCSF, MD Anderson, Dana-Farber.$$;

-- FOLLOW_UP_ACTIONS — empty write-back target. The Streamlit app inserts rows here when
-- a clinician logs a follow-up from the worklist.
CREATE OR REPLACE TABLE HCLS_DEMO_DB.DEMO.FOLLOW_UP_ACTIONS (
  ACTION_ID NUMBER AUTOINCREMENT START 1 INCREMENT 1,
  PATIENT_ID VARCHAR, VISIT_ID VARCHAR, ACTION_TEXT VARCHAR,
  CREATED_BY VARCHAR, CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------------------------------------
-- 2. LOAD THE 16 CLINICAL-VISIT MP3s FROM GITHUB INTO THE STAGE  (zero manual upload)
-- -------------------------------------------------------------------------------------
-- API integration scoped to the public lab repo owner. No secret needed (public repo).
CREATE OR REPLACE API INTEGRATION HCLS_LAB_GIT_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-nekulkarni')
  ENABLED = TRUE;

-- Git repository object that mirrors the public lab repo.
CREATE OR REPLACE GIT REPOSITORY HCLS_DEMO_DB.DEMO.LAB_REPO
  API_INTEGRATION = HCLS_LAB_GIT_API
  ORIGIN = 'https://github.com/sfc-gh-nekulkarni/voice-of-patient-lab.git';

-- Pull the latest commit, then copy the 16 MP3s into the SSE stage and register them.
ALTER GIT REPOSITORY HCLS_DEMO_DB.DEMO.LAB_REPO FETCH;
COPY FILES INTO @HCLS_DEMO_DB.DEMO.DEMO_STAGE/audio/
  FROM @HCLS_DEMO_DB.DEMO.LAB_REPO/branches/main/audio/;
ALTER STAGE HCLS_DEMO_DB.DEMO.DEMO_STAGE REFRESH;

-- -------------------------------------------------------------------------------------
-- 3. SETUP VERIFICATION  (every row should read OK)
-- -------------------------------------------------------------------------------------
SELECT 'PATIENT_DEMOGRAPHICS' AS object, COUNT(*) AS row_count, IFF(COUNT(*)=35,'OK','CHECK') AS status FROM HCLS_DEMO_DB.DEMO.PATIENT_DEMOGRAPHICS
UNION ALL SELECT 'PATIENT_CONDITIONS', COUNT(*), IFF(COUNT(*)=35,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.PATIENT_CONDITIONS
UNION ALL SELECT 'PROVIDERS', COUNT(*), IFF(COUNT(*)=6,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.PROVIDERS
UNION ALL SELECT 'DIAGNOSES', COUNT(*), IFF(COUNT(*)=6,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.DIAGNOSES
UNION ALL SELECT 'PATIENT_CONTACT', COUNT(*), IFF(COUNT(*)=35,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.PATIENT_CONTACT
UNION ALL SELECT 'VISIT_METADATA', COUNT(*), IFF(COUNT(*)=16,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.VISIT_METADATA
UNION ALL SELECT 'TRIAL_DOCS', COUNT(*), IFF(COUNT(*)=4,'OK','CHECK') FROM HCLS_DEMO_DB.DEMO.TRIAL_DOCS
UNION ALL SELECT 'AUDIO_FILES_IN_STAGE', COUNT(*), IFF(COUNT(*)=16,'OK','CHECK') FROM DIRECTORY(@HCLS_DEMO_DB.DEMO.DEMO_STAGE) WHERE RELATIVE_PATH ILIKE 'audio/%.mp3'
ORDER BY object;
