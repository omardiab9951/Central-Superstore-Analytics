"""Read-only reconciliation of the Excel source against the PostgreSQL warehouse."""

from __future__ import annotations

import hashlib
import random
import sys
from collections import defaultdict
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pandas as pd
import psycopg
from psycopg.rows import dict_row


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKBOOK_NAME = "Central_Superstore.xlsx"
SHEET_NAME = "Central_Region"
DATABASE_NAME = "central_superstore_dw"
SCHEMA_NAME = "warehouse"
RANDOM_SEED = 2026
MONEY_TOLERANCE = Decimal("0.0001")
EXPECTED_COLUMNS = [
    "Row ID", "Order ID", "Order Date", "Ship Date", "Ship Mode", "Customer ID",
    "Customer Name", "Segment", "Country", "City", "State", "Postal Code",
    "Region", "Product ID", "Category", "Sub-Category", "Product Name", "Sales",
    "Quantity", "Discount", "Profit",
]
TEXT_COLUMNS = [
    "Order ID", "Ship Mode", "Customer ID", "Customer Name", "Segment", "Country",
    "City", "State", "Region", "Product ID", "Category", "Sub-Category", "Product Name",
]
MONEY_COLUMNS = {"Sales", "Discount", "Profit"}


def locate_workbook() -> Path:
    """Find the supplied workbook at the project root or in the optional data folder."""
    for candidate in (PROJECT_ROOT / "data" / WORKBOOK_NAME, PROJECT_ROOT / WORKBOOK_NAME):
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"Could not find {WORKBOOK_NAME} in the project root or data folder")


def sha256_file(path: Path) -> str:
    """Fingerprint the source before and after reading to confirm it stayed unchanged."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_excel_source(path: Path) -> tuple[pd.DataFrame, str]:
    """Read and normalize comparison values without writing to the workbook."""
    before_hash = sha256_file(path)
    frame = pd.read_excel(
        path,
        sheet_name=SHEET_NAME,
        engine="openpyxl",
        dtype={"Postal Code": "string"},
    )
    if list(frame.columns) != EXPECTED_COLUMNS:
        raise ValueError(f"Unexpected workbook columns: {list(frame.columns)!r}")
    if len(frame) != 2_323:
        raise ValueError(f"Expected 2,323 source rows, found {len(frame):,}")
    for column in TEXT_COLUMNS:
        frame[column] = frame[column].astype("string").str.strip()
    frame["Postal Code"] = frame["Postal Code"].map(lambda value: str(value).strip().removesuffix(".0"))
    for column in ("Order Date", "Ship Date"):
        frame[column] = pd.to_datetime(frame[column], errors="raise").dt.date
    frame["Row ID"] = pd.to_numeric(frame["Row ID"], errors="raise").astype("int64")
    frame["Quantity"] = pd.to_numeric(frame["Quantity"], errors="raise").astype("int64")
    if sha256_file(path) != before_hash:
        raise RuntimeError("The workbook changed while it was being read")
    return frame, before_hash


def decimal_sum(values: Any) -> Decimal:
    """Sum source numbers through decimal strings, avoiding binary-float accumulation."""
    return sum((Decimal(str(value)) for value in values), Decimal("0"))


def print_result(check: str, expected: Any, actual: Any, passed: bool) -> bool:
    """Print one simple PASS/FAIL result and return its status."""
    print(f"{check}: expected={expected}; actual={actual}; status={'PASS' if passed else 'FAIL'}")
    return passed


def source_totals(frame: pd.DataFrame) -> dict[str, Decimal | int]:
    return {
        "Sales": decimal_sum(frame["Sales"]),
        "Profit": decimal_sum(frame["Profit"]),
        "Quantity": int(frame["Quantity"].sum()),
    }


def fetch_summary_and_groups(connection: psycopg.Connection[Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Read warehouse counts and grouped additive totals using SELECT statements only."""
    with connection.cursor() as cursor:
        cursor.execute(
            'SELECT '
            '(SELECT count(*) FROM warehouse."FactSales") AS fact_rows, '
            '(SELECT count(DISTINCT "CustomerID") FROM warehouse."DimCustomer") AS customers, '
            '(SELECT count(DISTINCT "ProductID") FROM warehouse."DimProduct") AS product_ids, '
            '(SELECT count(*) FROM warehouse."DimProduct") AS product_members, '
            '(SELECT count(*) FROM warehouse."DimLocation") AS locations, '
            '(SELECT count(DISTINCT "OrderID") FROM warehouse."FactSales") AS orders, '
            '(SELECT COALESCE(sum("Sales"), 0) FROM warehouse."FactSales") AS sales, '
            '(SELECT COALESCE(sum("Profit"), 0) FROM warehouse."FactSales") AS profit, '
            '(SELECT COALESCE(sum("Quantity"), 0) FROM warehouse."FactSales") AS quantity'
        )
        summary = cursor.fetchone()

        cursor.execute(
            'SELECT p."Category" AS category, sum(f."Sales") AS sales, sum(f."Profit") AS profit '
            'FROM warehouse."FactSales" f '
            'JOIN warehouse."DimProduct" p ON p."ProductKey" = f."ProductKey" '
            'GROUP BY p."Category" ORDER BY p."Category"'
        )
        category = {row["category"]: {"Sales": row["sales"], "Profit": row["profit"]} for row in cursor.fetchall()}

        cursor.execute(
            'SELECT l."Region" AS region, l."State" AS state, '
            'sum(f."Sales") AS sales, sum(f."Profit") AS profit '
            'FROM warehouse."FactSales" f '
            'JOIN warehouse."DimLocation" l ON l."LocationKey" = f."LocationKey" '
            'GROUP BY l."Region", l."State" ORDER BY l."Region", l."State"'
        )
        region_state = {
            (row["region"], row["state"]): {"Sales": row["sales"], "Profit": row["profit"]}
            for row in cursor.fetchall()
        }
    return summary, category, region_state


