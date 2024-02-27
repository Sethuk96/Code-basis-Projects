use retail_events_db;
select * from dim_campaigns;
select * from dim_products;
select * from dim_stores;
select * from fact_events;

ALTER TABLE fact_events
CHANGE COLUMN `quantity_sold(before_promo)` `quantity_sold_before_promo` INT,
CHANGE COLUMN `quantity_sold(after_promo)` `quantity_sold_after_promo` INT;
-- ----------------------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;
SET sql_safe_updates = 1;
-- ------------------------------------------------------------------------
Update fact_events
set quantity_sold_after_promo= quantity_sold_after_promo * 2 
where promo_type="BOGOF";
-- ----------------------------------------------------------------------------------------------------------

ALTER TABLE fact_events ADD COLUMN promo_price DECIMAL(10,0);

UPDATE fact_events AS fe
JOIN (
    SELECT 
        event_id,
        CASE 
            WHEN promo_type = '25% OFF' THEN base_price * (1-0.25)
            WHEN promo_type = '33% OFF' THEN base_price * (1-0.33)
            WHEN promo_type = '50% OFF' THEN base_price * (1 - 0.50)
            WHEN promo_type = '500 Cashback' THEN base_price - 500
            WHEN promo_type = 'BOGOF' THEN base_price * 0.5
        END AS promo_price
    FROM 
        fact_events
) AS sub ON fe.event_id = sub.event_id
SET 
    fe.promo_price = sub.promo_price;
select * from fact_events;
-- --------------------------------------------------------------------------------------------------------------
/* 1) Provide the list of products with base price graeter than 500 and that are featured in promo type 
BOGOF this information help us identify high value products that are currently being high discounted which
can be evaluating for our pricing andf promotion strategies */
select dp.product_name,
fe.base_price,
dp.product_code 
from dim_products dp inner join fact_events fe 
on dp.product_code=fe.product_code 
where fe.promo_type='BOGOF' and 
fe.base_price>500 group by dp.product_name,
dp.product_code,fe.base_price;
-- ----------------------------------------------------------------------------------------------------------------
/*2 Generate the report that provides an overview of the number of stores in each city this result will be 
sorted in descending order of stores count allowing us to identify the city with highest store presence that 
report include two essential fields city and store count which will assist in optimizing our retail operations */
select city,count(city) as Total_store from dim_stores group by city order by count(city) desc;
-- -----------------------------------------------------------------------------------------------------------------
/* 3) Generate a report that display each campaign along with the total revenue generated before and after the campaign?
The report includes three key fields campaign_name,total_revenue(before_promotion),total_revenue(after_promotion)
This report should help in evaluating the financial impact our promotion campaigns */

 WITH total_sum AS (
    SELECT
        dc.campaign_name,
        FORMAT(SUM(fe.base_price * fe.quantity_sold_before_promo) / 1000000, 2) AS Total_Revenue_before_promotion,
        FORMAT(SUM(fe.promo_price * fe.quantity_sold_after_promo) / 1000000, 2) AS Total_Revenue_after_promotion
    FROM
        fact_events fe
    INNER JOIN
        dim_campaigns dc ON fe.campaign_id = dc.campaign_id
    GROUP BY
        dc.campaign_name
)
SELECT
    campaign_name,
    concat(Total_Revenue_before_promotion,' M') As Total_Revenue_before_promotion_Millions,
    concat(Total_Revenue_after_promotion,' M') as Total_Revenue_after_promotion_Millions
FROM
    total_sum;

/* 4) Produce a report that calculates the Incremental sold unit (ISU) for each category during the diwali campaign 
Additionally provide ranking for the category based ISU The report include three key field category,ISU%, and Rank 
This Information will assit in assessing the category wise success and impact of the diwali campaign on 
incremental sales */ 


WITH report AS (
    SELECT
        dp.category,
        sum(fe.quantity_sold_after_promo) as Total_quantity_sold_After_promo, 
        sum(fe.quantity_sold_before_promo) as Total_quantity_sold_before_promo
    FROM
        dim_products dp
        INNER JOIN fact_events fe ON dp.product_code = fe.product_code
    WHERE
        fe. campaign_id = 'CAMP_DIW_01' 
    GROUP BY
        dp.category
),
report_2 as (
	select category,Total_quantity_sold_before_promo,Total_quantity_sold_after_promo,
    ((Total_quantity_sold_After_promo - Total_quantity_sold_before_promo)/Total_quantity_sold_before_promo)*100  
    as ISU from report),
ranked_report AS (
    SELECT
        category,
        CONCAT(FORMAT(ISU, 2), '%') AS ISU_Percentage,
        RANK() OVER (ORDER BY ISU DESC) AS category_Rank
    FROM
        report_2
)
SELECT
    category,
    ISU_Percentage,
    category_Rank
FROM
    ranked_report;

-- ---------------------------------------------------------------------------------------------------------------
/* 5) Create report featurin g the top 5 products ranked by incremental revenue (IR%) across the all campaign
The report will provide essentail information including product name,category,IR%,This analysis will help 
identify the most sucessful product interm of incremental revenue 
across our campaign assisting in product optimization */

	
    with report_1 as (
    select 
        dp.product_code,
        dp.product_name,
        sum((fe.base_price * fe.quantity_sold_before_promo)) as Total_revenue_bp,
        sum((fe.promo_price * fe.quantity_sold_after_promo)) as Total_revenue_ap
    from 
        fact_events fe
    inner join 
        dim_products dp on fe.product_code = dp.product_code 
    group by  
        product_code,
        dp.product_name
),

report_2 as (
    select 
        product_code,
        product_name,
        ((Total_revenue_ap - Total_revenue_bp) / Total_revenue_bp) * 100 as IR 
    from 
        report_1
    group by 
        product_code,
        product_name
)
select 
    product_name,category,
CONCAT(FORMAT(IR, 2), '%') AS IR_percentage
from 
    report_2 order by IR desc limit 5;
    
    


    
   

