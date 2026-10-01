-- Phase 7: advanced read-only SQL for the Central Superstore warehouse.
-- Run with psql while connected to central_superstore_dw.
-- Query numbering continues after Phase 6 (Queries 1-20): this file contains 21-32.
-- Every statement is a SELECT; no data or database objects are changed.

-- Query 21: What are the top three profit-making product members within each category?
-- CTE 1 sums facts at ProductKey grain; this keeps the 16 multi-name Product IDs separate.
-- CTE 2 uses PARTITION BY Category so ranks restart for each category.
-- RANK leaves gaps after ties, DENSE_RANK does not, and ROW_NUMBER gives each row a unique sequence.
WITH product_profit AS (
    SELECT
        p."ProductKey",
        p."ProductID",
        p."ProductName",
        p."Category",
        p."SubCategory",
        SUM(f."Profit") AS total_profit,
        SUM(f."Sales") AS total_sales
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
),
ranked_products AS (
    SELECT
        product_profit.*,
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

-- Query 22: What are month-over-month and year-over-year sales changes?
-- CTE 1 aggregates line facts to one row per order month before calculating trends.
-- CTE 2 uses LAG(1) for the previous observed month, LAG(12) for the same month last year,
-- and LEAD(1) to show the next month. The warehouse has 48 consecutive months, verified separately.
WITH monthly_sales AS (
    SELECT
        date_trunc('month', order_date."FullDate")::DATE AS month_start,
        SUM(f."Sales") AS month_sales,
        SUM(f."Profit") AS month_profit,
        COUNT(DISTINCT f."OrderID") AS month_orders
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    GROUP BY date_trunc('month', order_date."FullDate")::DATE
),
monthly_comparison AS (
    SELECT
        monthly_sales.*,
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

-- Query 23: How do cumulative sales and profit build over time?
-- CTE 1 reduces order lines to one monthly total before the windows run.
-- CTE 2 uses SUM OVER ordered by month to add each month to all earlier months.
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

-- Query 24: What is the rolling three-month average of monthly sales and profit?
-- CTE 1 creates monthly amounts first, so the moving average is over months, not lines.
-- AVG OVER with two preceding rows plus the current row takes the latest three monthly totals.
-- At the first two months only the available one or two months are included.
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

-- Query 25: How many customers fall into transparent spend bands?
-- CTE 1 first calculates each customer's lifetime order count and spend.
-- CASE in CTE 2 assigns analysis-only tiers: High >= $5,000, Medium >= $1,000, otherwise Low.
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

-- Query 26: How does the one-time versus repeat customer mix behave?
-- CTE first counts distinct orders and totals each customer's facts.
-- CASE then labels customers with exactly one order or more than one order.
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

-- Query 27: What product-member bands account for sales under an ABC/Pareto view?
-- CTE 1 groups by ProductKey, preserving distinct observed names for a shared ProductID.
-- CTE 2 calculates a running sales total and whole-portfolio total with SUM OVER.
-- CTE 3 assigns A through the product that crosses 80%, B through the product crossing 95%, then C.
WITH product_sales AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName",
           SUM(f."Sales") AS product_sales
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
SELECT abc_class, COUNT(*) AS product_members,
       SUM(product_sales) AS class_sales,
       ROUND(100.0 * SUM(product_sales) / MAX(portfolio_sales), 2) AS portfolio_sales_percent
FROM product_classes
GROUP BY abc_class
ORDER BY CASE abc_class WHEN 'A: first ~80%' THEN 1 WHEN 'B: next ~15%' THEN 2 ELSE 3 END;

-- Query 28: Which customers make up the top sales decile?
-- CTE 1 totals each customer first, rather than ranking raw fact lines.
-- CTE 2 assigns NTILE(10) buckets, PERCENT_RANK (0=highest here), and a unique row number.
WITH customer_sales AS (
    SELECT c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment",
           COUNT(DISTINCT f."OrderID") AS order_count,
           SUM(f."Sales") AS total_sales,
           SUM(f."Profit") AS total_profit
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
SELECT "CustomerID", "CustomerName", "Segment", order_count,
       total_sales, total_profit, sales_decile,
    ROUND((100.0 * sales_percent_rank)::NUMERIC, 2) AS percent_rank_percent,
       sales_row_number
FROM customer_deciles
WHERE sales_decile = 1
ORDER BY sales_row_number;

-- Query 29: Which product members earn less profit than their own category average?
-- CTE 1 first creates one profit total per ProductKey.
-- The correlated subquery uses the current member's Category to calculate its peer-group average.
WITH product_totals AS (
    SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
           SUM(f."Profit") AS total_profit,
           SUM(f."Sales") AS total_sales
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
    GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
)
SELECT current_product."ProductKey", current_product."ProductID", current_product."ProductName",
       current_product."Category", current_product."SubCategory",
       current_product.total_profit,
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

-- Query 30: What share of all line-level losses comes from each sub-category?
-- CTE 1 groups only negative line profit as a positive loss amount by sub-category.
-- CTE 2 uses SUM OVER () for the total loss and a cumulative window for ranked contribution.
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

-- Query 31: Which states contribute the greatest share of line-level losses?
-- CTE 1 aggregates negative profit by state; CTE 2 compares each amount with total loss.
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

-- Query 32: Which product members contribute most to gross negative profit?
-- CTE 1 groups loss magnitudes by ProductKey, preserving product-name variants.
-- CTE 2 ranks and computes cumulative loss contribution with a window over product members.
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