# CONFIRMAR DEVOLUCION v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica: `docs/database/modelo-fisico-v0.5-db-2.md` y `database/schema-v0.5-db-2.sql` validado en PostgreSQL 17.11.

Este documento disena conceptualmente la transaccion `CONFIRMAR DEVOLUCION`. No define framework, API, DTOs, endpoints, servicios, repositorios, frontend, backend ni stack de aplicacion.

## Estado del diseno

- Estado: BORRADOR INICIAL
- Version: v0.1
- Compatible funcionalmente con especificacion maestra v0.5
- Requiere evolucion fisica posterior a PostgreSQL v0.5-db-2 para `returns.client_operation_id`
- Implementacion: todavia no iniciada

Cualquier validacion contra este documento debe considerar que `CONFIRMAR VENTA v0.1` permanece VALIDADO / CONGELADO y no se modifica aqui.

## 1. Principio fundamental

Una devolucion no modifica ni reescribe la venta original.

La venta confirmada es historica. Sus cantidades, precios, descuentos, impuestos, costos y totales guardados en `sales` y `sale_items` son snapshots historicos y no deben disminuirse ni recalcularse por una devolucion.

La devolucion se representa como un documento independiente:

- `returns`: cabecera de devolucion vinculada a `sales`.
- `return_items`: lineas devueltas vinculadas a `sale_items`.

Las correcciones operativas se realizan mediante movimientos compensatorios:

- inventario positivo solo si la disposicion es `RESTOCK`;
- caja negativa solo si el metodo de reembolso afecta efectivo fisico;
- demanda de reposicion negativa solo por devolucion `RESTOCK` y hasta el limite aplicable de demanda existente;
- estado operativo materializado en `sales.status`;
- auditoria append-only.

Actualizar `sales.status` a `PARTIALLY_RETURNED` o `RETURNED` no modifica cantidades, precios, descuentos, impuestos, costos ni totales historicos de la venta. `sales.status` es un estado operativo materializado/resumido; la fuente detallada de verdad de cantidades devueltas sigue siendo `returns` + `return_items` confirmados.

## 2. Entradas conceptuales

La operacion requiere, como minimo:

- `business_id` derivado de la sucursal o contexto autenticado.
- `branch_id` objetivo de la devolucion.
- `terminal_id` autenticada como contexto operativo de ejecucion; no se persiste directamente en `returns` para el MVP.
- `user_id` actor.
- `cash_session_id` solo si `refund_amount > 0` y el unico metodo de reembolso afecta caja fisica.
- `sale_id` de la venta original.
- `client_operation_id` generado por el POS para deduplicacion local de la devolucion.
- `idempotency_key` de operacion critica.
- `request_hash` canonico del payload conceptual.
- motivo general de la devolucion.
- metodo de reembolso unico, resuelto contra `payment_methods`, obligatorio solo si `refund_amount > 0`.
- lineas a devolver con `sale_item_id`, `quantity_base` a devolver y `disposition`.

Cada `disposition` debe ser una de:

- `RESTOCK`: mercancia vendible vuelve al inventario disponible.
- `DAMAGED`: mercancia recibida de vuelta, no apta para venta y tratada operativamente como merma inmediata.

No se fija DTO ni API. El payload canonico exacto queda fuera de este documento.

## 3. Verificacion real contra db-2

Tablas y columnas verificadas en `database/schema-v0.5-db-2.sql`:

- `returns`: `id`, `public_id`, `branch_id`, `sale_id`, `cash_session_id`, `created_by_user_id`, `confirmed_by_user_id`, `folio`, `status`, `reason`, `refund_amount`, `refund_payment_method_id`, `confirmed_at`, `created_at`, `updated_at`.
- `return_items`: `id`, `return_id`, `sale_id`, `sale_item_id`, `disposition`, `quantity_base`, `refund_amount`, `reason`, `created_at`.
- `sales`: `id`, `public_id`, `branch_id`, `terminal_id`, `cash_session_id`, `user_id`, `customer_id`, `price_list_id`, `folio`, `status`, `replenishment_channel`, snapshots, totales, `currency`, `client_operation_id`, `confirmed_at`, `created_at`.
- `sale_items`: `id`, `sale_id`, `line_number`, `product_id`, `product_unit_id`, snapshots comerciales y SAT, `factor_to_base_snapshot`, `quantity`, `quantity_base`, `unit_price_snapshot`, `discount_amount`, `tax_snapshot`, `unit_cost_snapshot`, `subtotal`, `tax_total`, `total`, `created_at`.
- `payment_methods`: `id`, `business_id`, `code`, `name`, `replenishment_channel`, `affects_cash`, `active`.
- `cash_sessions`: `id`, `public_id`, `branch_id`, `cash_register_id`, `terminal_id`, usuarios de apertura/cierre, importes, `status`, timestamps.
- `cash_movements`: `id`, `public_id`, `cash_session_id`, `movement_type`, `amount_delta`, referencia, `reason`, `actor_user_id`, timestamps.
- `inventory_balances`: PK `(branch_id, product_id)`, `quantity_base`, `average_cost_base`, `version`, `updated_at`.
- `inventory_movements`: `movement_type`, `quantity_delta_base`, `unit_cost_base`, `balance_after_base`, referencia, `reason`, `actor_user_id`, timestamps.
- `replenishment_positions`: PK `(branch_id, product_id, channel)`, `demand_qty_base`, `committed_qty_base`, `available_to_order_base`, `version`, `updated_at`.
- `replenishment_movements`: `movement_type`, `demand_delta_base`, `committed_delta_base`, referencia, `actor_user_id`, timestamps.
- `document_sequences`: `business_id`, `branch_id`, `document_type`, `prefix`, `next_number`, `padding`, `active`.
- `idempotency_keys`: `business_id`, `branch_id`, `operation_type`, `idempotency_key`, `request_hash`, `status`, resultado, `response_body`, error, `locked_until`, `expires_at`.
- `audit_log`: `actor_user_id`, `branch_id`, `terminal_id`, `action`, `entity_type`, `entity_id`, `entity_public_id`, `before_data`, `after_data`, `context`, red y timestamps.

Gaps fisicos relevantes detectados:

- `returns` no tiene `request_hash`; el hash vive en `idempotency_keys`.
- `return_items` no tiene columnas separadas de subtotal, descuento, impuesto o costo; solo persiste `refund_amount` monetario por linea.

Decision fisica para `DAMAGED`: db-2 no modela inventario no vendible, cuarentena ni almacen de danados; para el MVP no se requiere modelarlo porque `DAMAGED` se trata como merma inmediata fuera del inventario operativo controlado por el POS.

Decision fisica para reembolsos: db-2 ya soporta la politica MVP de un unico metodo por devolucion mediante `returns.refund_amount` y `returns.refund_payment_method_id`. No se requiere `return_payments`, `return_refund_payments`, `refund_allocations` ni tabla equivalente.

Cambio fisico requerido posterior a db-2:

- agregar `returns.client_operation_id TEXT NOT NULL`;
- agregar unicidad conceptual `UNIQUE(branch_id, client_operation_id)`.

Esta decision ya queda cerrada para el diseno transaccional, pero no se modifica db-2. db-2 permanece congelado como version validada. No se crea db-3 ni migracion en este micro-hito; la evolucion fisica se hara posteriormente, una vez cerradas las decisiones de diseno que puedan afectar schema.

Decision definitiva sobre `terminal_id` para MVP:

