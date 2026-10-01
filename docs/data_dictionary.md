# Star Schema Data Dictionary

The PostgreSQL types below are the implemented types verified against the live `central_superstore_dw` catalog on 2026-10-01. Every listed column is `NOT NULL`; primary, foreign, and unique key roles are called out below. For source-backed columns, “Excel source column” names the column in `Central_Superstore.xlsx`, sheet `Central_Region`. “Derived” means calculated from the source date rather than independently supplied in Excel.

## `DimCustomer`

One row per source customer ID. The profile confirms each ID maps to one name and one segment.

| Column | PostgreSQL type | Description | Key type | Excel source column |
|---|---|---|---|---|
| `CustomerKey` | `INTEGER` | Warehouse-assigned identity for a customer dimension row. | PK; surrogate key | Not in Excel; database identity |
| `CustomerID` | `VARCHAR(20)` | Source customer identifier; unique within the observed dataset. | Natural/business key; unique | `Customer ID` |
| `CustomerName` | `TEXT` | Customer's display name. | Descriptive attribute | `Customer Name` |
| `Segment` | `VARCHAR(30)` | Customer segment label. | Descriptive attribute | `Segment` |

## `DimProduct`

One row per observed `(ProductID, ProductName)` combination after ETL outer-whitespace trimming. Product category and sub-category are included as descriptive attributes. `ProductID` alone is not unique in this table because 16 IDs have more than one source name.

| Column | PostgreSQL type | Description | Key type | Excel source column |
|---|---|---|---|---|
| `ProductKey` | `INTEGER` | Warehouse-assigned identity for an observed product member. | PK; surrogate key | Not in Excel; database identity |
| `ProductID` | `VARCHAR(30)` | Source product identifier; repeated for IDs with conflicting observed product names. | Part of composite natural/business key | `Product ID` |
| `ProductName` | `TEXT` | Product label after the ETL trims outer whitespace. Preserve distinct variants until an authoritative resolution is available. | Part of composite natural/business key | `Product Name` |
| `Category` | `VARCHAR(50)` | High-level product grouping. | Descriptive attribute | `Category` |
| `SubCategory` | `VARCHAR(50)` | Product grouping within the category. | Descriptive attribute | `Sub-Category` |

Implemented composite unique key: `(ProductID, ProductName)`. It is composite because it uses more than one column. The profile verifies category and sub-category consistency per `ProductID`; those fields are not needed to distinguish the observed name variants.

## `DimDate`

One row per calendar day from 2013-01-03 through 2017-01-05 inclusive, covering both source date roles.

| Column | PostgreSQL type | Description | Key type | Excel source column |
|---|---|---|---|---|
| `DateKey` | `INTEGER` | Deterministic `YYYYMMDD` key for the calendar date. | PK; derived calendar key | Derived from `FullDate` |
| `FullDate` | `DATE` | Calendar date represented by the row. | Natural key; unique | `Order Date` and `Ship Date` |
| `Year` | `SMALLINT` | Calendar year of `FullDate`. | Derived attribute | Derived from `FullDate` |
| `Quarter` | `SMALLINT` | Calendar quarter, 1 through 4. | Derived attribute | Derived from `FullDate` |
| `Month` | `SMALLINT` | Calendar month number, 1 through 12. | Derived attribute | Derived from `FullDate` |
| `MonthName` | `VARCHAR(12)` | Calendar month name. | Derived attribute | Derived from `FullDate` |
| `Day` | `SMALLINT` | Day of month. | Derived attribute | Derived from `FullDate` |
| `DayOfWeek` | `VARCHAR(12)` | Weekday name. | Derived attribute | Derived from `FullDate` |
| `IsWeekend` | `BOOLEAN` | True for Saturday or Sunday; false for Monday through Friday. | Derived attribute | Derived from `FullDate` |

The same `DateKey` is referenced by `FactSales.OrderDateKey` and `FactSales.ShipDateKey`; these foreign keys describe different date roles.

## `DimLocation`

One row per observed `(Country, State, City, PostalCode)` combination. The full tuple is the implemented natural key. Although postal codes uniquely map to locations in this snapshot, that uniqueness is not assumed to hold beyond this source extract.

| Column | PostgreSQL type | Description | Key type | Excel source column |
|---|---|---|---|---|
| `LocationKey` | `INTEGER` | Warehouse-assigned identity for a location row. | PK; surrogate key | Not in Excel; database identity |
| `Country` | `VARCHAR(100)` | Country associated with the source location; the observed value is `United States`. | Part of composite natural/business key; descriptive attribute | `Country` |
| `State` | `VARCHAR(100)` | State associated with the source location. | Part of composite natural/business key | `State` |
| `City` | `VARCHAR(100)` | City associated with the source location. | Part of composite natural/business key | `City` |
| `PostalCode` | `VARCHAR(20)` | Postal code. Use text even though Excel values were observed as integers, because postal codes are identifiers, not quantities, and text avoids losing leading zeroes if future sources contain them. | Part of composite natural/business key | `Postal Code` |
| `Region` | `VARCHAR(50)` | Sales region label; the observed value is `Central`. | Descriptive attribute; constant in this extract | `Region` |

## `FactSales`

One row per product line within an order. It stores measures and keys to the descriptive dimensions, plus source identifiers and shipment mode.

