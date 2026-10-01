"""Repeatable read-only EXPLAIN benchmarking for Phase 10."""

from __future__ import annotations

import argparse
import hashlib
import statistics
from typing import Any

import psycopg
from psycopg.rows import dict_row


WORKLOADS = {
    "Q1_order_date_range": '''
        SELECT count(*) AS lines, sum(f."Sales") AS sales, sum(f."Profit") AS profit
        FROM warehouse."FactSales" AS f
        JOIN warehouse."DimDate" AS d ON d."DateKey" = f."OrderDateKey"
        WHERE d."FullDate" >= DATE '2015-01-01'
          AND d."FullDate" < DATE '2016-01-01'
    ''',
    "Q2_customer_lookup": '''
        SELECT c."CustomerID", sum(f."Sales") AS sales, sum(f."Profit") AS profit
        FROM warehouse."DimCustomer" AS c
        JOIN warehouse."FactSales" AS f ON f."CustomerKey" = c."CustomerKey"
        WHERE c."CustomerID" = 'AB-10105'
        GROUP BY c."CustomerID"
    ''',
    "Q3_product_member_lookup": '''
        SELECT p."ProductKey", p."ProductID", p."ProductName",
               sum(f."Sales") AS sales, sum(f."Profit") AS profit
        FROM warehouse."DimProduct" AS p
        JOIN warehouse."FactSales" AS f ON f."ProductKey" = p."ProductKey"
        WHERE p."ProductID" = 'OFF-BI-10004995'
        GROUP BY p."ProductKey", p."ProductID", p."ProductName"
        ORDER BY p."ProductKey"
    ''',
    "Q4_location_view_filter": '''
        SELECT region, state, product_category, total_sales, total_profit
        FROM warehouse.vw_category_region_profitability
        WHERE state = 'Texas' AND product_category = 'Office Supplies'
        ORDER BY region, state, product_category
    ''',
    "Q5_ship_date_range": '''
        SELECT count(*) AS lines, sum(f."Sales") AS sales
        FROM warehouse."FactSales" AS f
        JOIN warehouse."DimDate" AS d ON d."DateKey" = f."ShipDateKey"
        WHERE d."FullDate" >= DATE '2016-10-01'
          AND d."FullDate" < DATE '2017-01-01'
    ''',
    "Q6_period_kpi_function": '''
        SELECT *
        FROM warehouse.fn_kpi_by_period(DATE '2015-01-01', DATE '2015-12-31', 'month', 'Furniture', NULL)
        ORDER BY period_start
    ''',
}

REWRITES = {
    "filter_early": {
        "original": '''
            SELECT state, product_category, sum(sales) AS sales, sum(profit) AS profit
            FROM (SELECT * FROM warehouse.vw_sales_detail) AS all_lines
            GROUP BY state, product_category
            HAVING state = 'Texas' AND product_category = 'Furniture'
            ORDER BY state, product_category
        ''',
        "rewritten": '''
            SELECT state, product_category, sum(sales) AS sales, sum(profit) AS profit
            FROM warehouse.vw_sales_detail
            WHERE state = 'Texas' AND product_category = 'Furniture'
            GROUP BY state, product_category
            ORDER BY state, product_category
        ''',
    },
    "select_needed_columns": {
        "original": '''
            SELECT wide.source_row_id, wide.order_id, wide.sales, wide.profit
            FROM (SELECT * FROM warehouse.vw_sales_detail) AS wide
            WHERE wide.order_id = 'CA-2011-112326'
            ORDER BY wide.source_row_id
        ''',
        "rewritten": '''
            SELECT source_row_id, order_id, sales, profit
            FROM warehouse.vw_sales_detail
            WHERE order_id = 'CA-2011-112326'
            ORDER BY source_row_id
        ''',
    },
    "sargable_date_filter": {
        "original": '''
            SELECT f."SourceRowID", f."Sales", f."Profit"
            FROM warehouse."FactSales" AS f
            JOIN warehouse."DimDate" AS d ON d."DateKey" = f."OrderDateKey"
            WHERE date_trunc('month', d."FullDate") = TIMESTAMP '2015-06-01 00:00:00'
            ORDER BY f."SourceRowID"
        ''',
        "rewritten": '''
            SELECT f."SourceRowID", f."Sales", f."Profit"
            FROM warehouse."FactSales" AS f
            JOIN warehouse."DimDate" AS d ON d."DateKey" = f."OrderDateKey"
            WHERE d."FullDate" >= DATE '2015-06-01'
              AND d."FullDate" < DATE '2015-07-01'
            ORDER BY f."SourceRowID"
        ''',
    },
    "correlated_average_to_join": {
        "original": '''
            SELECT p.product_key, p.product_id, p.product_name, p.product_category,
                   p.total_profit,
                   (SELECT avg(peer.total_profit)
                    FROM warehouse.vw_product_performance AS peer
                    WHERE peer.product_category = p.product_category) AS category_average_profit
            FROM warehouse.vw_product_performance AS p
            WHERE p.total_profit < (
                SELECT avg(peer.total_profit)
                FROM warehouse.vw_product_performance AS peer
                WHERE peer.product_category = p.product_category
            )
            ORDER BY p.total_profit, p.product_key
            LIMIT 20
        ''',
        "rewritten": '''
            SELECT p.product_key, p.product_id, p.product_name, p.product_category,
                   p.total_profit, averages.category_average_profit
            FROM warehouse.vw_product_performance AS p
            JOIN (
                SELECT product_category, avg(total_profit) AS category_average_profit
                FROM warehouse.vw_product_performance
                GROUP BY product_category
            ) AS averages USING (product_category)
            WHERE p.total_profit < averages.category_average_profit
            ORDER BY p.total_profit, p.product_key
            LIMIT 20
        ''',
    },
}


