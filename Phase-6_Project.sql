SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation;

SELECT
    SUM(customer_id IS NULL) AS null_customer_id,
    SUM(customer_zip_code IS NULL) AS null_zip,
    SUM(gender IS NULL) AS null_gender,
    SUM(age_group IS NULL) AS null_age_group,
    SUM(customer_segment IS NULL) AS null_segment
FROM customers;

SELECT
    SUM(order_id IS NULL) AS null_order_id,
    SUM(customer_id IS NULL) AS null_customer_id,
    SUM(order_status IS NULL) AS null_status,
    SUM(order_purchase_timestamp IS NULL) AS null_purchase_date
FROM orders;

SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

SELECT payment_type, COUNT(*) AS orders
FROM orders
GROUP BY payment_type
ORDER BY orders DESC;


USE my_project;

DROP VIEW IF EXISTS vw_master;

CREATE VIEW vw_master AS

WITH ranked_reviews AS
(
    SELECT
        review_id,
        order_id,
        review_score,
        review_comment_message,
        review_date,

        ROW_NUMBER() OVER
        (
            PARTITION BY order_id
            ORDER BY review_date, review_id
        ) AS rn

    FROM order_reviews
)

SELECT

    /* ================= ORDERS ================= */

    o.order_id,
    o.customer_id,
    o.order_status,
    o.payment_type,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_shipping_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    /* IMPORTANT: actual column names in Orders */
    o.`Delivery Delay` AS delivery_delay,
    o.`Delivery_Status` AS delivery_status,


    /* ================= CUSTOMERS ================= */

    c.customer_zip_code,
    c.gender,
    c.age_group,
    c.customer_segment,


    /* ================= ORDER ITEMS ================= */

    oi.order_item_id,
    oi.quantity,
    oi.product_id,
    oi.unit_price,
    oi.`discount(%)` AS discount_pct,
    oi.shipping_cost,
    oi.outlier,

    oi.`Gross Amount` AS gross_amount,
    oi.`Discount Amount` AS discount_amount,
    oi.`Net Product Amount` AS net_product_amount,
    oi.`Total Cost Including Shipping`
        AS total_cost_including_shipping,


    /* ================= PRODUCTS ================= */

    p.Category_name AS category_name,
    p.sub_category_name,
    p.product_weight_g,
    p.brand,
    p.cost_price,
    p.selling_price,
    p.stock_availability,
    p.Profit AS profit,
    p.`Profit Margin` AS profit_margin,


    /* ================= REVIEWS ================= */

    r.review_id,
    r.review_score,
    r.review_comment_message,
    r.review_date,


    /* ================= DATE FEATURES ================= */

    YEAR(o.order_purchase_timestamp) AS purchase_year,

    MONTH(o.order_purchase_timestamp) AS purchase_month,

    MONTHNAME(o.order_purchase_timestamp)
        AS purchase_month_name,

    DAYNAME(o.order_purchase_timestamp)
        AS purchase_day,

    QUARTER(o.order_purchase_timestamp)
        AS purchase_quarter


FROM orders AS o

LEFT JOIN customers AS c
    ON o.customer_id = c.customer_id

LEFT JOIN order_items AS oi
    ON o.order_id = oi.order_id

LEFT JOIN products AS p
    ON oi.product_id = p.product_id

LEFT JOIN ranked_reviews AS r
    ON o.order_id = r.order_id
    AND r.rn = 1;


-- Q1. How is overall sales revenue changing over time?

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS sales_month,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY sales_month;


-- Q2. Which product categories generate the highest sales?


SELECT
    category_name,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY category_name
ORDER BY net_sales DESC
LIMIT 15;

-- Q3. Which categories generate the highest profit?

SELECT
    category_name,
    ROUND(SUM(profit), 2) AS total_profit
FROM vw_master
GROUP BY category_name
ORDER BY total_profit DESC
LIMIT 15;

-- Q4. Which subcategories perform best?

SELECT
    sub_category_name,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY sub_category_name
ORDER BY net_sales DESC
LIMIT 15;

-- Q5. Which customer segments generate the most revenue?

SELECT
    customer_segment,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY customer_segment
ORDER BY net_sales DESC;

-- Q6. How many customers are New, Returning and Loyal?

SELECT
    customer_segment,
    COUNT(DISTINCT customer_id) AS customers
