"""Load the Central Superstore workbook into the PostgreSQL warehouse."""

from __future__ import annotations

import argparse
import hashlib
from calendar import month_name
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

import pandas as pd
import psycopg


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SHEET_NAME = "Central_Region"
WORKBOOK_NAME = "Central_Superstore.xlsx"
DATABASE_NAME = "central_superstore_dw"
SCHEMA_NAME = "warehouse"
EXPECTED_ROWS = 2_323
EXPECTED_COLUMNS = [
    "Row ID",
    "Order ID",
    "Order Date",
    "Ship Date",
    "Ship Mode",
    "Customer ID",
    "Customer Name",
    "Segment",
    "Country",
    "City",
    "State",
    "Postal Code",
    "Region",
    "Product ID",
    "Category",
    "Sub-Category",
    "Product Name",
    "Sales",
    "Quantity",
    "Discount",
    "Profit",
]
TEXT_COLUMNS = [
    "Order ID",
    "Ship Mode",
    "Customer ID",
    "Customer Name",
    "Segment",
    "Country",
    "City",
    "State",
    "Region",
    "Product ID",
    "Category",
    "Sub-Category",
    "Product Name",
]
LOCATION_COLUMNS = ["Country", "State", "City", "Postal Code"]
DATE_COLUMNS = ["Order Date", "Ship Date"]


