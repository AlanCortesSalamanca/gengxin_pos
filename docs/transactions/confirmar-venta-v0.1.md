# CONFIRMAR VENTA v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia física: `docs/database/modelo-fisico-v0.5-db-2.md` y `database/schema-v0.5-db-2.sql` validado en PostgreSQL 17.11.

Este documento diseña conceptualmente la transacción `CONFIRMAR VENTA`. No define framework, API, DTOs, servicios, repositorios ni código.

## 1. Objetivo

Confirmar una venta de forma atómica, trazable e idempotente, garantizando que:

- un retry, doble clic o pérdida de respuesta no cree dos ventas;
- terminal, sucursal, usuario, caja, cliente, lista de precios, productos, unidades y pagos sean válidos al momento de confirmar;
- el stock se revalide dentro de la transacción, no con base en una pantalla previa;
- inventario, caja, reposición, folio, cotización e idempotencia queden consistentes;
- ante cualquier fallo antes de `COMMIT`, no quede una venta parcial ni movimientos aislados.

## 2. Entradas conceptuales

La operación requiere, como mínimo:

- `business_id` derivado de la sucursal o contexto autenticado.
- `branch_id` objetivo de la venta.
- `terminal_id` autenticada.
- `user_id` actor.
- `cash_session_id` abierta.
- `client_operation_id` generado por el cliente POS para deduplicación local.
- `idempotency_key` de operación crítica.
- `request_hash` canónico del payload de confirmación.
- `customer_id` opcional.
- `price_list_id` efectiva.
- líneas con `product_id`, `product_unit_id`, cantidad, precio esperado, descuentos e impuestos calculados.
- pagos con `payment_method_id`, importe y referencia opcional.
- `quotation_id` opcional si la venta viene de cotización.

## 3. Validaciones

### Idempotencia

- Validar que `idempotency_key` exista en la solicitud y se registre con `operation_type = 'CONFIRM_SALE'`.
- Validar que `request_hash` corresponda exactamente al payload canónico esperado.
- Validar `client_operation_id` no vacío.
- Si ya existe `sales(branch_id, client_operation_id)`, devolver esa venta existente como defensa secundaria de deduplicación local. `sales` no guarda `request_hash`, por lo que no debe afirmarse que desde esa tabla se detecta payload distinto.

### Terminal, sucursal y usuario

- Validar que `branches.id = branch_id` exista, esté activa y pertenezca al `business_id` esperado.
- Validar que `terminals.id = terminal_id` exista, esté `ACTIVE` y pertenezca a la misma `branch_id`.
- Validar que `users.id = user_id` exista y esté `ACTIVE`.
- Validar que el usuario pueda operar la sucursal mediante `user_branches(user_id, branch_id)`.
- Validar permiso funcional de confirmar venta mediante roles/permisos. El código exacto de permiso queda pendiente de catálogo, pero la transacción debe exigirlo antes de escribir.

### Caja

- Validar que `cash_sessions.id = cash_session_id` exista, esté `OPEN` y pertenezca a la misma `branch_id` y `terminal_id`.
- La FK compuesta de `sales(cash_session_id, branch_id, terminal_id)` protege esta relación, pero debe fallar como error de dominio antes de llegar a error SQL.

### Cliente y lista de precios

- Si hay `customer_id`, validar que el cliente exista, esté activo y pertenezca al mismo `business_id`.
- Validar que `price_list_id` exista, esté activa, pertenezca al mismo `business_id` y use la moneda de la operación.
- Si el cliente define una lista propia, validar que la lista de la venta sea compatible con la política comercial vigente.

### Productos, unidades y precios

- Validar que cada producto exista, esté activo y pertenezca al `business_id`.
- Validar que cada `product_unit_id` exista, esté activo y pertenezca al mismo `product_id`.
- Validar `factor_to_base > 0` y convertir `quantity_base = quantity * factor_to_base`.
- Validar cantidades positivas.
- Validar que exista precio activo en `product_prices(price_list_id, product_id, product_unit_id)`.
- Validar precio no negativo.
- Para venta directa, usar precio activo vigente de `product_prices`. Si el POS envía un precio distinto al vigente, aplicar la política de `PRICE_CHANGED`.
- Para venta desde cotización `ISSUED` y vigente, conservar precio, descuento e impuestos snapshot de la cotización. Un cambio posterior en `product_prices` no provoca `PRICE_CHANGED`.
- Validar descuentos no negativos y que no excedan subtotal de línea ni total de documento.
- Validar impuestos con el `tax_profile` del producto y snapshots calculados.

