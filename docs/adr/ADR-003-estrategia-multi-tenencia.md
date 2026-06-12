# ADR-003: Estrategia de Multi-Tenencia para Moodle LMS Clásico

## Estado
**Aceptado**

## Contexto
El proyecto requiere que una sola instancia de Moodle LMS (versión gratuita clásica) pueda atender a **múltiples instituciones educativas o empresas** de forma aislada. Cada "tenant" debe:

- Tener sus propios cursos, usuarios, roles y configuraciones.
- No ver ni acceder a datos de otros tenants.
- Poder personalizar su apariencia (branding, logo, colores).
- Operar con su propia base de usuarios y matriculaciones.

Moodle LMS clásico **no incluye multi-tenencia nativa** (esa es una característica de Moodle Workplace, que es pago). Sin embargo, se puede lograr un aislamiento lógico mediante configuración, categorías y roles.

## Opciones consideradas

### Opción A: Instancias separadas de Moodle (una por tenant)
- **Pros:**
  - Aislamiento total de datos (físico).
  - Personalización completa por tenant.
  - Sin riesgo de fuga de datos entre tenants.
- **Contras:**
  - N instancias = N veces el consumo de recursos.
  - Mantenimiento multiplicado (actualizaciones, backups, monitorización).
  - No hay compartición de infraestructura.
  - Costo operativo lineal con el número de tenants.

### Opción B: Multi-tenencia lógica vía Categorías de Cursos + Roles + Cohorts
- **Pros:**
  - Una sola instancia, todos los tenants comparten infraestructura.
  - Moodle ya maneja categorías de cursos de forma jerárquica.
  - Se puede asignar un "tenant admin" con rol personalizado dentro de su categoría.
  - Los cohorts permiten agrupar usuarios por institución.
  - Personalización parcial: cada tenant puede tener su propio tema (theme) si se configura.
- **Contras:**
  - El aislamiento es lógico, no físico: un error en permisos podría exponer datos.
  - La personalización de branding por tenant requiere plugins adicionales o desarrollo.
  - La tabla de usuarios es compartida (todos los usuarios están en la misma tabla `mdl_user`).
  - Más complejidad administrativa al configurar roles y permisos.

### Opción C: Plugin de multi-tenencia (ej. "Multi-tenancy" de第三方 o desarrollo propio)
- **Pros:**
  - Aislamiento más fuerte sin necesidad de Workplace.
  - Posibilidad de separar tablas por tenant a nivel de plugin.
  - Experiencia similar a Workplace sin el costo de licencia.
- **Contras:**
  - Dependencia de plugins de terceros no oficiales (riesgo de seguridad, compatibilidad).
  - Desarrollo propio requiere modificar el core de Moodle, lo que complica actualizaciones.
  - No hay garantía de soporte a largo plazo.

## Decisión
Se elige la **Opción B: Multi-tenencia lógica vía Categorías + Roles + Cohorts**, complementada con un plugin de **aislamiento de sesión y datos** si es necesario. Esta opción ofrece el mejor equilibrio entre funcionalidad, mantenibilidad y cero modificaciones al core.

### Arquitectura de Tenencia

```
Moodle LMS (instancia única)
│
├── 🏢 Tenant A: "Universidad Nacional"
│   ├── Categoría: /Universidad Nacional/
│   │   ├── Curso: Matemáticas I
│   │   ├── Curso: Física II
│   │   └── Curso: Programación
│   ├── Cohorte: cohorte_universidad_nacional
│   ├── Roles: tenant_admin_A, profesor_A, estudiante_A
│   └── Tema (theme): boost_universidad (personalizado)
│
├── 🏢 Tenant B: "Empresa Capacitaciones SRL"
│   ├── Categoría: /Empresa Capacitaciones SRL/
│   │   ├── Curso: Compliance Laboral
│   │   └── Curso: Safety Training
│   ├── Cohorte: cohorte_empresa_capacitaciones
│   ├── Roles: tenant_admin_B, instructor_B, empleado_B
│   └── Tema (theme): boost_empresa (personalizado)
│
└── 🏢 Tenant C: "Colegio Secundario"
    ├── Categoría: /Colegio Secundario/
    ├── ... (misma estructura)
```