def plan_summary(plan_document: Any) -> tuple[list[str], int, int]:
    """Walk the EXPLAIN tree and total shared buffer hits/reads at the root node."""
    document = plan_document[0] if isinstance(plan_document, list) else plan_document
    root = document["Plan"]
    nodes: list[str] = []

    def visit(node: dict[str, Any]) -> None:
        nodes.append(node.get("Node Type", "unknown"))
        for child in node.get("Plans", []):
            visit(child)

    visit(root)
    return nodes, int(root.get("Shared Hit Blocks", 0)), int(root.get("Shared Read Blocks", 0))


def run_benchmark(cursor: psycopg.Cursor[Any], name: str, sql: str, runs: int) -> dict[str, Any]:
    """Execute the same EXPLAIN ANALYZE statement repeatedly and print measured facts."""
    times: list[float] = []
    last_document: Any = None
    for _ in range(runs):
        cursor.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql)
        last_document = cursor.fetchone()["QUERY PLAN"]
        document = last_document[0] if isinstance(last_document, list) else last_document
        times.append(float(document["Execution Time"]))
    nodes, hit_blocks, read_blocks = plan_summary(last_document)
    result = {
        "first_ms": times[0],
        "median_ms": statistics.median(times),
        "runs_ms": times,
        "nodes": nodes,
        "hit_blocks": hit_blocks,
        "read_blocks": read_blocks,
    }
    print(
        f"PLAN|{name}|first_ms={times[0]:.3f}|median_ms={statistics.median(times):.3f}|"
        f"runs_ms={','.join(f'{value:.3f}' for value in times)}|"
        f"nodes={' > '.join(nodes)}|shared_hit={hit_blocks}|shared_read={read_blocks}"
    )
    return result


def result_fingerprint(cursor: psycopg.Cursor[Any], sql: str) -> tuple[int, str]:
    """Hash the exact ordered query output so original and rewritten results can be compared."""
    cursor.execute(sql)
    rows = cursor.fetchall()
    canonical = "\n".join(repr(tuple(row.values())) for row in rows)
    return len(rows), hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only repeated EXPLAIN ANALYZE benchmark.")
    parser.add_argument("--database", default="central_superstore_dw", help="Warehouse database to measure")
    parser.add_argument("--runs", type=int, default=5, help="EXPLAIN runs per query; default 5")
    parser.add_argument("--skip-rewrites", action="store_true", help="Measure only the six representative workload queries")
    args = parser.parse_args()
    if args.runs < 5:
        raise ValueError("Use at least five runs to match the Phase 10 measurement requirement")

    # PostgreSQL reads the existing local pgpass.conf; this script has no password option.
    connection = psycopg.connect(
        host="localhost",
        port=5432,
        user="postgres",
        dbname=args.database,
        connect_timeout=10,
        application_name="central_superstore_phase10_benchmark",
        options="-c default_transaction_read_only=on",
        row_factory=dict_row,
    )
    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
                print(f"DATABASE|{args.database}|runs={args.runs}")
                for name, sql in WORKLOADS.items():
                    run_benchmark(cursor, name, sql, args.runs)
                    rows, digest = result_fingerprint(cursor, sql)
                    print(f"RESULT|{name}|rows={rows}|sha256={digest}")
                if not args.skip_rewrites:
                    for name, versions in REWRITES.items():
                        before = run_benchmark(cursor, f"{name}_original", versions["original"], args.runs)
                        original_rows, original_hash = result_fingerprint(cursor, versions["original"])
                        after = run_benchmark(cursor, f"{name}_rewritten", versions["rewritten"], args.runs)
                        rewritten_rows, rewritten_hash = result_fingerprint(cursor, versions["rewritten"])
                        same_result = original_rows == rewritten_rows and original_hash == rewritten_hash
                        print(
                            f"REWRITE|{name}|same_result={same_result}|rows={original_rows}/{rewritten_rows}|"
                            f"original_median_ms={before['median_ms']:.3f}|rewritten_median_ms={after['median_ms']:.3f}"
                        )
                        if not same_result:
                            raise AssertionError(f"Rewrite {name} returned different rows")
    finally:
        connection.close()
if __name__ == "__main__":
    main()
