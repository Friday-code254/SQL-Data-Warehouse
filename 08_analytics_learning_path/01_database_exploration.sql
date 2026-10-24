-- Business question: Which tables and columns are available in the warehouse?
-- Metric definitions: These are schema listings; no sales measures are calculated.
-- Interpretation: Run the second query to see the current Gold customer columns.
USE DataWarehouse;
GO

SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN (N'bronze', N'silver', N'gold', N'etl')
ORDER BY TABLE_SCHEMA, TABLE_NAME;

SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'gold' AND TABLE_NAME = N'dim_customers'
ORDER BY ORDINAL_POSITION;
GO