FROM customers
GROUP BY customer_segment
ORDER BY customers DESC;

-- Q7. What is the average order value?

WITH order_values AS (
    SELECT
        order_id,
        SUM(net_product_amount) AS order_value
    FROM vw_master
    GROUP BY order_id
)
SELECT
    ROUND(AVG(order_value), 2) AS average_order_value,
    ROUND(MIN(order_value), 2) AS minimum_order_value,
    ROUND(MAX(order_value), 2) AS maximum_order_value,
    ROUND(STDDEV_POP(order_value), 2) AS order_value_stddev
FROM order_values;

-- Q8. Which payment methods are most commonly used?

SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(
        COUNT(DISTINCT order_id) * 100.0 /
        (SELECT COUNT(DISTINCT order_id) FROM orders), 2
    ) AS order_share_pct
FROM orders
GROUP BY payment_type
ORDER BY order_count DESC;

-- Q9. What is the cancellation rate?

SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END)
        AS cancelled_orders,
    ROUND(
        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS cancellation_rate_pct
FROM orders;

-- Q10. Which product categories have the highest cancellation rate?
-- Use HAVING to avoid unstable rates from tiny categories.
-- The report's highest observed category was security_and_services,
-- based on only six orders.

SELECT
    category_name,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT CASE
        WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN order_status = 'cancelled' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS cancellation_rate_pct
FROM vw_master
GROUP BY category_name
HAVING COUNT(DISTINCT order_id) >= 5
ORDER BY cancellation_rate_pct DESC
LIMIT 15;

-- Q11. Which categories have the highest return rate?

SELECT
    category_name,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT CASE
        WHEN order_status = 'returned' THEN order_id END) AS returned_orders,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN order_status = 'returned' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS return_rate_pct
FROM vw_master
GROUP BY category_name
HAVING COUNT(DISTINCT order_id) >= 5
ORDER BY return_rate_pct DESC
LIMIT 15;

-- Q12. Does delivery delay affect customer satisfaction?
-- Pearson correlation between delivery delay and review score.

SELECT
    COUNT(*) AS observations,
    ROUND(
        (
            COUNT(*) * SUM(delivery_delay * review_score)
            - SUM(delivery_delay) * SUM(review_score)
        )
        /
        NULLIF(
            SQRT(
                (
                    COUNT(*) * SUM(delivery_delay * delivery_delay)
                    - POW(SUM(delivery_delay), 2)
                )
                *
                (
                    COUNT(*) * SUM(review_score * review_score)
                    - POW(SUM(review_score), 2)
                )
            ), 0
        ),
        6
    ) AS delivery_delay_review_correlation
FROM vw_master
WHERE delivery_delay IS NOT NULL
  AND review_score IS NOT NULL;

-- Compare average review score by delivery-delay bucket.
SELECT
    CASE
        WHEN delivery_delay < 0 THEN 'Early'
        WHEN delivery_delay = 0 THEN 'On Time'
        ELSE 'Late'
    END AS delivery_bucket,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM vw_master
WHERE review_score IS NOT NULL
GROUP BY
    CASE
        WHEN delivery_delay < 0 THEN 'Early'
        WHEN delivery_delay = 0 THEN 'On Time'
        ELSE 'Late'
    END
ORDER BY avg_review_score DESC;

-- ============================================================
-- Q13. What is the relationship between review score and order status?
-- ============================================================

SELECT
    order_status,
    review_score,
    COUNT(*) AS record_count
FROM vw_master
WHERE review_score IS NOT NULL
GROUP BY order_status, review_score
ORDER BY order_status, review_score;

-- Normalised version for better comparison:
SELECT
    order_status,
    review_score,
    COUNT(*) AS record_count,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (PARTITION BY order_status), 2
    ) AS pct_within_status
FROM vw_master
WHERE review_score IS NOT NULL
GROUP BY order_status, review_score
ORDER BY order_status, review_score;

-- Q14. Which customer segments are most likely to return?

SELECT
    customer_segment,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT CASE
        WHEN order_status = 'returned' THEN order_id END) AS returned_orders,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN order_status = 'returned' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS return_rate_pct
FROM vw_master
GROUP BY customer_segment
ORDER BY return_rate_pct DESC;

-- Q15. Which products contribute the most revenue?

