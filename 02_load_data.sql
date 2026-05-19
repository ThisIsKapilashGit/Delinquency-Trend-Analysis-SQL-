-- =============================================================================
-- 02_load_data.sql
-- Loads generated CSV files into MySQL tables
-- Run AFTER 01_create_tables.sql
-- NOTE: Update the file paths to match your local environment
-- =============================================================================

USE delinquency_db;

-- Temporarily disable foreign key checks for faster bulk load
SET foreign_key_checks = 0;

-- ── Load Loans ────────────────────────────────────────────────────────────────
LOAD DATA LOCAL INFILE '/path/to/delinquency-trend-analysis/data/loans.csv'
INTO TABLE loans
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(loan_id, customer_id, loan_type, disbursement_date, tenure_months,
 loan_amount, interest_rate, risk_bucket, cohort_month);

-- ── Load Payments ─────────────────────────────────────────────────────────────
LOAD DATA LOCAL INFILE '/path/to/delinquency-trend-analysis/data/loan_payments.csv'
INTO TABLE loan_payments
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(payment_id, loan_id, report_month, due_date,
 emi_amount, dpd, dpd_bucket, payment_status);

SET foreign_key_checks = 1;

-- ── Verify Row Counts ─────────────────────────────────────────────────────────
SELECT 'loans'         AS table_name, COUNT(*) AS row_count FROM loans
UNION ALL
SELECT 'loan_payments' AS table_name, COUNT(*) AS row_count FROM loan_payments;
