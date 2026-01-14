FROM php:8.2-fpm

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip zip curl mariadb-client \
  && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Robust PHP extension installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
  && install-php-extensions intl gd pdo_mysql zip mbstring xml opcache bcmath sodium mysqli

RUN mkdir -p /etc/mysql/conf.d \
 && printf "[client]\nskip-ssl\nskip-ssl-verify-server-cert\n" > /etc/mysql/conf.d/disable-ssl.cnf

# Increase PHP memory limit for CiviCRM
RUN echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/memory-limit.ini

WORKDIR /var/www/html
