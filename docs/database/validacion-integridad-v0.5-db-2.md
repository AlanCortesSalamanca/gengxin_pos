# Validación de integridad PostgreSQL v0.5-db-2

- PostgreSQL: 17.11
- Ejecución mediante Docker Compose
- Base: `gengxin_pos_schema_test`
- Archivo: `database/validation-v0.5-db-2.sql`
- `ON_ERROR_STOP=1`
- Exit code: 0
- Resultado: `BEGIN / DO / ROLLBACK`
- Errores del script: ninguno
- Datos temporales persistidos: NO
- Comprobación `alan.test`: 0
- Tablas públicas posteriores: 51

## Reglas comprobadas

El script comprobó las reglas incluidas en él, entre ellas:

- stock negativo rechazado
- código de barras duplicado rechazado
- segunda sesión OPEN rechazada
- venta con sesión de otra terminal rechazada
- precio negativo rechazado
- cantidades negativas de reposición rechazadas
- `committed_qty_base > demand_qty_base` permitido
- `available_to_order_base = 0` en ese caso
- lista default activa duplicada rechazada
- cotización y venta de distintas sucursales rechazadas
- `purchase_item` con línea de otro pedido rechazado
- `inventory_movements` append-only
- `cash_movements` append-only
- `replenishment_movements` append-only
- `invoice_events` append-only

La consulta auxiliar posterior que produjo un error por nombre de columna incorrecto no pertenecía al script de validación y no afecta este resultado.

Validaciones mínimas de integridad superadas: SÍ

Modelo físico PostgreSQL v0.5-db-2:
VALIDADO EN EJECUCIÓN REAL
