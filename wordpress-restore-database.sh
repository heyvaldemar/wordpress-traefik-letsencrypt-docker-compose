#!/bin/bash

# # wordpress-restore-database.sh Description
# This script facilitates the restoration of a database backup.
# 1. **Identify Containers**: It first identifies the service and backups containers by name, finding the appropriate container IDs.
# 2. **List Backups**: Displays all available database backups located at the specified backup path.
# 3. **Select Backup**: Prompts the user to copy and paste the desired backup name from the list to restore the database.
# 4. **Stop Service**: Temporarily stops the service to ensure data consistency during restoration.
# 5. **Restore Database**: Executes a sequence of commands to drop the current database, create a new one, and restore it from the selected compressed backup file.
# 6. **Start Service**: Restarts the service after the restoration is completed.
# To make the `wordpress-restore-database.shh` script executable, run the following command:
# `chmod +x wordpress-restore-database.sh`
# Usage of this script ensures a controlled and guided process to restore the database from an existing backup.

WORDPRESS_CONTAINER=$(docker ps -aqf "name=wordpress-wordpress")
WORDPRESS_BACKUPS_CONTAINER=$(docker ps -aqf "name=wordpress-backups")
WORDPRESS_DB_NAME="wordpressdb"
WORDPRESS_DB_USER=$(docker exec $WORDPRESS_BACKUPS_CONTAINER printenv WORDPRESS_DB_USER)
MARIADB_PASSWORD=$(docker exec $WORDPRESS_BACKUPS_CONTAINER printenv WORDPRESS_DB_PASSWORD)
BACKUP_PATH="/srv/wordpress-mariadb/backups/"

echo "--> All available database backups:"

for entry in $(docker container exec "$WORDPRESS_BACKUPS_CONTAINER" sh -c "ls $BACKUP_PATH")
do
  echo "$entry"
done

echo "--> Copy and paste the backup name from the list above to restore database and press [ENTER]"
echo "--> Example: wordpress-mariadb-backup-YYYY-MM-DD_hh-mm.gz"
echo -n "--> "

read SELECTED_DATABASE_BACKUP

echo "--> $SELECTED_DATABASE_BACKUP was selected"

echo "--> Stopping service..."
docker stop "$WORDPRESS_CONTAINER"

echo "--> Restoring database..."
docker exec "$WORDPRESS_BACKUPS_CONTAINER" sh -c "mariadb -h mariadb -u $WORDPRESS_DB_USER --password=$MARIADB_PASSWORD -e 'DROP DATABASE $WORDPRESS_DB_NAME; CREATE DATABASE $WORDPRESS_DB_NAME;' \
&& gunzip -c ${BACKUP_PATH}${SELECTED_DATABASE_BACKUP} | mariadb -h mariadb -u $WORDPRESS_DB_USER --password=$MARIADB_PASSWORD $WORDPRESS_DB_NAME"
echo "--> Database recovery completed..."

echo "--> Starting service..."
docker start "$WORDPRESS_CONTAINER"
