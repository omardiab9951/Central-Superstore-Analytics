# Phase 9 Stored Procedure and KPI Function

Phase 9 added two reusable PostgreSQL routines in [11_stored_procedures.sql](../sql/11_stored_procedures.sql). A **procedure** performs an action when called with `CALL`; here its results are returned as OUT parameters. A **function** can be selected like a table and returns one row per requested period. Both read only from the existing views and tables. No table, view, index, constraint, or data was changed by these routines.

The SQL file was run twice against the live `central_superstore_dw` database. Both runs succeeded with:

```text
CREATE PROCEDURE
COMMENT
CREATE FUNCTION
COMMENT
```

## KPI Definitions

- **Total Sales / Profit / Quantity:** sums over the matching fact lines after the supplied filters.
- **Profit margin percent:** `100 * total profit / total sales`; it is calculated from the totals, not by averaging line-level margins. If sales are zero, the margin is `NULL`.
- **Number of orders:** count of distinct `OrderID` values after the filters.
- **Number of customers:** count of distinct customers present in the matching facts.
- **Average order value (AOV):** filtered sales divided by distinct matching orders. The routines first aggregate lines by order, so every order contributes once even if it contains multiple product lines. AOV is `NULL` when no orders match.
- **Loss-making lines:** count of individual filtered fact lines with negative profit. It is not a count of orders or product members.
- **Product filter semantics:** where used by Phase 8 product reporting, the approved product grain remains `ProductKey`; multiple names for one ProductID are distinct product members.

## Procedure: `warehouse.sp_calculate_kpis`

**Purpose:** Return a single overall KPI set for an optional inclusive range of Order Dates with optional category and region filters.

**Parameters**

| Parameter | Mode | Meaning |
|---|---|---|
| `p_start_date` | IN | Inclusive earliest Order Date. NULL leaves the lower date bound open. |
| `p_end_date` | IN | Inclusive latest Order Date. NULL leaves the upper date bound open. |
| `p_category` | IN | Exact product category filter. NULL means all categories. |
| `p_region` | IN | Exact region filter. NULL means all regions. |
| `out_total_sales` | OUT | Sum of filtered line sales. |
| `out_total_profit` | OUT | Sum of filtered line profit, including negative profit. |
| `out_profit_margin_percent` | OUT | Margin from total profit divided by total sales, rounded to two decimals. |
| `out_total_quantity` | OUT | Sum of filtered quantities. |
| `out_number_of_orders` | OUT | Number of distinct filtered orders. |
| `out_number_of_customers` | OUT | Number of distinct filtered customers. |
| `out_average_order_value` | OUT | Average of order-level sales totals, rounded to two decimals. |
| `out_loss_making_lines` | OUT | Count of filtered fact lines with profit below zero. |

**Call example**

PostgreSQL requires a placeholder for every OUT parameter in a direct `CALL`; use `NULL` placeholders and PostgreSQL displays the output row.

```sql
CALL warehouse.sp_calculate_kpis(
    '2013-01-03', '2016-12-30', NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
```

To filter Furniture in the Central region for 2015:

```sql
CALL warehouse.sp_calculate_kpis(
    '2015-01-01', '2015-12-31', 'Furniture', 'Central',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
```

**Logic and error behavior:** The procedure rejects a start date later than the end date with `RAISE EXCEPTION` and SQLSTATE `22007`. Date bounds may independently be NULL; both NULL means all dates. Category and region are exact matches; NULL means no restriction. If the filters match no lines (including an unknown category or an out-of-range date window), it returns one row with zero sums/counts, NULL margin/AOV, and a NOTICE explaining the empty match. `NULLIF` prevents division-by-zero errors.

## Function: `warehouse.fn_kpi_by_period`

**Purpose:** Return table-style KPI rows at a selectable year, quarter, or month grain.

**Parameters**

| Parameter | Meaning |
|---|---|
| `p_start_date` | Inclusive Order Date lower bound; NULL means open. |
| `p_end_date` | Inclusive Order Date upper bound; NULL means open. |
| `p_period` | Required grain: `year`, `quarter`, or `month` (case/outer spaces are normalized). |
| `p_category` | Optional exact category; NULL means all categories. |
| `p_region` | Optional exact region; NULL means all regions. |

The result columns are `period_start`, `period_year`, `period_quarter`, `period_month`, total sales/profit, margin percent, quantity, orders, customers, AOV, and loss-making line count. Quarter is NULL for year grain; month is NULL for year and quarter grains.

**Call examples**

```sql
-- Annual KPIs for all data.
SELECT * FROM warehouse.fn_kpi_by_period(NULL, NULL, 'year', NULL, NULL)
ORDER BY period_start;

-- Quarterly KPIs for 2016 Furniture orders in Central.
SELECT * FROM warehouse.fn_kpi_by_period(
    '2016-01-01', '2016-12-31', 'quarter', 'Furniture', 'Central'
) ORDER BY period_start;

-- Monthly KPIs for the complete source range.
SELECT * FROM warehouse.fn_kpi_by_period(
    '2013-01-03', '2016-12-30', 'month', NULL, NULL
) ORDER BY period_start;
```

