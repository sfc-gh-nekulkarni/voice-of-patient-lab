import streamlit as st
import pandas as pd
from datetime import datetime
from snowflake.snowpark.context import get_active_session

# Page config — wide layout for the worklist cards
st.set_page_config(page_title="Clinical Signal Intelligence", page_icon="stethoscope", layout="wide")

# Connect to Snowflake (works automatically inside Streamlit-in-Snowflake)
session = get_active_session()
DB = "HCLS_DEMO_DB.DEMO"

# ─── Custom CSS for the clinician-grade UI ─────────────────────────────────────
# Uses Snowflake brand colors (navy, cyan) + clinical severity colors (red, amber, green)
st.markdown(
    """
    <style>
      .stApp { background: #F7FBFD; }
      .hero {
        background: linear-gradient(120deg, #11567F 0%, #1B7FB8 55%, #29B5E8 100%);
        padding: 26px 32px; border-radius: 16px; color: #fff; margin-bottom: 8px;
        box-shadow: 0 6px 22px rgba(17,86,127,0.25);
      }
      .hero h1 { color:#fff; font-size: 30px; margin: 0; font-weight: 800; letter-spacing:-0.5px;}
      .hero p { color:#D8F2FC; font-size: 15px; margin: 6px 0 0 0; }
      .card {
        background:#fff; border-radius:14px; padding:18px 20px; margin-bottom:14px;
        border:1px solid #E4EEF4; box-shadow:0 2px 10px rgba(17,86,127,0.06);
        border-left:6px solid #C9D6DE;
      }
      .card.EMERGENT { border-left-color:#E02424; }
      .card.URGENT   { border-left-color:#F59E0B; }
      .card.ROUTINE  { border-left-color:#5FB85F; }
      .pname { font-size:18px; font-weight:700; color:#11567F; }
      .pmeta { color:#5A7184; font-size:13px; }
      .badge { display:inline-block; padding:3px 12px; border-radius:999px; font-size:12px;
               font-weight:700; color:#fff; letter-spacing:.4px; }
      .badge.EMERGENT { background:#E02424; }
      .badge.URGENT   { background:#F59E0B; }
      .badge.ROUTINE  { background:#5FB85F; }
      .chip { display:inline-block; background:#FDECEC; color:#B91C1C; border:1px solid #F6C9C9;
              padding:2px 10px; border-radius:8px; font-size:11px; font-weight:600; margin-right:6px; }
      .action { background:#EAF7FC; border:1px solid #BFE6F5; border-radius:10px;
                padding:10px 14px; color:#11567F; font-size:14px; margin-top:8px; }
      .rationale { color:#445; font-size:13px; font-style:italic; margin-top:6px; }
      .hl { background:#FFE4A8; padding:0 3px; border-radius:3px; font-weight:600; }
    </style>
    """,
    unsafe_allow_html=True,
)

# ─── Hero banner ───────────────────────────────────────────────────────────────
st.markdown(
    """
    <div class="hero">
      <h1>Clinical Signal Intelligence</h1>
      <p>AI reads every visit transcript, flags the urgent signals a busy clinic can miss, and routes the next action - all inside Snowflake.</p>
    </div>
    """,
    unsafe_allow_html=True,
)


# ─── Data loading (cached for 2 min to avoid re-querying on every interaction) ─
@st.cache_data(ttl=120)
def load_worklist():
    """Load all visits joined with patient names and demographics for the worklist."""
    return session.sql(f"""
        SELECT v.VISIT_ID, v.PATIENT_ID, c.PATIENT_NAME, d.AGE, d.GENDER,
               v.VISIT_DATE, v.PROVIDER_NAME, v.URGENCY, v.TOPIC, v.SENTIMENT,
               v.SUMMARY, v.RECOMMENDED_ACTION, v.RISK_RATIONALE, v.TRANSCRIPT,
               v.RED_FLAG_HEMOPTYSIS, v.RED_FLAG_WEIGHT_LOSS, v.RED_FLAG_BLEEDING, v.MISSED_SIGNAL
        FROM {DB}.VISIT_ANALYSIS v
        JOIN {DB}.PATIENT_CONTACT c ON v.PATIENT_ID = c.PATIENT_ID
        JOIN {DB}.PATIENT_DEMOGRAPHICS d ON v.PATIENT_ID = d.PATIENT_ID
    """).to_pandas()


