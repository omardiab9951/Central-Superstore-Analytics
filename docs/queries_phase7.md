# Phase 7 Advanced SQL Queries

All 12 statements in [09_advanced_sql.sql](../sql/09_advanced_sql.sql) were executed on the live PostgreSQL warehouse. They are read-only `SELECT` queries. Query numbers continue after Phase 6's Queries 1–20; this file contains Queries 21–32. The SQL uses no view, procedure, index, or data-changing statement.

## Query 21: Top Product Members per Category

**Business question:** Which three product members make the most profit inside each category?

**SQL**
```sql
WITH product_profit AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
           SUM(f."Profit") AS total_profit, SUM(f."Sales") AS total_sales
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
),
ranked_products AS (
    SELECT product_profit.*,
           RANK() OVER (PARTITION BY "Category" ORDER BY total_profit DESC) AS profit_rank,
           DENSE_RANK() OVER (PARTITION BY "Category" ORDER BY total_profit DESC) AS dense_profit_rank,
           ROW_NUMBER() OVER (PARTITION BY "Category" ORDER BY total_profit DESC, "ProductKey") AS row_in_category
    FROM product_profit
)
SELECT "Category", profit_rank, dense_profit_rank, row_in_category,
       "ProductKey", "ProductID", "ProductName", total_profit, total_sales
FROM ranked_products
WHERE profit_rank <= 3
ORDER BY "Category", profit_rank, "ProductKey";
```

**Real output sample**
```text
Category         | Rank | Dense rank | Row | ProductKey | ProductID       | Profit
Furniture        | 1    | 1          | 1   | 64         | FUR-CH-10002320 | 770.3520
Furniture        | 2    | 2          | 2   | 37         | FUR-CH-10000454 | 731.9400
Furniture        | 3    | 3          | 3   | 55         | FUR-CH-10001854 | 673.8816
Office Supplies  | 1    | 1          | 1   | 474        | OFF-BI-10000545 | 3804.9000
Technology       | 1    | 1          | 1   | 1183       | TEC-CO-10004722 | 8399.9760
```

**Explanation:** `product_profit` is the first CTE (a named temporary result used by the following part of one query). It aggregates fact lines to product-member level. Product-level grouping is by `ProductKey`, so variants sharing a Product ID are not merged. `ranked_products` is the second CTE. Its `PARTITION BY Category` starts the ranking over for each category. `RANK` shares a rank for ties and leaves a gap after a tie; `DENSE_RANK` shares a tie rank but does not leave a gap; `ROW_NUMBER` always gives each row a unique position, using ProductKey to break ties. The final query returns ranks 1–3.

**Manager insight:** Canon copiers lead Technology, while a binding system is the top Office Supplies profit member. Chairs lead Furniture in this dataset.

## Query 22: Month-over-Month and Year-over-Year Sales

**Business question:** How did monthly sales change from the prior month and the same month of the prior year?

**SQL**
```sql
WITH monthly_sales AS (
    SELECT date_trunc('month', order_date."FullDate")::DATE AS month_start,
           SUM(f."Sales") AS month_sales,
           SUM(f."Profit") AS month_profit,
           COUNT(DISTINCT f."OrderID") AS month_orders
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    GROUP BY date_trunc('month', order_date."FullDate")::DATE
),
monthly_comparison AS (
    SELECT monthly_sales.*,
           LAG(month_sales) OVER (ORDER BY month_start) AS previous_month_sales,
           LAG(month_sales, 12) OVER (ORDER BY month_start) AS same_month_last_year_sales,
           LEAD(month_sales) OVER (ORDER BY month_start) AS next_month_sales
    FROM monthly_sales
)
SELECT month_start, month_sales, previous_month_sales,
       ROUND(100.0 * (month_sales - previous_month_sales) / NULLIF(previous_month_sales, 0), 2) AS mom_growth_percent,
       same_month_last_year_sales,
       ROUND(100.0 * (month_sales - same_month_last_year_sales) / NULLIF(same_month_last_year_sales, 0), 2) AS yoy_growth_percent,
       next_month_sales
FROM monthly_comparison
ORDER BY month_start;
```

