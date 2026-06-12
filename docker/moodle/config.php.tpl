<?php
// =============================================================================
// MoodleFlux - config.php (generado desde template)
// Basado en: ADR-001, ADR-004, ADR-005, ADR-006
// =============================================================================

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = '${MOODLE_DB_HOST}';
$CFG->dbname    = '${MOODLE_DB_NAME}';
$CFG->dbuser    = '${MOODLE_DB_USER}';
$CFG->dbpass    = '${MOODLE_DB_PASS}';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = [
    'dbpersist'  => false,
    'dbsocket'   => false,
    'dbport'     => 3306,
    'dbcollation' => 'utf8mb4_unicode_ci',
    'readonly'   => [],
];

$CFG->wwwroot   = '${MOODLE_WWWROOT:-https://localhost}';
$CFG->dataroot  = '/var/www/moodledata';
$CFG->dirroot   = '/var/www/html';
$CFG->libdir    = '/var/www/html/lib';
$CFG->localcachedir = '/tmp/moodle_localcache';
$CFG->tempdir   = '/tmp/moodle_temp';
$CFG->cachedir  = '/tmp/moodle_cache';
$CFG->admin     = 'admin';

$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host    = '${REDIS_HOST}';
$CFG->session_redis_port    = ${REDIS_PORT};
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix  = 'MOODLE_SESSION_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;

$CFG->cache_store_redis_1 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache1_',
    'database' => 1,
]);
$CFG->cache_store_redis_2 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache2_',
    'database' => 2,
]);
$CFG->cache_store_redis_3 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache3_',
    'database' => 3,
]);

$CFG->lock_factory = '\\core\\lock\\redis_lock_factory';
$CFG->lock_redis_host = '${REDIS_HOST}';
$CFG->lock_redis_port = ${REDIS_PORT};
$CFG->lock_redis_database = 4;

$CFG->siteidentifier = 'MoodleFlux_PoC';
$CFG->sitename = '${MOODLE_SITE_NAME:-MoodleFlux PoC}';
$CFG->lang = '${MOODLE_LANG:-es}';
$CFG->country = 'CO';
$CFG->timezone = '${TZ:-America/Bogota}';

$CFG->ssl_encrypt = true;
$CFG->loginhttps = true;
$CFG->cronclionly = true;
$CFG->preventexecpath = true;
$CFG->passwordpolicy = true;
$CFG->minpasswordlength = 8;
$CFG->disableuserimages = false;
$CFG->allowthemechangeonurl = false;
$CFG->rememberusername = 2;

$CFG->smtphosts = 'mailpit:1025';
$CFG->smtpsecure = 'none';
$CFG->smtpauthtype = 'LOGIN';
$CFG->smtpuser = '';
$CFG->smtppass = '';
$CFG->noreplyaddress = 'noreply@moodleflux.local';

$CFG->pathtophp = '/usr/local/bin/php';
$CFG->pathtodu = '/usr/bin/du';
$CFG->pathtodot = '/usr/bin/dot';
$CFG->aspellpath = '/usr/bin/aspell';
$CFG->pathtogs = '/usr/bin/gs';
$CFG->pathtopgit = '/usr/bin/git';
$CFG->cronremotepassword = '';
$CFG->tool_generator_users_password = 'moodleflux2026';

$CFG->debug = (E_ALL & ~E_DEPRECATED & ~E_STRICT);
$CFG->debugdisplay = 0;
$CFG->debugsmtp = 0;
$CFG->perfdebug = 0;
$CFG->langstringcache = true;

$CFG->local_tenant_isolation_enabled = false;

$CFG->passwordsaltmain = '${MOODLE_PASSWORD_SALT:-changeme_in_production}';

require_once(__DIR__ . '/lib/setup.php');
