# Phase 8 KPI Reporting Views

Six read-only views were created in the `warehouse` schema by [10_views.sql](../sql/10_views.sql). The file uses `CREATE OR REPLACE VIEW` and was run twice on the live PostgreSQL database; both runs returned six `CREATE VIEW` results without errors. The views store no extra data and do not change tables or constraints.

All names use the `vw_` prefix and snake_case. Sales/profit use four decimal places as stored; percentages and average order values are rounded to two decimals. Average order value (AOV) is calculated from order totals rather than line values.

## 1. `vw_sales_detail`

**Purpose:** Provide a readable, flattened row-level source for reports.

**Grain:** One row per `FactSales.SalesKey`, meaning one product line within one order.

**Audience / question:** Analysts asking, “What customer, product, location, order date, and ship date belong to this line?”

**Columns:** `sales_key`, `source_row_id`, `order_id`, `order_date`, `ship_date`, `ship_mode`, `customer_key`, `customer_id`, `customer_name`, `customer_segment`, `product_key`, `product_id`, `product_name`, `product_category`, `product_subcategory`, `location_key`, `country`, `region`, `state`, `city`, `postal_code`, `sales`, `profit`, `quantity`, `discount`, `order_year`, `order_quarter`, `order_month`, `order_month_name`, `order_is_weekend`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_sales_detail AS
SELECT f."SalesKey" AS sales_key, f."SourceRowID" AS source_row_id,
       f."OrderID" AS order_id, order_date."FullDate" AS order_date,
       ship_date."FullDate" AS ship_date, f."ShipMode" AS ship_mode,
       c."CustomerKey" AS customer_key, c."CustomerID" AS customer_id,
       c."CustomerName" AS customer_name, c."Segment" AS customer_segment,
       p."ProductKey" AS product_key, p."ProductID" AS product_id,
       p."ProductName" AS product_name, p."Category" AS product_category,
       p."SubCategory" AS product_subcategory, l."LocationKey" AS location_key,
       l."Country" AS country, l."Region" AS region, l."State" AS state,
       l."City" AS city, l."PostalCode" AS postal_code,
       f."Sales" AS sales, f."Profit" AS profit, f."Quantity" AS quantity,
       f."Discount" AS discount, order_date."Year" AS order_year,
       order_date."Quarter" AS order_quarter, order_date."Month" AS order_month,
       order_date."MonthName" AS order_month_name,
       order_date."IsWeekend" AS order_is_weekend
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
JOIN warehouse."DimDate" AS ship_date ON ship_date."DateKey" = f."ShipDateKey"
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey";
```

**Sample select 1, newest order lines**
```sql
SELECT source_row_id, order_id, order_date, customer_name, product_name, sales, profit
FROM warehouse.vw_sales_detail ORDER BY order_date DESC, source_row_id DESC LIMIT 3;
```

Actual result:
```text
Row ID | Order ID        | Order date | Customer           | Product                                      | Sales    | Profit
646    | CA-2014-126221  | 2016-12-30 | Chuck Clark        | Eureka The Boss Plus 12-Amp Hard Box Vacuum | 209.3000 | 56.5110
4240   | CA-2014-158673  | 2016-12-29 | Ken Brennan        | Xerox 1915                                    | 209.7000 | 100.6560
7486   | CA-2014-135111  | 2016-12-28 | Christopher Schild | Wilson Jones Impact Binders                  | 25.9000  | 12.6910
```

**Sample select 2, deepest Texas line losses**
```sql
SELECT source_row_id, state, product_id, product_name, sales, profit
FROM warehouse.vw_sales_detail
WHERE state = 'Texas' AND profit < 0
ORDER BY profit LIMIT 3;
```

Actual result: Row IDs `9775`, `5311`, and `1200`; their profits were `-3701.8928`, `-2287.7820`, and `-1850.9464`, respectively.

**How it works:** FactSales joins to customer, product, and location dimensions. DimDate is joined twice under `order_date` and `ship_date`, so each date’s role is unambiguous. The joins preserve the fact-line grain.

## 2. `vw_order_summary`

**Purpose:** Present order-level totals for order analysis and AOV calculations.

**Grain:** One row per distinct `OrderID`.

**Audience / question:** Sales operations asking, “What was each order worth, how many lines did it contain, and how long did shipping take?”

**Columns:** `order_id`, `order_date`, `ship_date`, `shipping_delay_days`, customer key/ID/name/segment, `ship_mode`, `region`, `state`, `total_sales`, `total_profit`, `total_quantity`, `number_of_lines`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_order_summary AS
SELECT d.order_id, MIN(d.order_date) AS order_date,
       MIN(d.ship_date) AS ship_date,
       MIN(d.ship_date) - MIN(d.order_date) AS shipping_delay_days,
       MIN(d.customer_key) AS customer_key, MIN(d.customer_id) AS customer_id,
       MIN(d.customer_name) AS customer_name,
       MIN(d.customer_segment) AS customer_segment,
       MIN(d.ship_mode) AS ship_mode, MIN(d.region) AS region, MIN(d.state) AS state,
       SUM(d.sales) AS total_sales, SUM(d.profit) AS total_profit,
       SUM(d.quantity) AS total_quantity, COUNT(*) AS number_of_lines
FROM warehouse.vw_sales_detail AS d
GROUP BY d.order_id;
```

