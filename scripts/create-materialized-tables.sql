-- Materialized tables for Metabase dashboards
-- These pre-computed tables are much faster than querying views directly
-- Uses direct queries instead of views since views may not exist in molia_symfo_8824

-- Table 1: Organization Costs Summary
DROP TABLE IF EXISTS mat_api_usage_organization_costs_summary;
CREATE TABLE mat_api_usage_organization_costs_summary (
    organization_id INT PRIMARY KEY,
    organization_name VARCHAR(255),
    total_operations BIGINT,
    total_cost_euros DECIMAL(12,6),
    ai_cost_euros DECIMAL(12,6),
    stt_cost_euros DECIMAL(12,6),
    ocr_cost_euros DECIMAL(12,6),
    document_count BIGINT,
    patient_synced_count BIGINT,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    stt_hours DECIMAL(12,6),
    ocr_images_processed BIGINT
);
INSERT INTO mat_api_usage_organization_costs_summary
SELECT
    o.id as organization_id,
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    COUNT(DISTINCT au.id) as total_operations,
    COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
    COALESCE(SUM(CASE WHEN au.operation_category = 'ai' THEN au.cost_eur ELSE 0 END), 0) as ai_cost_euros,
    COALESCE(SUM(CASE WHEN au.operation_category = 'stt' THEN au.cost_eur ELSE 0 END), 0) as stt_cost_euros,
    COALESCE(SUM(CASE WHEN au.operation_category = 'ocr' THEN au.cost_eur ELSE 0 END), 0) as ocr_cost_euros,
    COUNT(DISTINCT CASE WHEN au.document_id IS NOT NULL THEN au.document_id END) as document_count,
    COUNT(DISTINCT CASE WHEN au.patient_id IS NOT NULL THEN au.patient_id END) as patient_synced_count,
    COALESCE(SUM(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.input_tokens')), 'null'), '') AS SIGNED)), 0) as total_input_tokens,
    COALESCE(SUM(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.output_tokens')), 'null'), '') AS SIGNED)), 0) as total_output_tokens,
    COALESCE(SUM(CASE WHEN au.operation_category = 'stt'
        THEN CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.duration_ms')), 'null'), '') AS SIGNED) / 1000 / 3600
        ELSE 0 END), 0) as stt_hours,
    COUNT(CASE WHEN au.operation_category = 'ocr' THEN 1 END) as ocr_images_processed
FROM organization o
LEFT JOIN api_usage au ON o.id = au.organization_id
WHERE au.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY o.id, o.name, o.street_address, o.postal_code, o.city;

-- Table 2: Top Users By Cost
DROP TABLE IF EXISTS mat_api_usage_top_users_by_cost;
CREATE TABLE mat_api_usage_top_users_by_cost (
    user_id INT PRIMARY KEY,
    user_name VARCHAR(255),
    email VARCHAR(255),
    organization_name VARCHAR(255),
    total_operations BIGINT,
    total_cost_euros DECIMAL(12,6),
    ai_cost DECIMAL(12,6),
    stt_cost DECIMAL(12,6),
    ocr_cost DECIMAL(12,6),
    cost_rank_in_org BIGINT
);
INSERT INTO mat_api_usage_top_users_by_cost
SELECT
    u.id as user_id,
    CONCAT(u.first_name, ' ', u.last_name) as user_name,
    u.email,
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    COUNT(*) as total_operations,
    COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
    COALESCE(SUM(CASE WHEN au.operation_category = 'ai' THEN au.cost_eur ELSE 0 END), 0) as ai_cost,
    COALESCE(SUM(CASE WHEN au.operation_category = 'stt' THEN au.cost_eur ELSE 0 END), 0) as stt_cost,
    COALESCE(SUM(CASE WHEN au.operation_category = 'ocr' THEN au.cost_eur ELSE 0 END), 0) as ocr_cost,
    RANK() OVER (PARTITION BY o.id ORDER BY SUM(au.cost_eur) DESC) as cost_rank_in_org
FROM user u
JOIN organization_user ou ON u.id = ou.user_id
JOIN organization o ON ou.organization_id = o.id
JOIN api_usage au ON u.id = au.user_id
WHERE au.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY u.id, u.first_name, u.last_name, u.email, o.id, o.name, o.street_address, o.postal_code, o.city
ORDER BY total_cost_euros DESC
LIMIT 100;

-- Table 3: Daily Costs
DROP TABLE IF EXISTS mat_api_usage_daily_costs;
CREATE TABLE mat_api_usage_daily_costs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    date DATE,
    organization_name VARCHAR(255),
    operation_category VARCHAR(30),
    operation_count BIGINT,
    daily_cost_euros DECIMAL(12,6),
    ma7_cost_euros DECIMAL(12,6),
    INDEX idx_date (date)
);
INSERT INTO mat_api_usage_daily_costs (date, organization_name, operation_category, operation_count, daily_cost_euros, ma7_cost_euros)
SELECT
    DATE(au.created_at) as date,
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    au.operation_category,
    COUNT(*) as operation_count,
    COALESCE(SUM(au.cost_eur), 0) as daily_cost_euros,
    AVG(SUM(au.cost_eur)) OVER (
        PARTITION BY o.id, au.operation_category
        ORDER BY DATE(au.created_at)
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as ma7_cost_euros
FROM api_usage au
JOIN organization o ON au.organization_id = o.id
WHERE au.created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
GROUP BY DATE(au.created_at), o.id, o.name, o.street_address, o.postal_code, o.city, au.operation_category;

-- Table 4: AI Model Usage
DROP TABLE IF EXISTS mat_api_usage_ai_model;
CREATE TABLE mat_api_usage_ai_model (
    id INT AUTO_INCREMENT PRIMARY KEY,
    organization_name VARCHAR(255),
    model VARCHAR(255),
    model_name VARCHAR(255),
    request_count BIGINT,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_cost_euros DECIMAL(12,6),
    avg_input_tokens DECIMAL(12,2),
    avg_output_tokens DECIMAL(12,2)
);
INSERT INTO mat_api_usage_ai_model (organization_name, model, model_name, request_count, total_input_tokens, total_output_tokens, total_cost_euros, avg_input_tokens, avg_output_tokens)
SELECT
    organization_name,
    model,
    CASE
        WHEN model LIKE '%claude-3-haiku%' THEN 'Claude 3 Haiku'
        WHEN model LIKE '%claude-3-5-sonnet%' THEN 'Claude 3.5 Sonnet'
        WHEN model LIKE '%claude-3-7-sonnet%' THEN 'Claude 3.7 Sonnet'
        WHEN model LIKE '%claude-sonnet-4%' THEN 'Claude 4 Sonnet'
        WHEN model LIKE '%claude-3-sonnet%' THEN 'Claude 3 Sonnet'
        WHEN model LIKE '%llama3-2-1b%' THEN 'Llama 3.2 1B'
        WHEN model LIKE '%llama3-2-3b%' THEN 'Llama 3.2 3B'
        WHEN model LIKE '%pixtral-large%' THEN 'Pixtral Large'
        WHEN model LIKE '%nova-lite%' THEN 'Nova Lite'
        WHEN model LIKE '%nova-micro%' THEN 'Nova Micro'
        WHEN model LIKE '%nova-pro%' THEN 'Nova Pro'
        ELSE model
    END as model_name,
    request_count,
    total_input_tokens,
    total_output_tokens,
    total_cost_euros,
    avg_input_tokens,
    avg_output_tokens
FROM (
    SELECT
        COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
        JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.model')) as model,
        COUNT(*) as request_count,
        COALESCE(SUM(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.input_tokens')), 'null'), '') AS SIGNED)), 0) as total_input_tokens,
        COALESCE(SUM(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.output_tokens')), 'null'), '') AS SIGNED)), 0) as total_output_tokens,
        COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
        COALESCE(AVG(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.input_tokens')), 'null'), '') AS SIGNED)), 0) as avg_input_tokens,
        COALESCE(AVG(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.output_tokens')), 'null'), '') AS SIGNED)), 0) as avg_output_tokens
    FROM api_usage au
    JOIN organization o ON au.organization_id = o.id
    WHERE au.operation_category = 'ai'
      AND au.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY o.id, o.name, o.street_address, o.postal_code, o.city, JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.model'))
) as subquery;

-- Table 5: Cost Per Document
DROP TABLE IF EXISTS mat_api_usage_cost_per_document;
CREATE TABLE mat_api_usage_cost_per_document (
    id INT AUTO_INCREMENT PRIMARY KEY,
    organization_name VARCHAR(255),
    document_type VARCHAR(50),
    document_count BIGINT,
    total_cost_euros DECIMAL(12,6),
    avg_cost_per_document DECIMAL(12,6),
    ai_cost DECIMAL(12,6),
    stt_cost DECIMAL(12,6),
    avg_generation_duration_ms DECIMAL(12,2)
);
INSERT INTO mat_api_usage_cost_per_document (organization_name, document_type, document_count, total_cost_euros, avg_cost_per_document, ai_cost, stt_cost, avg_generation_duration_ms)
SELECT
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    d.type as document_type,
    COUNT(DISTINCT d.id) as document_count,
    COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
    COALESCE(AVG(au.cost_eur), 0) as avg_cost_per_document,
    COALESCE(SUM(CASE WHEN au.operation_category = 'ai' THEN au.cost_eur ELSE 0 END), 0) as ai_cost,
    COALESCE(SUM(CASE WHEN au.operation_category = 'stt' THEN au.cost_eur ELSE 0 END), 0) as stt_cost,
    COALESCE(AVG(d.generation_duration), 0) as avg_generation_duration_ms
FROM document d
JOIN user u ON d.user_id = u.id
JOIN organization_user ou ON u.id = ou.user_id
JOIN organization o ON ou.organization_id = o.id
LEFT JOIN api_usage au ON d.id = au.document_id
WHERE d.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND d.generate_ended_at IS NOT NULL
GROUP BY o.id, o.name, o.street_address, o.postal_code, o.city, d.type;

-- Table 6: STT Quality Costs
DROP TABLE IF EXISTS mat_api_usage_stt_quality_costs;
CREATE TABLE mat_api_usage_stt_quality_costs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    organization_name VARCHAR(255),
    transcription_count BIGINT,
    avg_quality_score DECIMAL(5,2),
    avg_words_count DECIMAL(12,2),
    total_hours DECIMAL(12,6),
    total_cost_euros DECIMAL(12,6),
    avg_cost_per_transcription DECIMAL(12,6)
);
INSERT INTO mat_api_usage_stt_quality_costs (organization_name, transcription_count, avg_quality_score, avg_words_count, total_hours, total_cost_euros, avg_cost_per_transcription)
SELECT
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    COUNT(*) as transcription_count,
    COALESCE(AVG(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.quality_score')), 'null'), '') AS DECIMAL(5,2))), 0) as avg_quality_score,
    COALESCE(AVG(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.words_count')), 'null'), '') AS SIGNED)), 0) as avg_words_count,
    COALESCE(SUM(CAST(NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.duration_ms')), 'null'), '') AS SIGNED)), 0) / 1000 / 3600 as total_hours,
    COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
    COALESCE(AVG(au.cost_eur), 0) as avg_cost_per_transcription
FROM api_usage au
JOIN organization o ON au.organization_id = o.id
WHERE au.operation_category = 'stt'
  AND au.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND au.status = 'success'
GROUP BY o.id, o.name, o.street_address, o.postal_code, o.city;

-- Table 7: OCR Success Costs
DROP TABLE IF EXISTS mat_api_usage_ocr_success_costs;
CREATE TABLE mat_api_usage_ocr_success_costs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    organization_name VARCHAR(255),
    client_software VARCHAR(100),
    total_extractions BIGINT,
    successful_extractions BIGINT,
    success_rate_percent DECIMAL(5,2),
    total_cost_euros DECIMAL(12,6),
    avg_duration_ms DECIMAL(12,2)
);
INSERT INTO mat_api_usage_ocr_success_costs (organization_name, client_software, total_extractions, successful_extractions, success_rate_percent, total_cost_euros, avg_duration_ms)
SELECT
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.client_slug')) as client_software,
    COUNT(*) as total_extractions,
    SUM(CASE WHEN JSON_EXTRACT(au.operation_metadata, '$.extraction_success') = true THEN 1 ELSE 0 END) as successful_extractions,
    (SUM(CASE WHEN JSON_EXTRACT(au.operation_metadata, '$.extraction_success') = true THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as success_rate_percent,
    COALESCE(SUM(au.cost_eur), 0) as total_cost_euros,
    COALESCE(AVG(au.duration_ms), 0) as avg_duration_ms
FROM api_usage au
JOIN organization o ON au.organization_id = o.id
WHERE au.operation_category = 'ocr'
  AND au.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY o.id, o.name, o.street_address, o.postal_code, o.city, JSON_UNQUOTE(JSON_EXTRACT(au.operation_metadata, '$.client_slug'));

-- Table 8: Monthly Cost Comparison
DROP TABLE IF EXISTS mat_api_usage_monthly_cost_comparison;
CREATE TABLE mat_api_usage_monthly_cost_comparison (
    id INT AUTO_INCREMENT PRIMARY KEY,
    month VARCHAR(7),
    organization_name VARCHAR(255),
    operation_category VARCHAR(30),
    operation_count BIGINT,
    monthly_cost_euros DECIMAL(12,6),
    previous_month_cost DECIMAL(12,6),
    growth_percent DECIMAL(8,2),
    INDEX idx_month (month)
);
INSERT INTO mat_api_usage_monthly_cost_comparison (month, organization_name, operation_category, operation_count, monthly_cost_euros, previous_month_cost, growth_percent)
SELECT
    DATE_FORMAT(au.created_at, '%Y-%m') as month,
    COALESCE(o.name, CONCAT_WS(' ', o.street_address, o.postal_code, o.city), CONCAT('Org #', o.id)) as organization_name,
    au.operation_category,
    COUNT(*) as operation_count,
    COALESCE(SUM(au.cost_eur), 0) as monthly_cost_euros,
    LAG(SUM(au.cost_eur)) OVER (
        PARTITION BY o.id, au.operation_category
        ORDER BY DATE_FORMAT(au.created_at, '%Y-%m')
    ) as previous_month_cost,
    CASE
        WHEN LAG(SUM(au.cost_eur)) OVER (
            PARTITION BY o.id, au.operation_category
            ORDER BY DATE_FORMAT(au.created_at, '%Y-%m')
        ) IS NOT NULL
        AND LAG(SUM(au.cost_eur)) OVER (
            PARTITION BY o.id, au.operation_category
            ORDER BY DATE_FORMAT(au.created_at, '%Y-%m')
        ) > 0
        THEN ((SUM(au.cost_eur) - LAG(SUM(au.cost_eur)) OVER (
            PARTITION BY o.id, au.operation_category
            ORDER BY DATE_FORMAT(au.created_at, '%Y-%m')
        )) * 100.0 / LAG(SUM(au.cost_eur)) OVER (
            PARTITION BY o.id, au.operation_category
            ORDER BY DATE_FORMAT(au.created_at, '%Y-%m')
        ))
        ELSE NULL
    END as growth_percent
FROM api_usage au
JOIN organization o ON au.organization_id = o.id
WHERE au.created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
GROUP BY DATE_FORMAT(au.created_at, '%Y-%m'), o.id, o.name, o.street_address, o.postal_code, o.city, au.operation_category;

SELECT 'All 8 materialized tables created!' as status;