- `terminal_id` es contexto autenticado de ejecucion.
- Se usa para validar que la terminal exista, este `ACTIVE` y pertenezca a `branch_id`.
- Si el reembolso afecta caja, se usa para validar que `cash_sessions.terminal_id` corresponda a la terminal autenticada.
- No se agrega `returns.terminal_id`.
- La trazabilidad operacional del dispositivo se conserva en `audit_log.terminal_id`.
- Cuando hay caja, la terminal tambien queda verificable indirectamente mediante la `cash_session` utilizada.

Decision definitiva sobre retencion historica de `sales` para MVP:

- No se agrega `sales.deleted_at`, `sales.deleted_by`, `sales.is_deleted` ni otra columna equivalente.
- Una venta confirmada es un documento historico y no debe eliminarse fisicamente como mecanismo normal de operacion.
- Las correcciones posteriores se representan mediante estados, devoluciones, cancelaciones autorizadas y movimientos compensatorios o reversas cuando corresponda.
- `CONFIRMAR DEVOLUCION` no valida `sales.deleted_at IS NULL` porque esa columna no existe y no es necesaria para el MVP.
- La aplicacion futura no debe exponer una operacion normal de DELETE fisico para `sales` confirmadas.
- Una necesidad excepcional de mantenimiento, migracion o correccion administrativa fuera del flujo normal queda fuera de `CONFIRMAR DEVOLUCION` y requeriria controles operacionales especificos. No se disena ese flujo aqui.
- `sales.status = 'CANCELLED'` no elimina la venta; permanece como registro historico y auditable, pero no es retornable.

No se modifica schema en este documento.

## 4. Precondiciones

- La sucursal `branch_id` existe, esta activa y pertenece a `business_id`.
- La terminal `terminal_id` existe, esta `ACTIVE` y pertenece a `branch_id`.
- El usuario `user_id` existe y esta `ACTIVE`.
- El usuario pertenece a la sucursal mediante `user_branches(user_id, branch_id)`.
- El usuario tiene permiso funcional `RETURNS_CONFIRM` mediante `permissions.code`, roles activos y `role_permissions`.
- La venta `sale_id` existe, pertenece a la misma `branch_id` para el MVP y pertenece al mismo `business_id` via sucursal.
- La venta original esta en estado compatible para devolucion. En db-2 los estados disponibles son `CONFIRMED`, `PARTIALLY_RETURNED`, `RETURNED` y `CANCELLED`; para el MVP son retornables `CONFIRMED` y `PARTIALLY_RETURNED`.
- Una venta `RETURNED` no es retornable.
- Una venta `CANCELLED` no es retornable; `CANCELLED` no significa borrado fisico.
- Una venta ya completamente retornada por suma de `return_items` confirmados no es retornable, incluso si el estado materializado estuviera desfasado por un fallo previo a detectar.
- Si `refund_amount > 0`, existe exactamente un metodo de reembolso en `payment_methods`, pertenece al `business_id` y esta activo.
- Si `refund_amount > 0` y el metodo de reembolso afecta caja fisica, existe `cash_session_id`, la sesion esta `OPEN`, pertenece a la misma sucursal y corresponde a la misma terminal segun politica MVP.
- Si `refund_amount = 0`, no se requiere metodo de reembolso ni `cash_session_id`.
- Cada linea solicitada referencia un `sale_item` perteneciente a la venta original.

La elegibilidad para devolucion se determina con existencia de `sales.id`, pertenencia a `branch_id`, pertenencia al `business` correspondiente via sucursal, `sales.status` compatible y cantidades retornables restantes derivadas de `returns` + `return_items`.

## 5. Validaciones

### Venta original

- Validar existencia de `sales.id = sale_id`.
- Validar `sales.branch_id = branch_id` para el MVP.
- Validar que la sucursal de la venta pertenezca al `business_id` esperado.
- Validar estado compatible: `CONFIRMED` o `PARTIALLY_RETURNED`.
- Rechazar `RETURNED` y `CANCELLED`.
- Rechazar venta no retornable por reglas existentes.
- Permitir devolucion parcial.
- Permitir varias devoluciones confirmadas sobre la misma venta mientras la suma acumulada no exceda lo vendido por linea.
- No inventar cancelacion total automatica.
- No modificar cantidades ni totales historicos de `sale_items`.

### Lineas

- Cada `sale_item_id` debe existir.
- Cada `sale_item_id` debe pertenecer a `sale_id`.
- No aceptar lineas duplicadas en una misma solicitud; si se reciben, deben agregarse por `sale_item_id` antes de validar o rechazarse como payload ambiguo.
- `quantity_base` solicitada debe ser mayor a cero.
- `disposition` debe ser `RESTOCK` o `DAMAGED`.
- Si `disposition = 'DAMAGED'`, `return_items.reason` debe informarse conceptualmente con un motivo operacional breve; si falta, devolver `RETURN_DAMAGED_REASON_REQUIRED`.
- La suma solicitada por `sale_item_id` en la devolucion actual no debe exceder la cantidad retornable restante.

### Reembolso

- El importe total de reembolso se calcula desde snapshots historicos de `sale_items`, no desde precios vigentes.
- El `refund_amount` de `returns` debe ser la suma exacta de `return_items.refund_amount` redondeados conforme a la politica monetaria.
- Si `returns.refund_amount > 0`, debe existir exactamente un `returns.refund_payment_method_id`.
- Si `returns.refund_amount > 0`, el metodo de reembolso debe existir, pertenecer al negocio y estar activo.
- Si `returns.refund_amount > 0` y falta metodo de reembolso, devolver `RETURN_REFUND_METHOD_REQUIRED`.
- Si el request intenta dividir una misma devolucion entre mas de un metodo de reembolso, devolver `RETURN_REFUND_SPLIT_NOT_SUPPORTED`.
- Si `returns.refund_amount > 0` y `payment_methods.affects_cash = TRUE`, debe existir caja abierta y se crea un unico `cash_movements` negativo por el total de `returns.refund_amount`.
- Si `returns.refund_amount > 0` y `payment_methods.affects_cash = FALSE`, no se crea movimiento de caja.
- Si `returns.refund_amount = 0`, `returns.refund_payment_method_id = NULL`, `cash_session_id = NULL` y no se crea `cash_movements`.

### Autorizacion

El permiso propuesto para confirmar devoluciones es `RETURNS_CONFIRM`.

La autorizacion usa la convencion `<MODULE>_<ACTION>` y el modelo existente `users`, `user_roles`, `roles`, `role_permissions`, `permissions` y `user_branches`.

No se autoriza por nombre de rol. No se crea seed ni se modifica `permissions`.

Si el usuario tiene permiso pero no pertenece a la sucursal, devolver `USER_BRANCH_FORBIDDEN`. Si pertenece a la sucursal pero no tiene permiso, devolver `USER_PERMISSION_DENIED`.

## 6. Cantidades retornables

Para cada `sale_item` incluido:

- `returned_qty_base = SUM(return_items.quantity_base)` de devoluciones con `returns.status = 'CONFIRMED'` para ese `sale_item_id`.
- `remaining_returnable = sale_items.quantity_base - returned_qty_base`.
- `requested_return_qty > 0`.
- `requested_return_qty <= remaining_returnable`.

`returned_qty_base` incluye tanto lineas `RESTOCK` como lineas `DAMAGED`. Una unidad devuelta como `DAMAGED` ya fue devuelta comercialmente y no puede devolverse otra vez, aunque no vuelva al inventario vendible.

Ejemplo:

- `sale_item.quantity_base = 5`;
- devolucion 1: `2 RESTOCK`;
- devolucion 2: `2 DAMAGED`;
- `remaining_returnable = 1`.

