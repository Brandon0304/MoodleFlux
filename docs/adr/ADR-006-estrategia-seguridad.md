# ADR-006: Estrategia de Seguridad

## Estado
**Aceptado**

## Contexto
El sistema maneja datos sensibles de múltiples instituciones educativas y empresas: datos personales de estudiantes (nombres, correos, calificaciones), credenciales de acceso, contenido educativo propietario y configuraciones institucionales. Se requiere una estrategia de seguridad que cubra:

1. Protección de datos en tránsito y en reposo.
2. Gestión segura de credenciales y secrets.
3. Cumplimiento con la Ley 1581 de 2011 (Protección de Datos Personales - Colombia).
4. Aislamiento seguro entre tenants.
5. Hardening de la infraestructura Docker.

## Opciones consideradas

### Opción A: Seguridad básica por defecto (configuración mínima)
- **Pros:** Rápido de implementar, sin sobrecarga operativa.
- **Contras:** No cumple con requisitos legales (Ley 1581), vulnerable a fugas de datos entre tenants, sin trazabilidad de accesos.

### Opción B: Estrategia de seguridad en 3 capas (seleccionada)
- **Pros:**
  - Capa 1 - Infraestructura: Hardening Docker, redes aisladas, límites de recursos.
  - Capa 2 - Aplicación: Cifrado HTTPS, sesiones seguras en Redis, validación de entrada, control de acceso por roles.
  - Capa 3 - Datos: Cifrado en reposo, backups cifrados, gestión de PII según Ley 1581.
- **Contras:** Mayor complejidad operativa, requiere mantenimiento de certificados, los tenants no pueden gestionar su propio cifrado.

## Decisión
Se implementa una **estrategia de seguridad en 3 capas** con las siguientes decisiones específicas:

### 1. Seguridad de Infraestructura

| Decisión | Implementación |
|----------|---------------|
| Aislamiento de redes | `backend_net` interna sin acceso desde host (solo `frontend_net` expuesta) |
| Contenedores no root | PHP-FPM ejecutado con `user: www-data`, nunca como root |
| Límites de recursos | `mem_limit` y `cpus` configurados en cada contenedor para evitar DoS entre servicios |
| Imágenes oficiales | Solo imágenes oficiales de Docker Hub con versión fija (no `latest`) |
| Actualizaciones de seguridad | Escaneo semanal con `docker scout` o `trivy` |

### 2. Seguridad de la Aplicación

| Decisión | Implementación |
|----------|---------------|
| HTTPS | Nginx termina SSL/TLS. Local: certificado autofirmado. Producción: Let's Encrypt |
| TLS mínimo | TLS 1.2, desactivar SSLv3, TLSv1.0, TLSv1.1 |
| HSTS | `Strict-Transport-Security: max-age=31536000` en Nginx |
| Sesiones | Redis con TTL de 2h, renovación automática con actividad |
| Contraseñas | Mínimo 8 caracteres, complejidad mixta, hash bcrypt (Moodle default) |
| Bloqueo de cuenta | Tras 5 intentos fallidos, bloqueo de 15 minutos |
| CSRF | Activado (Moodle default) |
| File upload | Límite de 100MB, tipos restringidos (PDF, DOC, JPG, PNG) |

### 3. Gestión de Secrets

**NUNCA** almacenar secrets en el código o en `config.php` versionado.

```bash
# Estrategia: Variables de entorno + .env
# .env (NO versionado, agregar a .gitignore)
MYSQL_ROOT_PASSWORD=xxx
MYSQL_PASSWORD=xxx
REDIS_PASSWORD=xxx
MOODLE_ADMIN_PASS=xxx

# config.php lee desde variables de entorno
$CFG->dbpass = getenv('MYSQL_PASSWORD');
```

### 4. Protección de Datos Personales (Ley 1581)

| Requisito | Implementación |
|-----------|---------------|
| Aviso de privacidad | Pantalla de login + formulario de registro |
| Consentimiento explícito | Checkbox obligatorio al registrarse |
| Derechos ARCO | Procedimiento documentado en `docs/reference/security/01-seguridad-checklist.md` |
| Minimización de datos | Solo recolectar nombre, email y rol. No almacenar datos innecesarios |
| Retención | Datos de estudiantes retenidos por 2 años tras última actividad |
| Eliminación segura | Borrado lógico + purgado físico tras 30 días |
| Política de tratamiento | Documento público accesible desde el footer del sitio |

### 5. Aislamiento entre Tenants

| Mecanismo | Cómo se implementa |
|-----------|-------------------|
| A nivel de datos | Categorías de cursos separadas por tenant (ADR-003) |
| A nivel de aplicación | Roles personalizados con ámbito de categoría |
| A nivel de sesión | Un usuario autenticado solo ve datos de su tenant (vía cohortes) |
| A nivel de reportes | Filtros por categoría raíz en todos los reportes |

## Consecuencias

### Positivas
- Cumplimiento con Ley 1581 para operación en Colombia.
- Aislamiento seguro entre tenants sin necesidad de infraestructura separada.
- Secrets fuera del código versionado, reduciendo riesgo de exposición.
- Actualizaciones de seguridad manejables con escaneo periódico.

### Negativas
- Mayor complejidad operativa que una configuración mínima.
- Los certificados SSL requieren renovación (Let's Encrypt cada 90 días).
- El cifrado en reposo de moodledata no es nativo de Moodle (requiere cifrado a nivel de filesystem).
- Los tenants no tienen control sobre su propio cifrado (es centralizado).

## Referencias
- [ADR-003](./ADR-003-estrategia-multi-tenencia.md) — Multi-tenencia y roles
- [Ley 1581 de 2011](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=49981)
- [Moodle Security](https://docs.moodle.org/en/Security)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Docker Security](https://docs.docker.com/engine/security/)
- `docs/reference/security/01-seguridad-checklist.md`
