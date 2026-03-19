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

exec "$@"

