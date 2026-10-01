# Dataset Profile

## 1. Source Dataset
- **File:** `Central_Superstore.xlsx`
- **Sheet:** `Central_Region` (only sheet: `Central_Region`)
- **Rows:** 2,323 data rows, excluding the header
- **Columns:** 21
- **Workbook access:** Opened successfully in read-only mode; the source file was not written.

## 2. Column Dictionary

| Column name | Observed data type | Description/purpose | Missing values | Unique values |
|---|---|---|---:|---:|
| Row ID | integer | Source-row identifier. | 0 | 2,323 |
| Order ID | text | Identifier shared by product lines in the same order. | 0 | 1,175 |
| Order Date | date/datetime | Date the customer placed the order. | 0 | 720 |
| Ship Date | date/datetime | Date the order was shipped. | 0 | 746 |
| Ship Mode | text | Shipping service selected for the order. | 0 | 4 |
| Customer ID | text | Identifier for the customer. | 0 | 629 |
| Customer Name | text | Customer's displayed name. | 0 | 629 |
| Segment | text | Customer business segment. | 0 | 3 |
| Country | text | Country associated with the order location. | 0 | 1 |
| City | text | City associated with the order location. | 0 | 181 |
| State | text | State associated with the order location. | 0 | 13 |
| Postal Code | integer | Postal code associated with the order location. | 0 | 195 |
| Region | text | Sales region associated with the order. | 0 | 1 |
| Product ID | text | Identifier for the product. | 0 | 1,310 |
| Category | text | High-level product category. | 0 | 3 |
| Sub-Category | text | Product sub-category. | 0 | 17 |
| Product Name | text | Product's displayed name. | 0 | 1,295 |
| Sales | integer, number (decimal) | Sales amount recorded for this order line. | 0 | 1,955 |
| Quantity | integer | Number of units on this order line. | 0 | 14 |
| Discount | integer, number (decimal) | Discount rate recorded for this order line. | 0 | 9 |
| Profit | integer, number (decimal) | Profit or loss recorded for this order line. | 0 | 2,088 |

## 3. Data Quality

- **Missing values:** 0 missing cells across all columns. Per-column counts are shown above.
- **Completely duplicate data rows:** 0 duplicate occurrences (rows identical across all 21 fields).
- **Duplicate `Row ID` values:** 0 duplicated identifier values; `Row ID` is expected to identify a source row.
- **Repeated `Order ID` values:** 575 of 1,175 orders appear on multiple rows; this is consistent with orders containing multiple product lines, not a uniqueness failure.
- **Repeated `Customer ID` values:** 480 customers appear on multiple rows; 345 customers occur in more than one distinct order.
- **Repeated `Product ID` values:** 654 products appear on multiple rows; 654 products occur in more than one distinct order.
- **Invalid/missing dates:** Order Date has 0 non-date values; Ship Date has 0 non-date values.
- **Ship date before order date:** 0 rows.
- **Quantity checks:** 0 non-missing values are non-positive, non-numeric, or non-integer.
- **Sales checks:** 0 rows have zero or negative sales; 0 non-numeric and 0 non-finite values.
- **Discount checks:** 0 numeric values fall outside the expected 0 to 1 interval; 0 values are non-numeric; observed values are 0, 0.1, 0.2, 0.3, 0.32, 0.4, 0.5, 0.6, 0.8.
- **Profit checks:** 741 rows have negative profit (losses; these are analytically meaningful, not automatically invalid); 0 values are non-numeric.
- **Text formatting:** 4 text values have leading or trailing whitespace.
- **Region values:** Central (constant across non-missing rows).
- **Customer ID to Customer Name consistency:** 0 IDs map to multiple names.
- **Customer ID to Segment consistency:** 0 IDs map to multiple segments.
- **Product ID to Product Name consistency:** 16 IDs map to multiple names.
- **Product ID to Category consistency:** 0 IDs map to multiple categories.
- **Product ID to Sub-Category consistency:** 0 IDs map to multiple sub-categories.
- **Within-order consistency:** 0 orders vary in customer, order date, ship date, or ship mode across their rows.
- **Categorical domain review:** observed values are listed in Dataset Statistics. The workbook and plan do not provide an authoritative allowed-value list, so values are reported rather than labeled unexpected by assumption.

## 4. Dataset Statistics

| Measure | Result |
|---|---:|
| Unique customers | 629 |
| Unique products | 1,310 |
| Unique orders | 1,175 |
| States | 13 |
| Cities | 181 |
| Shipping modes | 4 |
| Customer segments | 3 |
| Product categories | 3 |
| Product sub-categories | 17 |
| Order Date range | 2013-01-03 to 2016-12-30 |
| Ship Date range | 2013-01-07 to 2017-01-05 |
| Total Sales | 501,239.89 |
| Total Quantity | 8,780.00 |
| Total Profit | 39,706.36 |
| Average Sales per row | 215.77 |
| Average Profit per row | 17.09 |
| Average Discount per row | 0.24 |