### Pagos y canal de reposición

- Validar que cada `payment_method_id` exista, esté activo y pertenezca al `business_id`.
- Resolver `replenishment_channel` desde `payment_methods.replenishment_channel`.
- En MVP, impedir mezcla de canales `CASH` y `TRANSFER` dentro de la misma venta.
- Validar que la suma de `sale_payments.amount` sea exactamente igual al total de la venta según regla de redondeo definida.
- Registrar todos los pagos en `sale_payments`, aunque no todos afecten caja física.

### Stock

- Bloquear `inventory_balances` de todos los productos vendidos para la sucursal.
- Revalidar stock dentro de la transacción.
- Rechazar si `quantity_base` solicitada por producto excede `inventory_balances.quantity_base`.
- Impedir stock negativo. La constraint `ck_inventory_balances_quantity_non_negative` queda como última defensa, no como validación principal.

### Cotización opcional

- Si existe `quotation_id`, bloquear la cotización.
- Validar misma `branch_id`.
- Validar estado apropiado para conversión, típicamente `ISSUED`.
- Validar que `converted_sale_id IS NULL` y que no esté `CONVERTED`, `EXPIRED` ni `CANCELLED`.
- Validar vigencia con `valid_until`.
- Si la cotización está vencida, no recalcularla silenciosamente; devolver `QUOTATION_EXPIRED`. La reemisión o revalidación será otro flujo.
- Conservar precio, descuento e impuestos snapshot de la cotización emitida y vigente.
- Revalidar producto/unidad válidos, stock, cliente, pagos, canal, permisos, estado y vigencia; una cotización no reserva inventario ni caja.

## 4. Estrategia de idempotencia

Se usan dos defensas complementarias:

- `idempotency_keys` es la defensa primaria: evita duplicados por retry HTTP, doble clic o pérdida de respuesta, y permite validar `request_hash`.
- `sales.client_operation_id` con `UNIQUE(branch_id, client_operation_id)` es una defensa secundaria de deduplicación local incluso si cambia la clave idempotente.
- Un transaction advisory lock determinista por `(branch_id, client_operation_id)` cierra la ventana en la que todavía no existe fila en `sales`.

### Adquisición de clave

Al iniciar la operación se intenta adquirir `idempotency_keys` con:

- `business_id`.
- `branch_id`.
- `operation_type = 'CONFIRM_SALE'`.
- `idempotency_key`.
- `request_hash`.
- `status = 'IN_PROGRESS'`.
- `locked_until` corto para recuperación de procesos caídos.
- `expires_at` según política de retención.

La fila debe bloquearse con semántica equivalente a `SELECT ... FOR UPDATE` sobre la clave única `(business_id, operation_type, idempotency_key)`.

### Barrera por `client_operation_id`

Después de adquirir o resolver `idempotency_key`, la transacción debe adquirir una barrera PostgreSQL mediante transaction advisory lock para `(branch_id, client_operation_id)`, conceptualmente con `pg_advisory_xact_lock(...)`. No se fija todavía la función o hash exacto de implementación.

El flujo es:

1. adquirir o resolver `idempotency_key`;
2. adquirir advisory lock determinista de `branch_id + client_operation_id`;
3. consultar `sales(branch_id, client_operation_id)`;
4. si existe, devolver la venta ya creada;
5. si no existe, continuar.

El advisory lock se libera automáticamente al `COMMIT` o `ROLLBACK`. La constraint `UNIQUE(branch_id, client_operation_id)` sigue siendo la última defensa en PostgreSQL.

Si ya existe una venta con el mismo `client_operation_id` pero otra `idempotency_key`, se devuelve la venta existente. Si en el futuro se quiere detectar reutilización de `client_operation_id` con payload distinto, será necesario persistir un fingerprint específico o adoptar otra política explícita.

### Si la clave está `IN_PROGRESS`