### Estrategia de Aislamiento por Tenant

| Dimensión | Estrategia | Implementación |
|-----------|------------|----------------|
| **Cursos** | Aislamiento por categoría | Cada tenant tiene una categoría raíz propia; los cursos se crean dentro de ella. Los permisos de categoría se heredan. |
| **Usuarios** | Separación por cohortes | Cada tenant tiene un cohorte. Los usuarios se asignan al cohorte de su tenant. Las visibilidades se controlan por cohorte. |
| **Roles** | Roles personalizados por tenant | Se crean roles a nivel de categoría: `tenant_admin`, `tenant_teacher`, `tenant_student`. El `tenant_admin` solo ve usuarios/cursos de su categoría. |
| **Branding** | Tema (theme) por tenant | Moodle soporta themes por categoría. Se puede asignar un theme diferente a cada categoría raíz de tenant. |
| **Autenticación** | Login único + redirección | Todos los usuarios usan el mismo login. Tras autenticarse, ven solo los cursos de su(s) tenant(s). |
| **Reportes** | Filtrados por tenant | Los reportes se generan con filtro por categoría raíz. |
| **Idioma** | Configurable por tenant | Moodle permite configuración de idioma por curso/categoría. |

### Plugin Requerido: "Tenant Isolation"
Para reforzar el aislamiento, se recomienda un **plugin local** (desarrollo mínimo) que:

1. En el hook `require_login`, verifique que el usuario pertenezca al cohorte del tenant del curso al que intenta acceder.
2. Filtre la lista de cursos disponibles para que cada usuario vea solo los de su(s) tenant(s).
3. En la página de administración de usuarios, el `tenant_admin` solo vea los usuarios de su cohorte.

Este plugin NO modifica el core de Moodle (usa APIs de hooks y events estándar) y es opcional para la primera fase de la prueba de concepto.

### Flujo de Aprovisionamiento de un Nuevo Tenant

```
1. Admin global crea categoría raíz → "/{Nombre del Tenant}/"
2. Admin global asigna theme → categoría raíz
3. Admin global crea cohorte → "cohorte_{slug_del_tenant}"
4. Admin global crea rol personalizado → "manager_{slug}" a nivel de categoría
5. Admin global crea usuario admin del tenant → con rol "manager_{slug}"
6. A partir de ahí, el admin del tenant opera autónomamente dentro de su categoría
```

### Limitaciones Conocidas
- **Tabla de usuarios única**: un usuario no puede tener el mismo email en dos tenants (es único global en `mdl_user`). Solución: usar `email + tenant_id` como identificador compuesto si se necesita, pero requiere modificar core.
- **Búsqueda global**: los resultados de búsqueda pueden mezclar contenidos de diferentes tenants si no se filtra por categoría.
- **Plugins de terceros**: algunos plugins no respetan los filtros por categoría y podrían exponer datos entre tenants.

## Consecuencias

### Positivas
- Una sola instancia de Moodle atiende N tenants sin multiplicar recursos.
- No se requiere modificar el core de Moodle (100% actualizable).
- La personalización por tenant es posible (tema, idioma, roles).
- El modelo de categorías + cohorts es escalable a cientos de tenants.
- Base para migrar a Moodle Workplace si se requiere en el futuro.

### Negativas
- El aislamiento es lógico, no físico: requiere disciplina administrativa.
- La tabla única de usuarios puede ser limitante.
- Algunos plugins podrían no respetar el aislamiento.
- El plugin de aislamiento adicional requiere desarrollo (aunque mínimo).

## Referencias
- [Moodle Course Categories](https://docs.moodle.org/en/Course_categories)
- [Moodle Cohorts](https://docs.moodle.org/en/Cohorts)
- [Moodle Roles and Permissions](https://docs.moodle.org/en/Roles)
- [Moodle Workplace Multi-tenancy](https://moodle.com/news/moodle-workplace-4-multi-tenancy/)
- [Moodle Themes per category](https://docs.moodle.org/en/Theme_settings)
