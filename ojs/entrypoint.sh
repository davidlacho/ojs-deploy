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

# Optional SMTP from environment (e.g. GitHub Actions secrets written to .env on deploy).
if [ -f "$CONFIG_FILE" ] && [ -n "${OJS_SMTP_SERVER:-}" ]; then
  php /usr/local/bin/configure-smtp.php
fi

# Ensure Bootstrap3 theme plugin exists on the persistent app volume.
BOOTSTRAP3_DIR="/var/www/html/plugins/themes/bootstrap3"
if [ ! -d "$BOOTSTRAP3_DIR" ]; then
  git clone --depth 1 https://github.com/pkp/bootstrap3.git "$BOOTSTRAP3_DIR"
  chown -R www-data:www-data "$BOOTSTRAP3_DIR" || true
fi

# Optional idempotent theme activation for one journal, controlled by env.
if [ -n "${OJS_JOURNAL_PATH:-}" ] && [ -n "${OJS_JOURNAL_THEME:-}" ] && [ -f "$CONFIG_FILE" ]; then
  php <<'PHP'
<?php
$cfg = parse_ini_file('/var/www/html/config.inc.php', true, INI_SCANNER_RAW);
if (!$cfg || empty($cfg['database'])) {
    exit(0);
}
$db = $cfg['database'];
$dsn = 'mysql:host=' . $db['host'] . ';dbname=' . $db['name'] . ';charset=utf8mb4';
try {
    $pdo = new PDO($dsn, $db['username'], $db['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    exit(0);
}
$journalPath = getenv('OJS_JOURNAL_PATH') ?: '';
$themePath = getenv('OJS_JOURNAL_THEME') ?: '';
if ($journalPath === '' || $themePath === '') {
    exit(0);
}
$themePluginMap = [
    'default' => 'defaultthemeplugin',
    'bootstrap3' => 'bootstrapthreethemeplugin',
];
$pluginName = $themePluginMap[$themePath] ?? null;
if (!$pluginName) {
    exit(0);
}

$stmt = $pdo->prepare('SELECT journal_id FROM journals WHERE path = ? LIMIT 1');
$stmt->execute([$journalPath]);
$journalId = (int) $stmt->fetchColumn();
if (!$journalId) {
    exit(0);
}

$pdo->beginTransaction();

$upd = $pdo->prepare('UPDATE journal_settings SET setting_value = ? WHERE journal_id = ? AND setting_name = "themePluginPath"');
$upd->execute([$themePath, $journalId]);
if ($upd->rowCount() === 0) {
    $ins = $pdo->prepare('INSERT INTO journal_settings (journal_id, locale, setting_name, setting_value) VALUES (?, ?, "themePluginPath", ?)');
    $ins->execute([$journalId, '', $themePath]);
}

$updPlugin = $pdo->prepare('UPDATE plugin_settings SET setting_value = "1", setting_type = "bool" WHERE plugin_name = ? AND context_id = ? AND setting_name = "enabled"');
$updPlugin->execute([$pluginName, $journalId]);
if ($updPlugin->rowCount() === 0) {
    $insPlugin = $pdo->prepare('INSERT INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES (?, ?, "enabled", "1", "bool")');
    $insPlugin->execute([$pluginName, $journalId]);
}

$pdo->commit();
PHP

  rm -rf /var/www/html/cache/t_compile/* /var/www/html/cache/_db 2>/dev/null || true
  mkdir -p /var/www/html/cache/_db
  chown -R www-data:www-data /var/www/html/cache || true
fi

exec "$@"

