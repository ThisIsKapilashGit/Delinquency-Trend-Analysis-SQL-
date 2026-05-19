-- =============================================================================
-- 01_trend_analysis.sql
-- Portfolio-level delinquency trend analysis using window functions
-- Includes MoM changes, rolling averages, and risk segmentation trends
-- =============================================================================

USE delinquency_db;

-- ── Query 1: Month-over-Month Portfolio Delinquency Trend ─────────────────────
-- Tracks key delinquency KPIs month over month across the entire portfolio
WITH monthly_kpis AS (
    SELECT
        DATE_FORMAT(p.report_month, '%Y-%m')    AS report_month,
        p.report_month                           AS report_month_dt,
        COUNT(DISTINCT p.loan_id)                AS active_loans,
        COUNT(DISTINCT CASE WHEN p.dpd > 0   THEN p.loan_id END) AS delinquent_loans,
        COUNT(DISTINCT CASE WHEN p.dpd > 30  THEN p.loan_id END) AS dpd30_plus,
        COUNT(DISTINCT CASE WHEN p.dpd > 60  THEN p.loan_id END) AS dpd60_plus,
        COUNT(DISTINCT CASE WHEN p.dpd > 90  THEN p.loan_id END) AS dpd90_plus,
        SUM(p.emi_amount)                        AS total_emi_due,
        SUM(CASE WHEN p.dpd > 0 THEN p.emi_amount ELSE 0 END) AS overdue_amount
    FROM loan_payments p
    GROUP BY p.report_month
)
SELECT
    report_month,
    active_loans,
    delinquent_loans,
    dpd30_plus,
    dpd60_plus,
    dpd90_plus,
    ROUND(delinquent_loans / active_loans * 100, 2)  AS delinquency_rate_pct,
    ROUND(dpd90_plus       / active_loans * 100, 2)  AS npa_rate_pct,
    ROUND(overdue_amount   / total_emi_due * 100, 2) AS overdue_amount_pct,

    -- Month-over-Month change in delinquency rate
    ROUND(
        (delinquent_loans / active_loans * 100) -
        LAG(delinquent_loans / active_loans * 100)
            OVER (ORDER BY report_month_dt),
        2
    ) AS mom_delinquency_rate_change,

    -- 3-month rolling average delinquency rate
    ROUND(
        AVG(delinquent_loans / active_loans * 100)
            OVER (ORDER BY report_month_dt ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        2
    ) AS rolling_3m_delinquency_rate

FROM monthly_kpis
ORDER BY report_month_dt;


-- ── Query 2: Delinquency Trend by Risk Bucket ─────────────────────────────────
-- Separate trend lines for Low / Medium / High risk segments
WITH risk_monthly AS (
    SELECT
        DATE_FORMAT(p.report_month, '%Y-%m')    AS report_month,
        p.report_month                           AS report_month_dt,
        l.risk_bucket,
        COUNT(DISTINCT p.loan_id)                AS active_loans,
        COUNT(DISTINCT CASE WHEN p.dpd > 30 THEN p.loan_id END) AS dpd30_plus,
        COUNT(DISTINCT CASE WHEN p.dpd > 90 THEN p.loan_id END) AS dpd90_plus
    FROM loan_payments p
    JOIN loans l ON p.loan_id = l.loan_id
    GROUP BY p.report_month, l.risk_bucket
)
SELECT
    report_month,
    risk_bucket,
    active_loans,
    dpd30_plus,
    dpd90_plus,
    ROUND(dpd30_plus / active_loans * 100, 2) AS dpd30_rate_pct,
    ROUND(dpd90_plus / active_loans * 100, 2) AS npa_rate_pct,
    -- Running total of NPA loans per risk bucket
    SUM(dpd90_plus) OVER (
        PARTITION BY risk_bucket
        ORDER BY report_month_dt
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_npa_loans,
    -- Rank months by worst NPA rate within each risk bucket
    RANK() OVER (
        PARTITION BY risk_bucket
        ORDER BY dpd90_plus / active_loans DESC
    ) AS worst_month_rank
FROM risk_monthly
ORDER BY report_month_dt, risk_bucket;


-- ── Query 3: Loan Type Delinquency Comparison ─────────────────────────────────
-- Which loan products carry the highest delinquency risk?
SELECT
    l.loan_type,
    DATE_FORMAT(p.report_month, '%Y-%m')         AS report_month,
    COUNT(DISTINCT p.loan_id)                     AS active_loans,
    COUNT(DISTINCT CASE WHEN p.dpd > 0  THEN p.loan_id END) AS delinquent,
    COUNT(DISTINCT CASE WHEN p.dpd > 90 THEN p.loan_id END) AS npa_loans,
    ROUND(
        COUNT(DISTINCT CASE WHEN p.dpd > 0 THEN p.loan_id END) * 100.0 /
        COUNT(DISTINCT p.loan_id), 2
    )                                             AS delinquency_rate_pct,
    -- Percentile rank of this loan type's delinquency rate in this month
    ROUND(
        PERCENT_RANK() OVER (
            PARTITION BY p.report_month
            ORDER BY COUNT(DISTINCT CASE WHEN p.dpd > 0 THEN p.loan_id END) * 1.0 /
                     COUNT(DISTINCT p.loan_id)
        ) * 100, 2
    )                                             AS percentile_rank
FROM loan_payments p
JOIN loans l ON p.loan_id = l.loan_id
GROUP BY l.loan_type, p.report_month
ORDER BY p.report_month, delinquency_rate_pct DESC;


-- ── Query 4: Early Warning — Rapid DPD Escalation Detection ──────────────────
-- Flags loans whose DPD increased sharply (>= 30 days) in a single month
-- These are high-risk accounts requiring immediate collections intervention
WITH dpd_changes AS (
    SELECT
        loan_id,
        report_month,
        dpd,
        LAG(dpd) OVER (PARTITION BY loan_id ORDER BY report_month) AS prev_dpd,
        dpd - LAG(dpd) OVER (PARTITION BY loan_id ORDER BY report_month) AS dpd_change
    FROM loan_payments
)
SELECT
    dc.loan_id,
    l.loan_type,
    l.risk_bucket,
    l.loan_amount,
    DATE_FORMAT(dc.report_month, '%Y-%m') AS escalation_month,
    dc.prev_dpd,
    dc.dpd                                AS current_dpd,
    dc.dpd_change,
    CASE
        WHEN dc.dpd_change >= 90 THEN 'CRITICAL'
        WHEN dc.dpd_change >= 60 THEN 'HIGH'
        WHEN dc.dpd_change >= 30 THEN 'MEDIUM'
    END AS escalation_severity
FROM dpd_changes dc
JOIN loans l ON dc.loan_id = l.loan_id
WHERE dc.dpd_change >= 30
ORDER BY dc.dpd_change DESC, dc.report_month;


-- ── Query 5: Portfolio at Risk (PAR) Summary ──────────────────────────────────
-- PAR = outstanding balance of loans with DPD > threshold / total outstanding
-- Standard regulatory and investor metric
SELECT
    DATE_FORMAT(p.report_month, '%Y-%m')  AS report_month,
    SUM(l.loan_amount)                     AS total_portfolio_value,
    SUM(CASE WHEN p.dpd > 30  THEN l.loan_amount ELSE 0 END) AS par_30,
    SUM(CASE WHEN p.dpd > 60  THEN l.loan_amount ELSE 0 END) AS par_60,
    SUM(CASE WHEN p.dpd > 90  THEN l.loan_amount ELSE 0 END) AS par_90,
    ROUND(SUM(CASE WHEN p.dpd > 30  THEN l.loan_amount ELSE 0 END) /
          SUM(l.loan_amount) * 100, 2)     AS par30_pct,
    ROUND(SUM(CASE WHEN p.dpd > 60  THEN l.loan_amount ELSE 0 END) /
          SUM(l.loan_amount) * 100, 2)     AS par60_pct,
    ROUND(SUM(CASE WHEN p.dpd > 90  THEN l.loan_amount ELSE 0 END) /
          SUM(l.loan_amount) * 100, 2)     AS par90_pct
FROM loan_payments p
JOIN loans l ON p.loan_id = l.loan_id
GROUP BY p.report_month
ORDER BY p.report_month;
