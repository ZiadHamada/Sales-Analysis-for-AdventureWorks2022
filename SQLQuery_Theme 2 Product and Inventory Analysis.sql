--What is the relationship between list price, standard cost, and profit margin?
 --What is the potential margin if we sold every product at its full list price?
DROP VIEW IF EXISTS Production.vw_PotentialProfitMargin
GO
create view Production.vw_PotentialProfitMargin  as
SELECT
    p.ProductID,
    p.Name AS ProductName,
    p.ListPrice,
    p.StandardCost,
    -- Calculate Gross Profit per item
    AVG(p.ListPrice - p.StandardCost) AS AvgPotentialGrossProfit,
    -- Calculate Profit Margin Percentage. Avoid division by zero.
    AVG(CASE 
        WHEN p.ListPrice > 0 
        THEN (p.ListPrice - p.StandardCost) / p.ListPrice * 100 
        ELSE 0 
    END) AS AvgPotentialProfitMarginPercentage
FROM Production.Product p
WHERE p.ListPrice > 0  -- Exclude products that are not for sale (e.g., kits, internal items)
AND p.StandardCost > 0 -- Exclude products with no cost
GROUP BY p.ProductID, p.Name, p.ListPrice, p.StandardCost
--ORDER BY ProfitMarginPercentage DESC;

--What was our actual profit margin, taking into account discounts and promotions?"

DROP VIEW IF EXISTS Production.vw_ActualProfitMargin
GO
create view Production.vw_ActualProfitMargin  as
SELECT
    p.ProductID,
    p.Name AS ProductName,
    p.ListPrice,
    p.StandardCost,
    -- Analyze actual sale prices, not just list price
    AVG(sod.UnitPrice) AS AvgActualSellingPrice,
    AVG(sod.UnitPrice - p.StandardCost) AS AvgActualGrossProfit,
    AVG(CASE 
           WHEN sod.UnitPrice > 0 
           THEN (sod.UnitPrice - p.StandardCost) / sod.UnitPrice * 100 
           ELSE 0 
    END
    ) AS AvgActualProfitMarginPercentage,
    SUM(sod.LineTotal) AS TotalProductRevenue, -- Total revenue for this product
    SUM(sod.OrderQty) AS TotalUnitsSold -- Total units sold
FROM Production.Product p
INNER JOIN Sales.SalesOrderDetail sod ON p.ProductID = sod.ProductID
INNER JOIN Sales.SalesOrderHeader soh ON sod.SalesOrderID = soh.SalesOrderID -- Often joined to filter by date
WHERE p.StandardCost > 0 
AND p.ListPrice > 0
GROUP BY p.ProductID, p.Name, p.ListPrice, p.StandardCost
--ORDER BY TotalProductRevenue DESC;


--How many days of inventory do we have on hand for each product? Is any product overstocked or understocked?
-- Define the analysis period (e.g., from 1 year ago to the last order date)

--DECLARE @LastOrderDate DATE = (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader);
--DECLARE @StartDate DATE = DATEADD(YEAR, -1, @LastOrderDate);

DROP VIEW IF EXISTS Production.vw_StatusProductInventory 
GO