- Si otra transacción mantiene el lock, devolver `SALE_IDEMPOTENCY_IN_PROGRESS` o esperar con timeout corto configurado.
- Si `locked_until` expiró, puede recuperarse la clave solo si no hay `result_entity_id` y el `request_hash` coincide.
- Si el `request_hash` no coincide, devolver `SALE_IDEMPOTENCY_KEY_REUSED`.

### Si la clave está `COMPLETED`

- Validar que el `request_hash` coincida.
- No crear una nueva venta.
- Devolver la respuesta persistida en `response_body` o reconstruir respuesta desde `result_entity_type='sales'` y `result_entity_id`.

### Si la clave está `FAILED`

- Si el `request_hash` no coincide, devolver `SALE_IDEMPOTENCY_KEY_REUSED`.
- Si el fallo fue de dominio determinístico, devolver el mismo error almacenado.
- Si el fallo fue técnico recuperable y no existe `result_entity_id`, se puede permitir reintento cambiando la fila a `IN_PROGRESS` con nuevo `locked_until`; esta política requiere revisión antes de implementación.

### Relación con rollback

Si la fila `IN_PROGRESS` se crea dentro de la misma transacción y luego ocurre `ROLLBACK`, esa fila también desaparece. Esto evita basura transaccional, pero no persiste el error. Para errores de dominio que se quiera cachear como `FAILED`, debe manejarse una ruta controlada: terminar sin escrituras operativas, actualizar `idempotency_keys.status = 'FAILED'` con `error_code/error_message`, y hacer `COMMIT` solo de la clave. Esta decisión debe implementarse deliberadamente, no como efecto accidental de excepciones SQL.

## 5. Orden definitivo de locks

El orden debe ser determinista para reducir deadlocks:

1. `idempotency_keys` por `(business_id, operation_type='CONFIRM_SALE', idempotency_key)`.
2. Transaction advisory lock por `(branch_id, client_operation_id)`.
3. `sales` por `(branch_id, client_operation_id)` si existe una venta previa para la misma operación local.
4. `quotations` por `quotation_id` si aplica.
5. `cash_sessions` por `cash_session_id`.
6. Catálogos validados por lectura consistente: `branches`, `terminals`, `users`, `user_branches`, `customers`, `price_lists`, `products`, `product_units`, `product_prices`, `payment_methods`.
7. `inventory_balances` de la sucursal en orden estable `ORDER BY product_id`.
8. `replenishment_positions` existentes en orden estable `ORDER BY product_id, channel`; si no existen, se crean con UPSERT determinista por producto/canal.
9. `document_sequences` para `business_id`, `branch_id`, `document_type = 'VEN'`.

Nota crítica: el folio se bloquea después de revalidar inventario para no mantener la secuencia bloqueada mientras se resuelven productos. Aun así, el folio se reserva antes de insertar `sales` y dentro de la misma transacción.

## 6. Orden transaccional propuesto

### BEGIN

1. Adquirir o resolver idempotencia.
2. Si la operación ya está `COMPLETED`, devolver la venta existente sin crear nada.
3. Adquirir advisory lock determinista por `(branch_id, client_operation_id)`.
4. Verificar venta previa por `sales(branch_id, client_operation_id)`; si existe, devolverla.
5. Validar `branch`, `terminal`, `user`, permisos y pertenencia a sucursal.
6. Bloquear y validar `cash_session` abierta de la misma sucursal y terminal.
7. Bloquear y validar cotización si aplica.
8. Resolver y validar cliente, lista de precios, productos, unidades, precios, descuentos e impuestos.
9. Resolver métodos de pago y `replenishment_channel`.
10. Rechazar mezcla de canales `CASH` / `TRANSFER` para MVP.
11. Validar total de pagos contra total de venta.
12. Agregar cantidades por `product_id` para evitar doble descuento si el producto aparece en varias líneas.
13. Bloquear `inventory_balances` por `branch_id` y productos agregados, en orden `product_id`.
14. Revalidar stock suficiente y capturar `average_cost_base` como costo de salida.
15. Bloquear o preparar `replenishment_positions` por `branch_id`, `product_id`, `channel` en orden estable.
16. Bloquear `document_sequences` de `VEN` para la sucursal.
17. Reservar folio incrementando `next_number`.
18. Insertar `sales` con `status='CONFIRMED'`, folio, canal, snapshots y totales.
19. Insertar `sale_items` con snapshots comerciales, `quantity_base` y `unit_cost_snapshot` desde `inventory_balances.average_cost_base`.
20. Actualizar `inventory_balances.quantity_base = quantity_base - vendido_base`, conservar `average_cost_base` e incrementar `version`.
21. Insertar `inventory_movements` tipo `SALE` con `quantity_delta_base` negativo, costo snapshot y `balance_after_base`.
22. Insertar `sale_payments` con snapshot de método y canal.
23. Insertar `cash_movements` solo para pagos cuyo `payment_methods.affects_cash = TRUE`; para efectivo usar `movement_type='SALE_CASH'` y `amount_delta > 0`.
24. Actualizar o crear `replenishment_positions` incrementando `demand_qty_base`; no modificar `committed_qty_base`.
25. Insertar un `replenishment_movements` por cada `sale_item`, con `reference_entity_type='sale_items'` y `reference_entity_id=sale_items.id`.
26. Convertir cotización si aplica: actualizar `quotations.status='CONVERTED'` y `converted_sale_id=sale.id`.
27. Insertar `audit_log` de venta confirmada.
28. Marcar `idempotency_keys.status='COMPLETED'`, `result_entity_type='sales'`, `result_entity_id=sale.id` y `response_body` mínima.

