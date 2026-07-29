#!/bin/bash
# Creates an isolated user + database for each app.
# Runs once on first cluster init (empty datadir) via docker-entrypoint-initdb.d.
set -euo pipefail

create_app_db() {
  local role="$1"
  local password="$2"
  local database="$3"
  # Escape single quotes for SQL string literals.
  local password_sql="${password//\'/\'\'}"

  if [ -z "$password" ]; then
    echo "error: empty password for role ${role}" >&2
    exit 1
  fi

  echo "Creating user and database '${database}' (owner ${role})"

  # During entrypoint init, root is available via unix socket without a password.
  mariadb -u root <<-EOSQL
		CREATE DATABASE \`${database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		CREATE USER '${role}'@'%' IDENTIFIED BY '${password_sql}';
		GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${role}'@'%';
		FLUSH PRIVILEGES;
	EOSQL
}

create_app_db nextcloud "$NEXTCLOUD_DB_PASSWORD" nextcloud
create_app_db forgejo "$FORGEJO_DB_PASSWORD" forgejo
create_app_db onlyoffice "$ONLYOFFICE_DB_PASSWORD" onlyoffice

echo "App databases ready: nextcloud, forgejo, onlyoffice"
