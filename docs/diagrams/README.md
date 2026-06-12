# Diagramas Arquitectónicos — Moodle LMS Reactivo Multi-Tenant

## Estructura

```
diagrams/
├── README.md              ← Este archivo (mapa de diagramas)
├── index.html             ← Galería visual (abrir en navegador)
│
├── c4/                    ← C4 Model (3 niveles)
│   ├── 01-contexto.{svg,mmd,puml}
│   ├── 02-contenedores.{svg,mmd,puml}
│   └── 03-componentes.{svg,mmd}
│
├── infra/                 ← Infraestructura Docker y resiliencia
│   ├── 01-red-puertos.{svg,mmd}
│   └── 02-resiliencia-estados.{svg,mmd}
│
├── tenant/                ← Multi-tenencia
│   ├── 01-arquitectura-multi-tenant.{svg,mmd,puml}
│   └── 02-aprovisionamiento-tenant.{svg,mmd}
│
└── flujos/                ← Diagramas de secuencia
    └── 01-flujo-solicitud.{svg,mmd}
```

## Mapa de Diagramas

| # | Diagrama | Carpeta | Formatos | Propósito |
|---|----------|---------|----------|-----------|
| 1 | Contexto C4 | `c4/01-contexto.*` | SVG, MMD, PUML | Actores del sistema e interacciones externas |
| 2 | Contenedores C4 | `c4/02-contenedores.*` | SVG, MMD, PUML | Arquitectura Docker (Nginx → PHP-FPM → Redis → MariaDB → moodledata) |
| 3 | Componentes C4 N3 | `c4/03-componentes.*` | SVG, MMD | Módulos PHP de Moodle con conexiones al stack reactivo |
| 4 | Red y Puertos Docker | `infra/01-red-puertos.*` | SVG, MMD | Topología de redes, puertos y volúmenes Docker |
| 5 | Resiliencia / Estados | `infra/02-resiliencia-estados.*` | SVG, MMD | Máquina de estados: comportamiento ante fallos |
| 6 | Multi-Tenant | `tenant/01-arquitectura-multi-tenant.*` | SVG, MMD, PUML | Aislamiento lógico de 3 instituciones |
| 7 | Aprovisionamiento Tenant | `tenant/02-aprovisionamiento-tenant.*` | SVG, MMD | Flujo: nuevo cliente → tenant operativo |
| 8 | Flujo de Solicitud | `flujos/01-flujo-solicitud.*` | SVG, MMD | Secuencia request bajo alta carga con caché |

## Formatos

- **SVG**: Imagen vectorial renderizada (abrir en navegador o visor de imágenes)
- **MMD**: Código fuente Mermaid.js (editable, renderizable con `npx @mermaid-js/mermaid-cli`)
- **PUML**: Código fuente PlantUML (editable, renderizable con `java -jar plantuml.jar`)

## Cómo Renderizar desde Fuente

```bash
# Mermaid (MMD → SVG)
export PUPPETEER_EXECUTABLE_PATH=/home/brandon/.cache/puppeteer/chrome/linux-149.0.7827.22/chrome-linux64/chrome
npx @mermaid-js/mermaid-cli -i archivo.mmd -o archivo.svg

# PlantUML (PUML → PNG/SVG)
java -jar plantuml.jar archivo.puml
```
