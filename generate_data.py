"""
generate_data.py
----------------
Generates synthetic loan delinquency data for the Delinquency Trend Analysis project.
Outputs two CSV files:
  - data/loans.csv         : Loan master data (one row per loan)
  - data/loan_payments.csv : Monthly payment records with DPD (Days Past Due)
"""

import csv
import random
from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

# ── Configuration ────────────────────────────────────────────────────────────
random.seed(42)

NUM_LOANS        = 500
OBSERVATION_DATE = date(2024, 12, 31)
COHORT_START     = date(2022, 1, 1)   # earliest disbursement month
COHORT_END       = date(2024, 6, 1)   # latest disbursement month

LOAN_TYPES    = ["Personal", "Home", "Auto", "Business", "Education"]
RISK_BUCKETS  = ["Low", "Medium", "High"]

# Probability of a payment being late per risk bucket
LATE_PROB = {"Low": 0.08, "Medium": 0.20, "High": 0.40}

# DPD range when a payment IS late, by risk bucket
DPD_RANGE = {
    "Low":    (1,  30),
    "Medium": (1,  90),
    "High":   (1, 180),
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def random_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))

def first_of_month(d: date) -> date:
    return d.replace(day=1)

def months_between(start: date, end: date) -> int:
    return (end.year - start.year) * 12 + (end.month - start.month)

# ── Generate Loan Master ───────────────────────────────────────────────────────

loans = []
for i in range(1, NUM_LOANS + 1):
    disbursement_date = random_date(COHORT_START, COHORT_END)
    tenure_months     = random.choice([12, 24, 36, 48, 60])
    risk              = random.choices(RISK_BUCKETS, weights=[50, 30, 20])[0]
    loan_amount       = round(random.uniform(50_000, 2_000_000), 2)
    interest_rate     = round(random.uniform(7.5, 18.0), 2)
    loan_type         = random.choice(LOAN_TYPES)

    loans.append({
        "loan_id":          f"LN{i:05d}",
        "customer_id":      f"CUST{random.randint(1, 800):05d}",
        "loan_type":        loan_type,
        "disbursement_date": disbursement_date.isoformat(),
        "tenure_months":    tenure_months,
        "loan_amount":      loan_amount,
        "interest_rate":    interest_rate,
        "risk_bucket":      risk,
        "cohort_month":     first_of_month(disbursement_date).isoformat(),
    })

# ── Generate Payment Records ──────────────────────────────────────────────────

payments = []
payment_id = 1

for loan in loans:
    disb      = date.fromisoformat(loan["disbursement_date"])
    tenure    = loan["tenure_months"]
    risk      = loan["risk_bucket"]
    loan_id   = loan["loan_id"]

    # How many months have passed since disbursement (capped at tenure)
    elapsed = min(months_between(disb, OBSERVATION_DATE), tenure)

    # Running DPD state — once a loan goes bad it tends to stay bad
    current_dpd = 0

    for m in range(1, elapsed + 1):
        due_date     = disb + relativedelta(months=m)
        report_month = first_of_month(due_date)

        # Determine if this payment is late
        is_late = random.random() < LATE_PROB[risk]

        if is_late:
            # DPD can increase from previous month (roll forward) or be fresh
            lo, hi   = DPD_RANGE[risk]
            new_dpd  = random.randint(lo, hi)
            # Roll-forward: DPD tends to accumulate
            current_dpd = max(current_dpd + random.randint(0, 30), new_dpd)
            current_dpd = min(current_dpd, 365)   # cap at 1 year
        else:
            # Payment made — DPD resets (partial cure possible)
            current_dpd = max(0, current_dpd - random.randint(30, 90))

        # DPD bucket classification
        if current_dpd == 0:
            dpd_bucket = "Current"
        elif current_dpd <= 30:
            dpd_bucket = "DPD 1-30"
        elif current_dpd <= 60:
            dpd_bucket = "DPD 31-60"
        elif current_dpd <= 90:
            dpd_bucket = "DPD 61-90"
        elif current_dpd <= 180:
            dpd_bucket = "DPD 91-180"
        else:
            dpd_bucket = "DPD 180+"

        emi_amount = round(loan["loan_amount"] / loan["tenure_months"], 2)

        payments.append({
            "payment_id":    payment_id,
            "loan_id":       loan_id,
            "report_month":  report_month.isoformat(),
            "due_date":      due_date.isoformat(),
            "emi_amount":    emi_amount,
            "dpd":           current_dpd,
            "dpd_bucket":    dpd_bucket,
            "payment_status": "Paid" if current_dpd == 0 else "Overdue",
        })
        payment_id += 1

# ── Write CSVs ────────────────────────────────────────────────────────────────

import os
os.makedirs("data", exist_ok=True)

loan_fields = [
    "loan_id", "customer_id", "loan_type", "disbursement_date",
    "tenure_months", "loan_amount", "interest_rate", "risk_bucket", "cohort_month"
]
with open("data/loans.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=loan_fields)
    w.writeheader()
    w.writerows(loans)

payment_fields = [
    "payment_id", "loan_id", "report_month", "due_date",
    "emi_amount", "dpd", "dpd_bucket", "payment_status"
]
with open("data/loan_payments.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=payment_fields)
    w.writeheader()
    w.writerows(payments)

print(f"✅  Generated {len(loans):,} loans and {len(payments):,} payment records.")
print("    → data/loans.csv")
print("    → data/loan_payments.csv")
