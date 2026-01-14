#!/usr/bin/env bash
set -euo pipefail

# Repo root (folder that contains webroot/)
REPO_ROOT="/workspaces/civicrm-govnotify-connector"
WEBROOT_HOST="$REPO_ROOT/webroot"
WEBROOT_CONT="/var/www/html"

# Find actual running container names
PHP_CONTAINER=$(docker ps --filter "name=php" --format "{{.Names}}" | head -n1)
DB_CONTAINER=$(docker ps --filter "name=db" --format "{{.Names}}" | head -n1)

if [ -z "$PHP_CONTAINER" ] || [ -z "$DB_CONTAINER" ]; then
  echo "ERROR: Could not find running PHP or DB containers"
  echo "PHP container: $PHP_CONTAINER"
  echo "DB container: $DB_CONTAINER"
  exit 1
fi

echo "==> Found containers:"
echo "    PHP: $PHP_CONTAINER"
echo "    DB: $DB_CONTAINER"

PHP_EXEC="docker exec -i $PHP_CONTAINER sh -lc"
DB_EXEC="docker exec -i $DB_CONTAINER sh -lc"

echo "==> Waiting for database to be ready..."
MAX_TRIES=30
TRIES=0
until $DB_EXEC "mysql --ssl-mode=DISABLED -udrupal -pdrupal -e 'SELECT 1' drupal" 2>/dev/null; do
  TRIES=$((TRIES + 1))
  if [ $TRIES -ge $MAX_TRIES ]; then
    echo "ERROR: Database failed to become ready after $MAX_TRIES attempts"
    echo "Checking database logs:"
    docker logs $DB_CONTAINER
    exit 1
  fi
  echo "Waiting for database connection... (attempt $TRIES/$MAX_TRIES)"
  sleep 3
done
echo "Database is ready!"

echo "==> Creating webroot directory if missing..."
mkdir -p "$WEBROOT_HOST"

echo "==> Installing Drupal codebase if missing..."
if [ ! -f "$WEBROOT_HOST/composer.json" ]; then
  $PHP_EXEC "cd $WEBROOT_CONT && composer create-project -n drupal/recommended-project:^10 ."
  echo "Setting permissions..."
  $PHP_EXEC "cd $WEBROOT_CONT && chown -R www-data:www-data ."
else
  echo "Drupal composer.json exists, skipping create-project."
fi

echo "==> Ensuring Drush is installed..."
$PHP_EXEC "cd $WEBROOT_CONT && composer require -n drush/drush:^12"

echo "==> Installing contrib deps (token/pathauto) if missing..."
$PHP_EXEC "cd $WEBROOT_CONT && composer require -n drupal/token drupal/pathauto"

echo "==> Installing Drupal site if not installed..."
if [ ! -f "$WEBROOT_HOST/web/sites/default/settings.php" ]; then
  $PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush si -y \
    --db-url='mysql://drupal:drupal@db/drupal?ssl-mode=DISABLED' \
    --site-name='Drupal + CiviCRM' \
    --account-name=admin \
    --account-pass=admin"
else
  echo "settings.php exists, skipping drush si."
fi

echo "==> Ensuring sites/default is writable..."
$PHP_EXEC "chmod -R u+w $WEBROOT_CONT/web/sites/default"

echo "==> Enabling useful modules..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush en -y syslog views_ui token pathauto"


echo "==> Requiring CiviCRM 6.4.1 packages (idempotent)..."
$PHP_EXEC "cd $WEBROOT_CONT && composer config --no-plugins allow-plugins.cweagans/composer-patches true"
$PHP_EXEC "cd $WEBROOT_CONT && composer config --no-plugins allow-plugins.civicrm/civicrm-asset-plugin true"
$PHP_EXEC "cd $WEBROOT_CONT && composer config --no-plugins allow-plugins.civicrm/composer-downloads-plugin true"
$PHP_EXEC "cd $WEBROOT_CONT && composer config --no-plugins allow-plugins.civicrm/composer-compile-plugin true"
$PHP_EXEC "cd $WEBROOT_CONT && composer config extra.compile-mode all"

$PHP_EXEC "cd $WEBROOT_CONT && composer require -n \
  civicrm/civicrm-core:6.4.1 \
  civicrm/civicrm-packages:6.4.1 \
  civicrm/civicrm-drupal-8:6.4.1"

echo "==> Cleaning up any leftover CiviCRM test tables..."
$DB_EXEC "mysql --ssl-mode=DISABLED -udrupal -pdrupal drupal -e 'DROP TABLE IF EXISTS civicrm_install_temp_table_test;'" 2>/dev/null || true

echo "==> Enabling CiviCRM module..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush en -y civicrm"

echo "==> Running CiviCRM installation..."
if $PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush ev \"return \\Drupal::database()->schema()->tableExists('civicrm_contact');\"" | grep -q "1"; then
  echo "CiviCRM already installed, skipping cv core:install"
else
  echo "Installing CiviCRM database..."
  $PHP_EXEC "cd $WEBROOT_CONT/web && \
    ../vendor/bin/drush cvapi System.install \
    --lang=en_US"
fi

echo "==> Clearing caches..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush cr"

echo ""
echo "==> Bootstrap complete!"
echo "============================================"
echo "Drupal admin login:  admin / admin"
echo "CiviCRM should be accessible at: /civicrm"
echo "============================================"