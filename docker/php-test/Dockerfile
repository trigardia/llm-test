FROM php:8.3-cli-alpine

RUN apk add --no-cache \
    git curl unzip bash libzip-dev icu-dev oniguruma-dev \
    && docker-php-ext-install zip intl mbstring bcmath pcntl \
    && pecl install redis \
    && docker-php-ext-enable redis

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Symfony CLI
RUN curl -sS https://get.symfony.com/cli/installer | bash \
    && mv /root/.symfony*/bin/symfony /usr/local/bin/symfony

WORKDIR /app

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV APP_ENV=test