SELECT
    product_id,
    category_name,
    sub_category_name,
    ROUND(SUM(net_product_amount), 2) AS revenue,
    SUM(quantity) AS quantity,
    ROUND(SUM(profit), 2) AS profit
FROM vw_master
GROUP BY product_id, category_name, sub_category_name
ORDER BY revenue DESC
LIMIT 20;

-- Q16. Customer Retention Analysis

SELECT
    c.customer_id,
    COUNT(DISTINCT o.order_id) AS total_orders,
    MIN(o.order_purchase_timestamp) AS first_purchase,
    MAX(o.order_purchase_timestamp) AS last_purchase,
    DATEDIFF(
        MAX(o.order_purchase_timestamp),
        MIN(o.order_purchase_timestamp)
    ) AS days_between_purchase
FROM customers c
LEFT JOIN orders o
    ON c.customer_id = o.customer_id
GROUP BY c.customer_id
ORDER BY total_orders DESC;

-- Q17. Repeat Customer Analysis

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(total_orders > 1) AS repeat_customers,
    SUM(total_orders = 1) AS one_time_customers,
    ROUND(
        SUM(total_orders > 1) * 100.0 / COUNT(*), 2
    ) AS repeat_customer_rate_pct
FROM customer_orders;

-- Q18. Customer Purchase Frequency

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
)
SELECT
    total_orders AS number_of_orders,
    COUNT(*) AS number_of_customers
FROM customer_orders
GROUP BY total_orders
ORDER BY total_orders;

-- Q19. Customer Segment vs Purchase Frequency

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
)
SELECT
    c.customer_segment,
    ROUND(AVG(co.total_orders), 3) AS average_orders_per_customer,
    COUNT(*) AS customers
FROM customer_orders co
JOIN customers c
    ON co.customer_id = c.customer_id
GROUP BY c.customer_segment
ORDER BY average_orders_per_customer DESC;

-- Q20. Age Group Analysis

SELECT
    age_group,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY age_group
ORDER BY net_sales DESC;

-- Q21. Gender Analysis

SELECT
    gender,
    ROUND(SUM(net_product_amount), 2) AS net_sales
FROM vw_master
GROUP BY gender
ORDER BY net_sales DESC;

-- Q22. Discount vs Sales Analysis

SELECT
    ROUND(discount_pct, 0) AS discount_band,
    COUNT(*) AS line_items,
    ROUND(AVG(net_product_amount), 2) AS avg_net_sales,
    ROUND(SUM(net_product_amount), 2) AS total_net_sales
FROM vw_master
WHERE discount_pct IS NOT NULL
GROUP BY ROUND(discount_pct, 0)
ORDER BY discount_band;

-- Pearson correlation: discount % vs net product amount.
SELECT
    COUNT(*) AS observations,
    ROUND(
        (
            COUNT(*) * SUM(discount_pct * net_product_amount)
            - SUM(discount_pct) * SUM(net_product_amount)
        )
        /
        NULLIF(
            SQRT(
                (
                    COUNT(*) * SUM(discount_pct * discount_pct)
                    - POW(SUM(discount_pct), 2)
                )
                *
                (
                    COUNT(*) * SUM(net_product_amount * net_product_amount)
                    - POW(SUM(net_product_amount), 2)
                )
            ), 0
        ),
        6
    ) AS discount_sales_correlation
FROM vw_master
WHERE discount_pct IS NOT NULL
  AND net_product_amount IS NOT NULL;

-- Q23. Profit Margin Analysis

SELECT
    category_name,
    ROUND(SUM(net_product_amount), 2) AS revenue,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(
        SUM(profit) * 100.0 / NULLIF(SUM(net_product_amount), 0), 2
    ) AS profit_margin_pct
FROM vw_master
GROUP BY category_name
ORDER BY profit_margin_pct DESC
LIMIT 15;

-- Q24. Delivery Status Analysis

SELECT
    delivery_status,
    COUNT(DISTINCT order_id) AS orders
FROM orders
GROUP BY delivery_status
ORDER BY orders DESC;

-- Management-friendly delivery buckets.
SELECT
    CASE
        WHEN `Delivery Delay` < 0 THEN 'Early'
        WHEN `Delivery Delay` = 0 THEN 'On Time'
        WHEN `Delivery Delay` > 0 THEN 'Late'
        ELSE 'Unknown'
    END AS delivery_bucket,

    COUNT(DISTINCT order_id) AS orders

