# Phase 6 Business Queries

All 20 statements in [08_business_queries.sql](../sql/08_business_queries.sql) were executed successfully on the live PostgreSQL warehouse using `psql -f sql/08_business_queries.sql`. The SQL contains only `SELECT` statements. No data or database objects were changed.

**Modeling rules used throughout:** orders contain multiple fact rows, so order counts use `COUNT(DISTINCT OrderID)` and order value is calculated after first aggregating to one row per order. Product-level queries group by `ProductKey`, keeping name variants for the 16 conflicting Product IDs separate. Date trend and delay queries join `DimDate` using clear `order_date` and `ship_date` aliases. Negative-profit lines remain visible.

## Query 1: Executive KPIs

**Business question:** What are overall sales, profit, quantity, order count, average order value, margin, and loss-line count?

**SQL**
```sql
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
```

**Real output sample**
```text
first_order_date | last_order_date | total_sales | total_profit | total_quantity | total_orders | average_order_value | profit_margin_percent | negative_profit_lines
2013-01-03       | 2016-12-30      | 501239.8908 | 39706.3625   | 8780           | 1175         | 426.59              | 7.92                  | 741
```

**How it works:** The date join supplies the order-date span. The outer query totals line measures and counts distinct orders. The scalar subquery first groups fact rows into one sales total per order, then averages those order totals. `NULLIF` protects the margin division if sales were zero.

**Manager insight:** The warehouse has positive overall profit and a 7.92% margin, but 741 lines lose money and merit deeper product/location investigation.

## Query 2: Category and Sub-Category Performance

**Business question:** Which product groups combine high sales with healthy profit and margin?

**SQL**
```sql
SELECT p."Category", p."SubCategory", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit, SUM(f."Quantity") AS total_quantity,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category", p."SubCategory"
ORDER BY p."Category", total_sales DESC;
```

**Real output sample**
```text
Category         | SubCategory | Sales      | Profit     | Quantity | Margin %
Furniture        | Chairs      | 85230.6460 | 6592.7221  | 615      | 7.74
Furniture        | Tables      | 39154.9710 | -3559.6504 | 262      | -9.09
Office Supplies  | Paper       | 17491.9020 | 6971.9005  | 1225     | 39.86
Technology       | Copiers     | 37259.5700 | 15608.8413 | 49       | 41.89
```

**How it works:** The product foreign key joins each line to its category and sub-category. The query groups by both descriptive fields and calculates additive measures before deriving the margin.

**Manager insight:** Tables, bookcases, furnishings, binders, and appliances have negative group profit; Copiers and Paper have comparatively strong margins.

## Query 3: Top Product Members by Sales

**Business question:** Which individual product members have the highest sales?

**SQL**
```sql
SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
       SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit, COUNT(*) AS order_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
ORDER BY total_sales DESC, p."ProductKey"
LIMIT 10;
```

**Real output sample**
```text
ProductKey | ProductID       | ProductName                                | Sales      | Profit
1183       | TEC-CO-10004722 | Canon imageCLASS 2200 Advanced Copier      | 17499.9500 | 8399.9760
1185       | TEC-MA-10000822 | Lexmark MX611dhe Monochrome Laser Printer  | 14279.9160 | -1189.9930
493        | OFF-BI-10001120 | Ibico EPK-21 Electric Binding System       | 11339.9400 | 1700.9910
```

**Product grouping choice:** Groups by `ProductKey`, not `ProductID`. This keeps each `ProductID + ProductName` dimension member distinct where the source has conflicting names.

**How it works:** Product attributes are joined through `ProductKey`, aggregated at the dimension-member level, ordered by sales, and limited to the ten highest.

**Manager insight:** The top seller is a Canon copier at 17,499.95 sales and 8,399.9760 profit. The second-ranked product by sales has negative profit, showing sales rank alone is not a profitability measure.

## Query 4: Top Product Members by Profit

**Business question:** Which product members contribute the most profit?

**SQL**
```sql
SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
       SUM(f."Profit") AS total_profit, SUM(f."Sales") AS total_sales,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
ORDER BY total_profit DESC, p."ProductKey"
LIMIT 10;
```