La validacion debe ejecutarse dentro de la transaccion operativa y despues de adquirir locks que serialicen devoluciones de la misma venta o de las mismas lineas.

La fuente de verdad de lo ya devuelto son `returns` confirmadas y sus `return_items`. `sales.status` es un resumen operativo materializado y no sustituye este calculo detallado.

Dos devoluciones simultaneas no deben poder devolver dos veces la ultima cantidad disponible. Para lograrlo, el flujo bloquea deterministamente la venta y las lineas originales relevantes antes de calcular `returned_qty_base` y `remaining_returnable`.

Despues de insertar una devolucion confirmada, y antes del `COMMIT`, se recalculan las cantidades devueltas acumuladas por cada `sale_item` de la venta:

- si existe al menos una cantidad devuelta, sea `RESTOCK` o `DAMAGED`, pero todavia existe alguna cantidad retornable, `sales.status = 'PARTIALLY_RETURNED'`;
- si todas las cantidades originales de todas las `sale_items` han sido devueltas completamente, sea como `RESTOCK` o como `DAMAGED`, `sales.status = 'RETURNED'`;
- no alterar una venta `CANCELLED`.

Actualizar `sales.status` no constituye reescritura destructiva del historico de la venta; no cambia `sale_items`, snapshots ni totales originales.

## 7. Locks propuestos

Nivel de aislamiento propuesto: `READ COMMITTED` + locks explicitos.

Orden determinista:

1. `idempotency_keys` por `(business_id, operation_type='CONFIRM_RETURN', idempotency_key)`.
2. Transaction advisory lock por `(branch_id, client_operation_id)` de la devolucion.
3. Busqueda de `returns(branch_id, client_operation_id)` existente, cuando el modelo fisico futuro incluya esa columna.
4. `sales` por `sale_id`.
5. `sale_items` originales seleccionados, filtrados por `sale_id`, en orden ascendente de `sale_items.id`.
6. `returns` confirmadas previas de la misma venta o consulta bloqueante equivalente de filas relevantes ya existentes.
7. `return_items` previos relevantes por `sale_item_id`, en orden ascendente de `sale_item_id, id`, cuando existan filas que bloquear.
8. `cash_sessions` por `cash_session_id` si el reembolso afecta caja.
9. `payment_methods` por lectura consistente; no requiere bloqueo de escritura salvo politica futura.
10. `inventory_balances` para lineas `RESTOCK`, por `(branch_id, product_id)` en orden ascendente de `product_id`.
11. `replenishment_positions` por `(branch_id, product_id, channel)` en orden ascendente de `product_id, channel`; si no existen, crear/asegurar mediante operacion determinista.
12. `document_sequences` por `(business_id, branch_id, document_type='DEV')`.

Justificacion critica:

- `idempotency_keys` evita doble ejecucion de la misma solicitud.
- El advisory lock de `client_operation_id` cierra la ventana concurrente antes de que exista la fila `returns`; no es necesario row-lockear una fila inexistente.
- La unicidad futura `UNIQUE(branch_id, client_operation_id)` en `returns` queda como defensa final persistente de PostgreSQL.
- Bloquear `sales` serializa devoluciones que compiten por la misma venta y permite actualizar `sales.status` de forma determinista.
- Bloquear `sale_items` relevantes serializa el calculo de cantidades retornables por linea.
- Bloquear filas previas de `returns` y `return_items` ayuda a obtener una vista estable de devoluciones ya confirmadas existentes, pero no basta si no existen filas previas; por eso el lock de `sales` y `sale_items` es el lock principal de serializacion.
- `inventory_balances`, `replenishment_positions`, `cash_sessions` y `document_sequences` se bloquean solo cuando aplican efectos sobre esas entidades.
- `document_sequences` se bloquea tarde, despues de validar cantidades y caja, para no retener la secuencia mientras se resuelven validaciones de dominio.

No se escribe SQL definitivo en este documento.

## 8. Orden transaccional propuesto

### FASE A - Reserva idempotente

La reserva idempotente ocurre en una transaccion corta dedicada a `idempotency_keys`:

1. Resolver o crear la clave unica `(business_id, operation_type='CONFIRM_RETURN', idempotency_key)`.
2. Si no existe, crearla con `status='IN_PROGRESS'`, `request_hash`, `locked_until` y `expires_at = NULL`.
3. Si existe `IN_PROGRESS` con mismo hash y lease vigente, devolver `RETURN_IDEMPOTENCY_IN_PROGRESS`.
4. Si existe `COMPLETED` con mismo hash, devolver la devolucion ya confirmada desde `result_entity_type='returns'` y `result_entity_id` o `response_body` minima.
5. Si existe con `request_hash` diferente, devolver `RETURN_IDEMPOTENCY_KEY_REUSED`.
6. Si existe `FAILED` con mismo hash, devolver el error de dominio almacenado.

### FASE B - Confirmar devolucion transaccional

Dentro de un unico `BEGIN` / `COMMIT` operativo:

1. Bloquear y verificar la fila `idempotency_keys` reservada.
2. Adquirir advisory lock determinista por `(branch_id, client_operation_id)`.
3. Buscar `returns(branch_id, client_operation_id)` existente, cuando la evolucion fisica futura este disponible.
4. Si existe, no ejecutar efectos de negocio nuevamente; reconciliar la `idempotency_key` actual hacia `COMPLETED` y devolver la devolucion existente.
5. Si no existe, continuar.
6. Validar `branch`, `terminal`, `user`, permiso `RETURNS_CONFIRM` y pertenencia a sucursal.
7. Bloquear `sales(sale_id)` y validar venta original.
8. Bloquear `sale_items` solicitados en orden determinista y validar pertenencia a la venta.
9. Calcular `returned_qty_base` y `remaining_returnable` con devoluciones confirmadas existentes dentro de la transaccion.
10. Validar cantidades solicitadas, disposicion y motivo operacional requerido para lineas `DAMAGED`.
11. Calcular importes de reembolso por linea desde snapshots historicos y derivar `returns.refund_amount` como suma exacta.
12. Validar la politica de metodo unico de reembolso.
13. Si `refund_amount > 0`, validar `payment_methods` para el unico metodo de reembolso; si `refund_amount = 0`, forzar metodo y caja a `NULL`.
14. Si `refund_amount > 0` y el metodo afecta caja, bloquear y validar `cash_sessions` abierta de la misma sucursal y terminal.
15. Bloquear `inventory_balances` para productos con `disposition='RESTOCK'`.
16. Bloquear o preparar `replenishment_positions` para productos/canal con lineas `RESTOCK`.
17. Bloquear `document_sequences` de `DEV` para la sucursal.
18. Reservar folio `DEV` incrementando `next_number` dentro de la misma transaccion.
19. Insertar `returns` con `status='CONFIRMED'`, folio, venta, usuario, motivo, metodo unico cuando aplique, importe total y `client_operation_id` cuando la evolucion fisica exista.
20. Insertar `return_items` con cantidades, disposicion, motivo por linea si aplica e importes.
21. Para lineas `RESTOCK`, actualizar `inventory_balances.quantity_base`, recalcular `average_cost_base` por promedio ponderado, incrementar `version` e insertar `inventory_movements` tipo `SALE_RETURN` con delta positivo.
22. Para lineas `DAMAGED`, no incrementar inventario vendible, no crear `SALE_RETURN` ni crear otro `inventory_movement`.
23. Para lineas `RESTOCK`, reducir `replenishment_positions.demand_qty_base` solo hasta el limite aplicable de demanda existente, sin modificar `committed_qty_base`.
24. Insertar `replenishment_movements` tipo `RETURN_RESTOCK` solo cuando la reduccion efectiva de demanda sea mayor a cero.
25. Para lineas `DAMAGED`, no modificar `replenishment_positions`, no reducir demanda y no crear `replenishment_movements`.
26. Recalcular cantidades devueltas acumuladas por venta y actualizar `sales.status` a `PARTIALLY_RETURNED` o `RETURNED` segun corresponda.
27. Si `refund_amount > 0` y el metodo afecta caja, insertar un unico `cash_movements` tipo `RETURN_CASH` con `amount_delta = -returns.refund_amount` y referencia a `returns`.
28. Insertar `audit_log` con `action='RETURN_CONFIRMED'`.
29. Marcar `idempotency_keys` como `COMPLETED`, con `result_entity_type='returns'`, `result_entity_id=returns.id`, `response_body` minima, errores nulos, `locked_until=NULL` y `expires_at` definido.