FROM orders

GROUP BY
    CASE
        WHEN `Delivery Delay` < 0 THEN 'Early'
        WHEN `Delivery Delay` = 0 THEN 'On Time'
        WHEN `Delivery Delay` > 0 THEN 'Late'
        ELSE 'Unknown'
    END

ORDER BY orders DESC;

-- Q25. Monthly Order Trend

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT order_id) AS order_count
FROM orders
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Q26. Review Score Distribution

SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM order_reviews),
        2
    ) AS review_share_pct
FROM order_reviews
WHERE review_score BETWEEN 1 AND 5
GROUP BY review_score
ORDER BY review_score;

-- Q27. Average Review Score by Category

SELECT
    category_name,
    COUNT(DISTINCT order_id) AS reviewed_orders,
    ROUND(AVG(review_score), 2) AS average_review_score
FROM vw_master
WHERE review_score IS NOT NULL
GROUP BY category_name
HAVING COUNT(DISTINCT order_id) >= 5
ORDER BY average_review_score DESC
LIMIT 15;

-- Q28. Correlation Analysis
-- MySQL does not provide a convenient full correlation matrix in
-- the same form as pandas.DataFrame.corr(). The following produces
-- the key business correlations used in the project.

SELECT 'Discount vs Net Sales' AS relationship,
       ROUND(
           (
               COUNT(*) * SUM(discount_pct * net_product_amount)
               - SUM(discount_pct) * SUM(net_product_amount)
           )
           /
           NULLIF(
               SQRT(
                   (COUNT(*) * SUM(discount_pct * discount_pct)
                    - POW(SUM(discount_pct), 2))
                   *
                   (COUNT(*) * SUM(net_product_amount * net_product_amount)
                    - POW(SUM(net_product_amount), 2))
               ), 0
           ), 6
       ) AS correlation
FROM vw_master
WHERE discount_pct IS NOT NULL
  AND net_product_amount IS NOT NULL

UNION ALL

SELECT 'Delivery Delay vs Review Score',
       ROUND(
           (
               COUNT(*) * SUM(delivery_delay * review_score)
               - SUM(delivery_delay) * SUM(review_score)
           )
           /
           NULLIF(
               SQRT(
                   (COUNT(*) * SUM(delivery_delay * delivery_delay)
                    - POW(SUM(delivery_delay), 2))
                   *
                   (COUNT(*) * SUM(review_score * review_score)
                    - POW(SUM(review_score), 2))
               ), 0
           ), 6
       )
FROM vw_master
WHERE delivery_delay IS NOT NULL
  AND review_score IS NOT NULL;

-- Q29. Key KPI Calculation

WITH order_values AS (
    SELECT
        order_id,
        SUM(net_product_amount) AS order_value
    FROM vw_master
    GROUP BY order_id
),
customer_order_counts AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
)
SELECT
    (SELECT COUNT(DISTINCT customer_id) FROM customers) AS total_customers,
    (SELECT COUNT(DISTINCT order_id) FROM orders) AS total_orders,
    (SELECT ROUND(SUM(net_product_amount), 2) FROM vw_master) AS total_revenue,
    (SELECT ROUND(SUM(profit), 2) FROM vw_master) AS total_profit,
    (SELECT ROUND(AVG(order_value), 2) FROM order_values) AS average_order_value,
    (
        SELECT ROUND(
            COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END)
            * 100.0 / COUNT(DISTINCT order_id), 2
        )
        FROM orders
    ) AS cancellation_rate_pct,
    (
        SELECT ROUND(
            COUNT(DISTINCT CASE WHEN order_status = 'returned' THEN order_id END)
            * 100.0 / COUNT(DISTINCT order_id), 2
        )
        FROM orders
    ) AS return_rate_pct,
    (SELECT ROUND(AVG(review_score), 2) FROM order_reviews) AS average_review_score,
    (
        SELECT ROUND(
            SUM(total_orders > 1) * 100.0 / COUNT(*), 2
        )
        FROM customer_order_counts
    ) AS repeat_customer_rate_pct;

-- Q30. Automatic Top Business Insights

