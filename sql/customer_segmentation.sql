-- 首先，找出数据集中最新的订单日期，作为分析基准日
DROP VIEW IF EXISTS analysis_date_view;
CREATE VIEW analysis_date_view AS
SELECT 
    DATE(MAX(purchase_timestamp)) AS max_order_date
FROM orders_clean
WHERE purchase_timestamp IS NOT NULL;

-- 让我们看一下这个日期是什么（你可以根据业务调整，比如用固定日期）
SELECT * FROM analysis_date_view;


-- 步骤1：确保分析基准日视图存在
DROP VIEW IF EXISTS analysis_date_view;
CREATE VIEW analysis_date_view AS
SELECT 
    DATE(MAX(purchase_timestamp)) AS max_order_date
FROM orders_clean
WHERE purchase_timestamp IS NOT NULL;

-- 步骤2：创建客户 RFM 基础表 (使用 CROSS JOIN)
DROP TABLE IF EXISTS customer_rfm_base;
CREATE TABLE customer_rfm_base AS
SELECT 
    c.customer_unique_id,
    -- Recency (R): 计算最近一次购买距分析基准日的天数
    -- 现在直接引用通过 CROSS JOIN 引入的 ad.max_order_date
    DATEDIFF(
        ad.max_order_date, 
        DATE(MAX(o.purchase_timestamp))
    ) AS recency_days,
    
    -- Frequency (F): 计算总订单数
    COUNT(DISTINCT o.order_id) AS frequency_count,
    
    -- Monetary (M): 计算总支付金额
    COALESCE(SUM(op.payment_value), 0) AS monetary_total
    
FROM customers_clean c
JOIN orders_clean o ON c.customer_id = o.customer_id
LEFT JOIN order_payments_clean op ON o.order_id = op.order_id
-- 关键修改：将分析基准日视图通过 CROSS JOIN 连接到主查询
CROSS JOIN analysis_date_view ad
-- 确保只统计已完成的订单（例如已交付的）
WHERE o.order_status = 'delivered' 
  AND o.purchase_timestamp IS NOT NULL
GROUP BY c.customer_unique_id, ad.max_order_date -- 注意：group by 需要包含 ad.max_order_date
HAVING COUNT(DISTINCT o.order_id) > 0; -- 确保是有购买记录的客户

-- 步骤3：查看 RFM 基础数据分布
SELECT 
    COUNT(*) AS customer_count,
    ROUND(AVG(recency_days), 1) AS avg_recency,
    ROUND(AVG(frequency_count), 2) AS avg_frequency,
    ROUND(AVG(monetary_total), 2) AS avg_monetary,
    MIN(recency_days) AS min_recency,
    MAX(recency_days) AS max_recency
FROM customer_rfm_base;


-- 创建 RFM 评分表
DROP TABLE IF EXISTS customer_rfm_scores;
CREATE TABLE customer_rfm_scores AS
SELECT 
    customer_unique_id,
    recency_days,
    frequency_count,
    monetary_total,
    -- 对R进行评分：recency_days越小越好，所以用升序排列，天数最小的给5分
    6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
    -- 对F进行评分：frequency_count越大越好，降序排列
    NTILE(5) OVER (ORDER BY frequency_count DESC) AS f_score,
    -- 对M进行评分：monetary_total越大越好，降序排列
    NTILE(5) OVER (ORDER BY monetary_total DESC) AS m_score
FROM customer_rfm_base;

-- 查看评分分布
SELECT 
    r_score,
    COUNT(*) AS cust_count,
    ROUND(AVG(recency_days), 1) AS avg_recency_in_group
FROM customer_rfm_scores
GROUP BY r_score
ORDER BY r_score DESC;

SELECT 
    f_score,
    COUNT(*) AS cust_count,
    ROUND(AVG(frequency_count), 2) AS avg_freq_in_group
FROM customer_rfm_scores
GROUP BY f_score
ORDER BY f_score DESC;

-- 创建最终的 RFM 客户分群表
DROP TABLE IF EXISTS customer_rfm_segments;
CREATE TABLE customer_rfm_segments AS
SELECT 
    customer_unique_id,
    recency_days,
    frequency_count,
    monetary_total,
    r_score,
    f_score,
    m_score,
    rfm_cell,  -- 这里直接使用内层查询已经计算好的列
    -- 定义客户细分群体
    CASE 
        -- 最佳客户：最近购买、高频、高消费
        WHEN (r_score >= 4 AND f_score >= 4 AND m_score >= 4) THEN '冠军客户'
        -- 高价值流失风险：很久没买，但曾经是高价值客户
        WHEN (r_score <= 2 AND f_score >= 4 AND m_score >= 4) THEN '需唤回贵宾'  
        -- 新客户：最近购买，但消费次数和金额还不高
        WHEN (r_score >= 4 AND f_score <= 2 AND m_score <= 2) THEN '潜力新客'
        -- 高消费低频客户：消费金额高，但买得少（可能买大件）
        WHEN (m_score >= 4 AND f_score <= 2) THEN '鲸鱼客户'
        -- 高频率低消费客户：经常买，但每次花得少
        WHEN (f_score >= 4 AND m_score <= 2) THEN '高粘性小客'
        -- 流失客户：很久没买，且历史价值不高
        WHEN (r_score = 1) THEN '流失客户'
        -- 用 RFM 代码定义更多精细类别（示例）
        WHEN rfm_cell IN ('555', '554', '545', '544') THEN '至尊VIP'
        WHEN rfm_cell IN ('111', '112', '121', '122', '211', '212') THEN '需重点挽回'
        ELSE '普通客户'
    END AS customer_segment,
    -- 综合价值评分
    ROUND((r_score * 0.4 + f_score * 0.3 + m_score * 0.3), 2) AS value_score
FROM (
    -- 内层查询：先计算所有基础字段和 rfm_cell
    SELECT 
        customer_unique_id,
        recency_days,
        frequency_count,
        monetary_total,
        r_score,
        f_score,
        m_score,
        CONCAT(CAST(r_score AS STRING), CAST(f_score AS STRING), CAST(m_score AS STRING)) AS rfm_cell
    FROM customer_rfm_scores
) AS inner_query;