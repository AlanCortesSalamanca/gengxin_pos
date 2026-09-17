# Ejecucion schema PostgreSQL v0.5-db-3

Estado: EJECUCION DE SCHEMA: VALIDADA.

Este documento registra hechos observados durante la ejecucion real de `database/schema-v0.5-db-3.sql` contra una base temporal de validacion. No marca todavia todo db-3 como VALIDADO / CONGELADO, porque falta documentar formalmente la suite de integridad db-3.

## Contexto

- Contenedor: `gengxin-postgres`.
- Estado observado: running / healthy.
- Version PostgreSQL: PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2).
- Base temporal utilizada: `gengxin_pos_db3_test`.
- Archivo ejecutado: `database/schema-v0.5-db-3.sql`.
- Modo de ejecucion: `psql` con `ON_ERROR_STOP=1`.

`gengxin_pos_db3_test` es una base temporal de validacion. No es una base de produccion.

## Resultado del schema

`database/schema-v0.5-db-3.sql` se ejecuto correctamente en PostgreSQL 17.11 y termino en `COMMIT`.

No se observaron errores `ERROR` ni `FATAL` durante la ejecucion del DDL.

## Delta db-3 verificado

Se verifico en `information_schema.columns` la existencia de la columna nueva en `returns`:

| table_name | column_name | data_type | is_nullable |
| --- | --- | --- | --- |
| returns | client_operation_id | text | NO |

Esto confirma que `returns.client_operation_id` existe como `TEXT NOT NULL`.

## UNIQUE verificada

PostgreSQL reporto la constraint:

- Nombre: `uq_returns_client_operation`.
- Definicion: `UNIQUE (branch_id, client_operation_id)`.

La unicidad es por sucursal. `client_operation_id` no es globalmente unico.

## Conteos observados

Conteos observados como evidencia complementaria de ejecucion:

- Tablas public/user-defined: 51.
- Enums PostgreSQL en `public`: 19.

Estos conteos no son por si solos un mecanismo suficiente de validacion. Solo complementan la evidencia de que db-3 conserva la estructura general esperada de db-2.

## Alcance

Este documento prueba unicamente:

- que `database/schema-v0.5-db-3.sql` es ejecutable;
- que PostgreSQL acepta el DDL;
- que el nuevo campo existe con tipo y nullability esperados;
- que la nueva UNIQUE existe;
- que los conteos estructurales observados son coherentes.

El resultado detallado de `database/validation-v0.5-db-3.sql` no se documenta aqui. Tendra su propio documento: `docs/database/validacion-integridad-v0.5-db-3.md`.

## Referencias

- `docs/database/modelo-fisico-v0.5-db-3.md`.
- `database/schema-v0.5-db-3.sql`.

db-3 deriva de db-2 y agrega la identidad logica persistente de devoluciones mediante `returns.client_operation_id` y `uq_returns_client_operation`.