### Reconciliacion por devolucion existente

Si FASE B encuentra una devolucion existente para `(branch_id, client_operation_id)`:

1. No crear otra `returns`.
2. No crear nuevos `return_items`.
3. No aumentar nuevamente inventario.
4. No recalcular nuevamente costo promedio.
5. No reducir nuevamente reposicion.
6. No generar otro reembolso.
7. No generar otro `cash_movement`.
8. No reservar otro folio.
9. No volver a modificar `sales.status`.
10. Reconciliar la `idempotency_key` actual hacia `COMPLETED`.
11. Usar `result_entity_type='returns'` y `result_entity_id=returns.id`.
12. Guardar `response_body` minima.
13. Establecer `locked_until = NULL` y `expires_at` segun politica de retencion.
14. Devolver la devolucion existente.

### FASE C - Fallo de dominio deterministico

Si FASE B falla por error de dominio deterministico:

1. Hacer `ROLLBACK` completo de FASE B.
2. Abrir una transaccion corta sin escrituras de negocio.
3. Bloquear `idempotency_keys`.
4. Verificar que `request_hash` coincida.
5. Guardar `status='FAILED'`, `error_code`, `error_message` seguro, `locked_until=NULL` y `expires_at`.
6. Hacer `COMMIT`.

No se guardan stack traces, SQL interno, secretos ni datos sensibles.

## 9. Inventario RESTOCK

Si `return_items.disposition = 'RESTOCK'`, la mercancia esta en condiciones vendibles y vuelve al inventario disponible.

Efectos conceptuales:

- incrementar `inventory_balances.quantity_base` para `(branch_id, product_id)`;
- recalcular `inventory_balances.average_cost_base` por promedio ponderado;
- incrementar `inventory_balances.version`;
- crear `inventory_movements.movement_type = 'SALE_RETURN'`;
- usar `quantity_delta_base` positivo;
- usar `reference_entity_type = 'return_items'` y `reference_entity_id = return_items.id`;
- conservar trazabilidad con `actor_user_id = user_id` y razon de devolucion.

### Costo del movimiento

Decision definitiva: una devolucion `RESTOCK` representa una entrada valorizada de inventario vendible.

El costo de entrada de cada `return_item` es `sale_items.unit_cost_snapshot` de la linea original. Por tanto, para cada movimiento `SALE_RETURN`:

- `inventory_movements.unit_cost_base = sale_items.unit_cost_snapshot`;
- no usar costo promedio actual como costo del movimiento;
- no usar precio de venta;
- no usar precio vigente;
- no usar costo actual de proveedor;
- no usar costo recalculado arbitrariamente.

`RESTOCK` debe recalcular `inventory_balances.average_cost_base` mediante promedio ponderado.

Para un producto con una sola entrada conceptual:

- `Q = inventory_balances.quantity_base` actual antes de la devolucion;
- `A = inventory_balances.average_cost_base` actual antes de la devolucion;
- `R = cantidad RESTOCK que entra`;
- `C = sale_items.unit_cost_snapshot` de las unidades retornadas;
- `Q_new = Q + R`;
- `A_new = ((Q * A) + (R * C)) / Q_new`.

La implementacion futura debe usar aritmetica decimal exacta. `inventory_balances.average_cost_base` se persiste redondeado a 6 decimales, compatible con `NUMERIC(18,6)`. No se usa `FLOAT`.

### Varias lineas del mismo producto

Una devolucion puede contener varias `return_items RESTOCK` del mismo `product_id` y esas lineas pueden tener distintos `sale_items.unit_cost_snapshot`. No se debe asumir un unico `C`.

Antes de actualizar `inventory_balances`, agrupar conceptualmente por `product_id`:

- `R_total = SUM(return_items.quantity_base RESTOCK)`;
- `V_return = SUM(return_items.quantity_base * sale_items.unit_cost_snapshot)`;
- `A_new = ((Q * A) + V_return) / (Q + R_total)`.

Esto evita errores si dos lineas historicas del mismo producto salieron con costos distintos.

Si `Q = 0`, entonces:

- `A_new = V_return / R_total`.

Es decir, el promedio ponderado de los costos historicos de las unidades que regresan. No conservar `average_cost_base = 0` si regresan unidades con costo historico positivo.

### Redondeo de costo

Mantener precision decimal suficiente durante el calculo. No redondear cada componente prematuramente.

Para varias lineas, primero sumar el valor total retornado con precision suficiente y despues calcular el promedio final. Persistir `inventory_balances.average_cost_base` redondeado a 6 decimales.

### Movimientos de inventario

Mantener un `inventory_movements` por cada `return_item RESTOCK` para conservar trazabilidad.

Cada movimiento:

- `movement_type = 'SALE_RETURN'`;
- `quantity_delta_base > 0`;
- `unit_cost_base = sale_items.unit_cost_snapshot`;
- `reference_entity_type = 'return_items'`;
- `reference_entity_id = return_items.id`.

Si varias lineas `RESTOCK` corresponden al mismo `product_id`:

- `inventory_balances` puede actualizarse de forma agregada;
- `inventory_movements` conserva granularidad por `return_item`.

Si `balance_after_base` debe calcularse por movimiento, procesar los movimientos del mismo producto en un orden estable para que los saldos posteriores sean deterministas.

No se define SQL definitivo.

### Justificacion

Conservar `average_cost_base` sin recalcular haria que la cantidad regresara al inventario pero la valuacion de esa unidad se absorbiera artificialmente al promedio actual.

Como se conoce el costo historico real usado cuando esa unidad salio, `sale_items.unit_cost_snapshot`, `RESTOCK` debe reingresar esa cantidad con ese valor y actualizar el promedio ponderado del inventario actual. Esto conserva mejor la trazabilidad de valuacion del MVP.

Recalcular el `average_cost_base` actual no modifica:

- `sale_items.unit_cost_snapshot`;
- margen historico de la venta;
- precios historicos;
- descuento;
- impuestos;
- totales originales.

La venta conserva su costo historico. Solo cambia la valuacion promedio del inventario disponible despues del reingreso fisico.

### Concurrencia de costo

El calculo debe ejecutarse despues de bloquear `inventory_balances(branch_id, product_id)`. Asi, `Q` y `A` son los valores autoritativos dentro de la transaccion.

Otra compra, devolucion, ajuste o entrada concurrente no debe provocar lost updates sobre `average_cost_base`. Mantener orden estable por `product_id`.

### Orden conceptual RESTOCK dentro de FASE B

Todo ocurre dentro del mismo `COMMIT` de la devolucion:

