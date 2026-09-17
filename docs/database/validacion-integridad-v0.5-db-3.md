# Validacion de integridad PostgreSQL v0.5-db-3

Estado: VALIDACION DE INTEGRIDAD: VALIDADA.

Este documento registra hechos observados durante la ejecucion real de `database/validation-v0.5-db-3.sql` contra una base temporal de validacion. No marca todavia todo db-3 como VALIDADO / CONGELADO; ese estado se decidira despues de revisar conjuntamente modelo fisico, schema, ejecucion, validation y documentacion de validacion.

## Contexto de ejecucion

- Contenedor: `gengxin-postgres`.
- Estado observado: running / healthy.
- PostgreSQL: PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2).
- Base temporal: `gengxin_pos_db3_test`.
- Archivo validado: `database/validation-v0.5-db-3.sql`.
- Modo de ejecucion: `psql` con `ON_ERROR_STOP=1`.

## Resultado global

`database/validation-v0.5-db-3.sql` ejecuto correctamente.

Salida estructural observada:

```text
BEGIN
DO
ROLLBACK
```

El `ROLLBACK` fue intencional y forma parte del diseno de la suite para descartar fixtures temporales. No representa un error.

## Validaciones heredadas de db-2

`database/validation-v0.5-db-3.sql` deriva directamente de `database/validation-v0.5-db-2.sql` y conserva las validaciones previas.

La evidencia global observada es que el bloque `DO` completo termino sin lanzar la excepcion final de validaciones fallidas.

## Nueva prueba NOT NULL

Se valido que `returns.client_operation_id` es obligatorio.

La suite intento insertar una devolucion sin `client_operation_id` y PostgreSQL rechazo la operacion mediante la restriccion `NOT NULL`.

Resultado: PASO.

## Nueva prueba UNIQUE misma sucursal

Se valido la unicidad `(branch_id, client_operation_id)` en `returns`.

Fixture:

- `client_operation_id = 'return-op-shared'`.

Primera devolucion branch A:

- `folio = 'DEV-A-001'`.
- Resultado: aceptada.

Segundo intento branch A:

- `folio = 'DEV-A-002'`.
- Mismo `client_operation_id = 'return-op-shared'`.
- Resultado esperado y observado por la suite: rechazado por `unique_violation`.

Los folios `DEV-A-001` y `DEV-A-002` eran diferentes, por lo que la prueba no dependia de `uq_returns_branch_folio`.

Resultado: PASO.

## Mismo client_operation_id en otra sucursal

Se valido el alcance de la unicidad.

Branch B utilizo:

- `client_operation_id = 'return-op-shared'`.
- `folio = 'DEV-B-001'`.

La insercion fue aceptada.

Por tanto, la unicidad no es global. Su alcance es `(branch_id, client_operation_id)`.

Resultado: PASO.

## Rollback y limpieza

Comprobacion posterior observada:

```text
businesses_test_rows = 0
```

Esto confirma que las fixtures temporales de la validacion no quedaron persistidas.

El schema db-3 permanece instalado en la base temporal; lo revertido fueron los datos creados dentro de la suite.

## Alcance

Este documento deja evidencia de:

- ejecucion correcta de `database/validation-v0.5-db-3.sql`;
- conservacion de la suite db-2;
- `NOT NULL` de `returns.client_operation_id`;
- `UNIQUE` por `branch_id + client_operation_id`;
- posibilidad de reutilizar el mismo identificador en otra branch;
- rollback limpio de fixtures.

No documenta ni valida logica futura de servicio como advisory locks, lifecycle de `idempotency_keys`, refunds, `RESTOCK`, `DAMAGED`, `sales.status`, caja o reposicion.

## Relacion con ejecucion del schema

La evidencia separada de que el DDL fue aplicado correctamente esta en `docs/database/ejecucion-schema-v0.5-db-3.md`.

Este documento se concentra en integridad, constraints y regresion estructural.