Numeric ranges:

| Column | Minimum | Maximum |
|---|---:|---:|
| Sales | 0.44 | 17,499.95 |
| Quantity | 1.00 | 14.00 |
| Discount | 0.00 | 0.80 |
| Profit | -3,701.89 | 8,399.98 |

Observed categorical values:

| Column | Values |
|---|---|
| Country | United States |
| State | Illinois, Indiana, Iowa, Kansas, Michigan, Minnesota, Missouri, Nebraska, North Dakota, Oklahoma, South Dakota, Texas, Wisconsin |
| Ship Mode | First Class, Same Day, Second Class, Standard Class |
| Segment | Consumer, Corporate, Home Office |
| Category | Furniture, Office Supplies, Technology |
| Sub-Category | Accessories, Appliances, Art, Binders, Bookcases, Chairs, Copiers, Envelopes, Fasteners, Furnishings, Labels, Machines, Paper, Phones, Storage, Supplies, Tables |
| Region | Central |

## 5. Relationship and Consistency Checks

- An order can have multiple rows: **yes**; 575 orders have multiple line rows. The maximum number of rows for one order is 10.
- Customers can appear across multiple orders: **yes**; 345 customer IDs appear in more than one order.
- Products can appear across multiple orders: **yes**; 654 product IDs appear in more than one order.
- Ship Date is on or after Order Date: **yes for all comparable rows**; violations: 0.
- Quantity is a positive whole number: **yes for all populated values**; invalid values: 0; missing: 0.
- Region is constant: **yes**; values: Central.
- Customer and product mapping conflict counts are listed in Data Quality; within-order conflicts: 0.

### First Five Data Rows

| Row ID | Order ID | Order Date | Ship Date | Ship Mode | Customer ID | Customer Name | Segment | Country | City | State | Postal Code | Region | Product ID | Category | Sub-Category | Product Name | Sales | Quantity | Discount | Profit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7981 | CA-2011-103800 | 2013-01-03T00:00:00 | 2013-01-07T00:00:00 | Standard Class | DP-13000 | Darren Powers | Consumer | United States | Houston | Texas | 77095 | Central | OFF-PA-10000174 | Office Supplies | Paper | Message Book, Wirebound, Four 5 1/2" X 4" Forms/Pg., 200 Dupl. Sets/Book | 16.448 | 2 | 0.2 | 5.5512 |
| 740 | CA-2011-112326 | 2013-01-04T00:00:00 | 2013-01-08T00:00:00 | Standard Class | PO-19195 | Phillina Ober | Home Office | United States | Naperville | Illinois | 60540 | Central | OFF-LA-10003223 | Office Supplies | Labels | Avery 508 | 11.784 | 3 | 0.2 | 4.2717 |
| 741 | CA-2011-112326 | 2013-01-04T00:00:00 | 2013-01-08T00:00:00 | Standard Class | PO-19195 | Phillina Ober | Home Office | United States | Naperville | Illinois | 60540 | Central | OFF-ST-10002743 | Office Supplies | Storage | SAFCO Boltless Steel Shelving | 272.736 | 3 | 0.2 | -64.7748 |
| 742 | CA-2011-112326 | 2013-01-04T00:00:00 | 2013-01-08T00:00:00 | Standard Class | PO-19195 | Phillina Ober | Home Office | United States | Naperville | Illinois | 60540 | Central | OFF-BI-10004094 | Office Supplies | Binders | GBC Standard Plastic Binding Systems Combs | 3.54 | 2 | 0.8 | -5.487 |
| 7661 | CA-2011-105417 | 2013-01-07T00:00:00 | 2013-01-12T00:00:00 | Standard Class | VS-21820 | Vivek Sundaresam | Consumer | United States | Huntsville | Texas | 77340 | Central | FUR-FU-10004864 | Furniture | Furnishings | Howard Miller 14-1/2" Diameter Chrome Round Wall Clock | 76.728 | 3 | 0.6 | -53.7096 |

### Last Five Data Rows