@st.cache_data(ttl=120)
def load_p007():
    """Load Sarah Chen's visits + diagnosis for the time-machine timeline."""
    visits = session.sql(f"""
        SELECT VISIT_DATE, URGENCY, SUMMARY, TRANSCRIPT, MISSED_SIGNAL
        FROM {DB}.VISIT_ANALYSIS WHERE PATIENT_ID='P007' ORDER BY VISIT_DATE
    """).to_pandas()
    dx = session.sql(f"""
        SELECT DIAGNOSIS, DIAGNOSIS_DATE, STAGE FROM {DB}.DIAGNOSES WHERE PATIENT_ID='P007'
    """).to_pandas()
    return visits, dx


# ─── Main layout ──────────────────────────────────────────────────────────────
df = load_worklist()
# Sort by clinical severity: EMERGENT=0, URGENT=1, ROUTINE=2
ORDER = {"EMERGENT": 0, "URGENT": 1, "ROUTINE": 2}
df["RANK"] = df["URGENCY"].map(ORDER).fillna(3)

# ─── KPI metrics row ──────────────────────────────────────────────────────────
k1, k2, k3, k4 = st.columns(4)
k1.metric("Visits analyzed", len(df))
k2.metric("Urgent / Emergent flags", int((df["RANK"] <= 1).sum()))
k3.metric("Missed signals caught", int(df["MISSED_SIGNAL"].fillna(False).sum()))
# Calculate the signal-to-diagnosis gap for Sarah Chen (the "208 days" metric)
v007, dx007 = load_p007()
if not dx007.empty and not v007.empty:
    first_missed = v007[v007["MISSED_SIGNAL"] == True]["VISIT_DATE"].min()
    dxd = pd.to_datetime(dx007["DIAGNOSIS_DATE"].iloc[0])
    days = (dxd - pd.to_datetime(first_missed)).days if pd.notna(first_missed) else None
    k4.metric("Hero signal-to-diagnosis gap", f"{days} days" if days else "n/a", delta="-7 months earlier possible", delta_color="inverse")
else:
    k4.metric("Hero signal-to-diagnosis gap", "n/a")

# ─── Three tabs: Worklist / Time Machine / Follow-up Actions ──────────────────
tab1, tab2, tab3 = st.tabs(["Risk Worklist", "Time Machine - Sarah Chen (P007)", "Follow-up Actions"])

with tab1:
    # Filter by urgency level — default shows EMERGENT + URGENT only
    fcol, _ = st.columns([2, 5])
    show = fcol.multiselect("Filter by risk", ["EMERGENT", "URGENT", "ROUTINE"],
                            default=["EMERGENT", "URGENT"])
    work = df[df["URGENCY"].isin(show)].sort_values(["RANK", "VISIT_DATE"], ascending=[True, False])
    st.caption(f"{len(work)} visit(s) shown, highest clinical risk first.")

    # Render each visit as a styled card with severity badge, red-flag chips, and action
    for _, r in work.iterrows():
        u = r["URGENCY"]
        # Build red-flag chips (only shown when True)
        chips = ""
        if r["RED_FLAG_HEMOPTYSIS"]: chips += '<span class="chip">Hemoptysis</span>'
        if r["RED_FLAG_WEIGHT_LOSS"]: chips += '<span class="chip">Weight loss</span>'
        if r["RED_FLAG_BLEEDING"]: chips += '<span class="chip">Bleeding</span>'
        if r["MISSED_SIGNAL"]: chips += '<span class="chip">Missed signal</span>'
        st.markdown(
            f"""
            <div class="card {u}">
              <span class="badge {u}">{u}</span>
              &nbsp;<span class="pname">{r['PATIENT_NAME']}</span>
              <span class="pmeta">&nbsp;- {int(r['AGE'])} {r['GENDER']} - {r['TOPIC']} - {r['VISIT_DATE']} - {r['PROVIDER_NAME']}</span>
              <div class="rationale">{r['RISK_RATIONALE'] or ''}</div>
              {('<div>'+chips+'</div>') if chips else ''}
              <div class="action"><b>Recommended action:</b> {r['RECOMMENDED_ACTION'] or ''}</div>
            </div>
            """,
            unsafe_allow_html=True,
        )
        # Expandable section: full transcript + write-back button
        with st.expander(f"Transcript & create follow-up - {r['PATIENT_NAME']} ({r['VISIT_ID']})"):
            st.write(f"**AI summary:** {r['SUMMARY']}")
            st.text_area("Visit transcript", r["TRANSCRIPT"], height=140, key=f"t_{r['VISIT_ID']}")
            default_act = r["RECOMMENDED_ACTION"] or "Follow up with patient"
            act = st.text_input("Action to log", value=default_act, key=f"a_{r['VISIT_ID']}")
            # Write-back: inserts a row into FOLLOW_UP_ACTIONS when clicked
            if st.button("Create follow-up action", key=f"b_{r['VISIT_ID']}"):
                safe = act.replace("'", "''")
                session.sql(
                    f"INSERT INTO {DB}.FOLLOW_UP_ACTIONS (PATIENT_ID, VISIT_ID, ACTION_TEXT, CREATED_BY) "
                    f"VALUES ('{r['PATIENT_ID']}','{r['VISIT_ID']}','{safe}', CURRENT_USER())"
                ).collect()
                st.success(f"Follow-up logged for {r['PATIENT_NAME']}.")

