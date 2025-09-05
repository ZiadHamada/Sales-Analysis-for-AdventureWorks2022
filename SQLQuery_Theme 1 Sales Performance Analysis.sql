--What are the total sales and revenue trends over time? (Monthly/Quarterly/Yearly)
WITH SalesOverTime AS (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        MONTH(OrderDate) AS OrderMonth,
        DATEPART(QUARTER, OrderDate) AS OrderQuarter,
        SUM(SubTotal) AS MonthlyRevenue,
        COUNT(SalesOrderID) AS NumberOfOrdersMonthly,
        SUM(COUNT(SalesOrderID)) OVER (PARTITION BY YEAR(OrderDate), DATEPART(QUARTER, OrderDate)) AS NumberOfOrdersQuarterly,
        SUM(COUNT(SalesOrderID)) OVER (PARTITION BY YEAR(OrderDate)) AS NumberOfOrdersYearly,
        -- Calculate Quarterly Revenue using a window function
        SUM(SUM(SubTotal)) OVER (PARTITION BY YEAR(OrderDate), DATEPART(QUARTER, OrderDate)) AS QuarterlyRevenue,
        SUM(SUM(SubTotal)) OVER (PARTITION BY YEAR(OrderDate)) AS YearlyRevenue
    FROM Sales.SalesOrderHeader
    GROUP BY YEAR(OrderDate), DATEPART(QUARTER, OrderDate), MONTH(OrderDate)
)

SELECT
    OrderYear,
    OrderQuarter,
    OrderMonth,
    round(MonthlyRevenue, 2) as MonthlyRevenue,
    round(QuarterlyRevenue,2) as QuarterlyRevenue,
    round(YearlyRevenue, 2) as YearlyRevenue,
    NumberOfOrdersMonthly,
    NumberOfOrdersQuarterly,
    NumberOfOrdersYearly,
    round(LAG(MonthlyRevenue) OVER (ORDER BY OrderYear, OrderMonth), 2) AS PreviousMonthRevenue,
    round((MonthlyRevenue - LAG(MonthlyRevenue) OVER (ORDER BY OrderYear, OrderMonth)) / 
    NULLIF(LAG(MonthlyRevenue) OVER (ORDER BY OrderYear, OrderMonth), 0) * 100, 2) AS GrowthPercentage
FROM SalesOverTime
ORDER BY OrderYear, OrderQuarter, OrderMonth;

--Who are our top 10 customers by revenue?
select TOP 10 CustomerID, round(sum(SubTotal), 2) as CustomerRevenue
from Sales.SalesOrderHeader
group by customerID
order by sum(SubTotal) desc

--Which products are the best and worst sellers? (Consider both quantity and revenue)
select top 10 p.Name, round(sum(sod.LineTotal), 1) as TotalRevenue, sum(sod.OrderQty) as Quantity  
from Sales.SalesOrderHeader as soh
inner join Sales.SalesOrderDetail as sod
on soh.SalesOrderID = sod.SalesOrderID
inner join Production.Product as p
on sod.ProductID = p.ProductID
group by p.Name
order by sum(sod.LineTotal) asc 

select top 10 p.Name, round(sum(sod.LineTotal), 1) as TotalRevenue, sum(sod.OrderQty) as Quantity  
from Sales.SalesOrderHeader as soh
inner join Sales.SalesOrderDetail as sod
on soh.SalesOrderID = sod.SalesOrderID
inner join Production.Product as p
on sod.ProductID = p.ProductID
group by p.Name
order by sum(sod.LineTotal) desc 

--How do sales vary by territory or country?
select st.CountryRegionCode, round(sum(SubTotal), 2) as Revenue
from Sales.SalesOrderHeader as soh
inner join Sales.SalesTerritory as st
on soh.TerritoryID = st.TerritoryID
group by st.CountryRegionCode
order by sum(SubTotal) desc


select st.Name, st.CountryRegionCode, round(sum(SubTotal), 2) as Revenue
from Sales.SalesOrderHeader as soh
inner join Sales.SalesTerritory as st
on soh.TerritoryID = st.TerritoryID
group by st.Name, st.CountryRegionCode
order by sum(SubTotal) desc

--Is there any seasonality in our sales?
WITH SalesData AS (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        MONTH(OrderDate) AS OrderMonth,
        DATENAME(MONTH, OrderDate) AS MonthName, -- e.g., 'January', 'July'
        DATEPART(QUARTER, OrderDate) AS OrderQuarter,
        SUM(SubTotal) AS TotalSalesMonthly,
        COUNT(SalesOrderID) AS NumberOfOrdersMonthly
    FROM Sales.SalesOrderHeader
    GROUP BY YEAR(OrderDate), DATEPART(QUARTER, OrderDate), MONTH(OrderDate), DATENAME(MONTH, OrderDate)
)

SELECT
    OrderYear,
    OrderQuarter,
    OrderMonth,
    MonthName,
    TotalSalesMonthly,
    NumberOfOrdersMonthly,
    -- Calculate the average monthly sales for each year (to compare monthly performance within a year)
    AVG(TotalSalesMonthly) OVER (PARTITION BY OrderYear) AS AvgMonthlySalesForYear,
    -- Calculate the average sales for each month across all years (e.g., avg all Januarys)
    AVG(TotalSalesMonthly) OVER (PARTITION BY OrderMonth) AS AvgSalesForThisMonth
FROM SalesData
Order by OrderYear, OrderMonth


DROP VIEW IF EXISTS Sales.vw_SeasonalitySales;
GO
CREATE VIEW Sales.vw_SeasonalitySales AS
WITH SalesData AS (
    SELECT
        YEAR(OrderDate) AS OrderYear,
        MONTH(OrderDate) AS OrderMonth,
        DATENAME(MONTH, OrderDate) AS MonthName, -- e.g., 'January', 'July'
        DATEPART(QUARTER, OrderDate) AS OrderQuarter,
        SUM(SubTotal) AS TotalSalesMonthly,
        COUNT(SalesOrderID) AS NumberOfOrdersMonthly
    FROM Sales.SalesOrderHeader
    GROUP BY YEAR(OrderDate), DATEPART(QUARTER, OrderDate), MONTH(OrderDate), DATENAME(MONTH, OrderDate)
)

SELECT
    OrderYear,
    OrderQuarter,
    OrderMonth,
    MonthName,
    TotalSalesMonthly,
    NumberOfOrdersMonthly,
    -- Calculate the average monthly sales for each year (to compare monthly performance within a year)
    AVG(TotalSalesMonthly) OVER (PARTITION BY OrderYear) AS AvgMonthlySalesForYear,
    -- Calculate the average sales for each month across all years (e.g., avg all Januarys)
    AVG(TotalSalesMonthly) OVER (PARTITION BY OrderMonth) AS AvgSalesForThisMonth
FROM SalesData
