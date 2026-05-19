-- =============================================================================
-- 01_dpd_movement.sql
-- DPD (Days Past Due) Movement & Roll Rate Analysis
-- Tracks how loans migrate between DPD buckets month over month
-- Roll rates are critical for loss forecasting and provisioning
-- =============================================================================

USE delinquency_db;

-- ── Query 1: Monthly DPD Bucket Distribution ──────────────────────────────────
-- Shows count and % of loans in each DPD bucket per reporting month
SELECT
    DATE_FORMAT(p.report_month, '%Y-%m') AS report_month,
    p.dpd_bucket,
    COUNT(DISTINCT p.loan_id)             AS loan_count,
    ROUND(
        COUNT(DISTINCT p.loan_id) * 100.0 /
        SUM(COUNT(DISTINCT p.loan_id)) OVER (PARTITION BY p.report_month),
        2
    )                                     AS bucket_pct
FROM loan_payments p
GROUP BY p.report_month, p.dpd_bucket
ORDER BY p.report_month,
    FIELD(p.dpd_bucket,
        'Current','DPD 1-30','DPD 31-60','DPD 61-90','DPD 91-180','DPD 180+');


-- ── Query 2: Roll Rate Matrix (Month-over-Month DPD Migration) ────────────────
-- For each loan, compares its DPD bucket in month M vs month M-1
-- This produces the transition/roll rate matrix
WITH monthly_buckets AS (
    SELECT
        loan_id,
        report_month,
        dpd_bucket,
        -- Get previous month's bucket using LAG window function
        LAG(dpd_bucket) OVER (
            PARTITION BY loan_id
            ORDER BY report_month
        ) AS prev_dpd_bucket,
        LAG(report_month) OVER (
            PARTITION BY loan_id
            ORDER BY report_month
        ) AS prev_report_month
    FROM loan_payments
),
valid_transitions AS (
    -- Only keep consecutive month transitions (avoid gaps)
    SELECT
        loan_id,
        report_month,
        prev_dpd_bucket  AS from_bucket,
        dpd_bucket       AS to_bucket
    FROM monthly_buckets
    WHERE
        prev_dpd_bucket IS NOT NULL
        AND TIMESTAMPDIFF(MONTH, prev_report_month, report_month) = 1
)
SELECT
    from_bucket,
    to_bucket,
    COUNT(*)  AS transition_count,
    -- Roll rate = % of loans that moved to this bucket from the from_bucket
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (PARTITION BY from_bucket),
        2
    ) AS roll_rate_pct
FROM valid_transitions
GROUP BY from_bucket, to_bucket
ORDER BY
    FIELD(from_bucket,
        'Current','DPD 1-30','DPD 31-60','DPD 61-90','DPD 91-180','DPD 180+'),
    FIELD(to_bucket,
        'Current','DPD 1-30','DPD 31-60','DPD 61-90','DPD 91-180','DPD 180+');


-- ── Query 3: Cure Rate Analysis ───────────────────────────────────────────────
-- Cure = a delinquent loan returning to "Current" status
-- High cure rates indicate effective collections; low rates signal write-off risk
WITH monthly_buckets AS (
    SELECT
        loan_id,
        report_month,
        dpd_bucket,
        LAG(dpd_bucket) OVER (PARTITION BY loan_id ORDER BY report_month) AS prev_bucket,
        LAG(report_month) OVER (PARTITION BY loan_id ORDER BY report_month) AS prev_month
    FROM loan_payments
),
cures AS (
    SELECT
        report_month,
        prev_bucket         AS from_bucket,
        COUNT(*)            AS cured_loans
    FROM monthly_buckets
    WHERE
        dpd_bucket   = 'Current'
        AND prev_bucket != 'Current'
        AND prev_bucket IS NOT NULL
        AND TIMESTAMPDIFF(MONTH, prev_month, report_month) = 1
    GROUP BY report_month, prev_bucket
),
delinquent_pool AS (
    -- Total delinquent loans per bucket per month (potential cures)
    SELECT
        report_month,
        dpd_bucket,
        COUNT(DISTINCT loan_id) AS delinquent_count
    FROM loan_payments
    WHERE dpd_bucket != 'Current'
    GROUP BY report_month, dpd_bucket
)
SELECT
    DATE_FORMAT(c.report_month, '%Y-%m') AS report_month,
    c.from_bucket,
    c.cured_loans,
    dp.delinquent_count                   AS eligible_pool,
    ROUND(c.cured_loans / dp.delinquent_count * 100, 2) AS cure_rate_pct
FROM cures c
JOIN delinquent_pool dp
    ON c.report_month = dp.report_month
    AND c.from_bucket  = dp.dpd_bucket
ORDER BY c.report_month, c.from_bucket;


-- ── Query 4: Flow Rate — Bucket-to-Bucket Progression Over Time ───────────────
-- Shows how quickly loans roll from early delinquency to severe delinquency
-- Used to estimate expected losses and set provisioning levels
WITH bucket_order AS (
    SELECT
        loan_id,
        report_month,
        dpd_bucket,
        CASE dpd_bucket
            WHEN 'Current'    THEN 0
            WHEN 'DPD 1-30'   THEN 1
            WHEN 'DPD 31-60'  THEN 2
            WHEN 'DPD 61-90'  THEN 3
            WHEN 'DPD 91-180' THEN 4
            WHEN 'DPD 180+'   THEN 5
        END AS bucket_rank,
        LAG(CASE dpd_bucket
            WHEN 'Current'    THEN 0
            WHEN 'DPD 1-30'   THEN 1
            WHEN 'DPD 31-60'  THEN 2
            WHEN 'DPD 61-90'  THEN 3
            WHEN 'DPD 91-180' THEN 4
            WHEN 'DPD 180+'   THEN 5
        END) OVER (PARTITION BY loan_id ORDER BY report_month) AS prev_bucket_rank
    FROM loan_payments
)
SELECT
    DATE_FORMAT(report_month, '%Y-%m') AS report_month,
    SUM(CASE WHEN bucket_rank > prev_bucket_rank THEN 1 ELSE 0 END) AS rolled_worse,
    SUM(CASE WHEN bucket_rank < prev_bucket_rank THEN 1 ELSE 0 END) AS cured,
    SUM(CASE WHEN bucket_rank = prev_bucket_rank THEN 1 ELSE 0 END) AS stayed_same,
    COUNT(*)                                                          AS total_transitions,
    ROUND(
        SUM(CASE WHEN bucket_rank > prev_bucket_rank THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) AS roll_forward_pct
FROM bucket_order
WHERE prev_bucket_rank IS NOT NULL
GROUP BY report_month
ORDER BY report_month;
