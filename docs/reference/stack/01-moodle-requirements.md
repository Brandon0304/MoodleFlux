# Requisitos Oficiales de Moodle LMS

## Versión Target: Moodle 5.0 (rama MOODLE_500_STABLE)

Fuente oficial: https://docs.moodle.org/dev/Moodle_5.0_release_notes

## Requisitos de Servidor Web

| Servidor | Soportado | Recomendado | Notas |
|----------|-----------|-------------|-------|
| Nginx | ✅ | **Sí** | Con PHP-FPM |
| Apache | ✅ | Sí | Con mod_php o PHP-FPM |
| IIS | ✅ | No | Solo Windows |

**Decisión del proyecto**: Nginx (ver ADR-001)

## Requisitos de PHP

| Componente | Versión Mínima | Versión Recomendada |
|------------|---------------|---------------------|
| PHP | 8.1 | **8.3** |
| PHP-FPM | Incluido | **Sí** |

### Extensiones PHP Obligatorias
```
curl, hash, iconv, json, mbstring, openssl, pcre, session, spl, standard,
dom, fileinfo, gd, intl, libxml, pdo, simplexml, xml, xmlrpc, zip, zlib,
soap, tokenizer, redis (para Redis cache store)
```

### Extensiones Recomendadas
```
opcache, apcu (caché local), redis (conexión a Redis), pgsql o mysqli
```

## Requisitos de Base de Datos

| Motor | Versión Mínima | Recomendada | Notas |
|-------|---------------|-------------|-------|
| MariaDB | 10.6.7 | **10.11** | ✅ Seleccionada |
| MySQL | 8.0 | 8.0 | |
| PostgreSQL | 13 | 16 | Alternativa viable |
| MSSQL | 2017 | 2019+ | |
| Oracle | 19c | 19c+ | Solo legacy |

## Requisitos de Caché

| Store | Versión | Propósito |
|-------|---------|-----------|
| Redis | 7.x | Sesiones, aplicación, locks |
| Memcached | 1.x | Alternativa (no seleccionada) |

## Almacenamiento

- **moodledata**: Sistema de archivos compartido (NFS, EFS, o volumen Docker)
- **Espacio mínimo**: 1 GB para código + 5 GB para datos (escalable)
- **Requerimiento clave**: Escritura rápida, baja latencia

## Referencias
- https://docs.moodle.org/dev/Moodle_5.0_release_notes
- https://docs.moodle.org/en/Installing_Moodle
- https://docs.moodle.org/en/Installing_Moodle#PHP_Extensions