**Sample select 1, largest orders**
```sql
SELECT order_id, order_date, number_of_lines, total_sales, total_profit, shipping_delay_days
FROM warehouse.vw_order_summary ORDER BY total_sales DESC LIMIT 3;
```

Actual result:
```text
Order ID        | Date       | Lines | Sales      | Profit    | Ship delay
CA-2013-118689  | 2015-10-03 | 5     | 18336.7400 | 8762.3891 | 7
CA-2011-139892  | 2013-09-08 | 7     | 10539.8960 | -1878.7892| 4
CA-2011-116904  | 2013-09-23 | 4     | 9900.1900  | 4668.6935 | 5
```

**Sample select 2, longest shipments**
```sql
SELECT order_id, ship_mode, order_date, ship_date, shipping_delay_days
FROM warehouse.vw_order_summary ORDER BY shipping_delay_days DESC, order_id LIMIT 3;
```

Actual result: `CA-2011-105893`, `CA-2011-115336`, and `CA-2011-118339`, each Standard Class, each shipped in 7 days.

**How it works:** It groups flattened order lines by OrderID. The source profiling established order-level customer/date/mode consistency; `MIN` carries those values to the single order row while `SUM` adds measures and `COUNT(*)` counts lines.

## 3. `vw_monthly_kpis`

**Purpose:** Supply executive monthly sales, profit, margin, quantity, order count, and AOV.

**Grain:** One row per order calendar year/month.

**Audience / question:** Executives asking, “How are sales, profit, and order value trending each month?”

**Columns:** `order_year`, `order_month`, `month_name`, `total_sales`, `total_profit`, `profit_margin_percent`, `total_quantity`, `number_of_orders`, `average_order_value`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_monthly_kpis AS
SELECT order_date."Year" AS order_year, order_date."Month" AS order_month,
       order_date."MonthName" AS month_name,
       SUM(order_totals.total_sales) AS total_sales,
       SUM(order_totals.total_profit) AS total_profit,
       ROUND(100.0 * SUM(order_totals.total_profit) /
             NULLIF(SUM(order_totals.total_sales), 0), 2) AS profit_margin_percent,
       SUM(order_totals.total_quantity) AS total_quantity,
       COUNT(*) AS number_of_orders,
       ROUND(AVG(order_totals.total_sales), 2) AS average_order_value
FROM warehouse.vw_order_summary AS order_totals
JOIN warehouse."DimDate" AS order_date
  ON order_date."FullDate" = order_totals.order_date
GROUP BY order_date."Year", order_date."Month", order_date."MonthName";
```

**Sample select 1, latest months**
```sql
SELECT order_year, order_month, month_name, total_sales, total_profit,
       profit_margin_percent, number_of_orders, average_order_value
