<?php
/**
 * Idempotently applies OJS [email] settings from environment when OJS_SMTP_SERVER is set.
 * Invoked from entrypoint; exits quietly if config is missing or SMTP is not configured.
 */
declare(strict_types=1);

$server = getenv('OJS_SMTP_SERVER') ?: '';
if ($server === '') {
    exit(0);
}

$path = '/var/www/html/config.inc.php';
if (!is_readable($path) || !is_writable($path)) {
    exit(0);
}

$port = getenv('OJS_SMTP_PORT') ?: '587';
$authRaw = getenv('OJS_SMTP_AUTH');
$auth = $authRaw === false ? 'tls' : $authRaw;
$user = getenv('OJS_SMTP_USERNAME') ?: '';
$pass = getenv('OJS_SMTP_PASSWORD') ?: '';
$from = getenv('OJS_SMTP_DEFAULT_ENVELOPE_SENDER') ?: '';
$allowEnv = getenv('OJS_SMTP_ALLOW_ENVELOPE_SENDER') ?: 'On';
$forceEnv = getenv('OJS_SMTP_FORCE_DEFAULT_ENVELOPE_SENDER') ?: 'Off';

$updates = [
    'default' => 'smtp',
    'smtp' => 'On',
    'smtp_server' => $server,
    'smtp_port' => $port,
    'smtp_username' => $user,
    'smtp_password' => $pass,
    'allow_envelope_sender' => $allowEnv,
    'force_default_envelope_sender' => $forceEnv,
];

$authLower = strtolower(trim($auth));
if ($authLower !== '' && $authLower !== 'none') {
    $updates['smtp_auth'] = $auth;
}

if ($from !== '') {
    $updates['default_envelope_sender'] = $from;
}

$lines = file($path, FILE_IGNORE_NEW_LINES);
if ($lines === false) {
    exit(0);
}

$inEmail = false;
/** @var array<string, bool> */
$seen = array_fill_keys(array_keys($updates), false);
$out = [];

foreach ($lines as $line) {
    if (preg_match('/^\[email\]\s*$/', $line)) {
        $inEmail = true;
        $out[] = $line;
        continue;
    }

    if ($inEmail && preg_match('/^\[[^\]]+\]\s*$/', $line)) {
        foreach ($updates as $k => $v) {
            if (!$seen[$k]) {
                $out[] = $k . ' = ' . formatIniValue($v);
                $seen[$k] = true;
            }
        }
        $inEmail = false;
        $out[] = $line;
        continue;
    }

    if ($inEmail && preg_match('/^\s*;?\s*([a-zA-Z0-9_]+)\s*=.*$/', $line, $m)) {
        $k = $m[1];
        if (array_key_exists($k, $updates)) {
            $line = $k . ' = ' . formatIniValue($updates[$k]);
            $seen[$k] = true;
        }
    }

    $out[] = $line;
}

if ($inEmail) {
    foreach ($updates as $k => $v) {
        if (!$seen[$k]) {
            $out[] = $k . ' = ' . formatIniValue($v);
        }
    }
}

file_put_contents($path, implode("\n", $out) . "\n");

/**
 * @param non-empty-string|'' $v
 */
function formatIniValue(string $v): string
{
    if ($v === '') {
        return '""';
    }
    if (preg_match('/^[A-Za-z0-9._@+-]+$/', $v)) {
        return $v;
    }

    return '"' . addcslashes($v, "\\\"\n\r") . '"';
}
