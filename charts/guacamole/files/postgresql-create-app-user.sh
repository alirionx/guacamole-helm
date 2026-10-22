#!/bin/sh
# Executed by the PostgreSQL image entrypoint on first start (/docker-entrypoint-initdb.d):
# creates the application user and the Guacamole database owned by it.
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --set=app_user="$APP_USER" --set=app_database="$APP_DATABASE" --set=app_password="$APP_PASSWORD" <<'SQL'
CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password';
CREATE DATABASE :"app_database" OWNER :"app_user";
SQL