**Real output sample**
```text
ProductKey | ProductID       | ProductName                               | Profit    | Sales      | Margin %
1183       | TEC-CO-10004722 | Canon imageCLASS 2200 Advanced Copier     | 8399.9760 | 17499.9500 | 48.00
474        | OFF-BI-10000545 | GBC Ibimaster 500 Manual ProClick Binding System | 3804.9000 | 10653.7200 | 35.71
1181       | TEC-CO-10003763 | Canon PC1060 Personal Laser Copier        | 2302.9671 | 4899.9300  | 47.00
```

**Product grouping choice:** Groups by `ProductKey` for the same reason as Query 3; name variants remain separate.

**How it works:** It joins and groups at product-member level, then sorts by summed profit rather than sales.

**Manager insight:** Copiers lead the most profitable individual product members. Use this alongside loss-making items, not as a substitute for understanding the full product mix.

## Query 5: Loss-Making Product Members

**Business question:** Which individual product members have negative total profit?

**SQL**
```sql
SELECT p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory",
       SUM(f."Profit") AS total_profit, SUM(f."Sales") AS total_sales, COUNT(*) AS order_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit ASC
LIMIT 15;
```

**Real output sample**
```text
ProductKey | ProductID       | ProductName                                | Profit      | Sales
625        | OFF-BI-10004995 | GBC DocuBind P400 Electric Binding System  | -3048.6176  | 8710.3360
573        | OFF-BI-10003527 | Fellowes PB500 Electric Punch Plastic Comb Binding Machine | -1525.1880 | 6100.7520
318        | OFF-AP-10002534 | 3.6 Cubic Foot Counter Height Office Refrigerator | -1378.8216 | 530.3160
```

**Product grouping choice:** Groups by `ProductKey`; this avoids merging different observed names that share a Product ID.

**How it works:** `HAVING` filters after the per-product totals are calculated, retaining only product members whose total profit is below zero.

**Manager insight:** The deepest sampled loss is a binding system that sold 8,710.3360 but lost 3,048.6176; pricing, discount, and cost assumptions should be reviewed.

## Query 6: Unprofitable Categories

**Business question:** Which broad category loses money overall?

**SQL**
```sql
SELECT p."Category", SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit,
       COUNT(*) FILTER (WHERE f."Profit" < 0) AS negative_profit_lines,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit;
```

**Real output sample**
```text
Category  | Sales      | Profit     | Negative lines | Margin %
Furniture | 163797.1638 | -2871.0494 | 317            | -1.75
```

**How it works:** The query groups all lines into broad categories, counts negative-profit lines with a filtered aggregate, and uses `HAVING` to show only categories with a net loss.

**Manager insight:** Furniture is the only category with a net loss, despite 163,797.1638 in sales; review its negative sub-categories and discount mix.

## Query 7: Highest-Sales Cities

**Business question:** Which cities generate the most sales and profit?

**SQL**
```sql
SELECT l."Region", l."State", l."City", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State", l."City"
ORDER BY total_sales DESC, l."State", l."City"
LIMIT 20;
```

**Real output sample**
```text
Region  | State    | City        | Sales      | Profit      | Margin %
Central | Texas    | Houston     | 64504.7604 | -10153.5485 | -15.74
Central | Illinois | Chicago     | 48539.5410 | -6654.5688  | -13.71
Central | Michigan | Detroit     | 42446.9440 | 13181.7908  | 31.05
```

**How it works:** Fact lines join to the full location dimension. Grouping by region, state, and city gives one aggregate per city; the query sorts by sales and returns the top 20.

**Manager insight:** Houston and Chicago combine high sales with substantial losses, while Detroit is strongly profitable; sales volume by itself should not guide expansion decisions.

## Query 8: State Performance

**Business question:** How do sales, profit, quantity, and margin compare across the Central-region states?

**SQL**
```sql
SELECT l."Region", l."State", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit, SUM(f."Quantity") AS total_quantity,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State"
ORDER BY total_profit DESC;
```