# ─── Tab 2: Sarah Chen time-machine timeline ──────────────────────────────────
with tab2:
    st.subheader("What if AI had been reading every visit?")
    if v007.empty or dx007.empty:
        st.info("P007 data not available.")
    else:
        v = v007.copy()
        v["VISIT_DATE"] = pd.to_datetime(v["VISIT_DATE"])
        dxd = pd.to_datetime(dx007["DIAGNOSIS_DATE"].iloc[0])
        first_missed = v[v["MISSED_SIGNAL"] == True]["VISIT_DATE"].min()
        gap = (dxd - first_missed).days
        # Show the key dates as metrics
        c1, c2, c3 = st.columns(3)
        c1.metric("First missed signal", first_missed.strftime("%b %d, %Y"))
        c2.metric("Actual diagnosis", dxd.strftime("%b %d, %Y"))
        c3.metric("Delay", f"{gap} days (~{round(gap/30)} months)")

        # Build a plotly timeline showing visits + diagnosis as colored dots
        timeline = v[["VISIT_DATE", "URGENCY", "SUMMARY"]].copy()
        dxrow = pd.DataFrame({"VISIT_DATE": [dxd], "URGENCY": ["DIAGNOSIS"],
                              "SUMMARY": [f"{dx007['DIAGNOSIS'].iloc[0]} - {dx007['STAGE'].iloc[0]}"]})
        timeline = pd.concat([timeline, dxrow], ignore_index=True)
        color_map = {"EMERGENT": "#E02424", "URGENT": "#F59E0B", "ROUTINE": "#5FB85F", "DIAGNOSIS": "#11567F"}
        try:
            import plotly.express as px
            fig = px.scatter(timeline, x="VISIT_DATE", y=[1] * len(timeline), color="URGENCY",
                             color_discrete_map=color_map, hover_data=["SUMMARY"], size=[18] * len(timeline))
            fig.update_yaxes(visible=False, range=[0.5, 1.5])
            fig.update_layout(height=240, showlegend=True, plot_bgcolor="#fff",
                              title="Sarah Chen - visit timeline vs. diagnosis")
            st.plotly_chart(fig, use_container_width=True)
        except Exception:
            st.dataframe(timeline)

        # The narrative — explain what happened and what AI would have caught
        st.markdown(f"""
        <div class="action">
        On <b>{first_missed.strftime('%b %d, %Y')}</b>, Sarah reported <span class="hl">coughing up blood</span>,
        <span class="hl">unintentional weight loss</span>, and a <span class="hl">worsening cough</span> -
        flagged here as <b>EMERGENT</b>. It was attributed to asthma. Her lung cancer was diagnosed
        <b>{gap} days later</b>. Catching this signal on day one could have started the workup ~7 months earlier.
        </div>
        """, unsafe_allow_html=True)

        # Show the actual transcript with red-flag keywords highlighted
        st.markdown("##### The visit transcript the AI flagged")
        miss = v[v["MISSED_SIGNAL"] == True].iloc[0]["TRANSCRIPT"]
        for kw in ["coughed up a little blood", "lost about eight pounds", "cough for about six weeks"]:
            miss = miss.replace(kw, f"||{kw}||")
        parts = miss.split("||")
        html = "".join(f'<span class="hl">{p}</span>' if i % 2 else p for i, p in enumerate(parts))
        st.markdown(f'<div class="card">{html}</div>', unsafe_allow_html=True)

# ─── Tab 3: Follow-up actions log ─────────────────────────────────────────────
with tab3:
    st.subheader("Follow-up actions logged from the worklist")
    acts = session.sql(f"""
        SELECT a.CREATED_AT, c.PATIENT_NAME, a.VISIT_ID, a.ACTION_TEXT, a.CREATED_BY
        FROM {DB}.FOLLOW_UP_ACTIONS a JOIN {DB}.PATIENT_CONTACT c ON a.PATIENT_ID=c.PATIENT_ID
        ORDER BY a.CREATED_AT DESC
    """).to_pandas()
    if acts.empty:
        st.info("No actions logged yet. Open a patient in the Risk Worklist and click 'Create follow-up action'.")
    else:
        st.dataframe(acts, use_container_width=True, hide_index=True)