**Real output sample**
```text
Month      | Sales      | Prior month | MoM %  | Same month prior year | YoY % | Next month
2013-01-01 | 1539.9060  | NULL        | NULL   | NULL                  | NULL  | 1233.1740
2013-02-01 | 1233.1740  | 1539.9060   | -19.92 | NULL                  | NULL  | 5827.6020
2014-01-01 | 2510.5116  | 10635.5660  | -76.40 | 1539.9060             | 63.03 | 2527.5860
2016-12-01 | 18883.0708 | 15154.9780  | 24.60  | 26269.2710            | -28.12| NULL
```

**Explanation:** `monthly_sales` aggregates all line rows to one order-date month first. `monthly_comparison` adds windows to those monthly rows. `LAG(..., 1)` looks back one row/month; `LAG(..., 12)` looks back 12 rows/months; `LEAD(..., 1)` looks forward one row/month. The live data was checked separately: there are **48 observed months**, exactly the 48 months from January 2013 through December 2016, with no gaps. Therefore 12 prior rows is the same calendar month a year earlier. `NULLIF` prevents division by zero.

**Manager insight:** December 2016 sales rose 24.60% over November but were 28.12% below December 2015. Month-to-month spikes can be large, so review both comparison bases.

## Query 23: Cumulative Sales and Profit

**Business question:** How do monthly amounts accumulate through the reporting period?

**SQL**
```sql
WITH monthly_totals AS (
    SELECT date_trunc('month', order_date."FullDate")::DATE AS month_start,
           SUM(f."Sales") AS month_sales,
           SUM(f."Profit") AS month_profit
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    GROUP BY date_trunc('month', order_date."FullDate")::DATE
),
monthly_running AS (
    SELECT monthly_totals.*,
           SUM(month_sales) OVER (ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_sales,
           SUM(month_profit) OVER (ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_profit
    FROM monthly_totals
)
SELECT month_start, month_sales, month_profit, running_sales, running_profit
FROM monthly_running
ORDER BY month_start;
```

**Real output sample**
```text
Month      | Month sales | Month profit | Running sales | Running profit
2013-01-01 | 1539.9060   | 118.4902     | 1539.9060     | 118.4902
2013-02-01 | 1233.1740   | 294.8067     | 2773.0800     | 413.2969
2013-12-01 | 10635.5660  | 887.8471     | 103838.1646   | 539.5534
2016-12-01 | 18883.0708  | -1238.3754   | 501239.8908   | 39706.3625
```

**Explanation:** `monthly_totals` first creates one row per month. `monthly_running` applies `SUM(...) OVER` in month order. The frame from `UNBOUNDED PRECEDING` through `CURRENT ROW` means start at the first month and add through the current month.

**Manager insight:** Running profit briefly became negative in early 2013 before recovering. The final running values reconcile to the warehouse grand totals.

## Query 24: Three-Month Moving Average

**Business question:** What is the smoothed three-month sales and profit trend?

**SQL**
```sql
WITH monthly_totals AS (
    SELECT date_trunc('month', order_date."FullDate")::DATE AS month_start,
           SUM(f."Sales") AS month_sales,
           SUM(f."Profit") AS month_profit
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    GROUP BY date_trunc('month', order_date."FullDate")::DATE
),
monthly_averages AS (
    SELECT monthly_totals.*,
           COUNT(*) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS months_in_average,
           ROUND(AVG(month_sales) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS sales_3_month_average,
           ROUND(AVG(month_profit) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS profit_3_month_average
    FROM monthly_totals
)
SELECT month_start, month_sales, month_profit, months_in_average,
       sales_3_month_average, profit_3_month_average
FROM monthly_averages
ORDER BY month_start;
```

**Real output sample**
```text
Month      | Sales      | Profit    | Months averaged | 3-month avg sales | 3-month avg profit
2013-01-01 | 1539.9060  | 118.4902  | 1               | 1539.91           | 118.49
2013-02-01 | 1233.1740  | 294.8067  | 2               | 1386.54           | 206.65
2013-03-01 | 5827.6020  | -274.0467 | 3               | 2866.89           | 46.42
2016-12-01 | 18883.0708 | -1238.3754| 3               | 15386.80          | -719.82
```

