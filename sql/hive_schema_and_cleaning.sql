-- 切换到你的数据库
USE mydb;

-- 1. 客户表 (customers)
DROP TABLE IF EXISTS customers_raw;
CREATE EXTERNAL TABLE customers_raw (
    customer_id STRING,
    customer_unique_id STRING,
    customer_zip_code_prefix STRING,
    customer_city STRING,
    customer_state STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1", "serialization.null.format"="");

-- 2. 地理位置表 (geolocation) - 注意：这个文件较大，可能需要特殊处理
DROP TABLE IF EXISTS geolocation_raw;
CREATE EXTERNAL TABLE geolocation_raw (
    geolocation_zip_code_prefix STRING,
    geolocation_lat DECIMAL(10,8),
    geolocation_lng DECIMAL(11,8),
    geolocation_city STRING,
    geolocation_state STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 3. 订单商品表 (order_items)
DROP TABLE IF EXISTS order_items_raw;
CREATE EXTERNAL TABLE order_items_raw (
    order_id STRING,
    order_item_id INT,
    product_id STRING,
    seller_id STRING,
    shipping_limit_date STRING,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2)
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 4. 订单支付表 (order_payments)
DROP TABLE IF EXISTS order_payments_raw;
CREATE EXTERNAL TABLE order_payments_raw (
    order_id STRING,
    payment_sequential INT,
    payment_type STRING,
    payment_installments INT,
    payment_value DECIMAL(10,2)
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 5. 订单评论表 (order_reviews) - 注意：review_comment_message可能包含换行符
DROP TABLE IF EXISTS order_reviews_raw;
CREATE EXTERNAL TABLE order_reviews_raw (
    review_id STRING,
    order_id STRING,
    review_score INT,
    review_comment_title STRING,
    review_comment_message STRING,
    review_creation_date STRING,
    review_answer_timestamp STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 6. 订单表 (orders) - 主表
DROP TABLE IF EXISTS orders_raw;
CREATE EXTERNAL TABLE orders_raw (
    order_id STRING,
    customer_id STRING,
    order_status STRING,
    order_purchase_timestamp STRING,
    order_approved_at STRING,
    order_delivered_carrier_date STRING,
    order_delivered_customer_date STRING,
    order_estimated_delivery_date STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 7. 产品表 (products)
DROP TABLE IF EXISTS products_raw;
CREATE EXTERNAL TABLE products_raw (
    product_id STRING,
    product_category_name STRING,
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 8. 卖家表 (sellers)
DROP TABLE IF EXISTS sellers_raw;
CREATE EXTERNAL TABLE sellers_raw (
    seller_id STRING,
    seller_zip_code_prefix STRING,
    seller_city STRING,
    seller_state STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 9. 产品类别翻译表 (product_category_translation)
DROP TABLE IF EXISTS product_category_translation_raw;
CREATE EXTERNAL TABLE product_category_translation_raw (
    product_category_name STRING,
    product_category_name_english STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/brazilian_ecommerce/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- 客户表清洗
DROP TABLE IF EXISTS customers_clean;
CREATE TABLE customers_clean AS
SELECT 
    customer_id,
    customer_unique_id,
    -- 清理邮编前缀：去除空格，确保格式正确
    TRIM(customer_zip_code_prefix) AS customer_zip_code_prefix,
    -- 清理城市名：去除首尾空格，首字母大写
    INITCAP(TRIM(customer_city)) AS customer_city,
    -- 州名标准化：转为大写
    UPPER(TRIM(customer_state)) AS customer_state,
    -- 标记数据质量
    CASE 
        WHEN customer_id IS NULL OR customer_id = '' THEN 0
        ELSE 1
    END AS is_valid_customer_id,
    CASE 
        WHEN customer_unique_id IS NULL OR customer_unique_id = '' THEN 0
        ELSE 1
    END AS is_valid_unique_id
FROM customers_raw
-- 去除完全重复的行
GROUP BY 
    customer_id, customer_unique_id, customer_zip_code_prefix, 
    customer_city, customer_state;

-- 验证客户表
SELECT 
    COUNT(*) AS total_customers,
    COUNT(DISTINCT customer_id) AS unique_customers,
    COUNT(DISTINCT customer_unique_id) AS unique_customer_entities,
    SUM(CASE WHEN is_valid_customer_id = 0 THEN 1 ELSE 0 END) AS invalid_customer_ids
FROM customers_clean;

-- 地理位置表清洗（去重，计算中心点）
DROP TABLE IF EXISTS geolocation_clean;
CREATE TABLE geolocation_clean AS
SELECT 
    geolocation_zip_code_prefix,
    -- 对同一邮编前缀的地理坐标取平均值（中心点）
    ROUND(AVG(CAST(geolocation_lat AS DECIMAL(10,8))), 8) AS avg_latitude,
    ROUND(AVG(CAST(geolocation_lng AS DECIMAL(11,8))), 8) AS avg_longitude,
    -- 使用最常见的城市和州
    MAX(geolocation_city) AS geolocation_city,  -- 假设同一邮编前缀主要属于一个城市
    MAX(geolocation_state) AS geolocation_state,
    -- 统计数据点数量
    COUNT(*) AS location_points_count,
    -- 计算坐标变化范围（标准差）
    ROUND(STDDEV(CAST(geolocation_lat AS DOUBLE)), 8) AS lat_stddev,
    ROUND(STDDEV(CAST(geolocation_lng AS DOUBLE)), 8) AS lng_stddev
FROM geolocation_raw
WHERE geolocation_lat IS NOT NULL 
  AND geolocation_lng IS NOT NULL
  AND geolocation_zip_code_prefix IS NOT NULL
  AND geolocation_zip_code_prefix != ''
GROUP BY geolocation_zip_code_prefix;

-- 为地理位置表创建索引（视图优化查询）
DROP VIEW IF EXISTS geolocation_by_state;
CREATE VIEW geolocation_by_state AS
SELECT 
    geolocation_state,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS zip_code_count,
    COUNT(DISTINCT geolocation_city) AS city_count,
    ROUND(AVG(avg_latitude), 6) AS state_avg_lat,
    ROUND(AVG(avg_longitude), 6) AS state_avg_lng
FROM geolocation_clean
GROUP BY geolocation_state;
mestamp) = 1;

-- 创建清洗后的订单表 (兼容性写法)
DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean AS
SELECT 
    order_id,
    customer_id,
    order_status,
    purchase_timestamp,
    approved_timestamp,
    delivered_carrier_timestamp,
    delivered_customer_timestamp,
    estimated_delivery_timestamp,
    actual_delivery_days,
    order_status_category,
    is_valid_order_id,
    has_purchase_timestamp
FROM (
    -- 内层子查询：为每一行计算行号
    SELECT 
        order_id,
        customer_id,
        -- 订单状态标准化
        UPPER(TRIM(order_status)) AS order_status,
        -- 时间戳转换（处理空值）
        CASE 
            WHEN order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_purchase_timestamp, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS purchase_timestamp,
        
        CASE 
            WHEN order_approved_at IS NOT NULL AND order_approved_at != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_approved_at, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS approved_timestamp,
        
        CASE 
            WHEN order_delivered_carrier_date IS NOT NULL AND order_delivered_carrier_date != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_delivered_carrier_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS delivered_carrier_timestamp,
        
        CASE 
            WHEN order_delivered_customer_date IS NOT NULL AND order_delivered_customer_date != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_delivered_customer_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS delivered_customer_timestamp,
        
        CASE 
            WHEN order_estimated_delivery_date IS NOT NULL AND order_estimated_delivery_date != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_estimated_delivery_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS estimated_delivery_timestamp,
        
        -- 计算衍生字段 (优化：直接使用上面转换后的字段)
        CASE 
            WHEN order_delivered_customer_date IS NOT NULL AND order_delivered_customer_date != ''
                 AND order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp != ''
            THEN DATEDIFF(
                CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_delivered_customer_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP),
                CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(order_purchase_timestamp, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            )
            ELSE NULL
        END AS actual_delivery_days,
        
        -- 标记订单状态类别
        CASE 
            WHEN UPPER(TRIM(order_status)) IN ('DELIVERED', 'SHIPPED') THEN 'COMPLETED'
            WHEN UPPER(TRIM(order_status)) IN ('CANCELED', 'UNAVAILABLE') THEN 'CANCELLED'
            WHEN UPPER(TRIM(order_status)) IN ('PROCESSING', 'APPROVED') THEN 'IN_PROGRESS'
            ELSE 'OTHER'
        END AS order_status_category,
        
        -- 数据质量标记
        CASE 
            WHEN order_id IS NULL OR order_id = '' THEN 0
            ELSE 1
        END AS is_valid_order_id,
        
        CASE 
            WHEN order_purchase_timestamp IS NULL OR order_purchase_timestamp = '' THEN 0
            ELSE 1
        END AS has_purchase_timestamp,
        -- 关键：为每个order_id分区，按购买时间排序，生成行号
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_purchase_timestamp) AS rn
    FROM orders_raw
    WHERE order_id IS NOT NULL AND order_id != ''
) ranked_orders
-- 外层查询：只取行号为1的记录，实现去重
WHERE rn = 1;
DROP VIEW IF EXISTS orders_daily_stats;
CREATE VIEW orders_daily_stats AS
SELECT 
    DATE(purchase_timestamp) AS order_date,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'DELIVERED' THEN 1 ELSE 0 END) AS delivered_orders,
    SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END) AS canceled_orders,
    AVG(actual_delivery_days) AS avg_delivery_days,
    COUNT(DISTINCT customer_id) AS unique_customers
FROM orders_clean
WHERE purchase_timestamp IS NOT NULL
GROUP BY DATE(purchase_timestamp);

-- 订单商品表清洗
DROP TABLE IF EXISTS order_items_clean;
CREATE TABLE order_items_clean AS
SELECT 
    order_id,
    order_item_id,
    product_id,
    seller_id,
    -- 时间戳转换
    CASE 
        WHEN shipping_limit_date IS NOT NULL AND shipping_limit_date != ''
        THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(shipping_limit_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
        ELSE NULL
    END AS shipping_limit_timestamp,
    -- 价格处理（确保非负）
    GREATEST(COALESCE(price, 0), 0) AS price,
    GREATEST(COALESCE(freight_value, 0), 0) AS freight_value,
    -- 计算总价
    GREATEST(COALESCE(price, 0), 0) + GREATEST(COALESCE(freight_value, 0), 0) AS total_price,
    -- 标记高价商品
    CASE 
        WHEN COALESCE(price, 0) > 1000 THEN 'PREMIUM'
        WHEN COALESCE(price, 0) > 100 THEN 'MID_RANGE'
        ELSE 'ECONOMY'
    END AS price_category,
    -- 数据质量标记
    CASE 
        WHEN order_id IS NULL OR order_id = '' OR product_id IS NULL OR product_id = '' THEN 0
        ELSE 1
    END AS is_valid_record
FROM order_items_raw
WHERE order_id IS NOT NULL AND order_id != ''
  AND order_item_id IS NOT NULL;

-- 创建订单商品聚合视图
DROP VIEW IF EXISTS order_items_summary;
CREATE VIEW order_items_summary AS
SELECT 
    order_id,
    COUNT(*) AS item_count,
    SUM(price) AS total_item_price,
    SUM(freight_value) AS total_freight,
    SUM(total_price) AS order_total,
    MAX(price) AS max_item_price,
    MIN(price) AS min_item_price,
    AVG(price) AS avg_item_price
FROM order_items_clean
WHERE is_valid_record = 1
GROUP BY order_id;

-- 订单支付表清洗
DROP TABLE IF EXISTS order_payments_clean;
CREATE TABLE order_payments_clean AS
SELECT 
    order_id,
    payment_sequential,
    -- 支付类型标准化
    UPPER(TRIM(payment_type)) AS payment_type,
    -- 确保分期数为正整数
    GREATEST(COALESCE(payment_installments, 1), 1) AS payment_installments,
    -- 支付金额处理（确保非负）
    GREATEST(COALESCE(payment_value, 0), 0) AS payment_value,
    -- 计算每期支付金额
    CASE 
        WHEN GREATEST(COALESCE(payment_installments, 1), 1) > 0
        THEN ROUND(GREATEST(COALESCE(payment_value, 0), 0) / GREATEST(COALESCE(payment_installments, 1), 1), 2)
        ELSE GREATEST(COALESCE(payment_value, 0), 0)
    END AS installment_value,
    -- 支付方式分类
    CASE 
        WHEN UPPER(TRIM(payment_type)) LIKE '%CREDIT%' THEN 'CREDIT_CARD'
        WHEN UPPER(TRIM(payment_type)) LIKE '%DEBIT%' THEN 'DEBIT_CARD'
        WHEN UPPER(TRIM(payment_type)) LIKE '%VOUCHER%' THEN 'VOUCHER'
        WHEN UPPER(TRIM(payment_type)) LIKE '%BOLETO%' THEN 'BANK_SLIP'
        ELSE 'OTHER'
    END AS payment_category,
    -- 标记大额支付
    CASE 
        WHEN COALESCE(payment_value, 0) > 5000 THEN 1
        ELSE 0
    END AS is_high_value_payment
FROM order_payments_raw
WHERE order_id IS NOT NULL AND order_id != ''
  AND payment_sequential IS NOT NULL;

-- 创建支付汇总视图
DROP VIEW IF EXISTS order_payments_summary;
CREATE VIEW order_payments_summary AS
SELECT 
    order_id,
    COUNT(*) AS payment_count,
    SUM(payment_value) AS total_paid,
    MAX(payment_sequential) AS max_payment_sequence,
    -- 支付方式统计
    SUM(CASE WHEN payment_category = 'CREDIT_CARD' THEN 1 ELSE 0 END) AS credit_card_payments,
    SUM(CASE WHEN payment_category = 'BANK_SLIP' THEN 1 ELSE 0 END) AS bank_slip_payments,
    SUM(CASE WHEN payment_category = 'VOUCHER' THEN 1 ELSE 0 END) AS voucher_payments,
    -- 检查支付完整性
    CASE 
        WHEN COUNT(*) > 1 THEN 'MULTIPLE_PAYMENTS'
        ELSE 'SINGLE_PAYMENT'
    END AS payment_pattern
FROM order_payments_clean
GROUP BY order_id;



-- 订单评论表清洗（处理文本评论）- 兼容性版本
DROP TABLE IF EXISTS order_reviews_clean;

CREATE TABLE order_reviews_clean AS
SELECT 
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_timestamp,
    review_answer_timestamp,
    response_time_hours,
    comment_length,
    sentiment,
    has_comment
FROM (
    -- 内层子查询：计算行号用于去重
    SELECT 
        review_id,
        order_id,
        -- 评分标准化（1-5分）
        CASE 
            WHEN review_score BETWEEN 1 AND 5 THEN review_score
            WHEN review_score > 5 THEN 5
            WHEN review_score < 1 THEN 1
            ELSE 3  -- 默认值
        END AS review_score,
        -- 清理评论标题
        TRIM(review_comment_title) AS review_comment_title,
        -- 清理评论内容（去除多余空格、换行符）
        REGEXP_REPLACE(TRIM(COALESCE(review_comment_message, '')), '\\s+', ' ') AS review_comment_message,
        -- 时间戳转换
        CASE 
            WHEN review_creation_date IS NOT NULL AND review_creation_date != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(review_creation_date, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS review_creation_timestamp,
        
        CASE 
            WHEN review_answer_timestamp IS NOT NULL AND review_answer_timestamp != ''
            THEN CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(review_answer_timestamp, 'yyyy-MM-dd HH:mm:ss')) AS TIMESTAMP)
            ELSE NULL
        END AS review_answer_timestamp,
        -- 计算回复时间（小时） - 使用转换后的时间戳计算
        CASE 
            WHEN review_creation_date IS NOT NULL AND review_creation_date != ''
                 AND review_answer_timestamp IS NOT NULL AND review_answer_timestamp != ''
            THEN ROUND(
                (UNIX_TIMESTAMP(review_answer_timestamp, 'yyyy-MM-dd HH:mm:ss') - 
                 UNIX_TIMESTAMP(review_creation_date, 'yyyy-MM-dd HH:mm:ss')) / 3600.0, 2
            )
            ELSE NULL
        END AS response_time_hours,
        -- 评论长度
        LENGTH(TRIM(COALESCE(review_comment_message, ''))) AS comment_length,
        -- 情感分类（基于评分）
        CASE 
            WHEN review_score >= 4 THEN 'POSITIVE'
            WHEN review_score = 3 THEN 'NEUTRAL'
            ELSE 'NEGATIVE'
        END AS sentiment,
        -- 检查是否有评论内容
        CASE 
            WHEN review_comment_message IS NOT NULL AND TRIM(review_comment_message) != '' THEN 1
            ELSE 0
        END AS has_comment,
        -- 关键：为每个review_id生成行号，按创建时间排序
        ROW_NUMBER() OVER (PARTITION BY review_id ORDER BY review_creation_date) AS rn
    FROM order_reviews_raw
    WHERE review_id IS NOT NULL AND review_id != ''
      AND order_id IS NOT NULL AND order_id != ''
) ranked_reviews
-- 外层过滤：只保留行号为1的记录，实现去重
WHERE rn = 1;

-- 创建评论分析视图
DROP VIEW IF EXISTS reviews_daily_stats;
CREATE VIEW reviews_daily_stats AS
SELECT 
    DATE(review_creation_timestamp) AS review_date,
    COUNT(*) AS total_reviews,
    AVG(review_score) AS avg_rating,
    SUM(CASE WHEN sentiment = 'POSITIVE' THEN 1 ELSE 0 END) AS positive_reviews,
    SUM(CASE WHEN sentiment = 'NEGATIVE' THEN 1 ELSE 0 END) AS negative_reviews,
    AVG(response_time_hours) AS avg_response_time
FROM order_reviews_clean
WHERE review_creation_timestamp IS NOT NULL
GROUP BY DATE(review_creation_timestamp);


-- 产品表清洗 - 兼容性版本
DROP TABLE IF EXISTS products_clean;

CREATE TABLE products_clean AS
SELECT 
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_kg,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    product_volume_cm3,
    product_density,
    weight_category,
    has_category,
    has_weight
FROM (
    -- 内层子查询：计算行号用于去重
    SELECT 
        product_id,
        -- 产品类别清理
        TRIM(product_category_name) AS product_category_name,
        -- 处理缺失的维度信息
        COALESCE(product_name_lenght, 0) AS product_name_length,
        COALESCE(product_description_lenght, 0) AS product_description_length,
        COALESCE(product_photos_qty, 0) AS product_photos_qty,
        -- 重量处理（克转千克）
        CASE 
            WHEN product_weight_g IS NOT NULL AND product_weight_g > 0 
            THEN ROUND(product_weight_g / 1000.0, 3)
            ELSE NULL
        END AS product_weight_kg,
        -- 尺寸处理（确保合理性）
        GREATEST(COALESCE(product_length_cm, 0), 0) AS product_length_cm,
        GREATEST(COALESCE(product_height_cm, 0), 0) AS product_height_cm,
        GREATEST(COALESCE(product_width_cm, 0), 0) AS product_width_cm,
        -- 计算体积（立方厘米）
        CASE 
            WHEN product_length_cm > 0 AND product_height_cm > 0 AND product_width_cm > 0
            THEN product_length_cm * product_height_cm * product_width_cm
            ELSE NULL
        END AS product_volume_cm3,
        -- 计算密度（g/cm³）
        CASE 
            WHEN product_weight_g > 0 AND product_length_cm > 0 
                 AND product_height_cm > 0 AND product_width_cm > 0
            THEN ROUND(product_weight_g / (product_length_cm * product_height_cm * product_width_cm), 4)
            ELSE NULL
        END AS product_density,
        -- 产品尺寸分类
        CASE 
            WHEN product_weight_g > 5000 THEN 'HEAVY'
            WHEN product_weight_g > 1000 THEN 'MEDIUM'
            WHEN product_weight_g > 0 THEN 'LIGHT'
            ELSE 'UNKNOWN'
        END AS weight_category,
        -- 数据完整性标记
        CASE 
            WHEN product_category_name IS NOT NULL AND product_category_name != '' THEN 1
            ELSE 0
        END AS has_category,
        CASE 
            WHEN product_weight_g IS NOT NULL AND product_weight_g > 0 THEN 1
            ELSE 0
        END AS has_weight,
        -- 关键：为每个product_id生成行号，按产品名称长度降序排序
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY product_name_lenght DESC) AS rn
    FROM products_raw
    WHERE product_id IS NOT NULL AND product_id != ''
) ranked_products
-- 外层过滤：只保留行号为1的记录，实现去重
WHERE rn = 1;

-- 创建产品类别统计视图
DROP VIEW IF EXISTS products_by_category;
CREATE VIEW products_by_category AS
SELECT 
    product_category_name,
    COUNT(*) AS product_count,
    ROUND(AVG(product_weight_kg), 3) AS avg_weight_kg,
    ROUND(AVG(product_volume_cm3), 0) AS avg_volume,
    ROUND(AVG(product_photos_qty), 1) AS avg_photos
FROM products_clean
WHERE product_category_name IS NOT NULL AND product_category_name != ''
GROUP BY product_category_name
ORDER BY product_count DESC;

-- 卖家表清洗
DROP TABLE IF EXISTS sellers_clean;
CREATE TABLE sellers_clean AS
SELECT 
    seller_id,
    -- 清理邮编前缀
    TRIM(seller_zip_code_prefix) AS seller_zip_code_prefix,
    -- 清理城市名
    INITCAP(TRIM(seller_city)) AS seller_city,
    -- 州名标准化
    UPPER(TRIM(seller_state)) AS seller_state,
    -- 标记活跃卖家（基于后续的订单数据）
    1 AS is_active_seller,  -- 初始标记，后续可以更新
    -- 数据质量标记
    CASE 
        WHEN seller_id IS NULL OR seller_id = '' THEN 0
        ELSE 1
    END AS is_valid_seller_id
FROM sellers_raw
WHERE seller_id IS NOT NULL AND seller_id != ''
GROUP BY seller_id, seller_zip_code_prefix, seller_city, seller_state;

-- 创建卖家地理位置视图
DROP VIEW IF EXISTS sellers_by_state;

CREATE VIEW sellers_by_state AS
SELECT 
    seller_state,
    COUNT(DISTINCT seller_id) AS seller_count,
    COUNT(DISTINCT seller_city) AS city_count,
    -- 聚合所有城市（自动去重）
    CONCAT_WS(', ', COLLECT_SET(seller_city)) AS cities_list,
    
    -- 聚合并排序
    CONCAT_WS(', ', SORT_ARRAY(COLLECT_SET(seller_city))) AS sorted_cities
FROM sellers_clean
WHERE seller_state IS NOT NULL
GROUP BY seller_state
ORDER BY seller_count DESC;


-- 产品类别翻译表清洗
DROP TABLE IF EXISTS product_category_translation_clean;
CREATE TABLE product_category_translation_clean AS
SELECT 
    -- 清理葡萄牙语类别名
    TRIM(product_category_name) AS product_category_name_original,
    -- 清理英语翻译
    INITCAP(TRIM(product_category_name_english)) AS product_category_name_english,
    -- 标记是否为标准翻译
    CASE 
        WHEN product_category_name_english IS NOT NULL 
             AND product_category_name_english != '' THEN 1
        ELSE 0
    END AS has_translation,
    -- 分类级别（基于名称中的斜杠）
    LENGTH(product_category_name) - LENGTH(REPLACE(product_category_name, '_', '')) + 1 AS category_depth
FROM product_category_translation_raw
WHERE product_category_name IS NOT NULL AND product_category_name != ''
GROUP BY product_category_name, product_category_name_english;


-- 1. 创建订单完整视图（整合所有订单相关信息）
DROP VIEW IF EXISTS orders_complete_view;
CREATE VIEW orders_complete_view AS
SELECT 
    o.order_id,
    o.customer_id,
    o.order_status,
    o.purchase_timestamp,
    o.actual_delivery_days,
    -- 客户信息
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    -- 订单商品汇总
    COALESCE(ois.item_count, 0) AS item_count,
    COALESCE(ois.order_total, 0) AS order_total_amount,
    -- 支付汇总
    COALESCE(ops.total_paid, 0) AS total_paid,
    COALESCE(ops.payment_count, 0) AS payment_count,
    -- 评论信息
    COALESCE(orc.review_score, 0) AS review_score,
    COALESCE(orc.sentiment, 'NO_REVIEW') AS review_sentiment,
    -- 交付表现
    CASE 
        WHEN o.actual_delivery_days IS NOT NULL 
             AND o.estimated_delivery_timestamp IS NOT NULL
             AND o.delivered_customer_timestamp IS NOT NULL
        THEN CASE 
            WHEN o.delivered_customer_timestamp <= o.estimated_delivery_timestamp 
            THEN 'ON_TIME'
            ELSE 'DELAYED'
        END
        ELSE 'UNKNOWN'
    END AS delivery_performance,
    -- 计算支付差额
    COALESCE(ois.order_total, 0) - COALESCE(ops.total_paid, 0) AS payment_balance
FROM orders_clean o
LEFT JOIN customers_clean c ON o.customer_id = c.customer_id
LEFT JOIN order_items_summary ois ON o.order_id = ois.order_id
LEFT JOIN order_payments_summary ops ON o.order_id = ops.order_id
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score, MAX(sentiment) AS sentiment
    FROM order_reviews_clean
    GROUP BY order_id
) orc ON o.order_id = orc.order_id
WHERE o.is_valid_order_id = 1;

-- 2. 创建产品完整视图（整合翻译信息）
DROP VIEW IF EXISTS products_complete_view;
CREATE VIEW products_complete_view AS
SELECT 
    p.product_id,
    p.product_category_name AS original_category,
    COALESCE(t.product_category_name_english, p.product_category_name) AS category_english,
    p.product_weight_kg,
    p.product_volume_cm3,
    p.weight_category,
    p.has_category,
    p.has_weight,
    -- 销售统计（需要后续与订单数据关联）
    0 AS total_sold,  -- 占位符，后续可以更新
    0.0 AS avg_sale_price  -- 占位符
FROM products_clean p
LEFT JOIN product_category_translation_clean t 
    ON p.product_category_name = t.product_category_name_original;

-- 3. 创建卖家绩效视图
DROP VIEW IF EXISTS seller_performance_view;
CREATE VIEW seller_performance_view AS
SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    -- 销售统计
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(DISTINCT oi.product_id) AS unique_products_sold,
    SUM(oi.price) AS total_revenue,
    AVG(oi.price) AS avg_product_price,
    -- 地理位置信息
    g.avg_latitude,
    g.avg_longitude,
    -- 绩效指标
    CASE 
        WHEN COUNT(DISTINCT oi.order_id) > 100 THEN 'TOP_SELLER'
        WHEN COUNT(DISTINCT oi.order_id) > 10 THEN 'ACTIVE_SELLER'
        ELSE 'OCCASIONAL_SELLER'
    END AS seller_tier
FROM sellers_clean s
LEFT JOIN order_items_clean oi ON s.seller_id = oi.seller_id
LEFT JOIN geolocation_clean g ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
GROUP BY s.seller_id, s.seller_city, s.seller_state, g.avg_latitude, g.avg_longitude;


-- 1. 数据完整性报告
DROP VIEW IF EXISTS data_quality_report;
CREATE VIEW data_quality_report AS
SELECT 
    'customers' AS table_name,
    COUNT(*) AS total_records,
    SUM(is_valid_customer_id) AS valid_customer_ids,
    ROUND(SUM(is_valid_customer_id) * 100.0 / COUNT(*), 2) AS validity_percentage
FROM customers_clean
UNION ALL
SELECT 
    'orders',
    COUNT(*),
    SUM(is_valid_order_id),
    ROUND(SUM(is_valid_order_id) * 100.0 / COUNT(*), 2)
FROM orders_clean
UNION ALL
SELECT 
    'order_items',
    COUNT(*),
    SUM(is_valid_record),
    ROUND(SUM(is_valid_record) * 100.0 / COUNT(*), 2)
FROM order_items_clean
UNION ALL
SELECT 
    'products',
    COUNT(*),
    SUM(has_category),
    ROUND(SUM(has_category) * 100.0 / COUNT(*), 2)
FROM products_clean
UNION ALL
SELECT 
    'sellers',
    COUNT(*),
    SUM(is_valid_seller_id),
    ROUND(SUM(is_valid_seller_id) * 100.0 / COUNT(*), 2)
FROM sellers_clean;

-- 2. 时间线完整性检查
DROP VIEW IF EXISTS timeline_completeness;
CREATE VIEW timeline_completeness AS
SELECT 
    'orders' AS table_type,
    YEAR(purchase_timestamp) AS year,
    MONTH(purchase_timestamp) AS month,
    COUNT(*) AS record_count
FROM orders_clean
WHERE purchase_timestamp IS NOT NULL
GROUP BY YEAR(purchase_timestamp), MONTH(purchase_timestamp)
UNION ALL
SELECT 
    'reviews',
    YEAR(review_creation_timestamp),
    MONTH(review_creation_timestamp),
    COUNT(*)
FROM order_reviews_clean
WHERE review_creation_timestamp IS NOT NULL
GROUP BY YEAR(review_creation_timestamp), MONTH(review_creation_timestamp)
ORDER BY table_type, year, month;

-- 3. 外键关系完整性检查
DROP VIEW IF EXISTS referential_integrity_check;
CREATE VIEW referential_integrity_check AS
SELECT 
    'order_items -> orders' AS relationship,
    COUNT(DISTINCT oi.order_id) AS distinct_order_ids_in_items,
    COUNT(DISTINCT o.order_id) AS matching_order_ids_in_orders,
    COUNT(DISTINCT oi.order_id) - COUNT(DISTINCT o.order_id) AS orphaned_records
FROM order_items_clean oi
LEFT JOIN orders_clean o ON oi.order_id = o.order_id
UNION ALL
SELECT 
    'orders -> customers',
    COUNT(DISTINCT o.customer_id),
    COUNT(DISTINCT c.customer_id),
    COUNT(DISTINCT o.customer_id) - COUNT(DISTINCT c.customer_id)
FROM orders_clean o
LEFT JOIN customers_clean c ON o.customer_id = c.customer_id;