FROM warehouse.vw_monthly_kpis ORDER BY order_year DESC, order_month DESC LIMIT 3;
```

Actual result:
```text
Month       | Sales      | Profit     | Margin | Orders | AOV
2016-12     | 18883.0708 | -1238.3754 | -6.56% | 53     | 356.28
2016-11     | 15154.9780 | -1518.5954 | -10.02%| 61     | 248.44
2016-10     | 12122.3362 | 597.5207   | 4.93%  | 38     | 319.01
```

**Sample select 2, highest-profit months**
```sql
SELECT order_year, month_name, total_sales, total_profit, average_order_value
FROM warehouse.vw_monthly_kpis ORDER BY total_profit DESC LIMIT 3;
```

Actual result: October 2015 (`25098.0560` sales, `10656.8408` profit, `1045.75` AOV), December 2015 (`26269.2710`, `7364.1770`, `709.98`), and December 2014 (`16737.6012`, `4191.4962`, `464.93`).

**How it works:** It reads one row per order from `vw_order_summary` before monthly aggregation. Thus `AVG(total_sales)` weights each order once, not each product line. Profit margin is monthly profit divided by monthly sales.

## 4. `vw_customer_kpis`

**Purpose:** Summarize customer lifetime value and order activity.

**Grain:** One row per active CustomerKey (a customer with at least one fact/order).

**Audience / question:** Customer teams asking, “Who are the high-value customers, how often do they order, and when did they last order?”

**Columns:** `customer_key`, `customer_id`, `customer_name`, `customer_segment`, `total_sales`, `total_profit`, `number_of_orders`, `average_order_value`, `first_order_date`, `last_order_date`, `customer_value_tier`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_customer_kpis AS
SELECT c."CustomerKey" AS customer_key, c."CustomerID" AS customer_id,
       c."CustomerName" AS customer_name, c."Segment" AS customer_segment,
       SUM(o.total_sales) AS total_sales, SUM(o.total_profit) AS total_profit,
       COUNT(*) AS number_of_orders,
       ROUND(AVG(o.total_sales), 2) AS average_order_value,
       MIN(o.order_date) AS first_order_date, MAX(o.order_date) AS last_order_date,
       CASE WHEN SUM(o.total_sales) >= 5000 THEN 'High (>= 5000)'
            WHEN SUM(o.total_sales) >= 1000 THEN 'Medium (1000-4999.99)'
            ELSE 'Low (< 1000)' END AS customer_value_tier
FROM warehouse.vw_order_summary AS o
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = o.customer_key
GROUP BY c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment";
```

**Sample select 1, top spenders**
```sql
SELECT customer_id, customer_name, customer_segment, total_sales, total_profit,
       number_of_orders, average_order_value, customer_value_tier
FROM warehouse.vw_customer_kpis ORDER BY total_sales DESC LIMIT 3;
```

Actual result: Tamara Chand `18437.1380` sales / `8745.0635` profit / 2 orders / `9218.57` AOV; Adrian Barton `12181.5940` / `5362.6135` / 5 / `2436.32`; Becky Martin `10539.8960` / `-1878.7892` / 1 / `10539.90`.

**Sample select 2, most frequent customers**
```sql
SELECT customer_id, customer_name, number_of_orders, first_order_date, last_order_date,
       customer_value_tier
FROM warehouse.vw_customer_kpis ORDER BY number_of_orders DESC, total_sales DESC LIMIT 3;
```

Actual result: Steve Chapman (7 orders), Matt Abelman (6), and Adrian Barton (5).

**How it works:** It reads the order-level view first, so order count and AOV are computed over one record per order. The CASE thresholds are analysis tiers: High at $5,000+, Medium at $1,000–$4,999.99, otherwise Low.

## 5. `vw_product_performance`

**Purpose:** Compare sales, profit, margin, quantity, and loss incidence per product member.