**Explanation:** Monthly aggregation occurs before the moving average. The `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` window takes this month and up to the two previous monthly rows. `months_in_average` makes the edge behavior visible: January uses one month and February uses two; from March onward the frame contains three.

**Manager insight:** The smoothed view helps distinguish a single-month spike from a sustained trend; December’s trailing three-month average profit is negative.

## Query 25: CASE-Based Customer Spend Bands

**Business question:** How many customers fall into high, medium, and low lifetime-sales bands?

**SQL**
```sql
WITH customer_totals AS (
    SELECT c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment",
           COUNT(DISTINCT f."OrderID") AS order_count,
           SUM(f."Sales") AS customer_sales,
           SUM(f."Profit") AS customer_profit
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
    GROUP BY c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment"
),
customer_tiers AS (
    SELECT customer_totals.*,
           CASE WHEN customer_sales >= 5000 THEN 'High (>= 5000)'
                WHEN customer_sales >= 1000 THEN 'Medium (1000-4999.99)'
                ELSE 'Low (< 1000)' END AS spend_tier
    FROM customer_totals
)
SELECT spend_tier, COUNT(*) AS customers,
       SUM(order_count) AS customer_orders,
       SUM(customer_sales) AS tier_sales,
       SUM(customer_profit) AS tier_profit,
       ROUND(AVG(customer_sales), 2) AS average_customer_sales
FROM customer_tiers
GROUP BY spend_tier
ORDER BY MIN(customer_sales) DESC;
```

**Real output sample**
```text
Tier                  | Customers | Orders | Sales      | Profit     | Avg customer sales
High (>= 5000)         | 10        | 28     | 85541.8408 | 24268.0558 | 8554.18
Medium (1000-4999.99)  | 147       | 374    | 273605.5930| 19061.8508 | 1861.26
Low (< 1000)           | 472       | 773    | 142092.4570| -3623.5441 | 301.04
```

**Explanation:** `customer_totals` groups line data to one row per customer before classifying or averaging. `customer_tiers` applies `CASE` to the spend total. The $1,000 and $5,000 thresholds are explicit analysis bands chosen for this report, not source-provided classifications.

**Manager insight:** Only 10 customers are in the high-spend band, while the low-spend band has a net loss in aggregate and warrants targeted retention/profitability analysis.

## Query 26: One-Time Versus Repeat Customers

**Business question:** How do customers with one order compare with repeat customers?

**SQL**
```sql
WITH customer_activity AS (
    SELECT c."CustomerKey", c."CustomerID", c."CustomerName",
           COUNT(DISTINCT f."OrderID") AS order_count,
           SUM(f."Sales") AS customer_sales,
           SUM(f."Profit") AS customer_profit
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
    GROUP BY c."CustomerKey", c."CustomerID", c."CustomerName"
),
customer_types AS (
    SELECT customer_activity.*,
           CASE WHEN order_count = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type
    FROM customer_activity
)
SELECT customer_type, COUNT(*) AS customers,
       SUM(order_count) AS orders,
       SUM(customer_sales) AS total_sales,
       SUM(customer_profit) AS total_profit,
       ROUND(AVG(customer_sales), 2) AS average_customer_sales
FROM customer_types
GROUP BY customer_type
ORDER BY customer_type;
```

**Real output**
```text
Type     | Customers | Orders | Sales      | Profit     | Avg customer sales
One-time | 284       | 284    | 136487.0578| 8861.5620  | 480.59
Repeat   | 345       | 891    | 364752.8330| 30844.8005 | 1057.25
```

**Explanation:** The first CTE aggregates all fact lines to customer grain and counts distinct orders. The second labels each customer using `CASE`. The outer query compares the two customer groups.

**Manager insight:** Repeat customers account for most orders, sales, and profit, supporting retention efforts.

## Query 27: Product ABC / Pareto Sales Classes