### COMMIT

## 7. Escrituras definitivas

La transacción crea o actualiza:

- `idempotency_keys`: `IN_PROGRESS` al inicio y `COMPLETED` al final si confirma.
- `document_sequences`: incremento de `next_number` para `VEN`.
- `sales`: cabecera confirmada.
- `sale_items`: líneas con snapshots y costo unitario snapshot.
- `sale_payments`: todos los pagos recibidos.
- `inventory_balances`: reducción de existencias por producto y sucursal; `average_cost_base` no se recalcula.
- `inventory_movements`: movimientos `SALE` negativos append-only.
- `cash_movements`: solo pagos que afectan caja física.
- `replenishment_positions`: incremento de demanda por `branch_id`, `product_id`, `channel`; `available_to_order_base` lo calcula PostgreSQL.
- `replenishment_movements`: movimientos append-only de demanda, uno por línea de venta, referenciando `sale_items`.
- `quotations`: solo si aplica conversión, queda `CONVERTED` con `converted_sale_id`.
- `audit_log`: evento mínimo de venta confirmada.

## 8. Inventario

Para cada línea:

- convertir cantidad de presentación a unidad base con `product_units.factor_to_base`;
- agrupar por producto para comparar contra saldo real;
- bloquear `inventory_balances(branch_id, product_id)`;
- validar stock suficiente dentro de la transacción;
- descontar `quantity_base`;
- conservar `average_cost_base`;
- guardar `sale_items.unit_cost_snapshot = inventory_balances.average_cost_base`;
- crear `inventory_movements.movement_type='SALE'` con delta negativo.

Las ventas no recalculan costo promedio. El costo promedio cambia en entradas o ajustes que correspondan, no en una salida normal.

## 9. Caja

`sale_payments` registra todos los pagos, incluso tarjeta o transferencia.

`cash_movements` se crea solamente cuando `payment_methods.affects_cash = TRUE`.

Para efectivo:

- `movement_type = 'SALE_CASH'`;
- `amount_delta` positivo;
- `cash_session_id` de la sesión bloqueada;
- referencia a la venta;
- `actor_user_id = user_id`.

No se debe asumir que toda venta genera caja física.

## 10. Reposición

La venta incrementa demanda de reposición por producto y canal.

Para cada producto vendido:

- actualizar `replenishment_positions(branch_id, product_id, channel)`;
- incrementar `demand_qty_base`;
- no modificar `committed_qty_base`;
- dejar que `available_to_order_base` se calcule como `GREATEST(demand_qty_base - committed_qty_base, 0)`;
- insertar `replenishment_movements` con `demand_delta_base > 0`, `committed_delta_base = 0`.

Para demanda originada por venta, la referencia estándar es:

- `reference_entity_type = 'sale_items'`;
- `reference_entity_id = sale_items.id`;
- un `replenishment_movement` por cada línea de venta.