1. Bloquear `inventory_balances(branch_id, product_id)` para productos `RESTOCK` en orden estable por `product_id`.
2. Leer `quantity_base` y `average_cost_base` actuales como `Q` y `A`.
3. Agrupar entradas `RESTOCK` por `product_id`.
4. Calcular `R_total` y `V_return` por producto.
5. Calcular `Q_new = Q + R_total`.
6. Calcular `A_new = ((Q * A) + V_return) / Q_new` o `A_new = V_return / R_total` cuando `Q = 0`.
7. Actualizar `inventory_balances.quantity_base = Q_new`.
8. Actualizar `inventory_balances.average_cost_base = A_new` redondeado a 6 decimales e incrementar `version`.
9. Insertar `inventory_movements SALE_RETURN` por cada `return_item RESTOCK`.

## 10. Inventario DAMAGED

Decision definitiva: si `return_items.disposition = 'DAMAGED'`, la devolucion se trata como devolucion comercial con merma inmediata.

Para el MVP, `DAMAGED` significa mercancia recibida de vuelta pero no apta para venta y tratada operativamente como merma inmediata. No significa stock vendible, stock disponible, cuarentena, inventario reparable, inventario pendiente de revision ni mercancia recuperable.

La cantidad fisica devuelta queda fuera del inventario operativo controlado por el POS desde el momento de confirmar la devolucion. No se modela inventario no vendible, cuarentena ni almacen de danados.

Efectos conceptuales:

- no modificar `inventory_balances.quantity_base`;
- no modificar `inventory_balances.average_cost_base`;
- no crear entrada vendible en `inventory_balances`;
- no crear `inventory_movements.movement_type = 'SALE_RETURN'`;
- no crear otro tipo de `inventory_movement`;
- no generar `unit_cost_base` en `inventory_movements`;
- no entrar en `R_total`;
- no entrar en `V_return`;
- no modificar `replenishment_positions.demand_qty_base`;
- no modificar `replenishment_positions.committed_qty_base`;
- no crear `replenishment_movements.movement_type = 'RETURN_RESTOCK'`;
- no reducir automaticamente demanda de reposicion;
- no inventar tabla de inventario danado, cuarentena, reparacion, garantia, destruccion ni devolucion a proveedor.

La venta original ya desconto la unidad del inventario vendible. Al regresar como `DAMAGED`, no debe reincorporarse a ese mismo saldo. Crear `inventory_movements.movement_type = 'SALE_RETURN'` implicaria una entrada positiva y exigiria coherencia con `inventory_balances.quantity_base`; como la unidad no vuelve al stock vendible, no se debe crear `SALE_RETURN`.

Tampoco se inventa otro `movement_type` en este hito. Para `CONFIRMAR DEVOLUCION v0.1`, el unico cambio fisico requerido posterior a db-2 sigue siendo:

- `returns.client_operation_id TEXT NOT NULL`;
- `UNIQUE(branch_id, client_operation_id)`.

No agregar al futuro modelo fisico requerido por este flujo:

- `damaged_inventory`;
- `quarantine_inventory`;
- `inventory_damage_balances`;
- `warehouse_damaged`;
- tablas equivalentes;
- nuevo `inventory_movement_type`.

La evidencia de la devolucion `DAMAGED` queda persistida mediante:

- `returns`;
- `return_items` con `disposition = 'DAMAGED'`, `quantity_base`, `refund_amount` y `reason`;
- `audit_log` con `action = 'RETURN_CONFIRMED'` y resumen por disposicion.

Por tanto no se pierde trazabilidad del hecho, aunque la unidad no forme parte de `inventory_balances`.

Para `DAMAGED`, `return_items.reason` debe ser requerido conceptualmente. Debe describir de forma breve el motivo operacional, por ejemplo:

- roto;
- quemado;
- incompleto;
- golpeado;
- defecto visible;
- no apto para reventa.

No se crea catalogo ni enum de motivos ahora. No se modifica schema si `return_items.reason` actualmente permite `NULL`. La obligatoriedad se protege a nivel de servicio/transaccion en la implementacion futura. Error estable: `RETURN_DAMAGED_REASON_REQUIRED`.

`sale_items.unit_cost_snapshot` permanece disponible como historico de costo de la venta, pero no se usa para crear una entrada de inventario `DAMAGED`.

Si en el futuro el negocio necesita controlar fisicamente cuarentena, reparacion, garantia, devolucion a proveedor o destruccion posterior, eso requerira un modulo/modelo separado de inventario no vendible. Queda fuera del MVP actual.

## 11. Reposicion

La venta original incremento `replenishment_positions.demand_qty_base`. La devolucion solo compensa demanda automaticamente cuando la mercancia vuelve al inventario vendible con `disposition = 'RESTOCK'`.

Para cada `return_item` con `disposition = 'RESTOCK'`:

- identificar `sale_items.product_id` y `sales.replenishment_channel` de la venta original;
- calcular `restock_qty_base = return_items.quantity_base`;
- calcular `demand_reduction_base = LEAST(restock_qty_base, replenishment_positions.demand_qty_base)`;
- actualizar `replenishment_positions(branch_id, product_id, channel).demand_qty_base = current_demand_qty_base - demand_reduction_base`;
- impedir que `demand_qty_base` quede menor a cero;
- no modificar automaticamente `committed_qty_base`;
- insertar `replenishment_movements.movement_type = 'RETURN_RESTOCK'` solo si `demand_reduction_base > 0`;
- usar `demand_delta_base = -demand_reduction_base` y `committed_delta_base = 0`;
- referenciar preferentemente `return_items` con `reference_entity_type='return_items'` y `reference_entity_id=return_items.id`.

Si una devolucion `RESTOCK` ocurre cuando `replenishment_positions.demand_qty_base = 0`, entonces:

- aumenta inventario vendible;
- no reduce demanda por debajo de cero;
- no crea `replenishment_movements` con delta cero;
- la devolucion queda trazada mediante `return_items`, `inventory_movements` y `audit_log`.

Para cada `return_item` con `disposition = 'DAMAGED'`:

- no modificar `replenishment_positions.demand_qty_base`;
- no modificar `committed_qty_base`;
- no crear `replenishment_movements.movement_type = 'RETURN_RESTOCK'`.

`DAMAGED` no reduce `demand_qty_base` automaticamente porque la mercancia danada no vuelve al stock vendible y la necesidad operativa de reposicion continua.

El nombre `RETURN_RESTOCK` queda semanticamente correcto porque solo se usa cuando la mercancia vuelve a stock vendible y efectivamente reduce demanda.

Regla ya aceptada:

- `committed_qty_base` puede quedar mayor que `demand_qty_base`.

Ejemplo RESTOCK:

- venta = 10;
- demanda = 10;
- pedido comprometido = 10;
- devolucion `RESTOCK` = 4;
- resultado: `demand_qty_base = 6`, `committed_qty_base = 10`, `available_to_order_base = 0`.

Ejemplo DAMAGED:

- venta = 10;
- demanda = 10;
- pedido comprometido = 10;
- devolucion `DAMAGED` = 4;
- resultado: `demand_qty_base = 10`, `committed_qty_base = 10`.

En `DAMAGED`, la necesidad de reposicion no se compensa automaticamente porque la mercancia no vuelve al inventario vendible.

Este resultado es valido. No se libera compromiso automaticamente; ajustar pedidos o reservas comprometidas sera otro flujo.

## 12. Reembolso y caja

El reembolso tiene dos dimensiones distintas:

- devolucion monetaria al cliente;
- impacto fisico en caja.

La devolucion monetaria se registra en:

- `returns.refund_amount` como total devuelto;
- `returns.refund_payment_method_id` como metodo unico de reembolso cuando `refund_amount > 0`;
- `return_items.refund_amount` como importe por linea.

Decision definitiva: una devolucion usa como maximo un metodo de reembolso. No se soporta split refund dentro del mismo documento `returns`.

Para una devolucion con `returns.refund_amount > 0`, debe existir exactamente un `returns.refund_payment_method_id`. Ese metodo representa el metodo monetario de toda la devolucion.

No dividir una misma devolucion entre:

- efectivo + transferencia;
- efectivo + tarjeta;
- dos transferencias;
- dos metodos cualesquiera.

No crear tabla `return_payments`, `return_refund_payments`, `refund_allocations` ni tabla equivalente para MVP. La decision usa directamente el modelo existente `returns.refund_amount` y `returns.refund_payment_method_id`; por tanto no requiere cambio fisico posterior a db-2.

Si `returns.refund_amount > 0`:

- `refund_payment_method_id` es obligatorio conceptualmente;
- el metodo debe existir;
- el metodo debe pertenecer al `business_id`;
- el metodo debe estar activo;
- si falta, devolver `RETURN_REFUND_METHOD_REQUIRED`;
- si es invalido, inactivo o de otro negocio, devolver `RETURN_REFUND_METHOD_INVALID`.

Si el importe calculado de la devolucion es exactamente `refund_amount = 0`:

- `returns.refund_payment_method_id = NULL`;
- `cash_session_id = NULL`;
- no crear `cash_movements`, aunque conceptualmente el usuario haya seleccionado un metodo en la interfaz.

La operacion sigue siendo una devolucion valida porque puede existir una linea historica cuyo total reembolsable sea cero. No se inventa pago ni reembolso de monto cero.

El impacto fisico en caja depende de `payment_methods.affects_cash` del metodo de reembolso:

- si `refund_amount > 0` y `affects_cash = TRUE`, crear un unico `cash_movements.movement_type='RETURN_CASH'` con `amount_delta = -returns.refund_amount`;
- si `refund_amount > 0` y `affects_cash = FALSE`, no crear `cash_movements`;
- si `refund_amount = 0`, no crear `cash_movements`.

No todos los reembolsos afectan caja fisica. Tarjeta, transferencia, saldo a favor u otro metodo futuro pueden registrar devolucion monetaria sin movimiento en caja, siempre que el metodo exista en `payment_methods` y no afecte efectivo.

Cuando `refund_amount > 0` y el reembolso afecta caja:

- `cash_session_id` es obligatorio;
- la sesion debe estar `OPEN`;
- la sesion debe pertenecer a `branch_id`;
- para MVP, `cash_sessions.terminal_id` debe corresponder a la `terminal_id` autenticada;
- insertar un unico `cash_movements` negativo por el total monetario efectivo del documento `returns`;
- no crear un `cash_movements` por `return_item`;
- usar referencia a `returns`;
- usar `actor_user_id = user_id`.

Si `refund_amount > 0` y `payment_methods.affects_cash = FALSE`:

- no se requiere `cash_session_id`;
- no se crea `cash_movements`;
- `refund_payment_method_id` si se persiste en `returns`.

La devolucion monetaria sigue existiendo aunque no afecte efectivo fisico.

No se modifican los movimientos originales de la venta.

La especificacion actual no define una regla que obligue al metodo de reembolso a coincidir con un `sale_payments` original. Para `CONFIRMAR DEVOLUCION v0.1`, no se inventa una restriccion automatica de igualdad con el metodo de pago original. El metodo de reembolso seleccionado y autorizado para la devolucion es el que se guarda en `returns.refund_payment_method_id`.

Las politicas futuras de negocio o proveedor de pagos que obliguen a devolver a la tarjeta o cuenta original quedan fuera de este contrato MVP. No se modifica `sale_payments`.

Aunque una venta original tenga varias filas en `sale_payments`, una devolucion individual continua utilizando un unico `refund_payment_method_id`. No se prorratea automaticamente el reembolso entre los metodos originales y no se reconstruye el mix de pago original.

Una venta puede tener varias devoluciones independientes. Cada documento `returns` puede elegir su unico metodo de reembolso, siempre que cada devolucion cumpla sus propias reglas de cantidad retornable e importe.

Ejemplo valido:

- Devolucion 1: `refund_amount = 300`, `refund_method = CASH`;
- Devolucion 2: `refund_amount = 200`, `refund_method = TRANSFER`.

Ejemplo no permitido en MVP:

- una sola devolucion de `500` dividida en `300 CASH` y `200 TRANSFER`.

Si el negocio necesita split refund real en el futuro, sera una evolucion funcional y fisica separada.

`DAMAGED` sigue siendo una devolucion comercial valida. Por tanto, genera `return_items.refund_amount`, participa en `returns.refund_amount`, puede generar `RETURN_CASH` si el metodo afecta caja, consume cantidad retornable de la `sale_item` y participa en el calculo de `sales.status`. La disposicion fisica del producto no cambia el derecho monetario determinado por la devolucion aceptada.

Si no existe movimiento de caja, la terminal desde la que se confirmo la devolucion queda registrada en `audit_log.terminal_id`; `audit_log` es la fuente de trazabilidad operacional del dispositivo.

## 13. Totales de devolucion

Los importes se calculan desde snapshots historicos de `sale_items`:

- `unit_price_snapshot`;
- `discount_amount`;
- `tax_snapshot`;
- `subtotal`;
- `tax_total`;
- `total`;
- `quantity_base` y `quantity` originales.

No se consulta precio vigente actual para determinar cuanto devolver.

Politica monetaria:

- usar decimal exacto;
- almacenar dinero en `NUMERIC(18,2)`;
- usar `ROUND(..., 2)`;
- no usar `FLOAT` ni tipos binarios como autoridad monetaria.

Regla determinista propuesta para devolucion parcial:

- calcular `ratio = requested_quantity_base / sale_items.quantity_base` con precision decimal suficiente;
- `refund_subtotal_raw = sale_items.subtotal * ratio`;
- `refund_discount_raw = sale_items.discount_amount * ratio` solo para explicacion/auditoria conceptual, porque db-2 no lo persiste por separado;
- `refund_tax_raw = sale_items.tax_total * ratio`;
- `refund_total_raw = sale_items.total * ratio`;
- almacenar `return_items.refund_amount = ROUND(refund_total_raw, 2)`.

Para evitar que varias devoluciones parciales acumulen diferencias de centavos:

- si la devolucion actual deja `remaining_returnable = 0` para la linea, el `return_items.refund_amount` debe ser el remanente monetario exacto: `sale_items.total - SUM(return_items.refund_amount confirmados previos)`;
- si no es la ultima devolucion de la linea, usar `ROUND(sale_items.total * ratio, 2)`;
- validar que el acumulado de `return_items.refund_amount` confirmados para la linea nunca exceda `sale_items.total`.

Esta regla maneja lineas con descuento, impuesto y cantidad mayor a 1 porque prorratea el total historico efectivamente cobrado de la linea. Los componentes fiscales detallados y notas de credito SAT/CFDI quedan fuera de este documento.

DECISION / GAP A REVISAR: db-2 solo persiste `refund_amount` por linea, no el desglose de subtotal, descuento e impuesto devuelto. Si se requiere nota de credito fiscal detallada desde la devolucion, podria necesitarse persistencia adicional en otro hito.

## 14. Idempotencia

La devolucion debe ser idempotente.

