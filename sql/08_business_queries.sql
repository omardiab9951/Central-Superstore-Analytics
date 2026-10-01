-- Phase 6: core business reporting for the Central Superstore warehouse.
-- Run this file with psql while connected to central_superstore_dw.
-- All statements are read-only SELECT queries; this file creates no objects.
-- Monetary amounts use the warehouse's NUMERIC(14,4) values.

-- Query 1: Executive KPIs. The scalar subquery first totals each order, then
-- averages those order totals so Average Order Value is not a line average.
SELECT
    MIN(order_date."FullDate") AS first_order_date,
    MAX(order_date."FullDate") AS last_order_date,
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    SUM(f."Quantity") AS total_quantity,
    COUNT(DISTINCT f."OrderID") AS total_orders,
    ROUND((SELECT AVG(order_totals.order_sales)
           FROM (SELECT "OrderID", SUM("Sales") AS order_sales
                 FROM warehouse."FactSales"
                 GROUP BY "OrderID") AS order_totals), 2) AS average_order_value,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent,
    COUNT(*) FILTER (WHERE f."Profit" < 0) AS negative_profit_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date
  ON order_date."DateKey" = f."OrderDateKey";

-- Query 2: Which categories and sub-categories contribute sales and profit?
-- Profit margin is profit divided by sales; negative margins remain visible.
SELECT
    p."Category",
    p."SubCategory",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    SUM(f."Quantity") AS total_quantity,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category", p."SubCategory"
ORDER BY p."Category", total_sales DESC;

-- Query 3: Which product members lead by sales?
-- Group by ProductKey, not ProductID, so the 16 IDs with multiple names remain distinct.
SELECT
    p."ProductKey",
    p."ProductID",
    p."ProductName",
    p."Category",
    p."SubCategory",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(*) AS order_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
ORDER BY total_sales DESC, p."ProductKey"
LIMIT 10;

-- Query 4: Which product members contribute the most profit?
-- Group by ProductKey, not ProductID, preserving separate observed names.
SELECT
    p."ProductKey",
    p."ProductID",
    p."ProductName",
    p."Category",
    p."SubCategory",
    SUM(f."Profit") AS total_profit,
    SUM(f."Sales") AS total_sales,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
ORDER BY total_profit DESC, p."ProductKey"
LIMIT 10;

-- Query 5: Which individual product members lose money overall?
-- Group by ProductKey, not ProductID, and HAVING keeps only negative-profit members.
SELECT
    p."ProductKey",
    p."ProductID",
    p."ProductName",
    p."Category",
    p."SubCategory",
    SUM(f."Profit") AS total_profit,
    SUM(f."Sales") AS total_sales,
    COUNT(*) AS order_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit ASC
LIMIT 15;

-- Query 6: Which categories are unprofitable overall?
-- HAVING filters after aggregation; this surfaces, rather than hides, category losses.
SELECT
    p."Category",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(*) FILTER (WHERE f."Profit" < 0) AS negative_profit_lines,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit;

-- Query 7: Which cities produce the most sales and profit?
-- Group at Region/State/City level; LIMIT shows the 20 highest-sales locations.
SELECT
    l."Region",
    l."State",
    l."City",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State", l."City"
ORDER BY total_sales DESC, l."State", l."City"
LIMIT 20;

-- Query 8: How do sales and profit compare across states?
-- All 13 observed states are returned so executives can compare the full region.
SELECT
    l."Region",
    l."State",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    SUM(f."Quantity") AS total_quantity,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State"
ORDER BY total_profit DESC;

-- Query 9: Which customers have the highest sales, and what is their order value?
-- The subquery first creates exactly one row per customer/order; AOV then averages orders equally.
SELECT
    c."CustomerID",
    c."CustomerName",
    c."Segment",
    SUM(order_totals.order_sales) AS total_sales,
    SUM(order_totals.order_profit) AS total_profit,
    COUNT(*) AS number_of_orders,
    ROUND(AVG(order_totals.order_sales), 2) AS average_order_value
FROM (
    SELECT
        f."CustomerKey",
        f."OrderID",
        SUM(f."Sales") AS order_sales,
        SUM(f."Profit") AS order_profit
    FROM warehouse."FactSales" AS f
    GROUP BY f."CustomerKey", f."OrderID"
) AS order_totals
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = order_totals."CustomerKey"
GROUP BY c."CustomerID", c."CustomerName", c."Segment"
ORDER BY total_sales DESC
LIMIT 10;

-- Query 10: Which customers place the most distinct orders?
-- COUNT(DISTINCT OrderID) avoids counting the multiple product lines in an order as extra orders.
SELECT
    c."CustomerID",
    c."CustomerName",
    c."Segment",
    COUNT(DISTINCT f."OrderID") AS number_of_orders,
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY c."CustomerID", c."CustomerName", c."Segment"
ORDER BY number_of_orders DESC, total_sales DESC
LIMIT 10;

