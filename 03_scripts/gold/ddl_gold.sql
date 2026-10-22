/* Materialized, key-stable star schema. Re-running this file preserves all rows. */
USE DataWarehouse;
GO
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
/* The original Gold objects were views and stored no data; remove those views once. */
IF OBJECT_ID(N'gold.fact_sales', N'V') IS NOT NULL DROP VIEW gold.fact_sales;
IF OBJECT_ID(N'gold.dim_products', N'V') IS NOT NULL DROP VIEW gold.dim_products;
IF OBJECT_ID(N'gold.dim_customers', N'V') IS NOT NULL DROP VIEW gold.dim_customers;
GO
IF OBJECT_ID(N'gold.dim_customers', N'U') IS NULL CREATE TABLE gold.dim_customers (
    customer_key int IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_dim_customers PRIMARY KEY,
    customer_id int NOT NULL, customer_number nvarchar(50) NOT NULL,
    first_name nvarchar(100) NULL, last_name nvarchar(100) NULL, country nvarchar(100) NULL,
    marital_status nvarchar(20) NOT NULL, gender nvarchar(20) NOT NULL, birthdate date NULL, create_date date NULL,
    effective_start_date datetime2(3) NOT NULL, effective_end_date datetime2(3) NULL,
    is_current bit NOT NULL, attribute_hash binary(32) NOT NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.dim_customers') AND name=N'UX_gold_customer_current')
    CREATE UNIQUE INDEX UX_gold_customer_current ON gold.dim_customers(customer_id) WHERE is_current=1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.dim_customers') AND name=N'UX_gold_customer_number_current')
    CREATE UNIQUE INDEX UX_gold_customer_number_current ON gold.dim_customers(customer_number) WHERE is_current=1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.dim_customers') AND name=N'IX_gold_customer_number')
    CREATE INDEX IX_gold_customer_number ON gold.dim_customers(customer_number);

IF OBJECT_ID(N'gold.dim_products', N'U') IS NULL CREATE TABLE gold.dim_products (
    product_key int IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_dim_products PRIMARY KEY,
    product_id int NOT NULL, product_number nvarchar(50) NOT NULL, product_name nvarchar(100) NOT NULL,
    category_id nvarchar(50) NOT NULL, category nvarchar(100) NULL, subcategory nvarchar(100) NULL,
    maintenance nvarchar(20) NULL, cost decimal(19,4) NULL, product_line nvarchar(30) NOT NULL,
    start_date date NOT NULL, effective_start_date datetime2(3) NOT NULL,
    effective_end_date datetime2(3) NULL, is_current bit NOT NULL, attribute_hash binary(32) NOT NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.dim_products') AND name=N'UX_gold_product_current')
    CREATE UNIQUE INDEX UX_gold_product_current ON gold.dim_products(product_number) WHERE is_current=1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.dim_products') AND name=N'IX_gold_product_category')
    CREATE INDEX IX_gold_product_category ON gold.dim_products(category_id,product_line);

IF OBJECT_ID(N'gold.dim_date', N'U') IS NULL CREATE TABLE gold.dim_date (
    date_key int NOT NULL CONSTRAINT PK_gold_dim_date PRIMARY KEY,
    full_date date NOT NULL CONSTRAINT UQ_gold_dim_date_full_date UNIQUE,
    calendar_year smallint NOT NULL, calendar_quarter tinyint NOT NULL, month_number tinyint NOT NULL,
    month_name nvarchar(20) NOT NULL, week_of_year tinyint NOT NULL,
    day_of_month tinyint NOT NULL, day_of_week tinyint NOT NULL, day_name nvarchar(20) NOT NULL,
    is_weekend bit NOT NULL
);

IF OBJECT_ID(N'gold.fact_sales', N'U') IS NULL CREATE TABLE gold.fact_sales (
    fact_sales_key bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_fact_sales PRIMARY KEY,
    order_number nvarchar(50) NOT NULL, product_id int NOT NULL, product_number nvarchar(50) NOT NULL, customer_id int NOT NULL,
    product_key int NOT NULL, customer_key int NOT NULL,
    order_date_key int NOT NULL, shipping_date_key int NOT NULL, due_date_key int NOT NULL,
    order_date date NOT NULL, shipping_date date NULL, due_date date NULL,
    sales_amount decimal(19,4) NOT NULL, quantity int NOT NULL, price decimal(19,4) NOT NULL,
    correction_code nvarchar(50) NULL,
    source_line_hash binary(32) NOT NULL, loaded_at datetime2(3) NOT NULL CONSTRAINT DF_gold_fact_loaded DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_gold_fact_customer FOREIGN KEY(customer_key) REFERENCES gold.dim_customers(customer_key),
    CONSTRAINT FK_gold_fact_product FOREIGN KEY(product_key) REFERENCES gold.dim_products(product_key),
    CONSTRAINT FK_gold_fact_order_date FOREIGN KEY(order_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_gold_fact_ship_date FOREIGN KEY(shipping_date_key) REFERENCES gold.dim_date(date_key),
    CONSTRAINT FK_gold_fact_due_date FOREIGN KEY(due_date_key) REFERENCES gold.dim_date(date_key)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales') AND name=N'UX_gold_fact_source_line')
    CREATE UNIQUE INDEX UX_gold_fact_source_line ON gold.fact_sales(source_line_hash);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales') AND name=N'UX_gold_fact_grain')
    CREATE UNIQUE INDEX UX_gold_fact_grain ON gold.fact_sales(order_number,product_number,customer_id,order_date);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales') AND name=N'IX_gold_fact_order_date')
    CREATE INDEX IX_gold_fact_order_date ON gold.fact_sales(order_date_key) INCLUDE(sales_amount,quantity,product_key,customer_key);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales') AND name=N'IX_gold_fact_product_customer')
    CREATE INDEX IX_gold_fact_product_customer ON gold.fact_sales(product_key,customer_key);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'gold.fact_sales') AND name=N'IX_gold_fact_customer')
    CREATE INDEX IX_gold_fact_customer ON gold.fact_sales(customer_key) INCLUDE(sales_amount,quantity);
GO