**Business question:** How much of portfolio sales comes from the products contributing the first ~80%, next ~15%, and final ~5%?

**SQL**
```sql
WITH product_sales AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName", SUM(f."Sales") AS product_sales
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName"
),
product_cumulative AS (
    SELECT product_sales.*,
           SUM(product_sales) OVER (ORDER BY product_sales DESC, "ProductKey" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sales,
           SUM(product_sales) OVER () AS portfolio_sales
    FROM product_sales
),
product_classes AS (
    SELECT product_cumulative.*,
           CASE WHEN cumulative_sales - product_sales < portfolio_sales * 0.80 THEN 'A: first ~80%'
                WHEN cumulative_sales - product_sales < portfolio_sales * 0.95 THEN 'B: next ~15%'
                ELSE 'C: final ~5%' END AS abc_class
    FROM product_cumulative
)
SELECT abc_class, COUNT(*) AS product_members, SUM(product_sales) AS class_sales,
       ROUND(100.0 * SUM(product_sales) / MAX(portfolio_sales), 2) AS portfolio_sales_percent
FROM product_classes
GROUP BY abc_class
ORDER BY CASE abc_class WHEN 'A: first ~80%' THEN 1 WHEN 'B: next ~15%' THEN 2 ELSE 3 END;
```

**Real output**
```text
Class          | Product members | Sales      | Portfolio share
A: first ~80%  | 268             | 401347.8578| 80.07%
B: next ~15%   | 334             | 74831.9830 | 14.93%
C: final ~5%   | 724             | 25060.0500 | 5.00%
```

**Product grouping choice:** Uses `ProductKey`, consistent with Phase 6, preserving separate observed product-name members for the 16 conflicting Product IDs.

**Explanation:** `product_sales` first sums each product member. `product_cumulative` uses an ordered running `SUM OVER` plus an unpartitioned total for the full portfolio. `product_classes` uses `CASE` and the cumulative amount before the current product to include the product that crosses each cutoff. The result groups members into ABC classes.

**Manager insight:** 268 product members generate roughly 80% of sales; prioritize availability and margin monitoring for these members.

## Query 28: Top Sales Decile Customers

**Business question:** Which customers make up the top 10% by total sales?

**SQL**
```sql
WITH customer_sales AS (
    SELECT c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment",
           COUNT(DISTINCT f."OrderID") AS order_count,
           SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
    GROUP BY c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment"
),
customer_deciles AS (
    SELECT customer_sales.*,
           NTILE(10) OVER (ORDER BY total_sales DESC, "CustomerKey") AS sales_decile,
           PERCENT_RANK() OVER (ORDER BY total_sales DESC) AS sales_percent_rank,
           ROW_NUMBER() OVER (ORDER BY total_sales DESC, "CustomerKey") AS sales_row_number
    FROM customer_sales
)
SELECT "CustomerID", "CustomerName", "Segment", order_count, total_sales, total_profit,
       sales_decile, ROUND((100.0 * sales_percent_rank)::NUMERIC, 2) AS percent_rank_percent,
       sales_row_number
FROM customer_deciles
WHERE sales_decile = 1
ORDER BY sales_row_number;
```

**Real output sample**
```text
CustomerID | CustomerName | Sales      | Decile | Percent-rank % | Row
TC-20980   | Tamara Chand | 18437.1380 | 1      | 0.00           | 1
AB-10105   | Adrian Barton| 12181.5940 | 1      | 0.16           | 2
BM-11140   | Becky Martin | 10539.8960 | 1      | 0.32           | 3
```

**Explanation:** `customer_sales` creates one sales total per customer before ranking. `NTILE(10)` splits the ordered customer rows into ten nearly equal buckets; bucket 1 is the top decile. `PERCENT_RANK` reports relative rank from 0 to 1, while `ROW_NUMBER` gives a unique display sequence with a stable tie-breaker. The result contained 63 customers.

**Manager insight:** The top decile is a focused high-value group for loyalty and retention programs; it should be compared with profit as well as spend.

