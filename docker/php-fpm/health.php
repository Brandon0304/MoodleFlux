<?php
// =============================================================================
// MoodleFlux - Health Check Endpoint
// Basado en: ADR-008 (verifica PHP-FPM, Redis, MariaDB, moodledata)
// =============================================================================
header('Content-Type: application/json');
header('Cache-Control: no-cache, must-revalidate');

$status = 'OK';
$httpCode = 200;
$checks = [];

$checks['php-fpm'] = [
    'status' => 'healthy',
    'php_version' => PHP_VERSION,
];

try {
    $redis = new Redis();
    $redis->connect(
        getenv('REDIS_HOST') ?: 'redis',
        (int)(getenv('REDIS_PORT') ?: 6379),
        3
    );
    $info = $redis->info('stats');
    $clients = $redis->info('clients');
    $checks['redis'] = [
        'status' => 'healthy',
        'connected_clients' => (int)($clients['connected_clients'] ?? 0),
        'hit_rate_pct' => isset($info['keyspace_hits'], $info['keyspace_misses'])
            ? round(($info['keyspace_hits'] / max(1, $info['keyspace_hits'] + $info['keyspace_misses'])) * 100, 1)
            : 0,
    ];
    $redis->close();
} catch (Exception $e) {
    $checks['redis'] = ['status' => 'unhealthy', 'error' => $e->getMessage()];
    $status = 'DEGRADED';
    $httpCode = 503;
}

try {
    $mysqli = new mysqli(
        getenv('MOODLE_DB_HOST') ?: 'mariadb',
        getenv('MOODLE_DB_USER') ?: 'moodle',
        getenv('MOODLE_DB_PASS') ?: '',
        getenv('MOODLE_DB_NAME') ?: 'moodle',
        3306
    );
    if ($mysqli->connect_error) {
        throw new Exception($mysqli->connect_error);
    }
    $result = $mysqli->query("SELECT VERSION() as version");
    $row = $result->fetch_assoc();
    $result2 = $mysqli->query("SHOW STATUS LIKE 'Threads_connected'");
    $row2 = $result2->fetch_assoc();
    $checks['mariadb'] = [
        'status' => 'healthy',
        'version' => $row['version'],
        'connections' => (int)$row2['Value'],
    ];
    $mysqli->close();
} catch (Exception $e) {
    $checks['mariadb'] = ['status' => 'unhealthy', 'error' => $e->getMessage()];
    $status = 'DEGRADED';
    $httpCode = 503;
}

$moodledata = '/var/www/moodledata';
$checks['moodledata'] = [
    'status' => is_dir($moodledata) && is_writable($moodledata) ? 'healthy' : 'unhealthy',
    'disk_usage_pct' => round((1 - disk_free_space($moodledata) / disk_total_space($moodledata)) * 100, 1),
];

http_response_code($httpCode);
echo json_encode([
    'status' => $status,
    'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
    'checks' => $checks,
], JSON_PRETTY_PRINT);
