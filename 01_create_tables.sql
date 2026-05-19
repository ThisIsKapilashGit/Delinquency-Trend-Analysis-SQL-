-- =============================================================================
-- 01_create_tables.sql
-- Creates the database schema for Delinquency Trend Analysis
-- MySQL 8.0+
-- =============================================================================

CREATE DATABASE IF NOT EXISTS delinquency_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE delinquency_db;

-- ── Loan Master Table ─────────────────────────────────────────────────────────
DROP TABLE IF EXISTS loan_payments;
DROP TABLE IF EXISTS loans;

CREATE TABLE loans (
    loan_id           VARCHAR(10)    NOT NULL PRIMARY KEY,
    customer_id       VARCHAR(10)    NOT NULL,
    loan_type         VARCHAR(20)    NOT NULL,
    disbursement_date DATE           NOT NULL,
    tenure_months     TINYINT        NOT NULL,
    loan_amount       DECIMAL(15, 2) NOT NULL,
    interest_rate     DECIMAL(5, 2)  NOT NULL,
    risk_bucket       VARCHAR(10)    NOT NULL,
    cohort_month      DATE           NOT NULL,          -- first day of disbursement month
    INDEX idx_cohort_month (cohort_month),
    INDEX idx_risk_bucket  (risk_bucket),
    INDEX idx_loan_type    (loan_type)
);

-- ── Monthly Payment / DPD Tracking Table ─────────────────────────────────────
CREATE TABLE loan_payments (
    payment_id     INT            NOT NULL PRIMARY KEY,
    loan_id        VARCHAR(10)    NOT NULL,
    report_month   DATE           NOT NULL,             -- first day of reporting month
    due_date       DATE           NOT NULL,
    emi_amount     DECIMAL(15, 2) NOT NULL,
    dpd            SMALLINT       NOT NULL DEFAULT 0,   -- Days Past Due
    dpd_bucket     VARCHAR(20)    NOT NULL,
    payment_status VARCHAR(10)    NOT NULL,
    INDEX idx_loan_id      (loan_id),
    INDEX idx_report_month (report_month),
    INDEX idx_dpd_bucket   (dpd_bucket),
    CONSTRAINT fk_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);
