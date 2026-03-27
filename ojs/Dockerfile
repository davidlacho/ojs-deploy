FROM php:8.2-apache

# OJS runs on Apache + PHP. This image builds OJS from a PKP tar.gz release.

ARG OJS_TARBALL_URL
ENV OJS_TARBALL_URL="${OJS_TARBALL_URL}"

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    curl ca-certificates tar git \
    pkg-config \
    libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev libxml2-dev \
    libcurl4-openssl-dev libonig-dev \
  && rm -rf /var/lib/apt/lists/*

# PHP extensions needed by OJS deployments.
RUN docker-php-ext-configure gd \
  && docker-php-ext-install \
    intl mbstring pdo pdo_mysql mysqli xml zip gd curl bcmath ftp

RUN a2enmod rewrite headers ssl >/dev/null 2>&1 || true

# Create an uploads directory outside the web root.
RUN mkdir -p /var/ojs-files/public \
  && chown -R www-data:www-data /var/ojs-files

WORKDIR /var/www/html

# Download and unpack OJS into the image.
# Tarballs typically contain a single top-level directory; --strip-components=1 removes it.
RUN if [ -z "${OJS_TARBALL_URL}" ]; then echo "OJS_TARBALL_URL build arg is required" && exit 1; fi \
  && curl -fsSL "${OJS_TARBALL_URL}" -o /tmp/ojs.tar.gz \
  && tar -xzf /tmp/ojs.tar.gz --strip-components=1 -C /var/www/html \
  && rm -f /tmp/ojs.tar.gz \
  && chown -R www-data:www-data /var/www/html

# If OJS installer creates config and other files in the persistent volume,
# this entrypoint fixes permissions once and then starts Apache.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]

