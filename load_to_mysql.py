"""
load_to_mysql.py
----------------
Connects to MySQL and bulk-loads the generated CSVs into the delinquency_db schema.
Run this AFTER:
  1. python generate_data.py
  2. Executing sql/01_setup/01_create_tables.sql in MySQL

Requirements:
    pip install mysql-connector-python pandas
"""

import csv
import os
import mysql.connector
from datetime import date, datetime

# ── Configuration — update with your MySQL credentials ───────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     3306,
    "user":     "root",          # change as needed
    "password": "your_password", # change as needed
    "database": "delinquency_db",
}

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")


# ── Helpers ───────────────────────────────────────────────────────────────────

def parse_date(s: str):
    """Parse ISO date string or return None."""
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None

def read_csv(filename: str) -> list[dict]:
    path = os.path.join(DATA_DIR, filename)
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


# ── Load Functions ────────────────────────────────────────────────────────────

def load_loans(cursor, rows: list[dict]):
    sql = """
        INSERT IGNORE INTO loans
            (loan_id, customer_id, loan_type, disbursement_date,
             tenure_months, loan_amount, interest_rate, risk_bucket, cohort_month)
        VALUES
            (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = [
        (
            r["loan_id"],
            r["customer_id"],
            r["loan_type"],
            parse_date(r["disbursement_date"]),
            int(r["tenure_months"]),
            float(r["loan_amount"]),
            float(r["interest_rate"]),
            r["risk_bucket"],
            parse_date(r["cohort_month"]),
        )
        for r in rows
    ]
    cursor.executemany(sql, data)
    print(f"  ✅ Inserted {cursor.rowcount} rows into loans")


def load_payments(cursor, rows: list[dict]):
    sql = """
        INSERT IGNORE INTO loan_payments
            (payment_id, loan_id, report_month, due_date,
             emi_amount, dpd, dpd_bucket, payment_status)
        VALUES
            (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = [
        (
            int(r["payment_id"]),
            r["loan_id"],
            parse_date(r["report_month"]),
            parse_date(r["due_date"]),
            float(r["emi_amount"]),
            int(r["dpd"]),
            r["dpd_bucket"],
            r["payment_status"],
        )
        for r in rows
    ]
    cursor.executemany(sql, data)
    print(f"  ✅ Inserted {cursor.rowcount} rows into loan_payments")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("🔌 Connecting to MySQL...")
    conn   = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()

    try:
        print("\n📂 Loading loans.csv...")
        loan_rows = read_csv("loans.csv")
        load_loans(cursor, loan_rows)

        print("\n📂 Loading loan_payments.csv...")
        payment_rows = read_csv("loan_payments.csv")
        load_payments(cursor, payment_rows)

        conn.commit()
        print("\n🎉 Data load complete!")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()