**Real output sample**
```text
Region  | State     | Sales      | Profit     | Quantity | Margin %
Central | Michigan  | 76269.6140 | 24463.1876 | 946      | 32.07
Central | Indiana   | 53555.3600 | 18382.9363 | 578      | 34.33
Central | Texas     | 170188.0458 | -25729.3563| 3724     | -15.12
Central | Illinois  | 80166.1010 | -12607.8870| 1845     | -15.73
```

**How it works:** The location FK links lines to state attributes. The result has all 13 states and orders them by profit, including negative totals.

**Manager insight:** Michigan and Indiana are strongest by total profit, while Texas has the most sales and quantity but the largest loss.

## Query 9: Top Customers and Correct Average Order Value

**Business question:** Who are the top customers by sales, and how many orders and what average order value do they have?

**SQL**
```sql
SELECT c."CustomerID", c."CustomerName", c."Segment",
       SUM(order_totals.order_sales) AS total_sales,
       SUM(order_totals.order_profit) AS total_profit,
       COUNT(*) AS number_of_orders,
       ROUND(AVG(order_totals.order_sales), 2) AS average_order_value
FROM (
    SELECT f."CustomerKey", f."OrderID", SUM(f."Sales") AS order_sales,
           SUM(f."Profit") AS order_profit
    FROM warehouse."FactSales" AS f
    GROUP BY f."CustomerKey", f."OrderID"
) AS order_totals
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = order_totals."CustomerKey"
GROUP BY c."CustomerID", c."CustomerName", c."Segment"
ORDER BY total_sales DESC
LIMIT 10;
```

**Real output sample**
```text
CustomerID | CustomerName | Segment   | Sales     | Profit   | Orders | Average order value
TC-20980   | Tamara Chand | Corporate | 18437.1380| 8745.0635| 2      | 9218.57
AB-10105   | Adrian Barton | Consumer | 12181.5940| 5362.6135| 5      | 2436.32
```

**How it works:** The subquery groups each customer's fact lines to one row per order before the outer query counts orders and averages order totals. This prevents orders with more product lines from receiving extra weight.

**Manager insight:** Tamara Chand leads this sample by sales and has two high-value orders. Adrian Barton has more frequent orders and a lower average order value.

## Query 10: Customer Order Frequency

**Business question:** Which customers placed the most distinct orders?

**SQL**
```sql
SELECT c."CustomerID", c."CustomerName", c."Segment",
       COUNT(DISTINCT f."OrderID") AS number_of_orders,
       SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY c."CustomerID", c."CustomerName", c."Segment"
ORDER BY number_of_orders DESC, total_sales DESC
LIMIT 10;
```

**Real output sample**
```text
CustomerID | CustomerName   | Orders | Sales     | Profit
SC-20695   | Steve Chapman  | 7      | 1937.6080 | 539.0449
MA-17560   | Matt Abelman   | 6      | 1309.6930 | 497.7403
AB-10105   | Adrian Barton  | 5      | 12181.5940| 5362.6135
```

**How it works:** It groups fact lines by customer and counts distinct order identifiers so multiple product lines do not inflate order frequency.

**Manager insight:** The most frequent customer is not necessarily the highest spender; Steve Chapman has seven orders but lower total sales than several five-order customers.

## Query 11: Sales by Customer Segment

**Business question:** Which customer segment contributes sales, profit, customers, and orders?

**SQL**
```sql
SELECT c."Segment", SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit,
       COUNT(DISTINCT f."OrderID") AS number_of_orders,
       COUNT(DISTINCT c."CustomerID") AS number_of_customers,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY c."Segment"
ORDER BY total_sales DESC;
```

**Real output sample**
```text
Segment     | Sales      | Profit    | Orders | Customers | Margin %
Consumer    | 252031.4340| 8564.0481 | 604    | 328       | 3.40
Corporate   | 157995.8128| 18703.9020| 348    | 180       | 11.84
Home Office | 91212.6440 | 12438.4124| 223    | 121       | 13.64
```

