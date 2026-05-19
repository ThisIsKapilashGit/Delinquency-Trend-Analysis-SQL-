-- =============================================================================
-- 01_cohort_analysis.sql
-- Cohort-based delinquency analysis
-- Groups loans by disbursement month and tracks DPD evolution over loan age
-- =============================================================================

USE delinquency_db;

-- ── Query 1: Cohort Size Summary ──────────────────────────────────────────────
-- Shows how many loans were disbursed per cohort month, broken by risk bucket
SELECT
    DATE_FORMAT(l.cohort_month, '%Y-%m') AS cohort_month,
    l.risk_bucket,
    l.loan_type,
    COUNT(DISTINCT l.loan_id)            AS total_loans,
    SUM(l.loan_amount)                   AS total_disbursed_amount,
    ROUND(AVG(l.loan_amount), 2)         AS avg_loan_amount
FROM loans l
GROUP BY l.cohort_month, l.risk_bucket, l.loan_type
ORDER BY l.cohort_month, l.risk_bucket;


-- ── Query 2: Cohort DPD Heatmap (Vintage Analysis) ────────────────────────────
-- For each cohort, shows % of loans in a delinquent state at each loan age (month)
-- This is the core "vintage curve" used in credit risk analysis
WITH cohort_base AS (
    -- Total loans per cohort (denominator)
    SELECT
        cohort_month,
        COUNT(DISTINCT loan_id) AS cohort_size
    FROM loans
    GROUP BY cohort_month
),
loan_age AS (
    -- Compute months since disbursement for each payment record
    SELECT
        l.loan_id,
        l.cohort_month,
        p.report_month,
        -- loan_age_months = how many months after disbursement
        TIMESTAMPDIFF(MONTH, l.cohort_month, p.report_month) AS loan_age_months,
        p.dpd,
        p.dpd_bucket
    FROM loans l
    JOIN loan_payments p ON l.loan_id = p.loan_id
),
delinquent_counts AS (
    -- Count delinquent loans (DPD > 0) per cohort per loan age
    SELECT
        la.cohort_month,
        la.loan_age_months,
        COUNT(DISTINCT la.loan_id)                              AS total_active_loans,
        COUNT(DISTINCT CASE WHEN la.dpd > 0
                            THEN la.loan_id END)                AS delinquent_loans,
        COUNT(DISTINCT CASE WHEN la.dpd > 30
                            THEN la.loan_id END)                AS dpd_30plus_loans,
        COUNT(DISTINCT CASE WHEN la.dpd > 90
                            THEN la.loan_id END)                AS dpd_90plus_loans
    FROM loan_age la
    GROUP BY la.cohort_month, la.loan_age_months
)
SELECT
    DATE_FORMAT(dc.cohort_month, '%Y-%m')     AS cohort_month,
    dc.loan_age_months,
    cb.cohort_size,
    dc.total_active_loans,
    dc.delinquent_loans,
    dc.dpd_30plus_loans,
    dc.dpd_90plus_loans,
    -- Delinquency rates relative to cohort size
    ROUND(dc.delinquent_loans  / cb.cohort_size * 100, 2) AS delinquency_rate_pct,
    ROUND(dc.dpd_30plus_loans  / cb.cohort_size * 100, 2) AS dpd30_rate_pct,
    ROUND(dc.dpd_90plus_loans  / cb.cohort_size * 100, 2) AS dpd90_rate_pct
FROM delinquent_counts dc
JOIN cohort_base cb ON dc.cohort_month = cb.cohort_month
WHERE dc.loan_age_months BETWEEN 1 AND 24
ORDER BY dc.cohort_month, dc.loan_age_months;


-- ── Query 3: Cohort-level NPA (Non-Performing Asset) Rate ─────────────────────
-- DPD > 90 is typically classified as NPA in the Indian banking system
WITH cohort_summary AS (
    SELECT
        l.cohort_month,
        l.loan_type,
        l.risk_bucket,
        COUNT(DISTINCT l.loan_id)                                        AS total_loans,
        COUNT(DISTINCT CASE WHEN p.dpd > 90 THEN l.loan_id END)         AS npa_loans,
        SUM(l.loan_amount)                                               AS total_portfolio,
        SUM(CASE WHEN p.dpd > 90 THEN l.loan_amount ELSE 0 END)         AS npa_amount
    FROM loans l
    JOIN loan_payments p ON l.loan_id = p.loan_id
    GROUP BY l.cohort_month, l.loan_type, l.risk_bucket
)
SELECT
    DATE_FORMAT(cohort_month, '%Y-%m')          AS cohort_month,
    loan_type,
    risk_bucket,
    total_loans,
    npa_loans,
    ROUND(npa_loans   / total_loans    * 100, 2) AS npa_loan_count_pct,
    ROUND(npa_amount  / total_portfolio * 100, 2) AS npa_amount_pct
FROM cohort_summary
ORDER BY cohort_month, loan_type, risk_bucket;
