#!/bin/bash
# Creates an isolated role + database for each app.
# Runs once on first cluster init (empty PGDATA) via docker-entrypoint-initdb.d.
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

  echo "Creating role and database '${database}' (owner ${role})"

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
		CREATE ROLE ${role} LOGIN PASSWORD '${password_sql}';
		CREATE DATABASE ${database} OWNER ${role};
		REVOKE ALL ON DATABASE ${database} FROM PUBLIC;
		GRANT CONNECT ON DATABASE ${database} TO ${role};
		GRANT ALL PRIVILEGES ON DATABASE ${database} TO ${role};
	EOSQL

  # Postgres 15+: public schema privileges are revoked from PUBLIC by default.
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database" <<-EOSQL
		GRANT ALL ON SCHEMA public TO ${role};
		ALTER SCHEMA public OWNER TO ${role};
	EOSQL
}

create_app_db nextcloud "$NEXTCLOUD_DB_PASSWORD" nextcloud
create_app_db forgejo "$FORGEJO_DB_PASSWORD" forgejo
create_app_db onlyoffice "$ONLYOFFICE_DB_PASSWORD" onlyoffice

echo "App databases ready: nextcloud, forgejo, onlyoffice"