**How it works:** The customer dimension supplies the segment labels; fact amounts are summed and customer/order identifiers counted distinctly.

**Manager insight:** Consumer is the largest segment by sales, but Home Office has the strongest margin. Corporate contributes the largest profit total after Consumer.

## Query 12: Annual Sales Trends

**Business question:** How do sales, profit, quantity, orders, and margin change by year?

**SQL**
```sql
SELECT order_date."Year", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit, SUM(f."Quantity") AS total_quantity,
       COUNT(DISTINCT f."OrderID") AS number_of_orders,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year"
ORDER BY order_date."Year";
```

**Real output sample**
```text
Year | Sales      | Profit    | Quantity | Orders | Margin %
2013 | 103838.1646| 539.5534  | 1726     | 230    | 0.52
2014 | 102874.2220| 11716.8020| 1815     | 234    | 11.39
2015 | 147429.3760| 19899.1629| 2359     | 305    | 13.50
2016 | 147098.1282| 7550.8442 | 2880     | 406    | 5.13
```

**How it works:** The `order_date` alias makes clear that the order-date role of `DimDate` is used. Grouping by its year creates four annual totals.

**Manager insight:** Sales peaked slightly in 2015 and remained similar in 2016, but profit fell sharply in 2016 even as orders and quantity rose.

## Query 13: Quarterly Trends

**Business question:** Which quarters within each year had the highest sales and profit?

**SQL**
```sql
SELECT order_date."Year", order_date."Quarter", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit, COUNT(DISTINCT f."OrderID") AS number_of_orders
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year", order_date."Quarter"
ORDER BY order_date."Year", order_date."Quarter";
```

**Real output sample**
```text
Year | Quarter | Sales     | Profit    | Orders
2013 | 1       | 8600.6820 | 139.2502  | 33
2013 | 2       | 17407.1446| 969.4834  | 50
2015 | 4       | 68079.9538| 19509.5939| 106
2016 | 4       | 46160.3850| -2159.4501| 152
```

**How it works:** The order-date calendar attributes group facts by year and quarter; distinct orders avoid line-count inflation. The full query returns 16 year-quarter rows.

**Manager insight:** 2015 Q4 was an exceptional profit quarter. 2016 Q4 had the most orders of the shown quarters but ended with a loss.

## Query 14: Monthly Trends

**Business question:** What are the monthly sales and profit patterns over the four-year period?

**SQL**
```sql
SELECT order_date."Year", order_date."Month", order_date."MonthName",
       SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit,
       COUNT(DISTINCT f."OrderID") AS number_of_orders
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
GROUP BY order_date."Year", order_date."Month", order_date."MonthName"
ORDER BY order_date."Year", order_date."Month";
```

**Real output sample**
```text
Year | Month | MonthName | Sales      | Profit    | Orders
2013 | 1     | January   | 1539.9060  | 118.4902  | 8
2013 | 2     | February  | 1233.1740  | 294.8067  | 11
2013 | 9     | September | 34408.6898 | 1422.7972 | 29
2016 | 12    | December  | 18883.0708 | -1238.3754| 53
```

**How it works:** The query joins the order-date role and groups by year, month number, and month name. Numeric month ordering keeps months chronological. The query returned 48 rows.

**Manager insight:** September 2013 and October 2015 were notable sales months, while some high-activity late periods still had negative profit; inspect margins with seasonal sales.

## Query 15: Discount Bands

**Business question:** How do sales, profit, and margin vary across simple discount levels?

**SQL**
```sql
SELECT CASE
           WHEN f."Discount" = 0 THEN 'No discount'
           WHEN f."Discount" <= 0.20 THEN 'Low (0.01-0.20)'
           WHEN f."Discount" <= 0.40 THEN 'Medium (0.21-0.40)'
           ELSE 'High (over 0.40)'
       END AS discount_band,
       COUNT(*) AS order_lines, COUNT(DISTINCT f."OrderID") AS number_of_orders,
       COUNT(DISTINCT p."ProductKey") AS product_members,
       SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit,
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
```