## Query 29: Product Members Below Category-Average Profit

**Business question:** Which product members earn less than the average member profit in their category?

**SQL**
```sql
WITH product_totals AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
           SUM(f."Profit") AS total_profit, SUM(f."Sales") AS total_sales
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
)
SELECT current_product."ProductKey", current_product."ProductID", current_product."ProductName",
       current_product."Category", current_product."SubCategory", current_product.total_profit,
       ROUND(category_average.average_profit, 2) AS category_average_product_profit
FROM product_totals AS current_product
CROSS JOIN LATERAL (
    SELECT AVG(peer_product.total_profit) AS average_profit
    FROM product_totals AS peer_product
    WHERE peer_product."Category" = current_product."Category"
) AS category_average
WHERE current_product.total_profit < category_average.average_profit
ORDER BY current_product.total_profit ASC
LIMIT 20;
```

**Real output sample**
```text
ProductKey | ProductID       | ProductName                                 | Profit     | Category avg profit
625        | OFF-BI-10004995 | GBC DocuBind P400 Electric Binding System   | -3048.6176 | 11.21
573        | OFF-BI-10003527 | Fellowes PB500 Electric Punch Binding Machine| -1525.1880| 11.21
1185       | TEC-MA-10000822 | Lexmark MX611dhe Monochrome Laser Printer   | -1189.9930 | 129.61
```

**Product grouping choice:** Uses `ProductKey`, so product-name variants remain separate.

**Explanation:** `product_totals` computes one profit figure per product member. The `LATERAL` subquery is correlated: it runs the category-average calculation using the category from the current product row. The `WHERE` clause keeps members below that peer average.

**Manager insight:** Products with negative profit are far below their category averages; the query also identifies weaker-but-profitable members that may need pricing or cost review.

## Query 30: Loss Contribution by Sub-Category

**Business question:** Which sub-categories contribute the greatest share of all negative-profit dollars?

**SQL**
```sql
WITH subcategory_losses AS (
    SELECT p."SubCategory",
           SUM(CASE WHEN f."Profit" < 0 THEN -f."Profit" ELSE 0 END) AS loss_amount,
           COUNT(*) FILTER (WHERE f."Profit" < 0) AS loss_lines
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."SubCategory"
),
loss_shares AS (
    SELECT subcategory_losses.*,
           SUM(loss_amount) OVER () AS all_losses,
           SUM(loss_amount) OVER (ORDER BY loss_amount DESC, "SubCategory" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_losses
    FROM subcategory_losses
)
SELECT "SubCategory", loss_lines, loss_amount,
       ROUND(100.0 * loss_amount / NULLIF(all_losses, 0), 2) AS share_of_all_losses_percent,
       ROUND(100.0 * cumulative_losses / NULLIF(all_losses, 0), 2) AS cumulative_loss_share_percent
FROM loss_shares
WHERE loss_amount > 0
ORDER BY loss_amount DESC;
```

**Real output sample**
```text
Sub-category | Loss lines | Loss amount | Share | Cumulative share
Binders       | 233        | 21909.3980 | 38.91%| 38.91%
Appliances    | 67         | 8629.6412  | 15.32%| 54.23%
Tables        | 49         | 6568.3553  | 11.66%| 65.89%
Furnishings   | 138        | 5944.6552  | 10.56%| 76.45%
Chairs        | 94         | 4094.3445  | 7.27% | 83.72%
```

**Explanation:** `subcategory_losses` converts negative profit to positive loss magnitude and sums it by sub-category. `loss_shares` uses one window sum for the total across all groups and an ordered running sum for cumulative share. This reports the share of gross loss lines, not net category profit.

**Manager insight:** Binders account for 38.91% of gross losses; the top five sub-categories account for 83.72% cumulatively.

## Query 31: Loss Contribution by State

**Business question:** Which states contribute the greatest share of all negative-profit dollars?