| Column | PostgreSQL type | Description | Key type | Excel source column |
|---|---|---|---|---|
| `SalesKey` | `BIGINT` | Warehouse-assigned identity for one fact row. | PK; surrogate key | Not in Excel; database identity |
| `SourceRowID` | `INTEGER` | Source row identifier retained for traceability; unique across the 2,323 rows in the profile. | Alternate unique key; source identifier | `Row ID` |
| `OrderID` | `VARCHAR(30)` | Source order identifier; repeats across product lines in an order. | Natural/business order key; not unique in fact | `Order ID` |
| `OrderDateKey` | `INTEGER` | Date the order was placed. | FK to `DimDate.DateKey` (order-date role) | `Order Date` (mapped to `DimDate`) |
| `ShipDateKey` | `INTEGER` | Date the order was shipped. | FK to `DimDate.DateKey` (ship-date role) | `Ship Date` (mapped to `DimDate`) |
| `CustomerKey` | `INTEGER` | Customer dimension member for the order line. | FK to `DimCustomer.CustomerKey` | `Customer ID` (lookup to `DimCustomer`) |
| `ProductKey` | `INTEGER` | Product dimension member for the exact source ID/name combination on the line. | FK to `DimProduct.ProductKey` | `Product ID` and `Product Name` (lookup to `DimProduct`) |
| `LocationKey` | `INTEGER` | Location dimension member associated with the order line. | FK to `DimLocation.LocationKey` | `Country`, `State`, `City`, and `Postal Code` (lookup to `DimLocation`) |
| `ShipMode` | `VARCHAR(30)` | Shipping mode recorded for the order line. Kept in the fact because the source provides no other mode attributes. | Descriptive transaction attribute; not a key | `Ship Mode` |
| `Sales` | `NUMERIC(14,4)` | Sales amount for the line. | Measure; additive | `Sales` |
| `Quantity` | `INTEGER` | Whole number of units on the line. | Measure; additive | `Quantity` |
| `Discount` | `NUMERIC(5,4)` | Discount rate for the line. Do not sum as an amount. | Measure; non-additive rate | `Discount` |
| `Profit` | `NUMERIC(14,4)` | Profit or loss for the line. Negative values are present and valid for analysis. | Measure; additive | `Profit` |

The implemented identity columns are `SalesKey`, `CustomerKey`, `ProductKey`, and `LocationKey` (`GENERATED BY DEFAULT AS IDENTITY`). `DateKey` is supplied deterministically in `YYYYMMDD` form; `IsWeekend` has the database default `FALSE` and the ETL supplies the correct derived value.

## Implemented Constraints

These key and check constraints were read from the live PostgreSQL catalog and agree with [04_constraints.sql](../sql/04_constraints.sql):

| Table | Constraint | Columns or rule |
|---|---|---|
| `DimCustomer` | Primary key | `CustomerKey` |
| `DimCustomer` | Unique | `CustomerID` |
| `DimDate` | Primary key | `DateKey` |
| `DimDate` | Unique | `FullDate` |
| `DimProduct` | Primary key | `ProductKey` |
| `DimProduct` | Unique | `(ProductID, ProductName)` |
| `DimLocation` | Primary key | `LocationKey` |
| `DimLocation` | Unique | `(Country, State, City, PostalCode)` |
| `FactSales` | Primary key | `SalesKey` |
| `FactSales` | Unique | `SourceRowID` |
| `FactSales` | Unique | `(OrderID, ProductKey)` |
| `FactSales` | Foreign keys | `CustomerKey`, `ProductKey`, `LocationKey`, `OrderDateKey`, and `ShipDateKey` reference their documented dimension primary keys. |
| `FactSales` | Checks | `Quantity > 0`; `Sales >= 0`; `Discount` is between 0 and 1 inclusive. Negative `Profit` remains allowed. |

The additional `UNIQUE (OrderID, ProductKey)` is a product-member rule and is not identical to uniqueness of the source `(Order ID, Product ID)` pair when a product ID has multiple observed names. Review this assumption before applying the schema to broader order-line data; see [audit_phases_1_to_5.md](audit_phases_1_to_5.md).

## Foreign-Key Map

| Fact column | Referenced column | Relationship |
|---|---|---|
| `CustomerKey` | `DimCustomer.CustomerKey` | One customer to many sales lines |
| `ProductKey` | `DimProduct.ProductKey` | One product member to many sales lines |
| `OrderDateKey` | `DimDate.DateKey` | One date to many sales lines in the order-date role |
| `ShipDateKey` | `DimDate.DateKey` | One date to many sales lines in the ship-date role |
| `LocationKey` | `DimLocation.LocationKey` | One location to many sales lines |

## Source-Column Coverage

Every one of the 21 Excel columns is represented in the implemented model, either directly on `FactSales` or in a dimension used by that fact:

| Source column | Implemented destination |
|---|---|
| `Row ID` | `FactSales.SourceRowID` |
| `Order ID` | `FactSales.OrderID` |
| `Order Date` | `DimDate.FullDate` via `FactSales.OrderDateKey` |
| `Ship Date` | `DimDate.FullDate` via `FactSales.ShipDateKey` |
| `Ship Mode` | `FactSales.ShipMode` |
| `Customer ID` | `DimCustomer.CustomerID`, looked up to `FactSales.CustomerKey` |
| `Customer Name` | `DimCustomer.CustomerName` |
| `Segment` | `DimCustomer.Segment` |
| `Country` | `DimLocation.Country` |
| `City` | `DimLocation.City` |
| `State` | `DimLocation.State` |
| `Postal Code` | `DimLocation.PostalCode` |
| `Region` | `DimLocation.Region` |
| `Product ID` | `DimProduct.ProductID`, used with `ProductName` to identify the observed member |
| `Category` | `DimProduct.Category` |
| `Sub-Category` | `DimProduct.SubCategory` |
| `Product Name` | `DimProduct.ProductName` |
| `Sales` | `FactSales.Sales` |
| `Quantity` | `FactSales.Quantity` |
| `Discount` | `FactSales.Discount` |
| `Profit` | `FactSales.Profit` |

No source column is dropped in this design.
