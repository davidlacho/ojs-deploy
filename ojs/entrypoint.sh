#!/bin/sh
set -eu

# The OJS application lives on a named volume mounted at /var/www/html.
# On first boot, ensure it is writable by Apache.
PERM_MARKER="/var/www/html/.permfix_done"
if [ ! -f "$PERM_MARKER" ]; then
  chown -R www-data:www-data /var/www/html
  chmod -R g+rwX /var/www/html || true
  touch "$PERM_MARKER"
fi

# Ensure uploads root exists (mounted at /var/ojs-files).
mkdir -p /var/ojs-files /var/ojs-files/public
chown -R www-data:www-data /var/ojs-files || true

# Behind Traefik, map forwarded proto to HTTPS for PHP/OJS.
cat > /etc/apache2/conf-enabled/forwarded-proto.conf <<'APACHECONF'
SetEnvIf X-Forwarded-Proto "https" HTTPS=on
APACHECONF

# Keep host allow-list declarative for reverse-proxy deployments.
CONFIG_FILE="/var/www/html/config.inc.php"
if [ -n "${OJS_HOSTNAME:-}" ] && [ -f "$CONFIG_FILE" ]; then
  ALLOWED_JSON="[\"${OJS_HOSTNAME}\",\"www.${OJS_HOSTNAME}\"]"
  sed -i \
    -e "s#^allowed_hosts[[:space:]]*=.*#allowed_hosts = '${ALLOWED_JSON}'#" \
    -e "s#^base_url[[:space:]]*=.*#base_url = \"https://${OJS_HOSTNAME}\"#" \
    -e "s#^force_ssl[[:space:]]*=.*#force_ssl = On#" \
    "$CONFIG_FILE"
fi

exec "$@"