def excel_group_totals(frame: pd.DataFrame, group_columns: list[str]) -> dict[Any, dict[str, Decimal]]:
    groups: dict[Any, dict[str, list[Decimal]]] = defaultdict(lambda: {"Sales": [], "Profit": []})
    for row in frame[group_columns + ["Sales", "Profit"]].itertuples(index=False, name=None):
        key_values = row[:len(group_columns)]
        key = key_values[0] if len(key_values) == 1 else tuple(key_values)
        groups[key]["Sales"].append(Decimal(str(row[-2])))
        groups[key]["Profit"].append(Decimal(str(row[-1])))
    return {
        key: {measure: sum(values, Decimal("0")) for measure, values in measures.items()}
        for key, measures in groups.items()
    }


def compare_groups(
    heading: str,
    excel_groups: dict[Any, dict[str, Decimal]],
    database_groups: dict[Any, dict[str, Any]],
) -> list[bool]:
    """Print Excel, database, and signed differences for each group and measure."""
    print(f"\n{heading} (tolerance: absolute difference <= {MONEY_TOLERANCE})")
    print("group | measure | Excel | PostgreSQL | difference (PostgreSQL - Excel) | status")
    results = []
    all_keys = sorted(set(excel_groups) | set(database_groups), key=str)
    for key in all_keys:
        excel_values = excel_groups.get(key, {"Sales": Decimal("0"), "Profit": Decimal("0")})
        database_values = database_groups.get(key, {"Sales": Decimal("0"), "Profit": Decimal("0")})
        for measure in ("Sales", "Profit"):
            expected = excel_values[measure]
            actual = Decimal(str(database_values[measure]))
            difference = actual - expected
            passed = abs(difference) <= MONEY_TOLERANCE
            print(f"{key} | {measure} | {expected} | {actual} | {difference} | {'PASS' if passed else 'FAIL'}")
            results.append(passed)
    return results


def compare_random_facts(connection: psycopg.Connection[Any], frame: pd.DataFrame) -> list[bool]:
    """Sample 20 source row IDs and compare every Excel field through dimension joins."""
    row_ids = frame["Row ID"].tolist()
    sampled_ids = random.Random(RANDOM_SEED).sample(row_ids, 20)
    sql = '''
        SELECT f."SourceRowID" AS "Row ID",
               f."OrderID" AS "Order ID",
               order_date."FullDate" AS "Order Date",
               ship_date."FullDate" AS "Ship Date",
               f."ShipMode" AS "Ship Mode",
               c."CustomerID" AS "Customer ID",
               c."CustomerName" AS "Customer Name",
               c."Segment" AS "Segment",
               l."Country" AS "Country",
               l."City" AS "City",
               l."State" AS "State",
               l."PostalCode" AS "Postal Code",
               l."Region" AS "Region",
               p."ProductID" AS "Product ID",
               p."Category" AS "Category",
               p."SubCategory" AS "Sub-Category",
               p."ProductName" AS "Product Name",
               f."Sales" AS "Sales",
               f."Quantity" AS "Quantity",
               f."Discount" AS "Discount",
               f."Profit" AS "Profit"
        FROM warehouse."FactSales" f
        JOIN warehouse."DimDate" order_date ON order_date."DateKey" = f."OrderDateKey"
        JOIN warehouse."DimDate" ship_date ON ship_date."DateKey" = f."ShipDateKey"
        JOIN warehouse."DimCustomer" c ON c."CustomerKey" = f."CustomerKey"
        JOIN warehouse."DimProduct" p ON p."ProductKey" = f."ProductKey"
        JOIN warehouse."DimLocation" l ON l."LocationKey" = f."LocationKey"
        WHERE f."SourceRowID" = ANY(%s)
    '''
    with connection.cursor() as cursor:
        cursor.execute(sql, (sampled_ids,))
        database_rows = {row["Row ID"]: row for row in cursor.fetchall()}
    source_rows = frame.set_index("Row ID", drop=False)
    print(f"\nRandom fact comparison: seed={RANDOM_SEED}; rows=20; columns per row={len(EXPECTED_COLUMNS)}")
    results: list[bool] = []
    comparisons = 0
    for row_id in sampled_ids:
        source = source_rows.loc[row_id]
        actual = database_rows.get(row_id)
        if actual is None:
            print(f"Row ID {row_id}: missing from PostgreSQL result - FAIL")
            results.append(False)
            continue
        mismatches = []
        for column in EXPECTED_COLUMNS:
            expected_value = source[column]
            actual_value = actual[column]
            comparisons += 1
            if column in MONEY_COLUMNS:
                difference = Decimal(str(actual_value)) - Decimal(str(expected_value))
                if abs(difference) > MONEY_TOLERANCE:
                    mismatches.append(f"{column} delta={difference}")
            elif column in ("Order Date", "Ship Date"):
                if actual_value != expected_value:
                    mismatches.append(f"{column} Excel={expected_value!r} DB={actual_value!r}")
            elif column in ("Row ID", "Quantity"):
                if int(actual_value) != int(expected_value):
                    mismatches.append(f"{column} Excel={expected_value!r} DB={actual_value!r}")
            else:
                expected_text = str(expected_value).strip()
                if str(actual_value).strip() != expected_text:
                    mismatches.append(f"{column} Excel={expected_text!r} DB={actual_value!r}")
        passed = not mismatches
        results.append(passed)
        detail = "; ".join(mismatches) if mismatches else f"all {len(EXPECTED_COLUMNS)} columns match"
        print(f"Row ID {row_id}: {detail} - {'PASS' if passed else 'FAIL'}")
    print(f"Column comparisons performed: {comparisons}; expected: {20 * len(EXPECTED_COLUMNS)}")
    return results