**Real output sample**
```text
Band                | Lines | Orders | Product members | Sales      | Profit      | Margin %
No discount         | 828   | 410    | 661             | 243150.6400| 76125.4407  | 31.31
Low (0.01-0.20)     | 852   | 568    | 622             | 128955.1520| 15973.1962  | 12.39
Medium (0.21-0.40)  | 187   | 168    | 123             | 98974.9728 | -11598.8353 | -11.72
High (over 0.40)    | 456   | 351    | 309             | 30159.1260 | -40793.4391 | -135.26
```

**How it works:** `CASE` labels each fact line using its discount value. The resulting band is grouped and line, distinct-order, and distinct-product-member counts are reported. Product members are counted by `ProductKey`, so observed name variants remain separate.

**Manager insight:** The medium and high discount bands lose money overall. The high band has the largest loss despite relatively low sales; discount policy and product mix should be reviewed.

## Query 16: Shipping Mode Sales and Orders

**Business question:** Which shipping modes are used most often, and what sales/profit do their orders represent?

**SQL**
```sql
SELECT f."ShipMode", COUNT(DISTINCT f."OrderID") AS number_of_orders,
       COUNT(DISTINCT c."CustomerID") AS number_of_customers,
       COUNT(*) AS order_lines, SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit
FROM warehouse."FactSales" AS f
JOIN warehouse."DimCustomer" AS c ON c."CustomerKey" = f."CustomerKey"
GROUP BY f."ShipMode"
ORDER BY number_of_orders DESC;
```

**Real output sample**
```text
ShipMode       | Orders | Customers | Lines | Sales      | Profit
Standard Class | 715    | 483       | 1439  | 318527.5600| 25352.3807
Second Class   | 224    | 194       | 465   | 103550.0054| 9114.8349
First Class    | 174    | 159       | 299   | 58746.9154 | 3707.2672
Same Day       | 62     | 61        | 120   | 20415.4100 | 1531.8797
```

**How it works:** It groups by the transaction's shipping-mode label, totals the associated facts, and counts distinct orders and customers rather than treating every line as a separate order.

**Manager insight:** Standard Class carries most orders and sales. Profit remains positive for every mode in aggregate.

## Query 17: Shipping Delay

**Business question:** How many days elapse between order and shipment for each shipping mode?

**SQL**
```sql
SELECT order_delays."ShipMode", COUNT(*) AS number_of_orders,
       ROUND(AVG(order_delays.shipping_days), 2) AS average_shipping_days,
       MIN(order_delays.shipping_days) AS minimum_shipping_days,
       MAX(order_delays.shipping_days) AS maximum_shipping_days
FROM (
    SELECT f."OrderID", f."ShipMode",
           MIN(ship_date."FullDate" - order_date."FullDate") AS shipping_days
    FROM warehouse."FactSales" AS f
    JOIN warehouse."DimDate" AS order_date ON order_date."DateKey" = f."OrderDateKey"
    JOIN warehouse."DimDate" AS ship_date ON ship_date."DateKey" = f."ShipDateKey"
    GROUP BY f."OrderID", f."ShipMode"
) AS order_delays
GROUP BY order_delays."ShipMode"
ORDER BY average_shipping_days;
```

**Real output sample**
```text
ShipMode       | Orders | Average days | Minimum | Maximum
Same Day       | 62     | 0.05         | 0       | 1
First Class    | 174    | 2.23         | 1       | 3
Second Class   | 224    | 3.37         | 2       | 5
Standard Class | 715    | 4.99         | 4       | 7
```

**How it works:** The same date dimension is joined twice with role-specific aliases. The inner query creates one delay per order, then the outer query averages orders by shipping mode. This prevents orders with more product lines from counting more heavily.

**Manager insight:** Observed delivery intervals align with the service labels: Same Day is near zero, while Standard Class averages 4.99 days.

## Query 18: Loss-Making Lines by State

**Business question:** Where are loss-making order lines concentrated?

