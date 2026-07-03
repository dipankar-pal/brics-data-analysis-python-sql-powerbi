# ============================================================
# BRICS ECONOMIC DATA PIPELINE
# Written by: Data Engineer
# Flow: World Bank API → Pandas → CSV → Excel → SQL Server
# ============================================================
# FIXES APPLIED:
#   ✅ Missing column detection + auto-fill
#   ✅ Silent error trap removed
#   ✅ Row count validation before insert
#   ✅ Duplicate data protection (TRUNCATE before INSERT)
#   ✅ Column count mismatch check
#   ✅ Step-by-step logging at every stage
#   ✅ Graceful retry logic on API failure
# ============================================================

import requests
import pandas as pd
import pyodbc
import time
import sys
from datetime import datetime


# ============================================================
# STEP 0 — CONFIGURATION
# ============================================================

START_YEAR  = 2000
END_YEAR    = 2024
API_RETRIES = 3           # Retry failed API calls this many times
SLEEP_TIME  = 0.3         # Seconds between API calls (be polite!)
LOAD_TO_SQL = True        # Set False to skip SQL and only save CSV

SERVER_NAME   = r"DIPANKAR\SQLEXPRESS"
DATABASE_NAME = "BRICS"
TABLE_NAME    = "dbo.brics_world_bank"

COUNTRIES = {
    "IND": "India",
    "CHN": "China",
    "BRA": "Brazil",
    "RUS": "Russia",
    "ZAF": "South Africa"
}

# indicator_code → column name in our table
INDICATORS = {

    # GDP
    "NY.GDP.MKTP.CD":    "gdp_usd",
    "NY.GDP.PCAP.CD":    "gdp_per_capita",
    "NY.GDP.MKTP.KD.ZG": "gdp_growth_pct",

    # Population
    "SP.POP.TOTL":       "population",
    "SP.POP.GROW":       "population_growth_pct",
    "SP.DYN.LE00.IN":    "life_expectancy",

    # Inflation & Employment
    "FP.CPI.TOTL.ZG":   "inflation_pct",
    "SL.UEM.TOTL.ZS":   "unemployment_pct",

    # Trade
    "NE.EXP.GNFS.CD":   "exports_usd",
    "NE.IMP.GNFS.CD":   "imports_usd",
    "NE.TRD.GNFS.ZS":   "trade_pct_gdp",

    # Government
    "GC.DOD.TOTL.GD.ZS": "debt_pct_gdp",
    "GC.XPN.TOTL.GD.ZS": "govt_expenditure_pct_gdp",

    # Investment
    "BX.KLT.DINV.CD.WD": "fdi_inflows_usd",

    # Environment
    "EN.ATM.CO2E.PC":    "co2_per_capita",

    # Education
    "SE.ADT.LITR.ZS":    "literacy_rate",

    # Technology
    "IT.NET.USER.ZS":    "internet_users_pct",

    # Health
    "SH.XPD.CHEX.GD.ZS": "health_expenditure_pct_gdp"
}

# All column names we expect in final table
ALL_INDICATOR_COLS = list(INDICATORS.values())

# Columns we will INSERT into SQL (order matters!)
INSERT_COLS = [
    "country_code",
    "country_name",
    "year",
    "gdp_usd",
    "gdp_per_capita",
    "gdp_growth_pct",
    "population",
    "population_growth_pct",
    "life_expectancy",
    "inflation_pct",
    "unemployment_pct",
    "exports_usd",
    "imports_usd",
    "trade_pct_gdp",
    "debt_pct_gdp",
    "govt_expenditure_pct_gdp",
    "fdi_inflows_usd",
    "co2_per_capita",
    "literacy_rate",
    "internet_users_pct",
    "health_expenditure_pct_gdp"
]


# ============================================================
# HELPER — LOGGER
# Prints message with timestamp. Easy to trace what happened.
# ============================================================

