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

# Seafile needs three databases owned by one user.
create_seafile_dbs() {
  local password="$1"
  local password_sql="${password//\'/\'\'}"

  if [ -z "$password" ]; then
    echo "error: empty password for role seafile" >&2
    exit 1
  fi

  echo "Creating Seafile databases ccnet_db, seafile_db, seahub_db (owner seafile)"

  mariadb -u root <<-EOSQL
		CREATE DATABASE \`ccnet_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		CREATE DATABASE \`seafile_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		CREATE DATABASE \`seahub_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		CREATE USER 'seafile'@'%' IDENTIFIED BY '${password_sql}';
		GRANT ALL PRIVILEGES ON \`ccnet_db\`.* TO 'seafile'@'%';
		GRANT ALL PRIVILEGES ON \`seafile_db\`.* TO 'seafile'@'%';
		GRANT ALL PRIVILEGES ON \`seahub_db\`.* TO 'seafile'@'%';
		FLUSH PRIVILEGES;
	EOSQL
}

create_seafile_dbs "$SEAFILE_DB_PASSWORD"
create_app_db forgejo "$FORGEJO_DB_PASSWORD" forgejo

echo "App databases ready: ccnet_db/seafile_db/seahub_db, forgejo"