Si el mismo producto aparece en varias líneas, `inventory_balances` y `replenishment_positions` pueden actualizarse con cantidad agregada por `product_id`, pero el ledger `replenishment_movements` conserva granularidad por `sale_item`. Esto facilita devoluciones, `replenishment_allocations`, trazabilidad FIFO y auditoría de qué venta/línea originó la demanda.

Si ya existe `committed_qty_base > demand_qty_base`, la venta puede aumentar demanda y `available_to_order_base` seguirá siendo `0` hasta que la demanda supere lo comprometido.

## 11. Folio

La generación usa `document_sequences`; nunca `MAX(folio) + 1`.

La transacción debe:

- localizar la secuencia activa por `business_id`, `branch_id`, `document_type='VEN'`;
- bloquearla con `SELECT ... FOR UPDATE`;
- formar el folio con `prefix`, `next_number` y `padding`;
- incrementar `next_number`;
- usar el folio reservado en `sales.folio` dentro del mismo `COMMIT`.

Si la transacción hace `ROLLBACK` después de incrementar `next_number`, el incremento se revierte porque vive en la misma transacción. Por tanto no queda folio consumido sin venta. Si en el futuro se decide permitir huecos de folio por auditoría, debe documentarse como cambio explícito.

## 12. Cotización

Cuando la venta proviene de cotización:

- bloquear `quotations` al inicio del flujo, antes de inventario y folio;
- validar `branch_id` igual al de la venta;
- validar estado convertible;
- validar `converted_sale_id IS NULL`;
- validar vigencia;
- conservar precio, descuento e impuestos snapshot si la cotización está `ISSUED` y dentro de `valid_until`;
- devolver `QUOTATION_EXPIRED` si está vencida, sin recalcular silenciosamente;
- revalidar stock;
- crear la venta;
- actualizar `quotations.converted_sale_id = sales.id`;
- actualizar `quotations.status = 'CONVERTED'`.

Dos conversiones simultáneas de la misma cotización compiten por el lock de la fila; solo una puede observarla convertible.

## 13. Auditoría

Evento mínimo en `audit_log`:

- `actor_user_id = user_id`;
- `branch_id`;
- `terminal_id`;
- `action = 'SALE_CONFIRMED'`;
- `entity_type = 'sales'`;
- `entity_id = sales.id`;
- `entity_public_id = sales.public_id`;
- `after_data` con folio, total, moneda, canal, `cash_session_id`, conteo de líneas y conteo de pagos;
- `context` con `client_operation_id`, `idempotency_key` truncada o hasheada, `quotation_id` si aplica, origen POS y versión de flujo;
- `occurred_at` por defecto.

No guardar contraseñas, tokens, secretos, CSD, claves PAC ni datos sensibles innecesarios.

## 14. Nivel de aislamiento

Nivel de aislamiento propuesto para `CONFIRMAR VENTA`: `READ COMMITTED` + locks explícitos.

Justificación:

- `inventory_balances` se bloquea explícitamente;
- `cash_sessions` se bloquea;
- `quotations` se bloquea si aplica;
- `replenishment_positions` se serializa explícitamente;
- `document_sequences` se bloquea;
- idempotencia y `client_operation_id` tienen barreras explícitas mediante `idempotency_keys` y advisory lock transaccional.

No usar `SERIALIZABLE` por defecto en el MVP. Esta decisión podrá revisarse si las pruebas concurrentes encuentran una anomalía real.

## 15. Rollback y fallos

Si falla cualquier paso antes de `COMMIT`, PostgreSQL revierte:

- `sales`;
- `sale_items`;
- `sale_payments`;
- descuentos de `inventory_balances`;
- `inventory_movements`;
- `cash_movements`;
- `replenishment_positions` y `replenishment_movements`;
- conversión de cotización;
- incremento de `document_sequences.next_number`;
- evento de `audit_log`;
- cambio final de `idempotency_keys`.

No queda venta parcial, inventario descontado, movimiento de caja aislado, demanda de reposición aislada, cotización convertida sin venta ni folio confirmado de forma inconsistente.

Consideración de idempotencia: si la clave se crea en la misma transacción y todo hace `ROLLBACK`, la clave desaparece. Esto permite retry limpio, pero no conserva el motivo del fallo. Persistir errores `FAILED` exige una ruta controlada separada que no haga escrituras operativas.

## 16. Errores de dominio

Códigos propuestos:

