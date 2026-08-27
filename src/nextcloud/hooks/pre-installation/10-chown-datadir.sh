#!/bin/sh
# Bind-mounted ../../data/nextcloud/data is often root:root (Docker created the
# host path). The installer runs as www-data and refuses a non-writable data dir.
set -eu
mkdir -p /var/www/data
chown -R www-data:www-data /var/www/data
chmod 0750 /var/www/data
