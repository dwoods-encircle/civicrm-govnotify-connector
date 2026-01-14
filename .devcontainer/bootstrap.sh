#!/usr/bin/env bash
set -euo pipefail

# Repo root (folder that contains webroot/)
REPO_ROOT="/workspaces/civicrm-govnotify-connector"
WEBROOT_HOST="$REPO_ROOT/webroot"
WEBROOT_CONT="/var/www/html"

COMPOSE="docker compose -f $REPO_ROOT/.devcontainer/docker-compose.yml"
PHP_EXEC="$COMPOSE exec -T php sh -lc"
DB_EXEC="$COMPOSE exec -T db sh -lc"

echo "==> Ensuring webroot exists on host..."
mkdir -p "$WEBROOT_HOST"

echo "==> Waiting for MySQL..."
for i in {1..60}; do
  if $DB_EXEC "mysqladmin ping -h 127.0.0.1 -uroot -proot" >/dev/null 2>&1; then
    echo "MySQL is up."
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "ERROR: MySQL did not become ready in time."
    $COMPOSE logs --no-color db | tail -n 200 || true
    exit 1
  fi
done

echo "==> Installing Drupal codebase if missing..."
if [ ! -f "$WEBROOT_HOST/composer.json" ]; then
  $PHP_EXEC "cd $WEBROOT_CONT && composer create-project -n drupal/recommended-project:^10 ."
else
  echo "Drupal composer.json exists, skipping create-project."
fi

echo "==> Ensuring Drush is installed..."
$PHP_EXEC "cd $WEBROOT_CONT && composer require -n drush/drush:^12"

echo "==> Installing contrib deps (token/pathauto) if missing..."
# Only require if not present
$PHP_EXEC "cd $WEBROOT_CONT && composer require -n drupal/token drupal/pathauto"

echo "==> Installing Drupal site if not installed..."
if [ ! -f "$WEBROOT_HOST/web/sites/default/settings.php" ]; then
  $PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush si -y \
    --db-url='mysql://drupal:drupal@db/drupal?sslmode=DISABLED' \
    --site-name='Drupal + CiviCRM' \
    --account-name=admin \
    --account-pass=admin"
else
  echo "settings.php exists, skipping drush si."
fi

echo "==> Enabling useful modules..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush en -y syslog views_ui token pathauto"

echo "==> Requiring CiviCRM 6.4.1 packages (idempotent)..."
$PHP_EXEC "cd $WEBROOT_CONT && composer require -n \
  civicrm/civicrm-core:6.4.1 \
  civicrm/civicrm-packages:6.4.1 \
  civicrm/civicrm-drupal-8:6.4.1"

echo "==> Enabling CiviCRM module..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush en -y civicrm"

echo "==> Clearing caches..."
$PHP_EXEC "cd $WEBROOT_CONT && vendor/bin/drush cr"

echo ""
echo "==> Done."
echo "Drupal login:  admin / admin"
echo "Civi installer: /civicrm/install"
