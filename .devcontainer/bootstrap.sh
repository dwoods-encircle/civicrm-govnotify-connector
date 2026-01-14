#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose -f .devcontainer/docker-compose.yml"
PHP_RUN="$COMPOSE run --rm php sh -lc"
PHP_EXEC="$COMPOSE exec -T php sh -lc"

echo "==> Starting services..."
$COMPOSE up -d

echo "==> Waiting for MySQL..."
# Wait until db is healthy
for i in {1..60}; do
  if $COMPOSE ps --status=running | grep -q "db"; then
    if $COMPOSE exec -T db mysqladmin ping -h 127.0.0.1 -uroot -proot >/dev/null 2>&1; then
      echo "MySQL is up."
      break
    fi
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "ERROR: MySQL did not become ready in time."
    $COMPOSE logs --no-color db | tail -n 200 || true
    exit 1
  fi
done

# Ensure webroot exists
mkdir -p webroot

# Install Drupal if not present
if [ ! -f "webroot/composer.json" ]; then
  echo "==> Installing Drupal 10 (recommended-project)..."
  $PHP_RUN "cd /var/www/html && composer create-project drupal/recommended-project:^10 ."
else
  echo "==> Drupal project already present, skipping create-project."
fi

echo "==> Installing Drush..."
$PHP_RUN "cd /var/www/html && composer require -n drush/drush:^12"

# Install Drupal site if not already installed
if [ ! -f "webroot/web/sites/default/settings.php" ]; then
  echo "==> Installing Drupal site..."
  $PHP_EXEC "cd /var/www/html && vendor/bin/drush si -y \
  --db-url='mysql://drupal:drupal@db/drupal?sslmode=DISABLED' \
  --site-name='Drupal + CiviCRM' \
  --account-name=admin \
  --account-pass=admin"
else
  echo "==> Drupal already installed (settings.php exists), skipping drush si."
fi

$PHP_RUN "cd /var/www/html && composer require -n drupal/token drupal/pathauto"
$PHP_EXEC "cd /var/www/html && vendor/bin/drush en -y syslog token pathauto views_ui"

echo "==> Requiring CiviCRM 6.4.1 packages..."
$PHP_RUN "cd /var/www/html && composer require -n \
  civicrm/civicrm-core:6.4.1 \
  civicrm/civicrm-packages:6.4.1 \
  civicrm/civicrm-drupal-8:6.4.1"
  


echo "==> Enabling CiviCRM module..."
$PHP_EXEC "cd /var/www/html && vendor/bin/drush en -y civicrm || true"

echo "==> Clearing caches..."
$PHP_EXEC "cd /var/www/html && vendor/bin/drush cr || true"

echo ""
echo "==> Done."
echo "Drupal login:  admin / admin"
echo "Civi installer: /civicrm/install"