**Grain:** One row per ProductKey, matching Phases 6–7. Different names sharing a ProductID are not merged.

**Audience / question:** Merchandising teams asking, “Which product members earn or lose money?”

**Columns:** `product_key`, `product_id`, `product_name`, `product_category`, `product_subcategory`, `total_sales`, `total_profit`, `profit_margin_percent`, `total_quantity`, `number_of_lines`, `negative_profit_lines`, `is_loss_making`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_product_performance AS
SELECT p."ProductKey" AS product_key, p."ProductID" AS product_id,
       p."ProductName" AS product_name, p."Category" AS product_category,
       p."SubCategory" AS product_subcategory,
       SUM(d.sales) AS total_sales, SUM(d.profit) AS total_profit,
       ROUND(100.0 * SUM(d.profit) / NULLIF(SUM(d.sales), 0), 2) AS profit_margin_percent,
       SUM(d.quantity) AS total_quantity, COUNT(*) AS number_of_lines,
       COUNT(*) FILTER (WHERE d.profit < 0) AS negative_profit_lines,
       SUM(d.profit) < 0 AS is_loss_making
FROM warehouse.vw_sales_detail AS d
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = d.product_key
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory";
```

**Sample select 1, highest-profit product members**
```sql
SELECT product_key, product_id, product_name, product_category, total_sales,
       total_profit, profit_margin_percent, is_loss_making
FROM warehouse.vw_product_performance ORDER BY total_profit DESC LIMIT 3;
```

Actual result: ProductKeys `1183` Canon imageCLASS 2200 (`8399.9760` profit), `474` GBC Ibimaster 500 (`3804.9000`), and `1181` Canon PC1060 (`2302.9671`).

**Sample select 2, largest product losses**
```sql
SELECT product_key, product_id, product_name, total_profit, negative_profit_lines, is_loss_making
FROM warehouse.vw_product_performance WHERE is_loss_making ORDER BY total_profit LIMIT 3;
```

Actual result: ProductKeys `625` (`-3048.6176`), `573` (`-1525.1880`), and `318` (`-1378.8216`); all have `is_loss_making = true`.

**How it works:** The flattened line view is grouped by the dimension's surrogate ProductKey and labels. That follows the approved composite product-member design. The boolean flag is true only when the product member's total profit is below zero.

## 6. `vw_category_region_profitability`

**Purpose:** Find geographic and category groupings with weak margins and a high share of loss-making lines.

**Grain:** One Region + State + product Category combination (37 observed combinations).

**Audience / question:** Regional and category managers asking, “Where and in which category are losses concentrated?”

**Columns:** `region`, `state`, `product_category`, `total_sales`, `total_profit`, `profit_margin_percent`, `number_of_lines`, `negative_profit_lines`, `negative_profit_line_share_percent`.

**SQL**
```sql
CREATE OR REPLACE VIEW warehouse.vw_category_region_profitability AS
SELECT d.region, d.state, d.product_category,
       SUM(d.sales) AS total_sales, SUM(d.profit) AS total_profit,
       ROUND(100.0 * SUM(d.profit) / NULLIF(SUM(d.sales), 0), 2) AS profit_margin_percent,
       COUNT(*) AS number_of_lines,
       COUNT(*) FILTER (WHERE d.profit < 0) AS negative_profit_lines,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.profit < 0) / NULLIF(COUNT(*), 0), 2) AS negative_profit_line_share_percent
FROM warehouse.vw_sales_detail AS d
GROUP BY d.region, d.state, d.product_category;
```

**Sample select 1, strongest profit combinations**
```sql
SELECT region, state, product_category, total_sales, total_profit,
       profit_margin_percent, negative_profit_line_share_percent
FROM warehouse.vw_category_region_profitability ORDER BY total_profit DESC LIMIT 3;
```

Actual result: Central/Michigan/Office Supplies (`15005.3335` profit, 0.00% loss lines), Central/Indiana/Technology (`11000.8773`, 0.00%), and Central/Minnesota/Office Supplies (`7780.4995`, 0.00%).

**Sample select 2, weakest profit combinations**
```sql
SELECT region, state, product_category, total_sales, total_profit,
       negative_profit_line_share_percent
