#!/usr/bin/env bash

archive_name="backup.tar.gz"

# Install the Scalingo CLI tool in the container:
install-scalingo-cli

# Install additional tools to interact with the database:
dbclient-fetcher "${SCALINGO_ADDON_KIND}"

# Login to Scalingo, using the token stored in `SCALINGO_API_TOKEN`:
scalingo login --api-token "${SCALINGO_API_TOKEN}"

# Retrieve the addon id:
addon_id="$( scalingo --app "${SCALINGO_SOURCE_APP}" addons \
    | grep "${SCALINGO_ADDON_KIND}" \
    | grep -oP 'ad-[a-f0-9-]+' )"

# Download the latest backup available for the specified addon:
scalingo --app "${SCALINGO_SOURCE_APP}" --addon "${addon_id}" \
    backups-download --output "${archive_name}"

# Get the name of the backup file:
backup_file_name="$( tar --list --file="${archive_name}" \
                     | tail -n 1 \
                     | cut -d "/" -f 2 )"

# Extract the archive containing the downloaded backup:
tar --extract --verbose --file="${archive_name}" --directory="/app/backups/"

# Fix MySQL view definers (replace prod definer with local user)
echo "Fixing MySQL view definers..."
sed -i "s/DEFINER=\`[^\`]*\`@\`[^\`]*\`/DEFINER=\`${METABASE_ASKARA_DB_USER}\`@\`%\`/g" /app/backups/${backup_file_name}

# Restore the data:
mysql --user=${METABASE_ASKARA_DB_USER} --password=${METABASE_ASKARA_DB_PASSWORD} --host=${METABASE_ASKARA_DB_HOST} --port=${METABASE_ASKARA_DB_PORT} ${METABASE_ASKARA_DB_NAME} < /app/backups/${backup_file_name}

echo "Building materialized tables for Metabase dashboards..."

# MySQL connection shortcut
MYSQL_CMD="mysql --user=${METABASE_ASKARA_DB_USER} --password=${METABASE_ASKARA_DB_PASSWORD} --host=${METABASE_ASKARA_DB_HOST} --port=${METABASE_ASKARA_DB_PORT} ${METABASE_ASKARA_DB_NAME}"

# Create and populate materialized tables from views
# These pre-computed tables are much faster for Metabase queries

${MYSQL_CMD} -e "
-- Table 1: Organization Costs Summary
DROP TABLE IF EXISTS mat_api_usage_organization_costs_summary;
CREATE TABLE mat_api_usage_organization_costs_summary AS
SELECT * FROM view_api_usage_organization_costs_summary;
ALTER TABLE mat_api_usage_organization_costs_summary ADD PRIMARY KEY (organization_id);

-- Table 2: Top Users By Cost
DROP TABLE IF EXISTS mat_api_usage_top_users_by_cost;
CREATE TABLE mat_api_usage_top_users_by_cost AS
SELECT * FROM view_api_usage_top_users_by_cost;
ALTER TABLE mat_api_usage_top_users_by_cost ADD PRIMARY KEY (user_id);

-- Table 3: Daily Costs
DROP TABLE IF EXISTS mat_api_usage_daily_costs;
CREATE TABLE mat_api_usage_daily_costs AS
SELECT * FROM view_api_usage_daily_costs;
ALTER TABLE mat_api_usage_daily_costs ADD INDEX idx_date (date);

-- Table 4: AI Model Usage
DROP TABLE IF EXISTS mat_api_usage_ai_model;
CREATE TABLE mat_api_usage_ai_model AS
SELECT * FROM view_api_usage_ai_model;

-- Table 5: Cost Per Document
DROP TABLE IF EXISTS mat_api_usage_cost_per_document;
CREATE TABLE mat_api_usage_cost_per_document AS
SELECT * FROM view_api_usage_cost_per_document;

-- Table 6: STT Quality Costs
DROP TABLE IF EXISTS mat_api_usage_stt_quality_costs;
CREATE TABLE mat_api_usage_stt_quality_costs AS
SELECT * FROM view_api_usage_stt_quality_costs;

-- Table 7: OCR Success Costs
DROP TABLE IF EXISTS mat_api_usage_ocr_success_costs;
CREATE TABLE mat_api_usage_ocr_success_costs AS
SELECT * FROM view_api_usage_ocr_success_costs;

-- Table 8: Monthly Cost Comparison
DROP TABLE IF EXISTS mat_api_usage_monthly_cost_comparison;
CREATE TABLE mat_api_usage_monthly_cost_comparison AS
SELECT * FROM view_api_usage_monthly_cost_comparison;
ALTER TABLE mat_api_usage_monthly_cost_comparison ADD INDEX idx_month (month);
"

echo "Materialized tables created successfully!"