def find_workbook() -> Path:
    """Find the original workbook in either documented project location."""
    candidates = [
        PROJECT_ROOT / "data" / WORKBOOK_NAME,
        PROJECT_ROOT / WORKBOOK_NAME,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    tried = ", ".join(str(path) for path in candidates)
    raise FileNotFoundError(f"Could not find {WORKBOOK_NAME}; searched: {tried}")


def sha256_file(path: Path) -> str:
    """Calculate a file fingerprint without changing the file."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decimal_at_scale(value: Any, scale: int, column: str, source_row_id: Any) -> tuple[Decimal, bool]:
    """Convert a numeric cell to Decimal and report whether scale rounding occurred."""
    try:
        number = Decimal(str(value))
        quantum = Decimal(1).scaleb(-scale)
        rounded = number.quantize(quantum)
    except (InvalidOperation, ValueError) as error:
        raise ValueError(
            f"Invalid numeric value in {column!r} for source Row ID {source_row_id!r}: {value!r}"
        ) from error
    if not rounded.is_finite():
        raise ValueError(f"Non-finite numeric value in {column!r}: {value!r}")
    return rounded, rounded != number


def clean_source(
    workbook_path: Path,
) -> tuple[pd.DataFrame, list[dict[str, Any]], str, dict[str, Decimal | int]]:
    """Read Excel values and apply only the documented, auditable conversions."""
    source_hash = sha256_file(workbook_path)
    # Reading postal codes as strings avoids numerical formatting and leading-zero loss.
    source = pd.read_excel(
        workbook_path,
        sheet_name=SHEET_NAME,
        engine="openpyxl",
        dtype={"Postal Code": "string"},
    )
    if len(source) != EXPECTED_ROWS:
        raise ValueError(f"Expected {EXPECTED_ROWS:,} source rows, found {len(source):,}")
    if list(source.columns) != EXPECTED_COLUMNS:
        raise ValueError(f"Source columns differ from the Phase 1 profile: {list(source.columns)!r}")

    # Capture totals before scale normalization for an independent source reconciliation.
    raw_source_totals: dict[str, Decimal | int] = {
        "Sales": sum((Decimal(str(value)) for value in source["Sales"]), Decimal("0")),
        "Profit": sum((Decimal(str(value)) for value in source["Profit"]), Decimal("0")),
        "Quantity": int(pd.to_numeric(source["Quantity"], errors="raise").sum()),
    }

    cleaning_log: list[dict[str, Any]] = []

    # Remove accidental outer spaces from all text attributes without changing internal text.
    trim_changed_rows: set[int] = set()
    trim_changed_cells = 0
    for column in TEXT_COLUMNS:
        before = source[column].astype("string")
        after = before.str.strip()
        changed = before.notna() & before.ne(after)
        trim_changed_cells += int(changed.sum())
        trim_changed_rows.update(source.index[changed].tolist())
        source[column] = after
    cleaning_log.append({
        "action": "Trim leading/trailing spaces in all text columns",
        "affected_rows": len(trim_changed_rows),
        "affected_values": trim_changed_cells,
        "details": "Only outer whitespace was removed; internal product/customer text was kept as-is.",
    })

    # Convert Excel dates to Python date objects, which map directly to PostgreSQL DATE.
    for column in DATE_COLUMNS:
        converted = pd.to_datetime(source[column], errors="raise").dt.date
        source[column] = converted
        cleaning_log.append({
            "action": f"Convert {column} values to calendar dates",
            "affected_rows": len(source),
            "affected_values": int(converted.notna().sum()),
            "details": "Excel date values were converted to Python date values; their calendar days were preserved.",
        })

    # Keep postal codes textual. Numeric source values are rendered without a decimal suffix.
    def postal_as_text(value: Any) -> str:
        if pd.isna(value):
            raise ValueError("Postal Code contains a missing value")
        text = str(value).strip()
        if text.endswith(".0") and text[:-2].isdigit():
            text = text[:-2]
        return text

    source["Postal Code"] = source["Postal Code"].map(postal_as_text).astype("string")
    cleaning_log.append({
        "action": "Represent Postal Code as text",
        "affected_rows": len(source),
        "affected_values": len(source),
        "details": "All source postal codes are kept as text; existing text zeroes are not parsed as numbers.",
    })

    # Prepare exact decimal values matching the warehouse's NUMERIC scales.
    decimal_rounding: dict[str, int] = {}
    for column, scale in (("Sales", 4), ("Profit", 4), ("Discount", 4)):
        rounded_count = 0
        converted_values = []
        for row in source[["Row ID", column]].itertuples(index=False, name=None):
            value, rounded = decimal_at_scale(row[1], scale, column, row[0])
            converted_values.append(value)
            rounded_count += int(rounded)
        source[column] = converted_values
        decimal_rounding[column] = rounded_count
        cleaning_log.append({
            "action": f"Convert {column} to Decimal with {scale} fractional digits",
            "affected_rows": len(source),
            "affected_values": len(source),
            "details": f"Values rounded to the warehouse scale: {rounded_count}.",
        })

    original_row_ids = source["Row ID"].copy()
    original_quantities = source["Quantity"].copy()
    source["Row ID"] = pd.to_numeric(source["Row ID"], errors="raise").astype("int64")
    source["Quantity"] = pd.to_numeric(source["Quantity"], errors="raise").astype("int64")
    integer_value_changes = int(original_row_ids.ne(source["Row ID"]).sum()) + int(
        original_quantities.ne(source["Quantity"]).sum()
    )
    cleaning_log.append({
        "action": "Validate and store Row ID and Quantity as whole numbers",
        "affected_rows": len(source),
        "affected_values": 2 * len(source),
        "details": f"Both columns were checked and cast to integer; numeric values changed: {integer_value_changes}.",
    })
    if source.isna().any().any():
        missing_by_column = source.isna().sum()
        missing = {name: int(count) for name, count in missing_by_column.items() if count}
        raise ValueError(f"Unexpected missing values after extraction/cleaning: {missing}")
    if source["Row ID"].duplicated().any():
        raise ValueError("Row ID is not unique; refusing to load ambiguous source rows")
    if (source["Quantity"] <= 0).any():
        raise ValueError("Quantity must be a positive whole number")
    if any(value < 0 for value in source["Sales"]):
        raise ValueError("Sales contains a negative value, which violates the approved database check")
    if any(value < 0 or value > 1 for value in source["Discount"]):
        raise ValueError("Discount contains a value outside the approved 0-to-1 range")
    if any(source["Ship Date"] < source["Order Date"]):
        raise ValueError("At least one Ship Date occurs before its Order Date")

    if sha256_file(workbook_path) != source_hash:
        raise RuntimeError("Source workbook hash changed during read-only profiling")
    return source, cleaning_log, source_hash, raw_source_totals


def build_dimensions(source: pd.DataFrame) -> tuple[pd.DataFrame, ...]:
    """Build one row per approved dimension natural key and assign surrogate keys."""
    customer_attributes = source.groupby("Customer ID", dropna=False)[["Customer Name", "Segment"]].nunique()
    if (customer_attributes > 1).any().any():
        raise ValueError("Customer ID maps to more than one name or segment after trimming")

    product_attributes = source.groupby(["Product ID", "Product Name"], dropna=False)[["Category", "Sub-Category"]].nunique()
    if (product_attributes > 1).any().any():
        raise ValueError("A (Product ID, Product Name) natural key maps to conflicting category data")

    dim_customer = (
        source[["Customer ID", "Customer Name", "Segment"]]
        .drop_duplicates()
        .sort_values(["Customer ID"], kind="stable")
        .reset_index(drop=True)
    )
    dim_customer.insert(0, "CustomerKey", range(1, len(dim_customer) + 1))

    dim_product = (
        source[["Product ID", "Product Name", "Category", "Sub-Category"]]
        .drop_duplicates(subset=["Product ID", "Product Name"])
        .sort_values(["Product ID", "Product Name"], kind="stable")
        .reset_index(drop=True)
    )
    dim_product.insert(0, "ProductKey", range(1, len(dim_product) + 1))

    dim_location = (
        source[LOCATION_COLUMNS + ["Region"]]
        .drop_duplicates(subset=LOCATION_COLUMNS)
        .sort_values(LOCATION_COLUMNS, kind="stable")
        .reset_index(drop=True)
    )
    dim_location.insert(0, "LocationKey", range(1, len(dim_location) + 1))

    all_dates = source[DATE_COLUMNS].to_numpy().ravel().tolist()
    first_date = min(all_dates)
    last_date = max(all_dates)
    calendar_dates = [first_date + timedelta(days=offset) for offset in range((last_date - first_date).days + 1)]
    weekday_names = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    date_rows = []
    for calendar_day in calendar_dates:
        date_rows.append({
            "DateKey": int(calendar_day.strftime("%Y%m%d")),
            "FullDate": calendar_day,
            "Year": calendar_day.year,
            "Quarter": (calendar_day.month - 1) // 3 + 1,
            "Month": calendar_day.month,
            "MonthName": month_name[calendar_day.month],
            "Day": calendar_day.day,
            "DayOfWeek": weekday_names[calendar_day.weekday()],
            "IsWeekend": calendar_day.weekday() >= 5,
        })
    dim_date = pd.DataFrame(date_rows)
    return dim_date, dim_customer, dim_product, dim_location


def build_fact(source: pd.DataFrame, dimensions: tuple[pd.DataFrame, ...]) -> pd.DataFrame:
    """Look up every warehouse surrogate key and retain source line measures."""
    dim_date, dim_customer, dim_product, dim_location = dimensions
    fact = source.copy()
    fact["OrderDateKey"] = fact["Order Date"].map(
        dict(zip(dim_date["FullDate"], dim_date["DateKey"], strict=True))
    )
    fact["ShipDateKey"] = fact["Ship Date"].map(
        dict(zip(dim_date["FullDate"], dim_date["DateKey"], strict=True))
    )

    # Merge with each natural key and validate that every source line finds one dimension row.
    customer_lookup = dim_customer[["Customer ID", "CustomerKey"]]
    fact = fact.merge(customer_lookup, on="Customer ID", how="left", validate="many_to_one", sort=False)

    product_lookup = dim_product[["Product ID", "Product Name", "ProductKey"]]
    fact = fact.merge(
        product_lookup,
        on=["Product ID", "Product Name"],
        how="left",
        validate="many_to_one",
        sort=False,
    )

    location_lookup = dim_location[LOCATION_COLUMNS + ["LocationKey"]]
    fact = fact.merge(
        location_lookup,
        on=LOCATION_COLUMNS,
        how="left",
        validate="many_to_one",
        sort=False,
    )

    if len(fact) != len(source):
        raise ValueError(f"Fact key lookups changed row count: {len(source)} source vs {len(fact)} fact")
    foreign_keys = ["OrderDateKey", "ShipDateKey", "CustomerKey", "ProductKey", "LocationKey"]
    if fact[foreign_keys].isna().any().any():
        null_counts = {name: int(count) for name, count in fact[foreign_keys].isna().sum().items() if count}
        raise ValueError(f"A source line did not resolve to dimension keys: {null_counts}")

    return fact[[
        "Row ID",
        "Order ID",
        "OrderDateKey",
        "ShipDateKey",
        "CustomerKey",
        "ProductKey",
        "LocationKey",
        "Ship Mode",
        "Sales",
        "Quantity",
        "Discount",
        "Profit",
    ]].rename(columns={
        "Row ID": "SourceRowID",
        "Order ID": "OrderID",
        "Ship Mode": "ShipMode",
    })


def copy_frame(cursor: psycopg.Cursor[Any], table: str, columns: list[str], frame: pd.DataFrame) -> None:
    """Use PostgreSQL's COPY protocol to transfer a DataFrame efficiently."""
    column_sql = ", ".join(f'"{column}"' for column in columns)
    copy_sql = f'COPY warehouse."{table}" ({column_sql}) FROM STDIN'
    with cursor.copy(copy_sql) as copy:
        for row in frame[columns].itertuples(index=False, name=None):
            # Convert NumPy scalar wrappers to ordinary Python values for psycopg adapters.
            copy.write_row(tuple(value.item() if hasattr(value, "item") else value for value in row))


def set_identity_sequence(cursor: psycopg.Cursor[Any], table: str, column: str, maximum: int) -> None:
    """Advance an identity sequence after loading explicit deterministic dimension keys."""
    sequence_name = cursor.execute(
        "SELECT pg_get_serial_sequence(%s, %s)",
        (f'{SCHEMA_NAME}."{table}"', column),
    ).fetchone()[0]
    if sequence_name and maximum > 0:
        cursor.execute("SELECT setval(%s, %s, true)", (sequence_name, maximum))


def expected_totals(source: pd.DataFrame) -> dict[str, Decimal | int]:
    """Calculate source totals after normalization to the warehouse's declared scales."""
    return {
        "Sales": sum(source["Sales"], Decimal("0")),
        "Profit": sum(source["Profit"], Decimal("0")),
        "Quantity": int(source["Quantity"].sum()),
    }


def load_transaction(
    source: pd.DataFrame,
    dimensions: tuple[pd.DataFrame, ...],
    fact: pd.DataFrame,
    raw_source_totals: dict[str, Decimal | int],
    database_name: str = DATABASE_NAME,
) -> dict[str, Any]:
    """Clear and reload all warehouse tables in one all-or-nothing transaction."""
    dim_date, dim_customer, dim_product, dim_location = dimensions
    connection_settings = {
        "host": "localhost",
        "port": 5432,
        "user": "postgres",
        "dbname": database_name,
        "connect_timeout": 10,
        "application_name": "central_superstore_phase4_etl",
    }
    # libpq reads the existing pgpass.conf file; no password is stored in this project.
    with psycopg.connect(**connection_settings) as connection:
        with connection.cursor() as cursor:
            # Truncate the fact and all referenced dimensions in one statement.
            # PostgreSQL requires every table linked by these foreign keys to be named together.
            cursor.execute(
                'TRUNCATE TABLE warehouse."FactSales", warehouse."DimDate", '
                'warehouse."DimCustomer", warehouse."DimProduct", warehouse."DimLocation" '
                'RESTART IDENTITY'
            )

            copy_frame(
                cursor,
                "DimDate",
                ["DateKey", "FullDate", "Year", "Quarter", "Month", "MonthName", "Day", "DayOfWeek", "IsWeekend"],
                dim_date,
            )
            copy_frame(cursor, "DimCustomer", ["CustomerKey", "CustomerID", "CustomerName", "Segment"],
                       dim_customer.rename(columns={"Customer ID": "CustomerID", "Customer Name": "CustomerName"}))
            copy_frame(cursor, "DimProduct", ["ProductKey", "ProductID", "ProductName", "Category", "SubCategory"],
                       dim_product.rename(columns={"Product ID": "ProductID", "Product Name": "ProductName", "Sub-Category": "SubCategory"}))
            copy_frame(cursor, "DimLocation", ["LocationKey", "Country", "State", "City", "PostalCode", "Region"],
                       dim_location.rename(columns={"Postal Code": "PostalCode"}))

            # Explicit dimension keys are assigned deterministically; advance identity sequences for later inserts.
            set_identity_sequence(cursor, "DimCustomer", "CustomerKey", len(dim_customer))
            set_identity_sequence(cursor, "DimProduct", "ProductKey", len(dim_product))
            set_identity_sequence(cursor, "DimLocation", "LocationKey", len(dim_location))

            copy_frame(
                cursor,
                "FactSales",
                ["SourceRowID", "OrderID", "OrderDateKey", "ShipDateKey", "CustomerKey", "ProductKey",
                 "LocationKey", "ShipMode", "Sales", "Quantity", "Discount", "Profit"],
                fact,
            )
            # Validate before commit: any failed check raises and rolls back the whole load.
            results = validate_loaded_data(cursor, source, dimensions, raw_source_totals)
    return results


def validate_loaded_data(
    cursor: psycopg.Cursor[Any],
    source: pd.DataFrame,
    dimensions: tuple[pd.DataFrame, ...],
    raw_source_totals: dict[str, Decimal | int],
) -> dict[str, Any]:
    """Compare uncommitted database rows and totals with the values prepared from Excel."""
    dim_date, dim_customer, dim_product, dim_location = dimensions
    expected_counts = {
        "DimDate": len(dim_date),
        "DimCustomer": len(dim_customer),
        "DimProduct": len(dim_product),
        "DimLocation": len(dim_location),
        "FactSales": len(source),
    }
    totals = expected_totals(source)
    results: dict[str, Any] = {
        "expected_counts": expected_counts,
        "expected_totals": totals,
        "raw_source_totals": raw_source_totals,
    }
    results["actual_counts"] = {}
    for table in ("DimDate", "DimCustomer", "DimProduct", "DimLocation", "FactSales"):
        cursor.execute(f'SELECT count(*) FROM warehouse."{table}"')
        results["actual_counts"][table] = cursor.fetchone()[0]
    cursor.execute(
        'SELECT count(*) FILTER (WHERE "OrderDateKey" IS NULL) + '
        'count(*) FILTER (WHERE "ShipDateKey" IS NULL) + '
        'count(*) FILTER (WHERE "CustomerKey" IS NULL) + '
        'count(*) FILTER (WHERE "ProductKey" IS NULL) + '
        'count(*) FILTER (WHERE "LocationKey" IS NULL) '
        'FROM warehouse."FactSales"'
    )
    results["null_foreign_key_cells"] = cursor.fetchone()[0]
    cursor.execute(
        'SELECT count(*), min("FullDate"), max("FullDate"), '
        'count(*) FILTER (WHERE "IsWeekend") '
        'FROM warehouse."DimDate"'
    )
    date_count, first_date, last_date, weekend_count = cursor.fetchone()
    results["calendar"] = {
        "count": date_count,
        "first_date": first_date,
        "last_date": last_date,
        "weekend_days": weekend_count,
    }
    cursor.execute(
        'SELECT COALESCE(sum("Sales"), 0), COALESCE(sum("Profit"), 0), '
        'COALESCE(sum("Quantity"), 0) FROM warehouse."FactSales"'
    )
    actual_sales, actual_profit, actual_quantity = cursor.fetchone()
    results["actual_totals"] = {
        "Sales": actual_sales,
        "Profit": actual_profit,
        "Quantity": actual_quantity,
    }
    if results["actual_counts"] != expected_counts:
        raise AssertionError(f"Table row counts do not match: {results}")
    if results["null_foreign_key_cells"] != 0:
        raise AssertionError(f"FactSales contains NULL foreign keys: {results['null_foreign_key_cells']}")
    for measure in ("Sales", "Profit", "Quantity"):
        if results["actual_totals"][measure] != totals[measure]:
            raise AssertionError(
                f"{measure} total differs: source={totals[measure]}, database={results['actual_totals'][measure]}"
            )
        if measure in ("Sales", "Profit"):
            # Compare the independent raw Excel sum after the database column's four-place scale.
            rounded_raw_total = raw_source_totals[measure].quantize(Decimal("0.0001"))
            if results["actual_totals"][measure] != rounded_raw_total:
                raise AssertionError(
                    f"{measure} differs from the raw Excel total at NUMERIC(14,4) scale: "
                    f"source={raw_source_totals[measure]}, database={results['actual_totals'][measure]}"
                )
    if results["calendar"]["count"] != (results["calendar"]["last_date"] - results["calendar"]["first_date"]).days + 1:
        raise AssertionError(f"DimDate is not continuous: {results['calendar']}")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only extract and transactional load for the Superstore warehouse.")
    parser.add_argument("--workbook", type=Path, help="Optional explicit path to Central_Superstore.xlsx")
    parser.add_argument(
        "--database",
        default=DATABASE_NAME,
        help="Target database (defaults to the project warehouse; useful for isolated rebuild tests).",
    )
    args = parser.parse_args()
    workbook_path = args.workbook.resolve() if args.workbook else find_workbook()
    if not workbook_path.is_file():
        raise FileNotFoundError(workbook_path)

    print(f"Source workbook: {workbook_path}")
    print(f"Target database: {args.database}")
    source, cleaning_log, source_hash, raw_source_totals = clean_source(workbook_path)
    print(f"Extracted: {len(source):,} rows x {len(source.columns)} columns from {SHEET_NAME}")
    print(f"Source SHA-256 (read-only check): {source_hash}")
    print("Cleaning log:")
    for entry in cleaning_log:
        print(
            f"  - {entry['action']}: {entry['affected_values']:,} values across "
            f"{entry['affected_rows']:,} rows. {entry['details']}"
        )

    dimensions = build_dimensions(source)
    fact = build_fact(source, dimensions)
    print("Prepared dimension counts:")
    for name, frame in zip(("DimDate", "DimCustomer", "DimProduct", "DimLocation"), dimensions, strict=True):
        print(f"  - {name}: {len(frame):,}")
    print(f"  - FactSales: {len(fact):,}")

    results = load_transaction(source, dimensions, fact, raw_source_totals, args.database)
    print("Post-load validation:")
    for table, expected in results["expected_counts"].items():
        actual = results["actual_counts"][table]
        print(f"  - {table}: {actual:,} rows (expected {expected:,}) - {'PASS' if actual == expected else 'FAIL'}")
    print(f"  - NULL foreign-key cells in FactSales: {results['null_foreign_key_cells']} - PASS")
    for measure in ("Sales", "Profit", "Quantity"):
        print(
            f"  - Total {measure}: database={results['actual_totals'][measure]} "
            f"Excel raw={results['raw_source_totals'][measure]} "
            f"normalized={results['expected_totals'][measure]} - PASS (at warehouse precision)"
        )
    print(
        f"  - Continuous DimDate: {results['calendar']['first_date']} through "
        f"{results['calendar']['last_date']} ({results['calendar']['count']:,} days) - PASS"
    )
    if sha256_file(workbook_path) != source_hash:
        raise RuntimeError("Source workbook hash changed during ETL; investigate immediately")
    print("Source workbook unchanged: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Keep the exception visible; psycopg's connection context rolls back failed transactions.
        print(f"ETL failed: {type(error).__name__}: {error}")
        raise