**SQL**
```sql
WITH state_losses AS (
    SELECT l."State",
           SUM(CASE WHEN f."Profit" < 0 THEN -f."Profit" ELSE 0 END) AS loss_amount,
           COUNT(*) FILTER (WHERE f."Profit" < 0) AS loss_lines,
           COUNT(DISTINCT f."OrderID") FILTER (WHERE f."Profit" < 0) AS orders_with_loss
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
    GROUP BY l."State"
),
state_loss_shares AS (
    SELECT state_losses.*,
           SUM(loss_amount) OVER () AS all_losses,
           SUM(loss_amount) OVER (ORDER BY loss_amount DESC, "State" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_losses
    FROM state_losses
)
SELECT "State", loss_lines, orders_with_loss, loss_amount,
       ROUND(100.0 * loss_amount / NULLIF(all_losses, 0), 2) AS share_of_all_losses_percent,
       ROUND(100.0 * cumulative_losses / NULLIF(all_losses, 0), 2) AS cumulative_loss_share_percent
FROM state_loss_shares
WHERE loss_amount > 0
ORDER BY loss_amount DESC;
```

**Real output**
```text
State    | Loss lines | Orders with loss | Loss amount | Share | Cumulative share
Texas    | 486        | 312              | 36813.1875  | 65.37%| 65.37%
Illinois | 255        | 182              | 19501.6975  | 34.63%| 100.00%
```

**Explanation:** `state_losses` totals only negative line profit as positive loss and counts affected lines/orders. `state_loss_shares` calculates each state's share of all negative-profit dollars and a running cumulative share.

**Manager insight:** Gross negative-profit dollars are concentrated entirely in Texas and Illinois in this source; Texas represents 65.37%.

## Query 32: Product Members by Loss Contribution

**Business question:** Which individual product members contribute most to total gross losses?

**SQL**
```sql
WITH product_losses AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
           SUM(CASE WHEN f."Profit" < 0 THEN -f."Profit" ELSE 0 END) AS loss_amount,
           COUNT(*) FILTER (WHERE f."Profit" < 0) AS loss_lines
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
),
ranked_product_losses AS (
    SELECT product_losses.*,
           DENSE_RANK() OVER (ORDER BY loss_amount DESC) AS loss_rank,
           SUM(loss_amount) OVER (ORDER BY loss_amount DESC, "ProductKey" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_losses,
           SUM(loss_amount) OVER () AS all_losses
    FROM product_losses
)
SELECT loss_rank, "ProductKey", "ProductID", "ProductName", "Category", "SubCategory",
       loss_lines, loss_amount,
       ROUND(100.0 * loss_amount / NULLIF(all_losses, 0), 2) AS share_of_all_losses_percent,
       ROUND(100.0 * cumulative_losses / NULLIF(all_losses, 0), 2) AS cumulative_loss_share_percent
FROM ranked_product_losses
WHERE loss_amount > 0
ORDER BY loss_amount DESC, "ProductKey"
LIMIT 20;
```

**Real output sample**
```text
Rank | ProductKey | ProductID       | ProductName                               | Loss amount | Loss share | Cumulative share
1    | 625        | OFF-BI-10004995 | GBC DocuBind P400 Electric Binding System | 5552.8392   | 9.86%      | 9.86%
2    | 573        | OFF-BI-10003527 | Fellowes PB500 Electric Punch Binding Machine | 3431.6730 | 6.09% | 15.95%
3    | 493        | OFF-BI-10001120 | Ibico EPK-21 Electric Binding System      | 2929.4845   | 5.20%      | 21.16%
```

**Product grouping choice:** Groups by `ProductKey`, not ProductID, to keep conflicting-name members distinct.

**Explanation:** `product_losses` first groups negative-profit magnitudes by product member. `ranked_product_losses` uses `DENSE_RANK` to order those members and two window sums to calculate each member's share and cumulative share. `DENSE_RANK` avoids rank-number gaps when loss amounts tie.

**Manager insight:** The top three loss-making product members contribute 21.16% of gross negative-profit dollars; this gives a focused starting set for investigation.

## Independent Pandas Verification