def main() -> int:
    workbook_path = locate_workbook()
    frame, source_hash = read_excel_source(workbook_path)
    source = source_totals(frame)
    print(f"Source: {workbook_path}; sheet={SHEET_NAME}; rows={len(frame)}; columns={len(frame.columns)}")
    print(f"Read-only workbook SHA-256: {source_hash}")
    print(f"Money comparison tolerance: absolute difference <= {MONEY_TOLERANCE}")

    # PostgreSQL is explicitly put in read-only mode to prevent accidental edits.
    settings = {
        "host": "localhost",
        "port": 5432,
        "user": "postgres",
        "dbname": DATABASE_NAME,
        "connect_timeout": 10,
        "application_name": "central_superstore_phase5_reconciliation",
        "options": "-c default_transaction_read_only=on",
        "row_factory": dict_row,
    }
    results: list[bool] = []
    with psycopg.connect(**settings) as connection:
        with connection.transaction():
            connection.execute("SET TRANSACTION READ ONLY")
            database_summary, database_category, database_region_state = fetch_summary_and_groups(connection)

            print("\nOverall row counts and totals:")
            results.append(print_result("FactSales rows", len(frame), database_summary["fact_rows"], len(frame) == database_summary["fact_rows"]))
            for label, source_count, database_count in (
                ("distinct customers", int(frame["Customer ID"].nunique()), database_summary["customers"]),
                ("distinct Product IDs", int(frame["Product ID"].nunique()), database_summary["product_ids"]),
                ("distinct product members", int(frame[["Product ID", "Product Name"]].drop_duplicates().shape[0]), database_summary["product_members"]),
                ("distinct locations", int(frame[["Country", "State", "City", "Postal Code"]].drop_duplicates().shape[0]), database_summary["locations"]),
                ("distinct orders", int(frame["Order ID"].nunique()), database_summary["orders"]),
            ):
                results.append(print_result(label, source_count, database_count, source_count == database_count))

            for measure in ("Sales", "Profit"):
                excel_total = source[measure]
                database_total = Decimal(str(database_summary[measure.lower()]))
                difference = database_total - excel_total
                passed = abs(difference) <= MONEY_TOLERANCE
                results.append(print_result(
                    f"total {measure} (tolerance {MONEY_TOLERANCE})",
                    excel_total,
                    f"{database_total}; difference={difference}",
                    passed,
                ))
            excel_quantity = source["Quantity"]
            database_quantity = database_summary["quantity"]
            results.append(print_result("total Quantity (exact integer comparison)", excel_quantity, database_quantity, excel_quantity == database_quantity))

            results.extend(compare_groups(
                "Sales and Profit by Category",
                excel_group_totals(frame, ["Category"]),
                database_category,
            ))
            results.extend(compare_groups(
                "Sales and Profit by Region/State",
                excel_group_totals(frame, ["Region", "State"]),
                database_region_state,
            ))
            results.extend(compare_random_facts(connection, frame))

    if sha256_file(workbook_path) != source_hash:
        raise RuntimeError("The source workbook hash changed during reconciliation")
    results.append(print_result("source workbook unchanged", source_hash, sha256_file(workbook_path), True))
    failures = len([result for result in results if not result])
    print(f"\nReconciliation summary: {len(results) - failures} PASS, {failures} FAIL")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Reconciliation failed: {type(error).__name__}: {error}", file=sys.stderr)
        raise