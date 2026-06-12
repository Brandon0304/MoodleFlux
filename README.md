# ⚡ MoodleFlux

> *Arquitectura reactiva para un LMS en flujo constante.*

**MoodleFlux** es una propuesta arquitectónica para desplegar [Moodle LMS](https://moodle.org) clásico (open source) sobre Docker con un enfoque **reactivo, resiliente y multi-tenant**. Todo el stack está diseñado para alta concurrencia, escalado horizontal y comportamiento graceful bajo carga.

---

## Stack

| Componente | Versión | Rol |
|-----------|---------|-----|
| Moodle LMS | MOODLE_500_STABLE (PHP 8.3) | Plataforma educativa |
| Nginx | 1.27+ | Proxy inverso, TLS, event-loop |
| PHP-FPM | 8.3 | Pool dinámico de workers |
| Redis | 7.x | Sesiones, caché, locks |
| MariaDB | 10.11 | Base de datos transaccional |
| Docker Compose | v2.x | Orquestación local |

---

## Principios arquitectónicos

- **Reactivo**: multi-capa con health checks, circuit breakers, degradación graceful
- **Multi-tenencia lógica**: categorías + cohorts + roles (sin Workplace, sin modificar core)
- **Seguridad por capas**: infraestructura → aplicación → datos
- **Observabilidad progresiva**: logs JSON → health endpoints → Prometheus/Grafana (futuro)
- **GitOps**: Git como fuente de verdad, despliegues versionados

---

## Estructura del repositorio

```
.
├── .agents/rules/          # Reglas del agente de arquitectura
├── .github/workflows/      # Pipelines CI/CD
├── docs/
│   ├── adr/                # Architectural Decision Records (ADRs)
│   ├── diagrams/           # Diagramas C4, infra, tenant, flujos
│   │   ├── c4/
│   │   ├── infra/
│   │   ├── tenant/
│   │   └── flujos/
│   ├── reference/          # Documentos de referencia
│   │   ├── stack/
│   │   ├── security/
│   │   ├── operations/
│   │   └── multi-tenant/
│   └── arquitectura-general.md
```

---

## Estrategia de ramas

```
main        → Producción (protegida)
develop     → Integración
feature/*   → Ramas temporales por feature
```

Toda feature se mergea vía Pull Request a `develop`. `develop` se fusiona a `main` en releases.

---

## Licencia

Proyecto académico y documental. Sin licencia específica — consultar términos de Moodle LMS (GPLv3+).