SELECT
    (SELECT category_name
     FROM (
         SELECT category_name, SUM(net_product_amount) AS sales
         FROM vw_master
         GROUP BY category_name
         ORDER BY sales DESC
         LIMIT 1
     ) x) AS top_sales_category,

    (SELECT category_name
     FROM (
         SELECT category_name, SUM(profit) AS total_profit
         FROM vw_master
         GROUP BY category_name
         ORDER BY total_profit DESC
         LIMIT 1
     ) y) AS top_profit_category,

    (SELECT customer_segment
     FROM (
         SELECT customer_segment, SUM(net_product_amount) AS sales
         FROM vw_master
         GROUP BY customer_segment
         ORDER BY sales DESC
         LIMIT 1
     ) z) AS top_revenue_customer_segment,

    (SELECT ROUND(
        COUNT(DISTINCT CASE WHEN order_status='cancelled' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2)
     FROM orders) AS cancellation_rate_pct,

    (SELECT ROUND(
        COUNT(DISTINCT CASE WHEN order_status='returned' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2)
     FROM orders) AS return_rate_pct,

    (SELECT ROUND(AVG(review_score),2) FROM order_reviews) AS average_review_score;

-- Q31. Final EDA Dashboard Data
-- These result sets can be connected to Power BI/Excel later,
-- but the analysis itself is performed completely in MySQL.

-- Dashboard 1: Customer Segments
SELECT customer_segment, COUNT(*) AS customers
FROM customers
GROUP BY customer_segment
ORDER BY customers DESC;

-- Dashboard 2: Order Status
SELECT order_status, COUNT(DISTINCT order_id) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- Dashboard 3: Review Scores
SELECT review_score, COUNT(*) AS reviews
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- Dashboard 4: Top 10 Categories
SELECT
    category_name,
    ROUND(SUM(net_product_amount),2) AS net_sales
FROM vw_master
GROUP BY category_name
ORDER BY net_sales DESC
LIMIT 10;

-- Dashboard 5: Monthly Sales
SELECT
    DATE_FORMAT(order_purchase_timestamp,'%Y-%m') AS month,
    ROUND(SUM(net_product_amount),2) AS net_sales
FROM vw_master
GROUP BY DATE_FORMAT(order_purchase_timestamp,'%Y-%m')
ORDER BY month;

-- Dashboard 6: One-Time vs Repeat Customers
WITH customer_orders AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN total_orders > 1 THEN 'Repeat Customer'
        ELSE 'One-Time Customer'
    END AS customer_type,
    COUNT(*) AS customers
FROM customer_orders
GROUP BY
    CASE
        WHEN total_orders > 1 THEN 'Repeat Customer'
        ELSE 'One-Time Customer'
    END;


-- BONUS: PROJECT-SPECIFIC CONVERSION PROXY
-- The dataset has no sessions/add-to-cart events, so true funnel
-- conversion cannot be calculated. Cancellation/completion is used
-- only as an operational conversion proxy.

SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN order_status='delivered' THEN order_id END)
        AS delivered_orders,
    ROUND(
        COUNT(DISTINCT CASE WHEN order_status='delivered' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS completed_order_rate_pct,
    COUNT(DISTINCT CASE WHEN order_status='cancelled' THEN order_id END)
        AS cancelled_orders,
    ROUND(
        COUNT(DISTINCT CASE WHEN order_status='cancelled' THEN order_id END)
        * 100.0 / COUNT(DISTINCT order_id), 2
    ) AS cancellation_rate_pct
FROM orders;

-- ============================================================
-- BONUS: RETENTION ACTION TABLE
-- Identify one-time customers as the primary second-purchase
-- conversion opportunity.


WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        MIN(order_purchase_timestamp) AS first_purchase,
        MAX(order_purchase_timestamp) AS last_purchase
    FROM orders
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_segment,
    c.age_group,
    c.gender,
    co.total_orders,
    co.first_purchase,
    co.last_purchase,
    CASE
        WHEN co.total_orders = 1 THEN 'TARGET_FOR_2ND_PURCHASE'
        WHEN co.total_orders > 1 THEN 'REPEAT_CUSTOMER'
        ELSE 'NO_ORDER'
    END AS retention_action
FROM customers c
LEFT JOIN customer_orders co
    ON c.customer_id = co.customer_id
ORDER BY retention_action, co.last_purchase DESC;
