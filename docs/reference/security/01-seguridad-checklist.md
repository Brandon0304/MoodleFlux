# Referencia: Checklist de Seguridad para Moodle LMS

## 1. Seguridad de la Aplicación (OWASP Top 10)

### 1.1 Control de Acceso
- [ ] **Roles y permisos**: Verificar que los roles personalizados por tenant (ADR-003) tengan permisos mínimos necesarios
- [ ] **Principio de mínimo privilegio**: Ningún rol debe tener permisos que no necesite
- [ ] **Protección de rutas administrativas**: `/admin/` debe requerir autenticación y rol adecuado
- [ ] **CSRF Protection**: Moodle la tiene incorporada, verificar que esté activa

### 1.2 Autenticación y Sesiones
- [ ] **Sesiones en Redis**: Configuradas según ADR-004
- [ ] **TTL de sesiones**: Configurar tiempo de expiración razonable (recomendado: 2h inactividad)
- [ ] **Política de contraseñas**: Configurar complejidad mínima en Moodle
- [ ] **MFA**: Evaluar si se requiere autenticación multifactor
- [ ] **Bloqueo por intentos fallidos**: Configurar account lockout tras N intentos

### 1.3 Validación de Entrada
- [ ] **XSS**: Moodle tiene filtros de salida (output escaping), mantenerlos activos
- [ ] **SQL Injection**: Moodle usa prepared statements (conectores actualizados)
- [ ] **File Upload**: Limitar tamaños y tipos de archivo en moodledata
- [ ] **Path Traversal**: Verificar que moodledata no sea accesible desde la web

### 1.4 Configuración de Seguridad de Moodle

Configuraciones recomendadas en Admin → Seguridad:

| Configuración | Valor Recomendado |
|--------------|-------------------|
| `protectusernames` | Activado |
| `cronclionly` | Activado (solo CLI para cron) |
| `disableusercreation` | Desactivado (según necesidad del tenant) |
| `enabletrusttext` | Desactivado |
| `allowobjectembed` | Desactivado |
| `enablewebservices` | Solo si se necesitan |
| `enablerssfeeds` | Desactivado (si no se usa) |

## 2. Seguridad de Infraestructura

### 2.1 Contenedores Docker
- [ ] **Imágenes oficiales**: Usar solo imágenes oficiales de Moodle, Nginx, Redis, MariaDB
- [ ] **Versiones específicas**: NO usar `latest`, fijar versión exacta (ej: `mariadb:10.11` no `mariadb:latest`)
- [ ] **Redes aisladas**: `backend_net` NO debe tener acceso desde el host (solo `frontend_net`)
- [ ] **Volúmenes**: moodledata no debe ser world-readable
- [ ] **Recursos limitados**: Configurar `mem_limit` y `cpus` en docker-compose para evitar DoS entre contenedores
- [ ] **No correr como root**: El proceso PHP-FPM debe ejecutarse con `user: www-data`

### 2.2 Base de Datos
- [ ] **Puerto no expuesto**: MariaDB (3306) solo accesible desde `backend_net`, NO desde el host
- [ ] **Usuario dedicado**: Crear usuario `moodle` con permisos solo sobre la base `moodle`
- [ ] **Root password**: Cambiar contraseña root por defecto
- [ ] **Cifrado en tránsito**: Para entornos no locales, usar TLS entre PHP-FPM y MariaDB

### 2.3 Redis
- [ ] **Puerto no expuesto**: Redis (6379) solo en `backend_net`
- [ ] **Password**: Configurar `requirepass` en Redis para entornos no locales
- [ ] **Comando FLUSHALL**: Renombrar o desactivar comandos peligrosos en producción

## 3. Protección de Datos Personales

### 3.1 Ley 1581 de 2011 (Colombia - Habeas Data)
- [ ] **Aviso de privacidad**: Visible en el login y registro
- [ ] **Autorización explícita**: Consentimiento del usuario para tratamiento de datos
- [ ] **Finalidad**: Especificar para qué se usan los datos (educación, calificaciones, etc.)
- [ ] **Derechos ARCO**: Acceso, Rectificación, Cancelación, Oposición — implementar procedimiento
- [ ] **Política de tratamiento**: Documento disponible y accesible
- [ ] **Periodo de retención**: Definir cuánto tiempo se conservan los datos de estudiantes
- [ ] **Eliminación segura**: Procedimiento para eliminar datos cuando se solicite

### 3.2 GDPR (si aplica)
- [ ] **Data Processing Agreement** (DPA) entre el operador y el responsable
- [ ] **Derecho al olvido**: Eliminación completa del usuario y sus datos
- [ ] **Portabilidad**: Exportación de datos del usuario en formato estándar
- [ ] **Breach notification**: Procedimiento para notificar violaciones de datos

## 4. Cifrado

### 4.1 En Tránsito
- [ ] **HTTPS**: Nginx debe terminar SSL/TLS (certificado autofirmado para local, Let's Encrypt para producción)
- [ ] **TLS 1.2/1.3**: Desactivar SSLv3, TLSv1.0, TLSv1.1
- [ ] **HSTS**: Configurar `Strict-Transport-Security` en Nginx

### 4.2 En Reposo
- [ ] **Base de datos**: MariaDB cifrado en reposo (Transparent Data Encryption) para datos sensibles
- [ ] **moodledata**: Cifrado de archivos sensibles (calificaciones, datos personales)
- [ ] **Backups**: Cifrar backups, especialmente si van a almacenamiento externo

## 5. Hardening de Contenedores

```dockerfile
# Prácticas recomendadas (conceptual)
FROM php:8.3-fpm-alpine

# No correr como root
USER www-data

# Sistema de archivos de solo lectura para el código
# (el moodledata va en volumen separado)
```

## 6. Auditoría y Logs

- [ ] **Logs de acceso**: Nginx access log con IP, ruta, user agent
- [ ] **Logs de error**: PHP-FPM error log
- [ ] **Logs de base de datos**: MariaDB slow query log
- [ ] **Logs de aplicación**: Moodle logging (Admin → Reports → Logs)
- [ ] **Retención de logs**: Definir política (mínimo 90 días)

## Referencias
- https://docs.moodle.org/en/Security
- https://owasp.org/www-project-top-ten/
- https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=49981 (Ley 1581)
- https://docs.docker.com/engine/security/
- https://mariadb.com/kb/en/securing-mariadb/