-- Query 11: Which customer segments generate the most sales and profit?
SELECT
    c."Segment",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(DISTINCT f."OrderID") AS number_of_orders,
    COUNT(DISTINCT c."CustomerID") AS number_of_customers,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY c."Segment"
ORDER BY total_sales DESC;

-- Query 12: What are the annual sales and profitability trends?
-- This explicitly uses the order-date role of DimDate.
SELECT
    order_date."Year",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    SUM(f."Quantity") AS total_quantity,
    COUNT(DISTINCT f."OrderID") AS number_of_orders,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year"
ORDER BY order_date."Year";

-- Query 13: Which quarters show stronger sales and profit in each year?
SELECT
    order_date."Year",
    order_date."Quarter",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(DISTINCT f."OrderID") AS number_of_orders
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year", order_date."Quarter"
ORDER BY order_date."Year", order_date."Quarter";

-- Query 14: How do sales and profit change month by month?
-- MonthName is paired with its numeric month so results sort in calendar order.
SELECT
    order_date."Year",
    order_date."Month",
    order_date."MonthName",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(DISTINCT f."OrderID") AS number_of_orders
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year", order_date."Month", order_date."MonthName"
ORDER BY order_date."Year", order_date."Month";

-- Query 15: How do discount bands relate to sales and profit?
-- CASE creates readable bands; the exact discount values remain unchanged in the source.
SELECT
    CASE
        WHEN f."Discount" = 0 THEN 'No discount'
        WHEN f."Discount" <= 0.20 THEN 'Low (0.01-0.20)'
        WHEN f."Discount" <= 0.40 THEN 'Medium (0.21-0.40)'
        ELSE 'High (over 0.40)'
    END AS discount_band,
    COUNT(*) AS order_lines,
    COUNT(DISTINCT f."OrderID") AS number_of_orders,
    COUNT(DISTINCT p."ProductKey") AS product_members,
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY CASE
        WHEN f."Discount" = 0 THEN 'No discount'
        WHEN f."Discount" <= 0.20 THEN 'Low (0.01-0.20)'
        WHEN f."Discount" <= 0.40 THEN 'Medium (0.21-0.40)'
        ELSE 'High (over 0.40)'
    END
ORDER BY MIN(f."Discount");

-- Query 16: Which shipping modes handle the most orders and sales?
-- Count distinct orders because each order can have multiple fact rows.
SELECT
    f."ShipMode",
    COUNT(DISTINCT f."OrderID") AS number_of_orders,
    COUNT(DISTINCT c."CustomerID") AS number_of_customers,
    COUNT(*) AS order_lines,
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY f."ShipMode"
ORDER BY number_of_orders DESC;

-- Query 17: How long does shipping take by shipping mode?
-- Use the order-date and ship-date roles with separate, explicit aliases.
SELECT
    order_delays."ShipMode",
    COUNT(*) AS number_of_orders,
    ROUND(AVG(order_delays.shipping_days), 2) AS average_shipping_days,
    MIN(order_delays.shipping_days) AS minimum_shipping_days,
    MAX(order_delays.shipping_days) AS maximum_shipping_days
FROM (
    SELECT
        f."OrderID",
        f."ShipMode",
        MIN(ship_date."FullDate" - order_date."FullDate") AS shipping_days
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    JOIN warehouse."DimDate" AS ship_date ON ship_date."DateKey" = f."ShipDateKey"
    GROUP BY f."OrderID", f."ShipMode"
) AS order_delays
GROUP BY order_delays."ShipMode"
ORDER BY average_shipping_days;

-- Query 18: Which states have the most loss-making order lines?
-- This groups individual negative-profit lines by state and does not filter losses away.
SELECT
    l."State",
    COUNT(*) AS negative_profit_lines,
    SUM(f."Sales") AS sales_on_loss_lines,
    SUM(f."Profit") AS profit_on_loss_lines,
    COUNT(DISTINCT f."OrderID") AS orders_with_loss_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
WHERE f."Profit" < 0
GROUP BY l."State"
ORDER BY profit_on_loss_lines ASC;

-- Query 19: How do profit and margin compare by category and discount level?
-- Grouping retains category context so discount-driven losses can be traced to product mix.
SELECT
    p."Category",
    f."Discount",
    COUNT(*) AS order_lines,
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category", f."Discount"
ORDER BY p."Category", f."Discount";

-- Query 20: Which states and cities have overall negative profit?
-- HAVING filters grouped locations, exposing geographic areas requiring investigation.
SELECT
    l."Region",
    l."State",
    l."City",
    SUM(f."Sales") AS total_sales,
    SUM(f."Profit") AS total_profit,
    COUNT(*) FILTER (WHERE f."Profit" < 0) AS negative_profit_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State", l."City"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit ASC
LIMIT 20;