Decision definitiva: `CONFIRMAR DEVOLUCION` requiere persistir `client_operation_id` en `returns` para tener idempotencia robusta equivalente al flujo de ventas.

Cambio fisico requerido en una evolucion posterior a db-2:

- `returns.client_operation_id TEXT NOT NULL`;
- `UNIQUE(branch_id, client_operation_id)`.

No se modifica schema en este documento.

### Diferencia entre `idempotency_key` y `client_operation_id`

`idempotency_key + request_hash` protege una solicitud concreta y sus retries.

`client_operation_id` identifica una devolucion logica creada por el POS.

Caso que debe evitarse:

- primera ejecucion: `branch_id = B`, `client_operation_id = X`, `idempotency_key = K1`;
- la devolucion queda confirmada;
- luego llega accidentalmente `branch_id = B`, `client_operation_id = X`, `idempotency_key = K2`.

Sin persistir `client_operation_id` en `returns`, db-2 no puede saber de forma autoritativa que `X` ya produjo una devolucion. Eso podria intentar repetir reembolso, entrada `RESTOCK`, movimientos, reposicion, folio y actualizacion de `sales.status`.

Por tanto se requiere una defensa persistente secundaria.

### Contrato de `client_operation_id`

`client_operation_id` identifica una unica devolucion logica dentro de una sucursal. Debe ser:

- generado por el POS;
- opaco para el servidor;
- estable durante retries de la misma devolucion logica;
- distinto para una nueva devolucion logica.

Una vez que existe `returns(branch_id, client_operation_id)`, ese identificador queda consumido para esa sucursal.

Si una devolucion falla antes de crear `returns` por un error de dominio deterministico y el usuario corrige la misma devolucion logica, puede conservar `client_operation_id`, pero debe usar nueva `idempotency_key` y nuevo `request_hash` del payload corregido. Esto es valido porque aun no existe `returns(branch_id, client_operation_id)`.

Una vez confirmada la devolucion, ese `client_operation_id` queda consumido.

### Defensas complementarias

Defensa primaria:

- `idempotency_keys` con `operation_type='CONFIRM_RETURN'`;
- `idempotency_key` unica por negocio y operacion;
- `request_hash` canonico para detectar payload distinto.

Sirve para retry HTTP, doble clic, perdida de respuesta y deteccion de reutilizacion de una misma `idempotency_key` con payload diferente.

Defensa secundaria:

- `returns.client_operation_id`;
- `UNIQUE(branch_id, client_operation_id)`.

Sirve para identificar persistentemente la devolucion logica e impedir una segunda devolucion si cambia accidentalmente la `idempotency_key`.

El nuevo `client_operation_id` persistente no sustituye `request_hash`. Si se reutiliza la misma `idempotency_key` con `request_hash` distinto, devolver `RETURN_IDEMPOTENCY_KEY_REUSED`.

El metodo de reembolso forma parte del payload canonico que contribuye a `request_hash`. Por tanto, la misma `idempotency_key` con `refund_payment_method_id` diferente debe producir un `request_hash` diferente y caer en `RETURN_IDEMPOTENCY_KEY_REUSED` si esa clave ya fue utilizada.

Para MVP no es necesario guardar otro payload hash en `returns`, porque `request_hash` ya vive en `idempotency_keys`. No se define todavia fingerprint adicional sobre `returns`.

### Advisory lock

Mantener transaction advisory lock por `(branch_id, client_operation_id)`. Su funcion es cerrar la ventana concurrente antes de que exista la fila `returns`.

Flujo conceptual futuro:

1. Resolver o reservar `idempotency_key`.
2. Adquirir advisory lock por `branch_id + client_operation_id`.
3. Consultar `returns(branch_id, client_operation_id)`.
4. Si existe, reconciliar/devolver la devolucion existente.
5. Si no existe, continuar.
6. `UNIQUE(branch_id, client_operation_id)` queda como defensa final persistente de PostgreSQL.

No se fija hash ni SQL concreto del advisory lock.

`response_body` debe ser minima, por ejemplo:

- `return_public_id`;
- `folio`;
- `status`;
- `refund_amount`;
- `confirmed_at`.

No guardar ticket completo, XML, PDF, secretos ni datos innecesarios en `idempotency_keys.response_body`.

## 15. Folio

La devolucion usa `document_sequences` con:

- `business_id`;
- `branch_id`;
- `document_type='DEV'`.

Nunca usar `MAX(folio) + 1`.

La secuencia se bloquea dentro de la transaccion operativa. Se forma el folio con `prefix`, `next_number` y `padding`, se incrementa `next_number` y se inserta `returns.folio` dentro del mismo `COMMIT`.

Si hay `ROLLBACK`, el incremento de `next_number` tambien se revierte y no queda folio parcial.

Si no existe secuencia activa `DEV`, devolver `DOCUMENT_SEQUENCE_NOT_FOUND` o `DOCUMENT_SEQUENCE_INACTIVE` segun corresponda.

## 16. Auditoria

Registrar evento minimo en `audit_log`:

- `actor_user_id = user_id`;
- `branch_id`;
- `terminal_id` de la terminal autenticada que ejecuto la confirmacion;
- `action = 'RETURN_CONFIRMED'`;
- `entity_type = 'returns'`;
- `entity_id = returns.id`;
- `entity_public_id = returns.public_id`;
- `after_data` con folio, estado, `refund_amount`, `refund_payment_method_id`, `sale_id`, conteo de lineas y resumen por disposicion;
- `context` con `client_operation_id`, `idempotency_key` truncada o hasheada, cantidades devueltas, motivo general, caja si aplica y version del flujo;
- `occurred_at` por defecto.

No guardar secretos, tokens, credenciales, datos de tarjeta, informacion PAC, CSD ni detalles tecnicos internos.

## 17. Atomicidad y rollback

Una devolucion confirmada debe ser atomica.

Dentro del mismo `COMMIT` deben quedar consistentes:

- `returns`;
- `returns.refund_amount`;
- `returns.refund_payment_method_id`, obligatorio si `refund_amount > 0` y `NULL` si `refund_amount = 0`;
- `return_items`;
- `sales.status` como estado operativo materializado;
- `inventory_balances.quantity_base`, `average_cost_base` y `version` para lineas `RESTOCK`;
- `inventory_movements` para lineas `RESTOCK`;
- un unico `cash_movements RETURN_CASH` si `refund_amount > 0` y `affects_cash = TRUE`;
- `replenishment_positions` si aplica reduccion de demanda por `RESTOCK`;
- `replenishment_movements` solo si `demand_reduction_base > 0`;
- `document_sequences` para `DEV`;
- `audit_log`;
- `idempotency_keys.status='COMPLETED'`.

Dentro del mismo `COMMIT` deben quedar consistentes para la porcion `DAMAGED`:

- `returns`;
- `return_items`;
- `refund_amount`;
- `cash_movements` si aplica;
- `sales.status`;
- `audit_log`;
- idempotencia.

La porcion `DAMAGED` no debe generar efecto sobre:

- `inventory_balances`;
- `inventory_movements`;
- `replenishment_positions`;
- `replenishment_movements`.

Si falla cualquier paso antes de `COMMIT`, PostgreSQL debe hacer `ROLLBACK` completo. No debe quedar:

- devolucion sin reembolso registrado;
- stock agregado sin devolucion;
- promedio ponderado recalculado sin devolucion;
- incremento de `inventory_balances.version` sin devolucion;
- `inventory_movements SALE_RETURN` sin devolucion confirmada;
- caja disminuida sin devolucion;
- reembolso registrado sin movimiento de caja cuando `affects_cash = TRUE`;
- movimiento de caja sin devolucion;
- dos metodos asociados al mismo `returns`;
- demanda compensada sin devolucion;
- folio/documento parcial;
- `sales.status = 'RETURNED'` o `PARTIALLY_RETURNED` si la devolucion correspondiente no quedo confirmada;
- idempotencia `COMPLETED` apuntando a una devolucion inexistente.

Si ocurre `ROLLBACK`, tambien se revierte el cambio de `sales.status`, el incremento de `inventory_balances.quantity_base`, el cambio de `average_cost_base`, el incremento de `version` y los `inventory_movements SALE_RETURN`.

Nunca debe quedar el promedio recalculado sin la devolucion confirmada correspondiente.

La FASE A puede dejar `idempotency_keys.status='IN_PROGRESS'` como lease persistente. Si FASE B falla por dominio deterministico, FASE C puede marcar `FAILED` en una transaccion corta sin escrituras de negocio.

## 18. Concurrencia

### A. Dos usuarios devuelven simultaneamente la ultima unidad retornable

Ambos intentan bloquear la misma `sales` y las mismas `sale_items`. Uno confirma primero. El segundo, al continuar, recalcula `returned_qty_base` con la devolucion confirmada y falla si ya no hay cantidad suficiente.

Resultado esperado: solo uno confirma esa ultima cantidad.

### B. Doble clic en confirmar devolucion

Si ambos intentos usan la misma `idempotency_key` y el mismo `client_operation_id`, `idempotency_keys` protege el mismo request. El primero reserva la clave y ejecuta. El segundo recibe `RETURN_IDEMPOTENCY_IN_PROGRESS` mientras esta en curso o la devolucion ya confirmada cuando la clave queda `COMPLETED`.

Si accidentalmente llega el mismo `client_operation_id` con otra `idempotency_key`, el advisory lock protege la creacion concurrente y la unicidad futura `UNIQUE(branch_id, client_operation_id)` sera la defensa persistente final. Si ya existe la devolucion, se devuelve/reconcilia; no se crea otra.

Resultado esperado: una sola devolucion.

### C. Dos devoluciones parciales distintas sobre la misma sale_item

Ambas se serializan por locks de `sales` y `sale_items`. La segunda recalcula cantidad restante despues de la primera.

Resultado esperado: ambas pueden confirmar si la suma no excede `sale_items.quantity_base`; de lo contrario, la segunda falla con `RETURN_QUANTITY_EXCEEDED`.

### D. Devolucion mientras existe pedido de proveedor comprometido

Si la devolucion es `RESTOCK`, reduce `demand_qty_base` hasta el limite aplicable y no modifica `committed_qty_base`. Si la devolucion es `DAMAGED`, no reduce demanda ni modifica compromiso.

Resultado esperado: para `RESTOCK`, `committed_qty_base` puede quedar mayor que `demand_qty_base` y `available_to_order_base` queda en `0`. Para `DAMAGED`, la demanda se mantiene porque la mercancia no vuelve a stock vendible.

### E. Dos devoluciones generan folio DEV simultaneamente

Ambas bloquean la fila `document_sequences` de `DEV` de forma serializada.

Resultado esperado: folios distintos sin colision.

El lock sobre `sales(sale_id)` tambien serializa la actualizacion de `sales.status`. Las cantidades retornables siguen calculandose con `return_items` de `returns` confirmadas dentro de la transaccion. Despues de insertar la nueva devolucion, el estado de la venta se recalcula o determina antes del `COMMIT`.

## 19. Errores de dominio

Codigos estables propuestos:

- `RETURN_IDEMPOTENCY_IN_PROGRESS`: existe una ejecucion activa para la misma clave.
- `RETURN_IDEMPOTENCY_KEY_REUSED`: la misma clave se uso con `request_hash` diferente.
- `RETURN_IDEMPOTENCY_FAILED`: la clave corresponde a un fallo deterministico previo; preferir devolver el error original almacenado.
- `SALE_NOT_FOUND`: la venta original no existe o no es visible para el negocio/sucursal.
- `SALE_NOT_RETURNABLE`: la venta no esta en estado o condicion retornable.
- `RETURN_QUANTITY_INVALID`: cantidad solicitada nula, negativa o invalida.
- `RETURN_QUANTITY_EXCEEDED`: cantidad solicitada supera lo retornable restante.
- `RETURN_ITEM_SALE_MISMATCH`: el `sale_item_id` no pertenece a `sale_id`.
- `RETURN_DISPOSITION_INVALID`: disposicion distinta de `RESTOCK` o `DAMAGED`.
- `RETURN_DAMAGED_REASON_REQUIRED`: se solicito `disposition = 'DAMAGED'` sin motivo operacional.
- `RETURN_REFUND_METHOD_REQUIRED`: `refund_amount > 0` y no se proporciono metodo de reembolso.
- `RETURN_REFUND_METHOD_INVALID`: metodo de reembolso inexistente, inactivo o de otro negocio.
- `RETURN_REFUND_SPLIT_NOT_SUPPORTED`: el request intenta dividir una misma devolucion entre mas de un metodo de reembolso.
- `RETURN_CASH_SESSION_REQUIRED`: el metodo afecta caja y no se informo `cash_session_id`.
- `RETURN_CASH_SESSION_CLOSED`: la caja no esta `OPEN`.
- `RETURN_CASH_SESSION_MISMATCH`: la caja no pertenece a la sucursal o terminal esperada.
- `RETURN_ALREADY_CONFIRMED`: reservado para flujos futuros que intenten confirmar una devolucion ya existente en estado confirmado.
- `DOCUMENT_SEQUENCE_NOT_FOUND`: no existe secuencia `DEV` para el alcance requerido.
- `DOCUMENT_SEQUENCE_INACTIVE`: la secuencia existe pero no esta activa.
- `USER_BRANCH_FORBIDDEN`: el usuario no pertenece a la sucursal.
- `USER_PERMISSION_DENIED`: el usuario no tiene `RETURNS_CONFIRM`.
- `TERMINAL_INACTIVE`: terminal inexistente, revocada o no activa.
- `TERMINAL_BRANCH_MISMATCH`: terminal fuera de la sucursal.
- `BRANCH_INACTIVE`: sucursal inexistente o inactiva.
- `USER_INACTIVE`: usuario inexistente o inactivo.

No se definen HTTP status codes en este documento.

## 20. Decisiones y gaps pendientes

Cambio fisico requerido posterior a db-2, ya decidido:

- agregar `returns.client_operation_id TEXT NOT NULL`;
- agregar `UNIQUE(branch_id, client_operation_id)`.

No se agrega `returns.terminal_id` al listado de cambios fisicos requeridos para el MVP. `terminal_id` queda como contexto operativo validado y auditado, no como identidad funcional de la devolucion.

No se agrega `sales.deleted_at`, `sales.deleted_by`, `sales.is_deleted` ni columna equivalente al futuro modelo fisico requerido por este flujo. La preservacion historica de ventas confirmadas se garantiza mediante la politica de no eliminacion fisica en operacion normal.

Decision definitiva sobre reembolsos multiples:

- un unico metodo de reembolso por `returns`;
- split refund fuera del MVP;
- no se agrega `return_payments`, `return_refund_payments`, `refund_allocations` ni tabla equivalente;
- no se requiere cambio fisico por esta decision.

Gaps de diseno que siguen pendientes:

- Desglose fiscal / tratamiento CFDI: `return_items` solo guarda `refund_amount`, no desglose de subtotal, descuento e impuesto devuelto.