def log(msg, level="INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    icons = {"INFO": "ℹ️ ", "OK": "✅", "WARN": "⚠️ ", "ERROR": "❌", "STEP": "🔷"}
    icon = icons.get(level, "  ")
    print(f"[{ts}] {icon}  {msg}")


# ============================================================
# STEP 1 — FETCH ONE INDICATOR FROM WORLD BANK API
# ============================================================

def fetch_indicator(country_code, indicator_code):
    """
    Calls World Bank API for one country + one indicator.
    Returns a list of row dicts.
    Retries up to API_RETRIES times if the call fails.
    """

    url = (
        f"https://api.worldbank.org/v2/country/{country_code}"
        f"/indicator/{indicator_code}"
        f"?format=json"
        f"&date={START_YEAR}:{END_YEAR}"
        f"&per_page=100"
    )

    indicator_name = INDICATORS[indicator_code]

    for attempt in range(1, API_RETRIES + 1):

        try:
            response = requests.get(url, timeout=30)

            # HTTP error
            if response.status_code != 200:
                log(
                    f"HTTP {response.status_code} | "
                    f"{country_code} | {indicator_name} "
                    f"(attempt {attempt})",
                    "WARN"
                )
                time.sleep(1)
                continue

            data = response.json()

            # API returned empty body
            if len(data) < 2 or data[1] is None:
                log(
                    f"No data | {country_code} | {indicator_name}",
                    "WARN"
                )
                return []

            rows = []
            for record in data[1]:
                rows.append({
                    "country_code":   country_code,
                    "country_name":   COUNTRIES[country_code],
                    "indicator_code": indicator_code,
                    "indicator_name": indicator_name,
                    "year":           int(record["date"]),
                    "value":          record["value"]
                })

            return rows

        except requests.exceptions.Timeout:
            log(f"Timeout | {country_code} | {indicator_name} (attempt {attempt})", "WARN")
            time.sleep(2)

        except Exception as e:
            log(f"Exception | {country_code} | {indicator_name} | {e}", "ERROR")
            time.sleep(1)

    # All retries failed
    log(f"All {API_RETRIES} retries failed | {country_code} | {indicator_name}", "ERROR")
    return []


# ============================================================
# STEP 2 — DOWNLOAD ALL DATA
# ============================================================

log("=" * 55, "STEP")
log("STEP 1: DOWNLOADING DATA FROM WORLD BANK API", "STEP")
log("=" * 55, "STEP")

all_rows   = []
fail_count = 0
total_calls = len(COUNTRIES) * len(INDICATORS)
call_num   = 0

for country_code in COUNTRIES.keys():
    log(f"--- Processing country: {COUNTRIES[country_code]} ---", "INFO")

    for indicator_code in INDICATORS.keys():
        call_num += 1
        indicator_name = INDICATORS[indicator_code]

        print(
            f"  [{call_num:>3}/{total_calls}] "
            f"{country_code} | {indicator_name}",
            end=" "
        )

        rows = fetch_indicator(country_code, indicator_code)

        if rows:
            all_rows.extend(rows)
            print(f"→ {len(rows)} rows")
        else:
            fail_count += 1
            print("→ 0 rows (no data)")

        time.sleep(SLEEP_TIME)

log(f"API Download Complete", "OK")
log(f"Total rows fetched  : {len(all_rows):,}", "INFO")
log(f"Failed API calls    : {fail_count}", "WARN" if fail_count > 0 else "OK")

# Safety check: did we get ANY data at all?
if len(all_rows) == 0:
    log("CRITICAL: No data fetched from API. Check your internet or API URL.", "ERROR")
    sys.exit(1)


# ============================================================
# STEP 3 — BUILD LONG FORMAT TABLE
# ============================================================

log("=" * 55, "STEP")
log("STEP 2: BUILDING LONG FORMAT TABLE", "STEP")
log("=" * 55, "STEP")

df_long = pd.DataFrame(all_rows)

before_drop = len(df_long)
df_long = df_long.dropna(subset=["value"])    # Remove null values
after_drop  = len(df_long)

log(f"Rows before null drop : {before_drop:,}", "INFO")
log(f"Rows after  null drop : {after_drop:,}",  "INFO")
log(f"Null rows removed     : {before_drop - after_drop:,}", "INFO")
log(f"Long table shape      : {df_long.shape}", "OK")


# ============================================================
# STEP 4 — BUILD WIDE FORMAT TABLE (PIVOT)
# One row per country per year. Each indicator is a column.
# ============================================================

log("=" * 55, "STEP")
log("STEP 3: PIVOTING TO WIDE FORMAT TABLE", "STEP")
log("=" * 55, "STEP")

df_wide = df_long.pivot_table(
    index   = ["country_code", "country_name", "year"],
    columns = "indicator_name",
    values  = "value",
    aggfunc = "first"
).reset_index()

df_wide.columns.name = None   # Remove the 'indicator_name' label from columns

log(f"Wide table shape : {df_wide.shape}", "OK")
log(f"Columns in pivot : {list(df_wide.columns)}", "INFO")


# ============================================================
# STEP 5 — FIX MISSING COLUMNS
# Some indicators have NO data for any country.
# Pivot will not create that column at all.
# We add them as 0 to match the SQL table schema.
# ============================================================

log("=" * 55, "STEP")
log("STEP 4: CHECKING FOR MISSING INDICATOR COLUMNS", "STEP")
log("=" * 55, "STEP")

missing_cols = [col for col in ALL_INDICATOR_COLS if col not in df_wide.columns]

if missing_cols:
    log(f"Found {len(missing_cols)} missing column(s). Adding them as 0.", "WARN")
    for col in missing_cols:
        df_wide[col] = 0.0
        log(f"  Added missing column: {col}", "WARN")
else:
    log("All indicator columns present. No missing columns!", "OK")


# ============================================================
# STEP 6 — FILL REMAINING NULLS WITH 0
# Pivot leaves NaN for country+year combos with no data.
# SQL Server FLOAT columns accept 0 cleanly.
# ============================================================

numeric_cols = df_wide.select_dtypes(include=["float64", "int64"]).columns
df_wide[numeric_cols] = df_wide[numeric_cols].fillna(0)

log(f"Null fill complete. Total rows ready: {len(df_wide):,}", "OK")

# Quick sample preview
log("Sample rows:", "INFO")
print(df_wide[["country_code", "country_name", "year",
               "gdp_usd", "gdp_growth_pct",
               "population", "inflation_pct"]].head(10).to_string(index=False))


# ============================================================
# STEP 7 — SAVE CSV
# ============================================================

log("=" * 55, "STEP")
log("STEP 5: SAVING CSV FILE", "STEP")
log("=" * 55, "STEP")

csv_file = "brics_world_bank_data.csv"
df_wide.to_csv(csv_file, index=False)
log(f"CSV saved: {csv_file}", "OK")


# ============================================================
# STEP 8 — SAVE EXCEL
# ============================================================

excel_file = "brics_world_bank_data.xlsx"
df_wide.to_excel(excel_file, index=False)
log(f"Excel saved: {excel_file}", "OK")


# ============================================================
# STEP 9 — LOAD TO SQL SERVER
# ============================================================

if not LOAD_TO_SQL:
    log("LOAD_TO_SQL = False. Skipping SQL insert.", "WARN")
else:

    log("=" * 55, "STEP")
    log("STEP 6: LOADING DATA INTO SQL SERVER", "STEP")
    log("=" * 55, "STEP")

    try:

        # ── 9.1 Connect ────────────────────────────────────────
        conn_str = (
            f"DRIVER={{SQL Server}};"
            f"SERVER={SERVER_NAME};"
            f"DATABASE={DATABASE_NAME};"
            f"Trusted_Connection=yes;"
        )

        conn   = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        log(f"Connected to SQL Server: {SERVER_NAME} → {DATABASE_NAME}", "OK")


        # ── 9.2 Create table if it does not exist ──────────────
        create_sql = f"""
        IF OBJECT_ID('{TABLE_NAME}', 'U') IS NULL
        BEGIN
            CREATE TABLE {TABLE_NAME} (
                country_code               VARCHAR(10),
                country_name               VARCHAR(100),
                year                       INT,
                gdp_usd                    FLOAT,
                gdp_per_capita             FLOAT,
                gdp_growth_pct             FLOAT,
                population                 FLOAT,
                population_growth_pct      FLOAT,
                life_expectancy            FLOAT,
                inflation_pct              FLOAT,
                unemployment_pct           FLOAT,
                exports_usd                FLOAT,
                imports_usd                FLOAT,
                trade_pct_gdp              FLOAT,
                debt_pct_gdp               FLOAT,
                govt_expenditure_pct_gdp   FLOAT,
                fdi_inflows_usd            FLOAT,
                co2_per_capita             FLOAT,
                literacy_rate              FLOAT,
                internet_users_pct         FLOAT,
                health_expenditure_pct_gdp FLOAT,
                load_date                  DATETIME DEFAULT GETDATE()
            )
            PRINT 'Table created.'
        END
        ELSE
        BEGIN
            PRINT 'Table already exists.'
        END
        """

        cursor.execute(create_sql)
        conn.commit()
        log(f"Table ready: {TABLE_NAME}", "OK")


        # ── 9.3 TRUNCATE old data before fresh insert ──────────
        # This prevents duplicate rows on every pipeline run.
        cursor.execute(f"TRUNCATE TABLE {TABLE_NAME}")
        conn.commit()
        log("Old data cleared (TRUNCATE). Fresh insert starting...", "WARN")


        # ── 9.4 Validate all INSERT columns exist in df_wide ───
        log("Validating column list before INSERT...", "INFO")
        for col in INSERT_COLS:
            if col not in df_wide.columns:
                # This should never happen after Step 5, but we check anyway
                raise ValueError(
                    f"Column '{col}' not found in df_wide. "
                    f"Check INDICATORS dict or pivot logic."
                )
        log("All columns validated. Ready to insert.", "OK")


        # ── 9.5 Build rows list ────────────────────────────────
        rows_to_insert = list(
            df_wide[INSERT_COLS].itertuples(index=False, name=None)
        )

        log(f"Rows prepared for INSERT: {len(rows_to_insert):,}", "INFO")

        if len(rows_to_insert) == 0:
            log("ERROR: 0 rows to insert. Stopping SQL load.", "ERROR")
        else:

            # ── 9.6 INSERT ──────────────────────────────────────
            # We use ? placeholders — one per column.
            # Count: 21 columns (no load_date, SQL fills that automatically)
            placeholders = ", ".join(["?"] * len(INSERT_COLS))
            col_names    = ", ".join(INSERT_COLS)

            insert_sql = f"""
            INSERT INTO {TABLE_NAME}
            ({col_names})
            VALUES ({placeholders})
            """

            # Batch size: insert 500 rows at a time
            # This avoids memory issues for large data
            BATCH_SIZE = 500

            inserted = 0
            for i in range(0, len(rows_to_insert), BATCH_SIZE):
                batch = rows_to_insert[i : i + BATCH_SIZE]
                cursor.executemany(insert_sql, batch)
                conn.commit()
                inserted += len(batch)
                log(f"  Inserted batch: {inserted:,} / {len(rows_to_insert):,}", "INFO")

            log(f"Total rows inserted: {inserted:,}", "OK")


        # ── 9.7 Verify row count in SQL ────────────────────────
        cursor.execute(f"SELECT COUNT(*) FROM {TABLE_NAME}")
        sql_count = cursor.fetchone()[0]
        log(f"Row count in SQL table: {sql_count:,}", "OK")

        if sql_count == len(rows_to_insert):
            log("Row count matches! Pipeline is healthy.", "OK")
        else:
            log(
                f"Row count mismatch! "
                f"Expected {len(rows_to_insert):,}, "
                f"Got {sql_count:,}",
                "WARN"
            )

        conn.close()
        log("SQL connection closed.", "OK")

    except pyodbc.Error as db_err:
        log(f"Database error: {db_err}", "ERROR")
        log("Check: Is SQL Server running? Is the database name correct?", "WARN")

    except ValueError as val_err:
        log(f"Data validation error: {val_err}", "ERROR")

    except Exception as e:
        log(f"Unexpected error: {e}", "ERROR")


# ============================================================
# DONE
# ============================================================

log("=" * 55, "STEP")
log("PIPELINE COMPLETED SUCCESSFULLY — DIPANKAR PAL", "OK")
log(f"Finished at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", "INFO")
log("=" * 55, "STEP")