**SQL**
```sql
SELECT l."State", COUNT(*) AS negative_profit_lines,
       SUM(f."Sales") AS sales_on_loss_lines, SUM(f."Profit") AS profit_on_loss_lines,
       COUNT(DISTINCT f."OrderID") AS orders_with_loss_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
WHERE f."Profit" < 0
GROUP BY l."State"
ORDER BY profit_on_loss_lines ASC;
```

**Real output**
```text
State    | Loss lines | Sales on loss lines | Profit on loss lines | Orders with loss lines
Texas    | 486        | 102656.4568         | -36813.1875          | 312
Illinois | 255        | 38626.2020          | -19501.6975          | 182
```

**How it works:** `WHERE` keeps only negative-profit facts before the state grouping. The query retains sales on those lines and counts distinct orders affected.

**Manager insight:** Texas and Illinois account for all state-level negative-profit lines returned by this query; Texas dominates both loss count and loss amount.

## Query 19: Profit by Category and Discount Level

**Business question:** Within each product category, at which exact discount levels does profit weaken?

**SQL**
```sql
SELECT p."Category", f."Discount", COUNT(*) AS order_lines,
       SUM(f."Sales") AS total_sales, SUM(f."Profit") AS total_profit,
       ROUND(100.0 * SUM(f."Profit") / NULLIF(SUM(f."Sales"), 0), 2) AS profit_margin_percent
FROM warehouse."FactSales" AS f
JOIN warehouse."DimProduct" AS p ON p."ProductKey" = f."ProductKey"
GROUP BY p."Category", f."Discount"
ORDER BY p."Category", f."Discount";
```

**Real output sample**
```text
Category        | Discount | Lines | Sales      | Profit      | Margin %
Furniture       | 0.0000   | 156   | 74929.3500 | 16641.3819  | 22.21
Furniture       | 0.3000   | 142   | 61178.9850 | -6866.8937  | -11.22
Office Supplies | 0.8000   | 300   | 16963.7560 | -30539.0392 | -180.03
Technology      | 0.4000   | 13    | 19546.2240 | -2666.8434  | -13.64
```

**How it works:** Product members join through `ProductKey`; grouping by category and the source discount value makes the discount/mix relationship visible without combining product name variants.

**Manager insight:** High discounts in Office Supplies and Furniture are associated with substantial category losses in this dataset. This is descriptive evidence, not proof that discount alone caused those losses.

## Query 20: Lowest-Profit Cities

**Business question:** Which cities have the lowest total profit, including city-level losses?

**SQL**
```sql
SELECT l."Region", l."State", l."City", SUM(f."Sales") AS total_sales,
       SUM(f."Profit") AS total_profit,
       COUNT(*) FILTER (WHERE f."Profit" < 0) AS negative_profit_lines
FROM warehouse."FactSales" AS f
JOIN warehouse."DimLocation" AS l ON l."LocationKey" = f."LocationKey"
GROUP BY l."Region", l."State", l."City"
HAVING SUM(f."Profit") < 0
ORDER BY total_profit ASC
LIMIT 20;
```

**Real output sample**
```text
Region  | State    | City        | Sales      | Profit      | Negative lines
Central | Texas    | Houston     | 64504.7604 | -10153.5485 | 185
Central | Texas    | San Antonio | 21843.5280 | -7299.0502  | 33
Central | Illinois | Chicago     | 48539.5410 | -6654.5688  | 155
```

**How it works:** Fact rows join to city-level location attributes. `HAVING` keeps cities with net negative profit after aggregation, and the ordering surfaces the largest losses first.

**Manager insight:** Houston, San Antonio, and Chicago are the largest city-level loss locations in the returned sample and are candidates for operational or pricing review.

## Independent Pandas Verification

Three selected queries were independently recomputed from the read-only Excel workbook using pandas, then compared with fresh PostgreSQL `SELECT` results. Source Sales and Profit values were normalized to four decimal places to match the warehouse's `NUMERIC(14,4)` precision. All comparisons below matched exactly; the declared comparison tolerance was `0.0001`.

### Query 2: Category/Sub-Category Totals