**Logic and error behavior:** The function filters fact lines, aggregates each order first, assigns the order to a calendar period using its Order Date, then calculates the period totals and order-level AOV. A reversed date range raises the same `22007` error. An unsupported period value raises SQLSTATE `22023` and names the accepted values. NULL date bounds mean open-ended; both NULL means all dates. If nothing matches, the function returns zero rows and emits a NOTICE. Empty periods are not fabricated.

## Real Results and Verification

### Full-range procedure vs warehouse totals

The live call for 2013-01-03 through 2016-12-30 with no category/region filter returned:

| Output | Procedure | FactSales / matching reference |
|---|---:|---:|
| Total Sales | 501239.8908 | 501239.8908 |
| Total Profit | 39706.3625 | 39706.3625 |
| Profit margin percent | 7.92 | 7.92 from totals |
| Total Quantity | 8780 | 8780 |
| Number of orders | 1175 | 1175 distinct OrderID |
| Number of customers | 629 | 629 distinct CustomerKey |
| Average order value | 426.59 | 426.59 from `vw_order_summary` |
| Loss-making lines | 741 | 741 fact lines |

An assertion block compared procedure OUT values to FactSales totals and to comparable sums/counts from `vw_order_summary` and `vw_monthly_kpis`; it emitted:

```text
NOTICE: PASS: procedure OUT values match FactSales, vw_order_summary, and vw_monthly_kpis for comparable totals/AOV.
NOTICE: Procedure: sales 501239.8908, profit 39706.3625, margin 7.92, quantity 8780, orders 1175, customers 629, AOV 426.59, loss lines 741
```

Summing per-year customer counts is not expected to equal lifetime distinct customers because a customer can appear in multiple years; the procedure's lifetime customer count is 629.

### Filtered procedure cases: procedure vs independent SQL vs pandas

The independent SQL recomputed the filtered line set from FactSales joined directly to DimDate, DimProduct, DimLocation, and DimCustomer, then formed order totals separately. Pandas independently filtered the read-only Excel rows and grouped them to order grain before calculating AOV. All eight returned KPI values matched in every comparison.

| Filter | Sales | Profit | Margin % | Quantity | Orders | Customers | AOV | Loss lines | Both comparisons |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2015 dates, all category/region | 147429.3760 | 19899.1629 | 13.50 | 2359 | 305 | 261 | 483.38 | 173 | PASS |
| All dates, Furniture, all regions | 163797.1638 | -2871.0494 | -1.75 | 1827 | 403 | 318 | 406.44 | 317 | PASS |
| 2016 dates, Central region, all categories | 147098.1282 | 7550.8442 | 5.13 | 2880 | 406 | 325 | 362.31 | 247 | PASS |

### Period function checks

| Grain | Rows | Sales sum | Profit sum | Quantity sum | Orders summed by period | Comparison |
|---|---:|---:|---:|---:|---:|---|
| Year | 4 | 501239.8908 | 39706.3625 | 8780 | 1175 | Totals reconcile |
| Quarter | 16 | 501239.8908 | 39706.3625 | 8780 | 1175 | Totals reconcile |
| Month | 48 | 501239.8908 | 39706.3625 | 8780 | 1175 | 48 monthly view rows |

The monthly function output was joined to `vw_monthly_kpis`: **48 rows compared, 0 mismatches** for sales, profit, margin, quantity, orders, and AOV. Annual function totals reconcile exactly with the full-range procedure and FactSales totals.

### Error and empty-result tests

- Reversed dates: both routines rejected 2016-12-31 through 2016-01-01 with SQLSTATE `22007`: `Start date (2016-12-31) must be on or before end date (2016-01-01)`.
- NULL date inputs: procedure returned the full-range totals; the function returned all four years when asked for year grain.
- Unknown category `Not A Category`: procedure returned zero sums/counts and NULL margin/AOV with a NOTICE; function returned 0 rows with a NOTICE.
- Date window 2000-01-01 through 2000-12-31: same documented empty behavior (zero/NULL output for procedure; zero rows for function).
- Unsupported function grain `week`: rejected with SQLSTATE `22023`: `Period must be one of year, quarter, or month; received week`.

### No-change and Phase 5 checks

Before and after routine creation and calls, live warehouse values remained: 2,323 facts, sales 501239.8908, profit 39706.3625, quantity 8780, 1,175 orders, 629 customers. All six Phase 8 views remained present. `sql/05_validation.sql` was rerun: **39 checks returned, 39 PASS, 0 FAIL**. The original workbook SHA-256 remained `abf10f5a41b104af55c78c6fbeec156267ABC373D5C885FECAF6C81324660ACF` (case-insensitive hex comparison).

Phase 9 is complete. Phase 10 indexing/performance work has not started.
