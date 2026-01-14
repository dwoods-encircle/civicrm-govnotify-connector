FROM php:8.2-fpm

# System deps + PHP extensions commonly needed by Drupal/CiviCRM
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip zip curl mariadb-client \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libicu-dev libxml2-dev libzip-dev \
    libonig-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) \
      gd intl pdo_mysql opcache zip mbstring xml \
  && pecl install apcu \
  && docker-php-ext-enable apcu \
  && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# A few sensible defaults
RUN { \
    echo "memory_limit=512M"; \
    echo "upload_max_filesize=64M"; \
    echo "post_max_size=64M"; \
    echo "max_execution_time=300"; \
  } > /usr/local/etc/php/conf.d/custom.ini

WORKDIR /var/www/html