FROM warehouse.vw_category_region_profitability ORDER BY total_profit LIMIT 3;
```

Actual result: Central/Texas/Office Supplies (`-18584.6434`, 41.89% loss lines), Central/Texas/Furniture (`-10436.1419`, 97.03%), and Central/Illinois/Furniture (`-9076.2894`, 98.37%).

**How it works:** Flattened sales lines are grouped by region, state, and category. The line share is `negative_profit_lines / number_of_lines * 100`; it is a share of lines, not a share of loss dollars.

## Verification Results

### Re-run safety

The exact `sql/10_views.sql` script was run twice on the live database. Each execution returned six `CREATE VIEW` results, confirming that `CREATE OR REPLACE VIEW` is rerunnable.

### Grain and additive-total checks

All six view grains were checked for uniqueness and all meaningful additive totals were compared with FactSales.

| View | Rows / grain-key distinct | Sales | Profit | Quantity | Lines | Negative lines | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `vw_sales_detail` | 2323 / 2323 | 501239.8908 | 39706.3625 | 8780 |  |  | PASS |
| `vw_order_summary` | 1175 / 1175 | 501239.8908 | 39706.3625 | 8780 | 2323 |  | PASS |
| `vw_monthly_kpis` | 48 / 48 | 501239.8908 | 39706.3625 | 8780 |  |  | PASS |
| `vw_customer_kpis` | 629 / 629 | 501239.8908 | 39706.3625 | Not applicable |  |  | PASS |
| `vw_product_performance` | 1326 / 1326 | 501239.8908 | 39706.3625 | 8780 | 2323 | 741 | PASS |
| `vw_category_region_profitability` | 37 / 37 | 501239.8908 | 39706.3625 | Not applicable | 2323 | 741 | PASS |

AOVs and percentages are non-additive and are not summed as totals. The customer view contains active customers with facts, which matches all 629 source customers.

### Pandas comparisons

The workbook was read-only. Monthly totals were independently aggregated in pandas by first grouping each order, then by calendar month; customer metrics were recomputed by grouping each order before customer AOV. The check rounded AOV to two decimals exactly as the views do.

- `vw_monthly_kpis`: all 48 rows and 240 monthly measures/counts matched. Sample January 2013: pandas and view both returned sales `1539.9060`, profit `118.4902`, quantity `62`, 8 orders, AOV `192.49`. December 2016: `18883.0708`, `-1238.3754`, 369, 53 orders, AOV `356.28`.
- `vw_customer_kpis`: all 629 rows and 5,661 compared fields matched, including names, segments, sales, profit, order count, rounded AOV, first/last dates, and value tier. Tamara Chand matched at sales `18437.1380`, profit `8745.0635`, 2 orders, AOV `9218.57`, first order `2013-11-07`, last order `2015-10-03`.

### Phase 6 query rewritten to use a view

Phase 6 Query 2 originally joined FactSales to DimProduct and grouped sales, profit, and quantity by category/sub-category. Its view-based equivalent is:

```sql
SELECT product_category AS category,
       product_subcategory AS subcategory,
       SUM(total_sales) AS total_sales,
       SUM(total_profit) AS total_profit,
       SUM(total_quantity) AS total_quantity
FROM warehouse.vw_product_performance
GROUP BY product_category, product_subcategory
ORDER BY product_category, total_sales DESC;
```

Compared side-by-side with the original Phase 6 query across all **17 groups**, the rewritten view query had **0 mismatched groups** for Sales, Profit, or Quantity.

### Phase 5 validation rerun

`sql/05_validation.sql` was rerun after view creation: **39 rows returned, 39 PASS, 0 FAIL**. Tables still contain 2,323 fact lines, Sales `501239.8908`, Profit `39706.3625`, and Quantity `8780`.

Phase 8 is complete. No stored procedures, indexes, or Phase 9 work were created.
