-- Materialized tables for Metabase dashboards
-- These pre-computed tables are much faster than querying views directly

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
SELECT * FROM view_api_usage_organization_costs_summary;

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
SELECT * FROM view_api_usage_top_users_by_cost;

-- Table 3: Daily Costs (use auto-increment id as primary key)
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
SELECT * FROM view_api_usage_daily_costs;

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
SELECT * FROM view_api_usage_ai_model;

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
SELECT * FROM view_api_usage_cost_per_document;

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
SELECT * FROM view_api_usage_stt_quality_costs;

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
SELECT * FROM view_api_usage_ocr_success_costs;

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
SELECT * FROM view_api_usage_monthly_cost_comparison;