The source workbook was read-only. For all comparisons, Sales and Profit were converted to four-decimal `Decimal` values to match the warehouse. Product members were formed from cleaned `(Product ID, Product Name)` pairs, consistent with the Phase 2 design. The independent checks used a `0.0001` absolute tolerance for monetary values and exact checks for ranks, classes, and counts.

### Query 21: Category-Partitioned Product Ranking

Pandas grouped the Excel data by Product ID/name/category/sub-category, assigned the deterministic ProductKey order, then computed `rank(method='min')` and `rank(method='dense')` by category.

| Category | Rank | ProductKey | Product | Pandas profit | PostgreSQL profit | Result |
|---|---:|---:|---|---:|---:|---|
| Furniture | 1 | 64 | Hon Pagoda Stacking Chairs | 770.3520 | 770.3520 | PASS |
| Furniture | 2 | 37 | Hon Deluxe Fabric Upholstered Stacking Chairs, Rounded Back | 731.9400 | 731.9400 | PASS |
| Furniture | 3 | 55 | Office Star Professional Matrix Back Chair | 673.8816 | 673.8816 | PASS |

All **9 returned product members / 72 field checks** matched exactly, including ranks and both ranking functions.

### Query 22: Monthly LAG/LEAD Growth

Pandas grouped workbook rows by calendar month, then independently shifted monthly sales by 1, 12, and -1 rows to reproduce prior month, prior year, and next month values.

| Month | Pandas month / previous / prior-year / next sales | PostgreSQL month / previous / prior-year / next sales | Result |
|---|---|---|---|
| 2013-01 | 1539.9060 / NULL / NULL / 1233.1740 | 1539.9060 / NULL / NULL / 1233.1740 | PASS |
| 2013-02 | 1233.1740 / 1539.9060 / NULL / 5827.6020 | 1233.1740 / 1539.9060 / NULL / 5827.6020 | PASS |
| 2014-01 | 2510.5116 / 10635.5660 / 1539.9060 / 2527.5860 | 2510.5116 / 10635.5660 / 1539.9060 / 2527.5860 | PASS |
| 2016-12 | 18883.0708 / 15154.9780 / 26269.2710 / NULL | 18883.0708 / 15154.9780 / 26269.2710 / NULL | PASS |

All **48 monthly rows × 4 lag/lead values = 192 comparisons** matched. Pandas also confirmed the 48 months are consecutive, so 12 rows back is the same month in the previous year.

### Query 27: ABC/Pareto Product Classes

Pandas grouped Excel lines by the cleaned product natural key, reproduced the ETL's deterministic ProductKey ordering, sorted by sales, calculated cumulative sales, then applied the same 80%/95% cutoffs.

| Class | Pandas members / sales | PostgreSQL members / sales | Result |
|---|---|---|---|
| A: first ~80% | 268 / 401347.8578 | 268 / 401347.8578 | PASS |
| B: next ~15% | 334 / 74831.9830 | 334 / 74831.9830 | PASS |
| C: final ~5% | 724 / 25060.0500 | 724 / 25060.0500 | PASS |

All **6 class-level count and total comparisons** matched exactly.

## Phase 7 Findings

- **Product leaders:** The top profit members differ by category; Technology is led by a Canon copier (`8399.9760` profit), while Office Supplies is led by a binding system (`3804.9000`).
- **Monthly trend:** The highest monthly sales in the period occur in September 2013 (`34408.6898`); the month-over-month series has all 48 months, so no artificial gap-fill was necessary.
- **Cumulative totals:** At December 2016, running sales and profit equal `501239.8908` and `39706.3625` respectively.
- **Customer mix:** 345 repeat customers produced 891 orders and `364752.8330` sales; 284 one-time customers produced 284 orders and `136487.0578` sales.
- **ABC sales concentration:** 268 product members account for 80.07% of sales.
- **Customer decile:** `NTILE(10)` places 63 of 629 customers in the top decile; its first customer is Tamara Chand at `18437.1380` sales.
- **Loss concentration:** Binders contribute 38.91% of gross negative-profit dollars; Texas contributes 65.37% and Illinois 34.63%.

Phase 7 is complete. No views, procedures, indexes, or Phase 8 work were created.