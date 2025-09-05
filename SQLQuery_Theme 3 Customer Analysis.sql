--What is the customer demographic breakdown (e.g., by region)?
DROP VIEW IF EXISTS Sales.vw_CustomerDemographic
GO
create view Sales.vw_CustomerDemographic  as
SELECT
    st.TerritoryID,
    st.Name AS Region,
    cr.Name AS Country,
    sp.Name AS StateProvince,
    COUNT(DISTINCT c.CustomerID) AS NumberOfCustomers,
    SUM(soh.SubTotal) AS TotalRevenue
FROM Sales.Customer c
INNER JOIN Sales.SalesTerritory st 
    ON c.TerritoryID = st.TerritoryID
INNER JOIN Person.Person p 
    ON c.PersonID = p.BusinessEntityID
INNER JOIN Person.BusinessEntityAddress bea 
    ON p.BusinessEntityID = bea.BusinessEntityID
INNER JOIN Person.Address a 
    ON bea.AddressID = a.AddressID
INNER JOIN Person.StateProvince sp 
    ON a.StateProvinceID = sp.StateProvinceID
INNER JOIN Person.CountryRegion cr 
    ON sp.CountryRegionCode = cr.CountryRegionCode
LEFT JOIN Sales.SalesOrderHeader soh 
    ON c.CustomerID = soh.CustomerID -- Use LEFT JOIN to include customers who haven't ordered
GROUP BY st.TerritoryID, st.Name, cr.Name, sp.Name
--ORDER BY TotalRevenue DESC;



--Can we identify our most valuable customers?
DROP VIEW IF EXISTS Sales.vw_ValuableCustomers
GO
create view Sales.vw_ValuableCustomers  as
-- First, declare the snapshot date (the date we are analyzing from)
--DECLARE @SnapshotDate DATE = (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader);
-- This gets the last order date in the system, making our analysis current.

WITH CustomerRFM AS (
    SELECT
        soh.CustomerID,
        p.FirstName + ' ' + p.LastName AS CustomerName,
        -- RECENCY: Days since last purchase
        DATEDIFF(DAY, MAX(soh.OrderDate), (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader)) AS Recency,
        -- FREQUENCY: Count of distinct orders
        COUNT(DISTINCT soh.SalesOrderID) AS Frequency,
        -- MONETARY: Total revenue from customer
        SUM(soh.SubTotal) AS Monetary
    FROM Sales.SalesOrderHeader soh
    INNER JOIN Sales.Customer c ON soh.CustomerID = c.CustomerID
    INNER JOIN Person.Person p ON c.PersonID = p.BusinessEntityID -- Gets customer name
    GROUP BY soh.CustomerID, p.FirstName, p.LastName
),
-- Second CTE: Assign scores (1-5) for each RFM value
RFM_Scored AS (
    SELECT
        *,
        -- NTILE divides the customer list into 5 groups for each metric.
        NTILE(5) OVER (ORDER BY Recency DESC) AS R_Score, -- High Recency (days ago) is bad, so order DESC
        NTILE(5) OVER (ORDER BY Frequency ASC) AS F_Score, -- Low Frequency is bad, order ASC
        NTILE(5) OVER (ORDER BY Monetary ASC) AS M_Score  -- Low Monetary is bad, order ASC
    FROM CustomerRFM
)
-- Final SELECT: Combine scores and segment customers
SELECT
    CustomerID,
    CustomerName,
    Recency,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    -- Create a combined RFM score (e.g., 555, 545, 111)
    CONCAT(R_Score, F_Score, M_Score) AS RFM_Score,
    -- Segment customers based on their scores
    CASE
        WHEN CONCAT(R_Score, F_Score, M_Score) IN ('555', '554', '545', '544') THEN 'Champions'
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 3 THEN 'Loyal Customers'
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'Potential Loyalists'
        WHEN R_Score >= 4 AND F_Score <= 2 AND M_Score <= 2 THEN 'New Customers'
        WHEN R_Score >= 3 AND F_Score <= 2 AND M_Score <= 2 THEN 'Promising'
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score <= 2 THEN 'Need Attention'
        WHEN R_Score <= 2 AND F_Score >= 4 AND M_Score >= 4 THEN 'At Risk'
        WHEN R_Score <= 2 AND F_Score >= 3 AND M_Score >= 3 THEN 'Cant Lose Them'
        WHEN R_Score <= 2 AND F_Score <= 2 AND M_Score <= 2 THEN 'Hibernating'
        ELSE 'Lost'
    END AS CustomerSegment
FROM RFM_Scored
--ORDER BY Monetary DESC; -- Order by most valuable first