| Row ID | Order ID | Order Date | Ship Date | Ship Mode | Customer ID | Customer Name | Segment | Country | City | State | Postal Code | Region | Product ID | Category | Sub-Category | Product Name | Sales | Quantity | Discount | Profit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 6822 | CA-2014-163860 | 2016-12-28T00:00:00 | 2017-01-01T00:00:00 | Standard Class | LO-17170 | Lori Olson | Corporate | United States | Peoria | Illinois | 61604 | Central | FUR-FU-10001935 | Furniture | Furnishings | 3M Hangers With Command Adhesive | 2.96 | 2 | 0.6 | -1.406 |
| 7485 | CA-2014-135111 | 2016-12-28T00:00:00 | 2017-01-02T00:00:00 | Standard Class | CS-12400 | Christopher Schild | Home Office | United States | Fargo | North Dakota | 58103 | Central | OFF-AR-10004707 | Office Supplies | Art | Staples in misc. colors | 2.48 | 1 | 0 | 0.868 |
| 7486 | CA-2014-135111 | 2016-12-28T00:00:00 | 2017-01-02T00:00:00 | Standard Class | CS-12400 | Christopher Schild | Home Office | United States | Fargo | North Dakota | 58103 | Central | OFF-BI-10004040 | Office Supplies | Binders | Wilson Jones Impact Binders | 25.9 | 5 | 0 | 12.691 |
| 4240 | CA-2014-158673 | 2016-12-29T00:00:00 | 2017-01-04T00:00:00 | Standard Class | KB-16600 | Ken Brennan | Corporate | United States | Grand Rapids | Michigan | 49505 | Central | OFF-PA-10000994 | Office Supplies | Paper | Xerox 1915 | 209.7 | 2 | 0 | 100.656 |
| 646 | CA-2014-126221 | 2016-12-30T00:00:00 | 2017-01-05T00:00:00 | Standard Class | CC-12430 | Chuck Clark | Home Office | United States | Columbus | Indiana | 47201 | Central | OFF-AP-10002457 | Office Supplies | Appliances | Eureka The Boss Plus 12-Amp Hard Box Upright Vacuum, Red | 209.3 | 2 | 0 | 56.511 |

### Text Values With Leading or Trailing Whitespace

| Column | Exact value (`repr`) | Occurrences |
|---|---|---:|
| Product Name | `'Kensington SlimBlade Notebook Wireless Mouse with Nano Receiver '` | 4 |

### Product ID to Product Name Conflicts

| Product ID | Observed names |
|---|---|
| FUR-CH-10001146 | Global Task Chair, Black, Global Value Mid-Back Manager's Chair, Gray |
| FUR-FU-10001473 | DAX Wood Document Frame, Eldon Executive Woodline II Desk Accessories, Mahogany |
| FUR-FU-10004270 | Eldon Image Series Desk Accessories, Burgundy, Executive Impressions 13" Clairmont Wall Clock |
| OFF-AR-10001149 | Avery Hi-Liter Comfort Grip Fluorescent Highlighter, Yellow Ink, Sanford Colorific Colored Pencils, 12/Box |
| OFF-BI-10002026 | Avery Arch Ring Binders, Ibico Recycled Linen-Style Covers |
| OFF-BI-10004632 | GBC Binding covers, Ibico Hi-Tech Manual Binding System |
| OFF-BI-10004654 | Avery Binding System Hidden Tab Executive Style Index Sets, VariCap6 Expandable Binder |
| OFF-PA-10000477 | Xerox 1952, Xerox 22 |
| OFF-PA-10000659 | Adams Phone Message Book, Professional, 400 Message Capacity, 5 3/6” x 11”, TOPS Carbonless Receipt Book, Four 2-3/4 x 7-1/4 Money Receipts per Page |
| OFF-PA-10001970 | Xerox 1881, Xerox 1908 |
| OFF-PA-10002195 | RSVP Cards & Envelopes, Blank White, 8-1/2" X 11", 24 Cards/25 Envelopes/Set, Xerox 1966 |
| OFF-PA-10002377 | Adams Telephone Message Book W/Dividers/Space For Phone Numbers, 5 1/4"X8 1/2", 200/Messages, Xerox 1916 |
| OFF-ST-10001228 | Fellowes Personal Hanging Folder Files, Navy, Personal File Boxes with Fold-Down Carry Handle |
| OFF-ST-10004950 | Acco Perma 3000 Stacking Storage Drawers, Tenex Personal Filing Tote With Secure Closure Lid, Black/Frost |
| TEC-AC-10002550 | Maxell 4.7GB DVD-RW 3/Pack, Memorex 25GB 6X Branded Blu-Ray Recordable Disc, 30/Pack |
| TEC-AC-10003832 | Imation 16GB Mini TravelDrive USB 2.0 Flash Drive, Logitech P710e Mobile Speakerphone |

## 6. Important Findings

- The source contains 2,323 order-line rows and 1,175 distinct orders.
- 629 distinct customers and 1,310 distinct products recur across order lines.
- The workbook reports 1 non-missing region value(s): Central.
- There are 741 negative-profit rows; losses should be retained for business analysis.
- Product names have 16 identifier mapping conflict(s); inspect before treating these attributes as unique dimension values.
- One or more data-quality checks flagged records; see the detailed counts above before loading or transforming the data.

## 7. Assumptions for Future Phases

- Each populated source row is treated as one order line; `Order ID` is therefore expected to repeat.
- `Row ID` is treated as a row identifier and checked for uniqueness, not as a business entity key.
- Repeated customer and product IDs are expected because the same entities participate in multiple order lines.
- Negative profit represents a possible loss and is retained; it is not classified as invalid solely because it is negative.
- Discount rates are checked against the conventional 0 to 1 interval; the check does not reinterpret or alter source values.
- No source values are changed by this profiler. Any future handling of conflicts, missing values, or invalid records must be justified and documented.