- `SALE_IDEMPOTENCY_IN_PROGRESS`
- `SALE_IDEMPOTENCY_KEY_REUSED`
- `SALE_IDEMPOTENCY_FAILED`
- `SALE_ALREADY_CONFIRMED`
- `TERMINAL_INACTIVE`
- `TERMINAL_BRANCH_MISMATCH`
- `BRANCH_INACTIVE`
- `USER_INACTIVE`
- `USER_BRANCH_FORBIDDEN`
- `USER_PERMISSION_DENIED`
- `CASH_SESSION_REQUIRED`
- `CASH_SESSION_CLOSED`
- `CASH_SESSION_TERMINAL_MISMATCH`
- `CUSTOMER_INACTIVE`
- `CUSTOMER_BUSINESS_MISMATCH`
- `PRICE_LIST_INACTIVE`
- `PRICE_LIST_BUSINESS_MISMATCH`
- `PRODUCT_INACTIVE`
- `PRODUCT_BUSINESS_MISMATCH`
- `PRODUCT_UNIT_INVALID`
- `PRICE_NOT_FOUND`
- `PRICE_CHANGED`
- `INVALID_QUANTITY`
- `INVALID_DISCOUNT`
- `INVALID_TAX_CALCULATION`
- `INSUFFICIENT_STOCK`
- `PAYMENT_METHOD_INACTIVE`
- `PAYMENT_TOTAL_MISMATCH`
- `MIXED_REPLENISHMENT_CHANNELS`
- `DOCUMENT_SEQUENCE_NOT_FOUND`
- `DOCUMENT_SEQUENCE_INACTIVE`
- `QUOTATION_NOT_FOUND`
- `QUOTATION_ALREADY_CONVERTED`
- `QUOTATION_BRANCH_MISMATCH`
- `QUOTATION_EXPIRED`
- `QUOTATION_STATUS_INVALID`

No se definen HTTP status codes en este documento.

## 17. Casos de concurrencia

### A. Dos terminales venden simultáneamente la última unidad

Ambas intentan bloquear el mismo `inventory_balances(branch_id, product_id)`. Una descuenta y confirma. La otra, al adquirir el lock después, revalida el saldo actualizado y falla con `INSUFFICIENT_STOCK`.

Resultado esperado: solo una confirma.

### B. Doble clic en una misma terminal

Ambos intentos usan la misma `idempotency_key` y `client_operation_id`. El primero adquiere la clave y confirma. El segundo recibe `SALE_IDEMPOTENCY_IN_PROGRESS` si llega durante la ejecución, o la venta ya creada si llega después del `COMMIT`.

Resultado esperado: una sola venta.

### C. Mismo `client_operation_id` enviado después de `COMMIT`

La unicidad `sales(branch_id, client_operation_id)` ya contiene la venta. Devolver la venta existente aunque llegue con otra `idempotency_key`. Como `sales` no almacena `request_hash`, no se detecta payload distinto solo con esta tabla; esa validación futura requerirá persistir un fingerprint específico o definir otra política explícita.

Resultado esperado: devolver la venta ya creada, no crear otra.

### D. Dos intentos simultáneos de convertir la misma cotización

Ambos intentan bloquear `quotations(id)`. Solo uno observa estado convertible y asigna `converted_sale_id`. El otro, al continuar, ve `CONVERTED` o `converted_sale_id` no nulo y falla con `QUOTATION_ALREADY_CONVERTED`.

Resultado esperado: solo uno puede convertirla.

### E. Dos ventas simultáneas generan folio

Ambas bloquean la misma fila de `document_sequences` de forma serializada. Cada una lee un `next_number` distinto después del incremento confirmado de la anterior.

Resultado esperado: folios distintos sin colisión.

## 18. Decisiones pendientes

- Definir código exacto de permiso para confirmar venta.
- Definir regla de redondeo para comparar pagos contra total.
- Definir timeout y política de espera para `SALE_IDEMPOTENCY_IN_PROGRESS`.
- Definir si errores de dominio se persisten como `FAILED` en `idempotency_keys` o si solo se cachean operaciones completadas.
- Definir retención de `idempotency_keys.expires_at` y tamaño permitido de `response_body`.
- Definir si se persistirá un fingerprint adicional para detectar reutilización de `client_operation_id` con payload distinto.
