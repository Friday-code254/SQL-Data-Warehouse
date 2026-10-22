#!/bin/zsh
# Double-click this file on a Mac. It starts SQL Server in Docker for the Data Warehouse project.
# Source files and generated UTF-16 bulk sidecars are bind-mounted into the SQL Server container.
CONTAINER="sql-dwh-project"
pause() { echo; read -k 1 -s "?Press any key to close."; echo; }
PASSWORD="${MSSQL_SA_PASSWORD:-}"
if [ -z "$PASSWORD" ]; then
  read -s "PASSWORD?Enter a strong SQL Server sa password (hidden): "
  echo
  if [ -z "$PASSWORD" ]; then echo "A non-empty password is required."; pause; exit 1; fi
  export MSSQL_SA_PASSWORD="$PASSWORD"
fi
cd "$(dirname "$0")"
PATH="/Applications/Docker.app/Contents/Resources/bin:/usr/local/bin:$PATH"

if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop is not running. Start Docker Desktop, wait for the whale icon, then double-click this file again."
  pause; exit 1
fi

# Use the project container so the configured dataset bind mount is present.
TARGET="$(docker ps --filter "name=^/sql-dwh-project$" --format '{{.Names}}' | head -1)"
if [ -z "$TARGET" ]; then
  OTHER="$(docker ps --filter publish=1433 --format '{{.Names}}' | head -1)"
  if [ -n "$OTHER" ]; then
    echo "Port 1433 is already in use by $OTHER. Stop that container or change the project port before starting this SQL Server."
    pause; exit 1
  fi
  echo "Starting SQL Server (the first start downloads it, about 1.5 GB) ..."
  docker compose up -d || { pause; exit 1; }
  TARGET="$CONTAINER"
else
  echo "Project SQL Server is already running in Docker ($TARGET)."
fi

sql() { docker exec "$TARGET" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$PASSWORD" -C -h -1 -Q "$1" 2>/dev/null; }
printf "Waiting for SQL Server "
for i in {1..120}; do sql "SELECT 1" >/dev/null && break; printf "."; sleep 2; done; echo
if ! sql "SELECT 1" >/dev/null; then
  echo "SQL Server did not answer. Open Docker Desktop, click the container $TARGET and read its log. The usual reason: Rosetta is off (section Mac: Docker in the guide)."
  pause; exit 1
fi

print -r -- 'Ready. The datasets are mounted read-only at /sql/dwh_project/01_datasets.'
echo "Install from the repository root with: sqlcmd -S localhost -U sa -P '<your password>' -C -i 00_setup/install.sql"
echo "For the Python runner, set SQLSERVER_DATASET_ROOT=/sql/dwh_project/01_datasets in the local .env file."
pause
