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

# Create materialized tables from SQL file (avoids shell escaping issues)
mysql --user=${METABASE_ASKARA_DB_USER} --password=${METABASE_ASKARA_DB_PASSWORD} --host=${METABASE_ASKARA_DB_HOST} --port=${METABASE_ASKARA_DB_PORT} ${METABASE_ASKARA_DB_NAME} < /app/scripts/create-materialized-tables.sql

echo "Materialized tables created successfully!"