| Group | Pandas Sales / Profit / Quantity | PostgreSQL Sales / Profit / Quantity | Result |
|---|---|---|---|
| Furniture / Chairs | 85230.6460 / 6592.7221 / 615 | 85230.6460 / 6592.7221 / 615 | PASS |
| Office Supplies / Paper | 17491.9020 / 6971.9005 / 1225 | 17491.9020 / 6971.9005 / 1225 | PASS |
| Technology / Copiers | 37259.5700 / 15608.8413 / 49 | 37259.5700 / 15608.8413 / 49 | PASS |

All **17 groups / 51 measure comparisons** passed; maximum absolute difference: **0.0000**.

### Query 12: Annual Trends

| Year | Pandas Sales / Profit / Quantity / Orders | PostgreSQL Sales / Profit / Quantity / Orders | Result |
|---:|---|---|---|
| 2013 | 103838.1646 / 539.5534 / 1726 / 230 | 103838.1646 / 539.5534 / 1726 / 230 | PASS |
| 2014 | 102874.2220 / 11716.8020 / 1815 / 234 | 102874.2220 / 11716.8020 / 1815 / 234 | PASS |
| 2015 | 147429.3760 / 19899.1629 / 2359 / 305 | 147429.3760 / 19899.1629 / 2359 / 305 | PASS |
| 2016 | 147098.1282 / 7550.8442 / 2880 / 406 | 147098.1282 / 7550.8442 / 2880 / 406 | PASS |

All **4 years / 16 measure comparisons** passed; maximum absolute difference: **0.0000**.

### Query 15: Discount Bands

| Band | Pandas lines / orders / sales / profit | PostgreSQL lines / orders / sales / profit | Result |
|---|---|---|---|
| No discount | 828 / 410 / 661 / 243150.6400 / 76125.4407 | 828 / 410 / 661 / 243150.6400 / 76125.4407 | PASS |
| Low (0.01-0.20) | 852 / 568 / 622 / 128955.1520 / 15973.1962 | 852 / 568 / 622 / 128955.1520 / 15973.1962 | PASS |
| Medium (0.21-0.40) | 187 / 168 / 123 / 98974.9728 / -11598.8353 | 187 / 168 / 123 / 98974.9728 / -11598.8353 | PASS |
| High (over 0.40) | 456 / 351 / 309 / 30159.1260 / -40793.4391 | 456 / 351 / 309 / 30159.1260 / -40793.4391 | PASS |

The pandas calculation identified distinct product members by `(Product ID, cleaned Product Name)`, matching the dimension's `ProductKey` rule. All **4 bands / 20 comparisons** passed; maximum absolute difference: **0**.

## Important Findings

- Total sales are `501239.8908`; total profit is `39706.3625`, a `7.92%` overall margin. There are 1,175 orders, and average order value is `426.59` after aggregating the line items per order.
- Losses are material and were not hidden: 741 of 2,323 fact lines have negative profit. Furniture loses `2871.0494` overall; Tables, Bookcases, and Furnishings are among its loss-making sub-categories.
- The high discount band (`over 0.40`) has `30159.1260` sales and `-40793.4391` profit. The medium band also loses `11598.8353`. This association should prompt investigation, not be interpreted as causation by itself.
- Texas has the highest state sales (`170188.0458`) but the largest state loss (`-25729.3563`); Illinois also loses `12607.8870`. In contrast, Michigan and Indiana are the most profitable states.
- Consumer is the largest segment by sales (`252031.4340`), while Home Office has the highest segment margin (`13.64%`).
- Annual sales rose from `103838.1646` in 2013 to around `147,000` in 2015–2016, but 2016 profit was lower than 2015 despite more orders and quantity.
- Standard Class accounts for 715 distinct orders and averages 4.99 shipping days. Same Day averages 0.03 days in the recorded date fields.
- Product-level rankings group by `ProductKey`; this respects the 16 Product IDs with multiple observed product names.

Phase 6 is complete. CTEs and window functions are intentionally reserved for Phase 7; no view, procedure, index, or data-changing statement was added.