CREATE VIEW Production.vw_StatusProductInventory AS
WITH LastOrderDateCTE AS (
    SELECT MAX(OrderDate) AS LastOrderDate FROM Sales.SalesOrderHeader
),
DateRangeCTE AS (
    SELECT 
        LastOrderDate,
        DATEADD(YEAR, -1, LastOrderDate) AS StartDate
    FROM LastOrderDateCTE
),
TotalInventory AS (
    SELECT
        ProductID,
        SUM(Quantity) AS TotalInventoryQty
    FROM Production.ProductInventory
    GROUP BY ProductID
),
ProductSales AS (
    SELECT
        sod.ProductID,
        SUM(sod.OrderQty) AS TotalUnitsSold,
        MAX(dr.PeriodDays) AS PeriodDays  -- Using MAX since all rows will have same value
    FROM Sales.SalesOrderDetail sod
    INNER JOIN Sales.SalesOrderHeader soh ON sod.SalesOrderID = soh.SalesOrderID
    CROSS JOIN (
        SELECT 
            DATEDIFF(DAY, StartDate, LastOrderDate) AS PeriodDays
        FROM DateRangeCTE
    ) dr
    WHERE soh.OrderDate BETWEEN (SELECT StartDate FROM DateRangeCTE) 
                            AND (SELECT LastOrderDate FROM DateRangeCTE)
    GROUP BY sod.ProductID
),
InventoryAnalysis AS (
    SELECT
        p.ProductID,
        p.Name AS ProductName,
        inv.TotalInventoryQty,
        COALESCE(ps.TotalUnitsSold, 0) AS TotalUnitsSold,
        ps.PeriodDays,
        -- Calculate Average Daily Sales (handling division by zero)
        CASE 
            WHEN ps.PeriodDays > 0 THEN COALESCE(ps.TotalUnitsSold, 0) * 1.0 / ps.PeriodDays 
            ELSE 0 
        END AS AvgDailySales
    FROM Production.Product p
    INNER JOIN TotalInventory inv ON p.ProductID = inv.ProductID
    LEFT JOIN ProductSales ps ON p.ProductID = ps.ProductID
    CROSS JOIN DateRangeCTE dr
    WHERE p.SellEndDate IS NULL
)

SELECT
    ProductID,
    ProductName,
    TotalInventoryQty,
    TotalUnitsSold,
    ROUND(AvgDailySales, 4) AS AvgDailySales,
    ROUND(CASE
        WHEN AvgDailySales > 0 THEN TotalInventoryQty / AvgDailySales
        ELSE NULL
    END, 0) AS DaysOnHand,
    CASE
        WHEN AvgDailySales = 0 THEN 'No Recent Sales - Review'
        WHEN (TotalInventoryQty / AvgDailySales) > 90 THEN 'Overstocked'
        WHEN (TotalInventoryQty / AvgDailySales) < 15 THEN 'Understocked - Risk'
        ELSE 'Adequate Stock'
    END AS StockStatus
FROM InventoryAnalysis;
GO

-- Create the table structure first
CREATE TABLE Production.StatusProductInventory (
    ProductID INT,
    ProductName NVARCHAR(255),
    TotalInventoryQty INT,
    TotalUnitsSold INT,
    AvgDailySales DECIMAL(18,4),
    DaysOnHand DECIMAL(18,0),
    StockStatus NVARCHAR(50)
);

-- Then query with ordering when needed
INSERT INTO Production.StatusProductInventory 
SELECT * 
FROM Production.vw_StatusProductInventory 

--What is the product categorization hierarchy, and how does sales revenue break down across categories and subcategories?

DROP VIEW IF EXISTS Production.vw_ProductCategorizationHierarchy
GO

CREATE VIEW Production.vw_ProductCategorizationHierarchy AS
SELECT
    pc.Name AS CategoryName,
    ps.Name AS SubcategoryName,
    SUM(sod.LineTotal) AS TotalRevenue,
    COUNT(DISTINCT sod.SalesOrderID) AS NumberOfOrders,
    -- Calculate the percentage of the total revenue for each row
    FORMAT(SUM(sod.LineTotal) / SUM(SUM(sod.LineTotal)) OVER() * 100, 'N2') AS PctOfSubcategory,
    -- Calculate the percentage within the category for each subcategory
    FORMAT(SUM(sod.LineTotal) / SUM(SUM(sod.LineTotal)) OVER(PARTITION BY pc.Name) * 100, 'N2') AS PctOfSubForCategoryRevenue
FROM Sales.SalesOrderDetail sod
INNER JOIN Production.Product p 
    ON sod.ProductID = p.ProductID
INNER JOIN Production.ProductSubcategory ps 
    ON p.ProductSubcategoryID = ps.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc 
    ON ps.ProductCategoryID = pc.ProductCategoryID
GROUP BY pc.Name, ps.Name
--ORDER BY TotalRevenue DESC; -- Orders by highest revenue subcategory first