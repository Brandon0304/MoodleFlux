# Referencia: Catálogo de Plugins para Moodle LMS

## 1. Plugins para Multi-Tenencia

### Plugin de Aislamiento (desarrollo propio recomendado)
- **Tipo**: Local plugin
- **Propósito**: Reforzar el aislamiento entre tenants (ADR-003)
- **Funcionalidad**:
  - Filtrar listado de cursos por cohorte/tenant
  - Restringir visibilidad de usuarios entre tenants
  - Forzar que un tenant admin solo vea su categoría
- **Complejidad**: Baja (usa APIs de hooks estándar de Moodle)
- **Mantenimiento**: Compatible con actualizaciones de Moodle (no toca core)

### Plugins de Terceros Evaluados

| Plugin | Propósito | Riesgo | Recomendado |
|--------|-----------|--------|:-----------:|
| **Local_Metadata** | Campos personalizados por tenant | Bajo | ✅ |
| **Theme selector by category** | Theme por categoría | Bajo | ✅ |
| **Cohort UI** | Gestión mejorada de cohorts | Bajo | ✅ |
| **Restrict access by cohort** | Acceso condicional por cohorte | Bajo | ✅ |

## 2. Plugines para Branding por Tenant

| Plugin | Propósito | Recomendado |
|--------|-----------|:-----------:|
| **Custom menu per category** | Menú personalizado por tenant | Sí |
| **Logo per category** | Logo diferente por categoría | Sí |
| **Custom CSS per category** | CSS personalizado por tenant | Sí |

## 3. Plugins para Rendimiento

| Plugin | Propósito | Recomendado |
|--------|-----------|:-----------:|
| **Local objectfs** | Almacenamiento de objetos S3/MinIO (reemplazo futuro de NFS) | Evaluar |
| **Cachestore redis** | Ya incluido en Moodle core | ✅ Ya en uso |
| **Session redis** | Ya incluido en Moodle core | ✅ Ya en uso |
| **Tool_opcache** | Gestión de OPcache | Sí |

## 4. Plugins para Reportes y Analítica

| Plugin | Propósito | Recomendado |
|--------|-----------|:-----------:|
| **Configurable reports** | Reportes personalizados | Sí |
| **Dashboard** | Dashboards por tenant | Sí |
| **Logstore_standard** | Logs estándar (incluido) | ✅ |
| **Logstore_database** | Logs a BD externa | Evaluar |

## 5. Plugins para Integración

| Plugin | Propósito | Recomendado |
|--------|-----------|:-----------:|
| **LDAP auth** | Autenticación contra LDAP/AD | Sí |
| **SAML auth** | SSO corporativo | Sí |
| **IMS Common Cartridge** | Importación/exportación de cursos | Sí |

## 6. Criterios para Seleccionar un Plugin

1. ✅ **Disponible en el directorio oficial** de Moodle (moodle.org/plugins)
2. ✅ **Compatible con la versión de Moodle** (5.0+)
3. ✅ **Mantenimiento activo** (actualizado en los últimos 12 meses)
4. ✅ **No modifica el core** de Moodle (usa APIs estándar)
5. ✅ **Calificación de la comunidad** ≥ 4.0 estrellas
6. ❌ **Evitar plugins que**:
   - Requieran parchear archivos del core
   - No tengan release reciente
   - Tengan reportes de seguridad abiertos

## 7. Proceso de Instalación

```bash
# Los plugins se instalan en:
moodle/
├── local/     # Plugins locales
├── mod/       # Módulos de actividad
├── block/     # Bloques
├── theme/     # Temas
└── auth/      # Autenticación

# Instalación típica:
cd moodle
git clone https://github.com/owner/moodle-plugin_local_xxx.git local/xxx
# Luego ir a: Admin → Notificaciones para instalar
```

## Referencias
- https://moodle.org/plugins/
- https://docs.moodle.org/en/Installing_plugins
- https://moodle.org/plugins/pluginversions.php
