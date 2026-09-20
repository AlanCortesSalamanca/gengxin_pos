# CONFIRMAR PEDIDO A PROVEEDOR v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica vigente: `docs/database/modelo-fisico-v0.5-db-3.md` y `database/schema-v0.5-db-3.sql`. PostgreSQL v0.5-db-3 esta VALIDADO / CONGELADO.

## Estado del diseno

- Estado: VALIDADO / CONGELADO
- Version: v0.1
- Implementacion: todavia no iniciada

Este documento disena conceptualmente la transaccion `CONFIRMAR PEDIDO A PROVEEDOR`. No define framework, API, DTOs, endpoints, servicios, repositorios, frontend, backend ni stack de aplicacion.

## 1. Principio fundamental

`CONFIRMAR PEDIDO` no crea un pedido nuevo.

La operacion trabaja sobre un `purchase_orders` ya persistido previamente con `status = 'DRAFT'`.

El `DRAFT` y sus `purchase_order_items` son la fuente autoritativa del contenido.

Las ediciones del `DRAFT` son otro flujo.

`CONFIRMAR PEDIDO`:

- no recibe las lineas como autoridad;
- no reescribe silenciosamente cantidades;
- no crea otra cabecera;
- no genera un nuevo folio;
- no modifica `document_sequences`.

## 2. Identidad del pedido

Decision cerrada: la identidad persistente secundaria de la operacion es `purchase_order_id` del `DRAFT` existente.

No se agrega `purchase_orders.client_operation_id`.

La idempotencia primaria usa `idempotency_keys`.

El patron conceptual es:

- `idempotency_keys`;
- `purchase_order_id` existente.

No se requiere db-4 para `CONFIRMAR PEDIDO A PROVEEDOR v0.1`.

Esto difiere de `CONFIRMAR VENTA` y `CONFIRMAR DEVOLUCION`: en esos flujos la entidad final (`sales` o `returns`) todavia no existia al iniciar la operacion critica. En `CONFIRMAR PEDIDO`, la fila `purchase_orders` ya existe como `DRAFT` antes de confirmar.

## 3. Entradas conceptuales

La operacion requiere, como minimo:

- `business_id` derivado de la sucursal o contexto autenticado;
- `branch_id`;
- `user_id`;
- `purchase_order_id`;
- `idempotency_key`;
- `request_hash`;
- `expected_draft_fingerprint`.

El request de confirmacion no incluye las lineas del pedido como autoridad.

`expected_draft_fingerprint`:

- es una precondicion optimista;
- se calcula a nivel servicio;
- representa cabecera y lineas relevantes del `DRAFT`;
- no es columna;
- no es identidad;
- no sustituye `request_hash`;
- no se persiste como fingerprint permanente;
- no requiere cambio fisico.

No se define algoritmo criptografico en este documento.

## 3.1. AUTORIZACION DE CONFIRMAR PEDIDO A PROVEEDOR

Permiso funcional definitivo MVP:

```text
PURCHASE_ORDERS_CONFIRM
```

Se mantiene la convencion conceptual `<MODULE>_<ACTION>`, consistente con permisos como `SALES_CONFIRM` y `RETURNS_CONFIRM`.

No usar nombres de rol como autorizacion.

Modelo de autorizacion existente:

- `users`;
- `user_roles`;
- `roles`;
- `role_permissions`;
- `permissions`;
- `user_branches`.

Un usuario puede confirmar un pedido a proveedor unicamente si:

- `users.status = 'ACTIVE'`;
- existe `user_branches(user_id, branch_id)`;
- posee al menos un `roles.active = TRUE` del `business_id` correspondiente;
- uno de esos roles tiene `permissions.code = 'PURCHASE_ORDERS_CONFIRM'`.

El permiso funcional no autoriza automaticamente todas las sucursales.

Se requieren ambas condiciones:

- acceso explicito a `branch_id`;
- `PURCHASE_ORDERS_CONFIRM`.

Si el usuario no pertenece a la sucursal, devolver `USER_BRANCH_FORBIDDEN`.

Si pertenece a la sucursal pero no tiene el permiso funcional, devolver `USER_PERMISSION_DENIED`.

Estos errores se mantienen compartidos con otros contratos.

Si `users.status <> 'ACTIVE'`, rechazar la confirmacion antes de efectos operativos con codigo conceptual `USER_INACTIVE`.

No existe bypass especial por nombre de rol. Un rol llamado `ADMIN`, `MANAGER` o `PURCHASING_MANAGER` no autoriza por si mismo.

Incluso un administrador debe poseer `PURCHASE_ORDERS_CONFIRM` mediante `role_permissions`.

La autorizacion debe ocurrir:

- despues de resolver/reservar idempotencia;
- dentro de FASE B antes de cualquier efecto operativo;
- antes de crear allocations;
- antes de incrementar `committed_qty_base`;
- antes de crear `ORDER_RESERVE`;
- antes de cambiar `purchase_orders` a `CONFIRMED`.

Debe ocurrir despues de bloquear `purchase_orders(id)` y antes de cualquier reconciliacion por estado del pedido para una key nueva o `IN_PROGRESS` recuperable. El lock es necesario para serializar el agregado, pero no autoriza por si mismo devolver o reconciliar un pedido confirmado.

No cambiar el orden global de locks por esta validacion.

Tambien se debe validar que `purchase_orders.branch_id = branch_id` esperado y que esa sucursal pertenezca al `business_id` del contexto.

No permitir confirmar un pedido de otra sucursal usando unicamente el id.

Tampoco permitir reconciliar/devolver un pedido ya confirmado de otra sucursal o sin autorizacion suficiente usando una nueva `idempotency_key` o una key `IN_PROGRESS` recuperable.

Los codigos aplicables de sucursal/business para `CONFIRM_ORDER` quedan definidos en el catalogo de errores de este documento.

Este micro-hito solo define el contrato. No insertar `permissions`, crear seeds, modificar schema ni modificar db-3.

## 3.2. Catalogo definitivo de errores de dominio CONFIRM_ORDER

Este catalogo aplica a `operation_type = 'CONFIRM_ORDER'`.

No define HTTP status, response envelope, endpoint, DTO ni textos de UI/localizacion.

Cuando se persista `error_message` en `idempotency_keys`, debe ser seguro, breve, sin secretos, sin hashes completos, sin SQL y sin stack traces.

### Catalogo definitivo

Idempotencia:

- `ORDER_IDEMPOTENCY_KEY_REUSED`;
- `ORDER_IDEMPOTENCY_IN_PROGRESS`.

Autorizacion:

- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`.

Sucursal / business:

- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`;
- `PURCHASE_ORDER_BRANCH_MISMATCH`.

Pedido:

- `PURCHASE_ORDER_NOT_FOUND`;
- `PURCHASE_ORDER_STATUS_INVALID`;
- `PURCHASE_ORDER_EMPTY`;
- `ORDER_DRAFT_STALE`;
- `ORDER_REPLENISHMENT_STALE`.

Proveedor:

- `SUPPLIER_INACTIVE`;
- `SUPPLIER_BUSINESS_MISMATCH`.

Producto / unidad:

- `PRODUCT_INACTIVE`;
- `PRODUCT_BUSINESS_MISMATCH`;
- `PRODUCT_UNIT_INVALID`.

### ORDER_DRAFT_STALE

`ORDER_DRAFT_STALE` ocurre cuando el `expected_draft_fingerprint` recibido no coincide con el fingerprint autoritativo del `DRAFT` persistido.

Significa que el contenido del `DRAFT` cambio desde que el usuario lo reviso.

Comportamiento:

- rechazar antes de efectos operativos;
- no exponer hashes completos;
- tratar como error deterministico;
- la `idempotency_key` actual termina `FAILED`;
- para corregir, usar nueva `idempotency_key`, nuevo `request_hash` y nuevo `expected_draft_fingerprint`.

Mensaje seguro conceptual: "El pedido fue modificado desde la ultima revision. Actualiza y revisa el borrador antes de confirmarlo."

### ORDER_REPLENISHMENT_STALE

`ORDER_REPLENISHMENT_STALE` ocurre cuando, despues de bloquear `replenishment_positions`, para algun `branch/product/channel` afectado, se cumple cualquiera de estas condiciones:

```text
SUM(replenishment_qty_base persistido aplicable) > available_to_order_base actual

SUM(replenishment_qty_base persistido aplicable) > total_sale_item_reservable seguro
```

Tambien aplica si, despues de recomputar bajo las barreras de concurrencia, el conjunto de `sale_items` prebloqueados ya no puede materializar integramente la reserva requerida.

Significa que el `DRAFT` puede seguir siendo exactamente el mismo, pero cambio externamente la demanda de reposicion disponible o ya no puede trazarse integramente por FIFO.

Comportamiento:

- rechazar toda la confirmacion;
- no reservar parcialmente;
- no convertir excedente a `stock_extra`;
- no modificar `purchase_order_items`;
- exigir revisar/reclasificar el `DRAFT`;
- no hacer retry interno automatico de FASE B;
- tratar como error deterministico;
- la `idempotency_key` actual termina `FAILED`.

Mensaje seguro conceptual: "La demanda de reposicion cambio. Revisa las cantidades del pedido antes de confirmarlo."

No exponer cantidades internas innecesarias en `error_message` si no son necesarias.

### PURCHASE_ORDER_EMPTY

`PURCHASE_ORDER_EMPTY` ocurre cuando, despues de bloquear `purchase_orders` y obtener las lineas, no existe ninguna `purchase_order_item` del pedido.

Un pedido puede permanecer vacio mientras esta `DRAFT`, pero no puede confirmarse sin al menos una linea valida.

Debe fallar antes de:

- bloquear `replenishment_positions`;
- crear `replenishment_allocations`;
- crear `ORDER_RESERVE`;
- cambiar `purchase_orders` a `CONFIRMED`.

Es error deterministico.

Mensaje seguro conceptual: "El pedido debe contener al menos una linea antes de confirmarse."

No requiere constraint fisico.

### Pedido y estado

`PURCHASE_ORDER_NOT_FOUND` se usa cuando `purchase_order_id` no corresponde a un `purchase_orders` visible/valido para la operacion. No revelar informacion sensible de pedidos de otros tenants.

`PURCHASE_ORDER_BRANCH_MISMATCH` se usa cuando el pedido fue localizado de forma segura pero `purchase_orders.branch_id != branch_id` esperado del comando/contexto. No intentar confirmar ni reconciliar efectos de otra sucursal.

`PURCHASE_ORDER_STATUS_INVALID` se usa unicamente para intento nuevo de confirmar un estado no confirmable sin evidencia de confirmacion historica.

Aplica a `CLOSED` y `CANCELLED` cuando no existen ambas evidencias:

- `confirmed_at`;
- `confirmed_by_user_id`.

No se usa para `CONFIRMED`, porque `CONFIRMED` se reconcilia idempotentemente.

No se usa para `CLOSED`/`CANCELLED` con evidencia historica de confirmacion, porque esos casos tambien se reconcilian.

No crear un error especifico de pedido ya confirmado.

### Branch / business

`BRANCH_INACTIVE` reutiliza el codigo compartido para sucursal del contexto inexistente, invalida o no operativa/activa para la operacion. No se crea `BRANCH_NOT_FOUND` en este contrato.

`BRANCH_BUSINESS_MISMATCH` ocurre cuando `branch_id` no pertenece al `business_id` esperado del contexto.

`BRANCH_BUSINESS_MISMATCH` es inconsistencia tenant/business del recurso/contexto. `USER_BRANCH_FORBIDDEN` es falta de acceso del usuario a una sucursal valida.

### Proveedor

`SUPPLIER_INACTIVE` ocurre si el proveedor del `DRAFT` existe pero `suppliers.active = FALSE`.

`SUPPLIER_BUSINESS_MISMATCH` ocurre si `supplier_id` no pertenece al `business_id` esperado.

En ambos casos se rechaza la confirmacion y no se modifica el pedido.

`supplier_id` inexistente en un `DRAFT` persistido protegido por FK es invariante roto/error interno, no error publico normal de `CONFIRM_ORDER`.

### Producto / unidad

`PRODUCT_INACTIVE` reutiliza la semantica global: algun `product_id` de `purchase_order_items` existe pero esta inactivo. El `DRAFT` conserva historia/snapshot, pero no puede confirmarse como nueva operacion usando un producto inactivo.

`PRODUCT_BUSINESS_MISMATCH` ocurre si algun producto pertenece a otro `business_id`. No crear prefijo especifico de pedido.

`PRODUCT_UNIT_INVALID` ocurre si la unidad/presentacion operativa de una linea no es valida para su `product_id` segun las relaciones vigentes necesarias para confirmar. No crear multiples codigos especificos de unidad.

### Constraints e invariantes internos

No agregar al catalogo publico errores especificos para estados que db-3 ya impide persistir normalmente:

- `ordered_qty <= 0`;
- `ordered_qty_base <= 0`;
- cantidades negativas por motivo;
- suma de motivos distinta de `ordered_qty_base`;
- `factor_to_base_snapshot <= 0`;
- `product_unit_id` fisicamente incompatible con `product_id`;
- `status` fuera del enum;
- `supplier_id` inexistente por FK;
- `product_id` inexistente por FK.

Si alguno aparece por corrupcion, datos legacy o bypass de constraints, tratarlo como invariante interno/tecnico y no inventar un codigo de dominio distinto por constraint.

### Idempotencia y reconciliacion

No crear un error publico generico para una key `FAILED`.

Una key `FAILED` con mismo `request_hash` devuelve el error de dominio original almacenado.

No son errores de `CONFIRM_ORDER`:

- `idempotency_key` `COMPLETED` con mismo hash: replay/reconstruccion del resultado;
- `idempotency_key` `FAILED` con mismo hash: replay del error original, sin nueva ejecucion;
- `purchase_orders.status = 'CONFIRMED'`, despues de validar ambito y autorizacion para la solicitud actual;
- `CLOSED` con evidencia historica de confirmacion, despues de validar ambito y autorizacion para la solicitud actual;
- `CANCELLED` con evidencia historica de confirmacion, despues de validar ambito y autorizacion para la solicitud actual;
- nueva `idempotency_key` sobre pedido ya historicamente confirmado, despues de validar ambito y autorizacion para la solicitud actual.

En esos casos aplicar el lifecycle idempotente ya cerrado.

### Cambio fisico

Este catalogo no requiere:

- columna;
- constraint;
- trigger;
- db-4.

## 4. Estados

`purchase_order_status` existente:

- `DRAFT`;
- `CONFIRMED`;
- `CLOSED`;
- `CANCELLED`.

Reglas ya cerradas:

- `DRAFT`: puede confirmarse si todas las validaciones pasan.
- `CONFIRMED`: si llega otro comando para el mismo `purchase_order_id`, no repetir efectos; reconciliar idempotencia y devolver el pedido existente.
- `CLOSED`: no confirmable como intento nuevo; un retry tardio puede reconciliarse solo si existe evidencia autoritativa de confirmacion previa.
- `CANCELLED`: no confirmable como intento nuevo; un retry tardio puede reconciliarse solo si existe evidencia autoritativa de confirmacion previa.

`CONFIRMAR PEDIDO` no reactiva pedidos `CLOSED` ni `CANCELLED`.

La evidencia autoritativa minima de confirmacion previa es:

- `confirmed_at IS NOT NULL`;
- `confirmed_by_user_id IS NOT NULL`.

## 5. Idempotencia CONFIRM_ORDER

Valores definitivos para MVP:

- `IN_PROGRESS`: `locked_until = now() + 30 segundos`.
- `IN_PROGRESS`: `expires_at = NULL`.
- `COMPLETED`: `expires_at = now() + 30 dias`.
- `FAILED`: `expires_at = now() + 30 dias`.

`locked_until` controla exclusivamente el lease de ejecucion.

No hay motivo funcional para apartarse del patron usado en `CONFIRMAR VENTA` y `CONFIRMAR DEVOLUCION`.

### request_hash

`request_hash` representa el comando real de confirmacion.

Debe incluir conceptualmente, como minimo:

- `operation_type = 'CONFIRM_ORDER'`;
- `purchase_order_id`;
- `expected_draft_fingerprint`;
- cualquier otra entrada real de confirmacion que altere el significado del comando.

No incluye lineas reenviadas por el cliente como autoridad.

Las lineas persistidas de `purchase_order_items` siguen siendo la autoridad del `DRAFT`.

No se define algoritmo criptografico concreto.

### Misma key con hash diferente

Para cualquier estado (`IN_PROGRESS`, `COMPLETED` o `FAILED`), si la misma `idempotency_key` llega con `request_hash` diferente, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

La comprobacion de hash debe ocurrir antes de aplicar cualquier tratamiento especifico por estado.

### FASE A - Reserva idempotente

FASE A es una transaccion corta dedicada a `idempotency_keys`.

Si no existe la key, crear:

- `operation_type = 'CONFIRM_ORDER'`;
- `status = 'IN_PROGRESS'`;
- `request_hash = hash canonico`;
- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`.

Si existe con hash distinto, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

Si existe `IN_PROGRESS` con mismo hash y `locked_until > now()`, devolver `ORDER_IDEMPOTENCY_IN_PROGRESS`. No mantener el request HTTP esperando 30 segundos.

Si existe `COMPLETED` con mismo hash, reproducir/devolver el resultado ya almacenado o reconstruirlo desde `result_entity_type` y `result_entity_id`.

Si existe `FAILED` con mismo hash, devolver el error de dominio almacenado. No reintentar automaticamente una misma key `FAILED`.

### Orden de semanticas

Para una key existente, primero manda el contrato propio de la key:

1. Hash distinto: `ORDER_IDEMPOTENCY_KEY_REUSED`.
2. `COMPLETED` con mismo hash: replay.
3. `FAILED` con mismo hash: error almacenado.
4. `IN_PROGRESS` con mismo hash: lease o recuperacion.

Solo durante recuperacion o ejecucion de una key nueva/`IN_PROGRESS` se usa el estado de `purchase_orders` para decidir:

- continuar si sigue `DRAFT`;
- reconciliar confirmacion historica;
- rechazar estado no confirmable.

Esto evita convertir una key `FAILED` antigua en `COMPLETED`.

### Regla critica sobre FAILED historico

Una `idempotency_key` que ya quedo `FAILED` con el mismo `request_hash` conserva ese resultado historico.

Ejemplo:

- `K1 + F1` falla por stale `DRAFT` y queda `FAILED`.
- Despues `K2 + F2` confirma correctamente el mismo `purchase_order`.
- Si vuelve `K1 + F1`, `K1` sigue devolviendo su fallo almacenado.

No reconciliar `K1` hacia `COMPLETED`.

El hecho de que otra key haya confirmado posteriormente el pedido no cambia el resultado historico de la solicitud `K1`.

### IN_PROGRESS expirado

Si existe `status = 'IN_PROGRESS'`, mismo `request_hash` y `locked_until <= now()`, solo puede recuperarse si:

- la fila de idempotencia puede adquirirse sin competir con una ejecucion activa;
- despues se bloquea `purchase_orders(id)`;
- se determina el estado real actual del pedido antes de repetir efectos.

No autorizar una segunda ejecucion unicamente porque hayan pasado 30 segundos.

Si el pedido sigue `status = 'DRAFT'` y no existe evidencia de confirmacion previa, puede renovarse `locked_until = now() + 30 segundos` y continuar.

Antes de cualquier efecto debe:

- validar ambito `business_id` / `branch_id` y autorizacion de la solicitud actual;
- obtener el `DRAFT` autoritativo;
- recalcular fingerprint;
- comparar `expected_draft_fingerprint`.

Si el fingerprint ya no coincide, el flujo falla deterministicamente segun el contrato correspondiente.

### Recuperacion sobre pedido ya confirmado

Si `purchase_orders.status = 'CONFIRMED'`, no repetir:

- `replenishment_allocations`;
- `committed_qty_base`;
- `ORDER_RESERVE`;
- audit de confirmacion;
- ningun efecto operacional.

Para una key nueva o `IN_PROGRESS` recuperable, esta reconciliacion solo puede ocurrir despues de validar ambito `business_id` / `branch_id` y autorizacion de la solicitud actual.

Reconciliar la key `IN_PROGRESS` actual hacia:

- `status = 'COMPLETED'`;
- `result_entity_type = 'purchase_orders'`;
- `result_entity_id = purchase_orders.id`;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

Guardar `response_body` minima.

### Recuperacion sobre CLOSED

`CLOSED` normalmente representa un pedido confirmado y posteriormente cerrado por compra.

Para reconciliar un retry tardio de `CONFIRM_ORDER` debe existir evidencia autoritativa de confirmacion previa:

- `confirmed_at IS NOT NULL`;
- `confirmed_by_user_id IS NOT NULL`.

Si esa evidencia existe, despues de validar ambito `business_id` / `branch_id` y autorizacion de la solicitud actual, no repetir efectos, reconciliar la key `IN_PROGRESS` hacia `COMPLETED` y devolver o referenciar el `purchase_order` existente.

Si la evidencia no existe, tratarlo como estado no confirmable y no inventar una historia de confirmacion.

### Recuperacion sobre CANCELLED

`CANCELLED` puede representar:

- `DRAFT` cancelado antes de confirmar;
- pedido confirmado y cancelado posteriormente.

Si `confirmed_at IS NOT NULL` y `confirmed_by_user_id IS NOT NULL`, existe evidencia de confirmacion historica.

Para una key `IN_PROGRESS` recuperada, despues de validar ambito `business_id` / `branch_id` y autorizacion de la solicitud actual, no repetir efectos y puede reconciliarse como confirmacion historicamente completada.

Si no existe esa evidencia, tratar el pedido como cancelado antes de confirmacion y por tanto no confirmable.

Nunca reactivar el pedido.

### Nueva o segunda idempotency_key

Si `K1` confirma `purchase_order_id = 123` y posteriormente llega una nueva key `K2` para el mismo `purchase_order_id`, `K2` no debe repetir efectos.

FASE B bloquea `purchase_orders(123)`.

Si el pedido esta `CONFIRMED`, o esta `CLOSED`/`CANCELLED` con evidencia autoritativa de confirmacion historica, validar primero ambito `business_id` / `branch_id` y autorizacion de la solicitud actual; solo despues reconciliar `K2` hacia `COMPLETED` apuntando al mismo `purchase_order`.

Esto aplica a una key nueva o `IN_PROGRESS` recuperable.

No aplica para sobrescribir una key que ya esta `FAILED`.

### F1 vs F2 entre keys distintas

Ejemplo:

- `K1`: `purchase_order_id = 123`, `expected_draft_fingerprint = F1`.
- `K2`: `purchase_order_id = 123`, `expected_draft_fingerprint = F2`.
- `K2` confirma.
- Despues llega `K1` como key nueva o `IN_PROGRESS` recuperable para el mismo pedido ya confirmado.

`purchase_order_id` confirmado gana como identidad logica:

- no repetir efectos;
- devolver o reconciliar el pedido existente.

Pero el sistema no puede afirmar que `F1 == F2` ni que ambos payloads representaban exactamente la misma version del `DRAFT`.

Actualmente `purchase_orders` no persiste:

- `confirmed_draft_fingerprint`;
- `request_hash` de confirmacion;
- fingerprint persistente equivalente.

No inventar esa capacidad.

### FAILED deterministico

Si FASE B falla por error de dominio deterministico:

1. Hacer `ROLLBACK` completo de FASE B.
2. Abrir una transaccion corta.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` de dominio estable.
7. Guardar `error_message` seguro, breve, sin secretos, hashes completos, SQL ni stack traces.
8. Establecer `locked_until = NULL`.
9. Establecer `expires_at = now() + 30 dias`.
10. Hacer `COMMIT`.

Pueden entrar conceptualmente en esta categoria:

- autorizacion: `USER_INACTIVE`, `USER_BRANCH_FORBIDDEN` o `USER_PERMISSION_DENIED`;
- sucursal/business: `BRANCH_INACTIVE` o `BRANCH_BUSINESS_MISMATCH`;
- pedido: `PURCHASE_ORDER_NOT_FOUND`, `PURCHASE_ORDER_BRANCH_MISMATCH`, `PURCHASE_ORDER_STATUS_INVALID`, `PURCHASE_ORDER_EMPTY`, `ORDER_DRAFT_STALE` u `ORDER_REPLENISHMENT_STALE`;
- proveedor: `SUPPLIER_INACTIVE` o `SUPPLIER_BUSINESS_MISMATCH`;
- producto/unidad: `PRODUCT_INACTIVE`, `PRODUCT_BUSINESS_MISMATCH` o `PRODUCT_UNIT_INVALID`.

Despues del `ROLLBACK` operativo, FASE C persiste `FAILED` con el codigo original.

### Correccion despues de FAILED

Si el usuario corrige o revisa el `DRAFT`, por ejemplo `F1 -> F2`, debe usar nueva `idempotency_key` y nuevo `request_hash`.

La key `FAILED` anterior no debe reutilizarse con el nuevo fingerprint.

Si se reutiliza la misma key con hash distinto, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

### Fallos tecnicos

Para caida de proceso, timeout interno, perdida de conexion, error inesperado o resultado transaccional desconocido, no marcar automaticamente `FAILED`.

La key puede permanecer `IN_PROGRESS` hasta que expire `locked_until`.

Despues aplicar recuperacion segura:

- adquirir la key;
- bloquear `purchase_orders`;
- inspeccionar estado y evidencia historica;
- reconciliar si ya fue confirmado;
- o renovar lease y continuar si sigue `DRAFT` y es seguro.

### COMPLETED y response_body

Cuando FASE B confirma correctamente el pedido, dentro del mismo `COMMIT` operacional marcar:

- `status = 'COMPLETED'`;
- `result_entity_type = 'purchase_orders'`;
- `result_entity_id = purchase_orders.id`;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

`response_body` tiene limite logico de 16 KiB.

Guardar una respuesta minima, por ejemplo:

- `purchase_order_public_id`;
- `folio`;
- `status`;
- `confirmed_at`.

No guardar:

- pedido completo;
- lineas completas;
- documentos;
- secretos;
- payload original completo.

Para replay puede usarse `response_body` minima o reconstruccion desde `result_entity_type` + `result_entity_id`.

### Audit log PURCHASE_ORDER_CONFIRMED

Cuando `CONFIRM_ORDER` ejecuta realmente la transicion `purchase_orders.status: DRAFT -> CONFIRMED`, debe insertar un unico evento en `audit_log` dentro de la misma FASE B y el mismo `COMMIT` operativo.

Estructura fisica disponible en db-3 para `audit_log`:

- `id`;
- `public_id`;
- `actor_user_id`;
- `branch_id`;
- `terminal_id`;
- `action`;
- `entity_type`;
- `entity_id`;
- `entity_public_id`;
- `before_data`;
- `after_data`;
- `context`;
- `ip_address`;
- `user_agent`;
- `occurred_at`;
- `created_at`.

`audit_log` no tiene columna fisica `business_id`. Para este evento, `business_id` se registra en `context` usando el JSONB existente.

Evento definitivo:

```text
action = 'PURCHASE_ORDER_CONFIRMED'
entity_type = 'purchase_orders'
entity_id = purchase_orders.id
entity_public_id = purchase_orders.public_id
actor_user_id = user_id
branch_id = purchase_orders.branch_id
```

`terminal_id` es nullable. `CONFIRM_ORDER` no depende funcionalmente de una terminal POS: si la operacion proviene de un contexto autenticado con terminal conocida, puede registrarse; si proviene de panel web/administrativo sin terminal, debe quedar `NULL`.

`before_data` minimo:

```json
{
  "status": "DRAFT"
}
```

`after_data` minimo:

```json
{
  "folio": "PED-000123",
  "status": "CONFIRMED",
  "supplier_id": 123,
  "replenishment_channel": "CASH",
  "subtotal": "100.00",
  "tax_total": "16.00",
  "total": "116.00",
  "confirmed_at": "2026-09-18T15:00:00-06:00",
  "line_count": 1,
  "ordered_qty_base_total": "1.0000",
  "replenishment_qty_base_total": "1.0000",
  "customer_special_qty_base_total": "0.0000",
  "stock_extra_qty_base_total": "0.0000",
  "reserved_qty_base_total": "1.0000"
}
```

Los valores del ejemplo son ilustrativos; la estructura y los campos son el contrato, no esos importes concretos.

Los totales son agregados del pedido confirmado. `reserved_qty_base_total` corresponde a la cantidad realmente reservada por allocations/`ORDER_RESERVE` en esta confirmacion.

No guardar lineas completas en `audit_log`.

`context` minimo:

```json
{
  "operation_type": "CONFIRM_ORDER",
  "flow_version": "v0.1",
  "business_id": 0,
  "idempotency_key_ref": "hash_o_truncado_seguro",
  "expected_draft_fingerprint": "...",
  "authoritative_draft_fingerprint": "...",
  "replenishment_allocations_count": 0,
  "order_reserve_count": 0,
  "operation_origin": "desktop|web|otro_si_es_confiable"
}
```

No guardar la `idempotency_key` completa. Usar una representacion segura, truncada o hasheada, que permita correlacion operacional sin exponer la key completa. No se define algoritmo criptografico concreto.

No duplicar `request_hash` en `audit_log`: `idempotency_keys` conserva la defensa primaria por request y los fingerprints del DRAFT aportan evidencia auditable suficiente para esta transicion. No copiar payload.

El fingerprint en `audit_log` es evidencia de auditoria. No convertirlo en constraint, identidad, requisito de idempotencia ni requisito de recuperacion. No cambia la semantica F1/F2 ya cerrada.

No insertar un nuevo evento `PURCHASE_ORDER_CONFIRMED` cuando la ejecucion solo hace:

- replay de `idempotency_key` `COMPLETED`;
- reconciliacion de `purchase_order` ya `CONFIRMED`;
- reconciliacion historica de `CLOSED`;
- reconciliacion historica de `CANCELLED`;
- segunda key sobre pedido ya historicamente confirmado.

El evento de confirmacion existe por la transicion real original, no una vez por retry. La reconciliacion solo actualiza/completa idempotencia segun su contrato.

No crear obligatoriamente `audit_log` por cada fallo deterministico de `CONFIRM_ORDER`. Los fallos quedan registrados en `idempotency_keys.status = 'FAILED'`, `error_code` y `error_message` seguro. La auditoria de intentos fallidos de seguridad queda como politica transversal futura si el sistema la necesita.

No guardar en `audit_log`:

- contrasenas;
- tokens;
- `idempotency_key` completa;
- secretos;
- credenciales;
- CSD;
- claves PAC;
- payload completo;
- stack traces;
- SQL;
- datos innecesarios de proveedor o productos;
- datos de `inventory_balances` o `inventory_movements`.

`CONFIRMAR PEDIDO` no toca inventario; el evento no debe insinuar aumento de stock.

Si FASE B hace `ROLLBACK`, el evento `PURCHASE_ORDER_CONFIRMED` tambien debe hacer `ROLLBACK`. Nunca debe quedar auditoria indicando confirmacion si la confirmacion operativa no quedo committed.

Esta auditoria cabe en el `audit_log` existente de db-3 y no requiere columnas nuevas, triggers nuevos ni db-4.

## 6. Autoridad del DRAFT

Mientras esta `DRAFT`, el usuario puede previamente:

- cargar pendientes;
- editar cantidades sugeridas;
- eliminar lineas;
- agregar productos manualmente;
- clasificar cantidades como `replenishment`, `customer_special` o `stock_extra`.

Al confirmar, `purchase_orders` + `purchase_order_items` actualmente persistidos son la autoridad.

`CONFIRMAR PEDIDO` no aplica de nuevo las lineas de una pantalla del cliente.

### Mutex logico del agregado

Decision cerrada: `purchase_orders(id)` es el mutex logico obligatorio del agregado `purchase_order` + `purchase_order_items`.

Toda mutacion de un pedido `DRAFT` debe adquirir primero `purchase_orders(id) FOR UPDATE` antes de modificar:

- cabecera;
- lineas;
- cantidades;
- proveedor;
- canal;
- cualquier dato incluido en `expected_draft_fingerprint`.

Esto incluye conceptualmente:

- agregar `purchase_order_items`;
- actualizar `purchase_order_items`;
- eliminar `purchase_order_items`;
- cambiar `supplier_id`;
- cambiar `replenishment_channel`;
- cancelar el `DRAFT`;
- confirmar el `DRAFT`.

Despues de adquirir `purchase_orders(id) FOR UPDATE`, todo flujo que pretenda editar debe volver a comprobar `purchase_orders.status = 'DRAFT'`.

Si ahora esta `CONFIRMED`, `CLOSED` o `CANCELLED`, la edicion debe rechazarse. No se define todavia codigo final del error.

Esta regla impide que una transaccion que estaba esperando el lock modifique el pedido despues de que otra transaccion lo confirmo, cancelo o cerro.

## 7. Stale DRAFT

Decision cerrada: el comando usa `expected_draft_fingerprint`.

Orden autoritativo:

1. Resolver idempotencia.
2. Bloquear `purchase_orders(id)`.
3. Validar ambito `business_id` / `branch_id` y autorizacion de la solicitud actual.
4. Resolver o reconciliar estado.
5. Si esta `DRAFT`, obtener las `purchase_order_items` actuales.
6. Calcular fingerprint autoritativo de cabecera + lineas.
7. Comparar con `expected_draft_fingerprint`.
8. Si no coincide, rechazar con `ORDER_DRAFT_STALE` antes de producir efectos.
9. Si coincide, continuar.

`ORDER_DRAFT_STALE` es error deterministico y la key actual termina `FAILED`.

`purchase_orders` no tiene columna `version`.

`purchase_order_items` no tiene `version` ni `updated_at`.

Por eso `purchase_orders.updated_at` por si solo no es una precondicion fuerte suficiente para detectar toda modificacion de lineas.

Si todos los flujos de edicion respetan el mutex de cabecera `purchase_orders(id)`, ninguna linea puede insertarse, modificarse o eliminarse entre el calculo del fingerprint y el `COMMIT` de confirmacion.

`expected_draft_fingerprint` sigue siendo necesario para detectar que el usuario intenta confirmar una version distinta de la que reviso.

`purchase_orders.updated_at` es metadato operativo/auditable. No es la precondicion fuerte de concurrencia y no sustituye `expected_draft_fingerprint`.

## 8. Folio

`purchase_orders.folio` es `NOT NULL`.

El `DRAFT` ya tiene folio antes de esta transaccion.

`CONFIRMAR PEDIDO`:

- conserva ese folio;
- no reserva `PED`;
- no bloquea `document_sequences`;
- no incrementa `next_number`.

La generacion del folio `PED` pertenece al flujo de creacion del `DRAFT`, no a su confirmacion.

## 9. Motivos de cantidad

La regla fisica existente es:

```text
ordered_qty_base = replenishment_qty_base + customer_special_qty_base + stock_extra_qty_base
```

Esta regla esta protegida por `ck_purchase_order_items_reason_sum`.

Significado:

- `replenishment_qty_base`: intencion persistida de cubrir demanda de reposicion de ventas del mismo `branch_id`, `product_id` y `channel`.
- `customer_special_qty_base`: cantidad pedida por motivo especial de cliente, pero no forma parte de la demanda de reposicion modelada por `replenishment_positions`.
- `stock_extra_qty_base`: cantidad planeada como stock extra.
- `ordered_qty_base`: cantidad total solicitada al proveedor.

## 10. Autoridad de reposicion

`replenishment_positions` es la autoridad agregada por:

- `branch_id`;
- `product_id`;
- `channel`.

La disponibilidad se calcula como:

```text
available_to_order_base = GREATEST(demand_qty_base - committed_qty_base, 0)
```

La disponibilidad debe evaluarse dentro de la transaccion despues de bloquear la posicion correspondiente.

Para `CONFIRM_ORDER v0.1`, la posicion agregada no sustituye la trazabilidad FIFO por `sale_item`.

La confirmacion debe respetar dos limites por `branch/product/channel`:

```text
available_to_order_base

total_sale_item_reservable
```

`available_to_order_base` es el limite operacional agregado de `replenishment_positions`.

`total_sale_item_reservable` es la suma de `reservable` de `sale_items` elegibles del mismo branch, producto y canal historico, pertenecientes al conjunto seguro prebloqueado para esta ejecucion.

Conceptualmente:

```text
confirmable_cap = LEAST(available_to_order_base, total_sale_item_reservable)
```

`confirmable_cap` es solo un limite de validacion. No autoriza reservar automaticamente una cantidad menor.

Si `replenishment_qty_base` solicitado excede `confirmable_cap`, rechazar todo el pedido con `ORDER_REPLENISHMENT_STALE`.

## 11. Demanda cambio desde el DRAFT

Decision cerrada: si el `DRAFT` persiste `replenishment_qty_base = X` y, al confirmar, `available_to_order_base < X` o `total_sale_item_reservable < X` para la cantidad agregada aplicable, no se confirma.

No se debe:

- reservar parcialmente;
- convertir sobrante a `stock_extra_qty_base`;
- reescribir `purchase_order_items`.

La confirmacion debe rechazarse como `DRAFT` obsoleto respecto a reposicion y exigir revision/edicion previa.

El codigo definitivo es `ORDER_REPLENISHMENT_STALE`.

Motivo: la razon persistida debe conservar trazabilidad.

Ejemplos definitivos:

- si `available_to_order_base = 10`, `total_sale_item_reservable = 6` y `replenishment_qty_base = 10`, devolver `ORDER_REPLENISHMENT_STALE`;
- si `available_to_order_base = 6`, `total_sale_item_reservable = 10` y `replenishment_qty_base = 10`, devolver `ORDER_REPLENISHMENT_STALE`.

En ambos casos no crear allocations, no incrementar `committed_qty_base`, no crear `ORDER_RESERVE` y no confirmar.

`MANUAL_CORRECTION` puede corregir/reconciliar el agregado de reposicion, pero no crea demanda comercial nueva, demanda FIFO independiente, `sale_item`, allocation ni capacidad reservable independiente.

Una compra sin demanda trazable de `sale_item` debe clasificarse como `stock_extra_qty_base` o `customer_special_qty_base`, segun su motivo real.

## 12. Pedido menor que demanda

Si:

```text
available_to_order_base = 10
replenishment_qty_base = 6
```

Entonces:

- reservar exactamente 6;
- `committed_qty_base` aumenta en 6;
- las allocations suman 6;
- quedan 4 disponibles para otro pedido.

## 13. Pedido mayor intencional

Si demanda real disponible = 6 y el usuario quiere pedir 10, el `DRAFT` correcto debe expresar, por ejemplo:

```text
replenishment_qty_base = 6
stock_extra_qty_base = 4
```

Tambien puede usar `customer_special_qty_base` si realmente corresponde a ese motivo.

No debe persistirse `replenishment_qty_base = 10` si solo 6 representan demanda real de reposicion.

## 14. CUSTOMER_SPECIAL

Para `CONFIRMAR PEDIDO v0.1`, `customer_special_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations` de demanda de ventas;
- no modifica `demand_qty_base`.

No se inventa un ledger separado de demanda especial en este flujo.

## 15. STOCK_EXTRA

`stock_extra_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations`;
- no modifica `demand_qty_base`.

## 16. Demanda reservable por sale_item

Para cada `sale_item` del mismo branch, producto y canal historico de la venta:

```text
base_demand = sale_items.quantity_base

restock_returned =
  SUM(return_items.quantity_base)
  de devoluciones CONFIRMED para ese sale_item
  con disposition = 'RESTOCK'

fulfilled =
  SUM(replenishment_allocations.fulfilled_qty_base)
  para ese sale_item

active_reserved =
  SUM(reserved_qty_base - fulfilled_qty_base - released_qty_base)
  para ese sale_item

reservable =
  GREATEST(base_demand - restock_returned - fulfilled - active_reserved, 0)
```

`DAMAGED` no reduce demanda de reposicion.

`released_qty_base` deja de consumir reserva.

La posicion agregada `replenishment_positions` sigue siendo la barrera autoritativa para reserva concurrente.

Para confirmar un pedido, `total_sale_item_reservable` se calcula como:

```text
SUM(reservable)
```

solo de `sale_items`:

- del mismo branch;
- del mismo producto;
- del mismo `replenishment_channel` historico;
- elegibles por FIFO;
- pertenecientes al conjunto seguro prebloqueado por la ejecucion actual.

## 17. FIFO

Orden FIFO determinista:

1. `sales.confirmed_at ASC`.
2. `sales.id ASC`.
3. `sale_items.line_number ASC`.
4. `sale_items.id ASC`.

El desempate debe ser estable incluso con timestamps iguales.

No se agregan nuevas columnas.

Toda cantidad confirmada como reposicion debe asignarse integramente a `sale_items` trazables por FIFO. En v0.1 no existe reposicion confirmada sin trazabilidad FIFO materializable.

Despues de adquirir la primera `replenishment_positions`, `CONFIRM_ORDER` no puede ampliar el conjunto FIFO ni adquirir nuevos locks sobre `sale_items`. FIFO para efectos debe usar solo `sale_items` prebloqueados.

## 18. replenishment_allocations

Al confirmar, para la parte realmente reservada, crear allocations con granularidad:

```text
sale_item + purchase_order_item
```

Estado inicial conceptual:

- `reserved_qty_base > 0`;
- `fulfilled_qty_base = 0`;
- `released_qty_base = 0`.

No crear allocations de reposicion para:

- `stock_extra_qty_base`;
- `customer_special_qty_base`.

Mantener la unicidad existente `UNIQUE(sale_item_id, purchase_order_item_id)`.

Esta unicidad no sustituye el mutex de `replenishment_positions`. Dos pedidos distintos pueden reservar porciones distintas de un mismo `sale_item` con distinto `purchase_order_item_id`, siempre que la posicion y `active_reserved` lo permitan.

No reescribir allocations historicas ajenas.

## 19. ORDER_RESERVE

`replenishment_movements.movement_type = 'ORDER_RESERVE'` debe reflejar unicamente cantidad realmente reservada.

`committed_delta_base > 0`.

La cantidad total de `ORDER_RESERVE` asociada al pedido debe corresponder a la suma de `reserved_qty_base` creados, no a `ordered_qty_base`.

Para trazabilidad fina, usar conceptualmente:

```text
reference_entity_type = 'purchase_order_items'
reference_entity_id = purchase_order_items.id
```

cuando se registre movimiento por linea.

No se fija SQL definitivo.

## 20. committed_qty_base

Actualizacion conceptual:

```text
committed_qty_base nuevo = committed_qty_base actual + cantidad realmente reservada
```

No inflar `committed_qty_base` con:

- `stock_extra`;
- `customer_special`;
- cantidad no asignada.

## 21. Varias lineas del mismo producto

Si existen varias `purchase_order_items` del mismo `product_id`, por ejemplo por distintas presentaciones, agregar conceptualmente por:

- `product_id`;
- `channel`.

Esto sirve para validar disponibilidad total contra `replenishment_positions`.

Pero se conserva trazabilidad individual por `purchase_order_item`.

Orden entre lineas del mismo producto:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.

La asignacion debe evitar doble consumo de un mismo reservable entre varias lineas del mismo pedido.

`active_reserved` debe considerar allocations creadas por lineas anteriores del mismo `CONFIRM_ORDER` durante la ejecucion, o la asignacion debe planearse de forma conjunta antes de insertar.

La suma de allocations nuevas debe corresponder a la suma de `replenishment_qty_base` efectivamente confirmada.

## 22. Concurrencia entre pedidos

Barrera principal:

```text
replenishment_positions(branch_id, product_id, channel)
```

bloqueada para actualizacion.

Dos `DRAFT` distintos que intentan reservar la misma demanda se serializan mediante esa posicion.

Dos `CONFIRM_ORDER` distintos pueden tomar `FOR KEY SHARE` sobre los mismos `sale_items`, porque es un lock debil compatible para lectura/referencia.

Luego se serializan en `replenishment_positions`.

Despues de que el primero confirma, el segundo obtiene la posicion, observa `committed_qty_base`, allocations y disponibilidad actualizados, recomputa y:

- confirma si todavia cabe en `available_to_order_base` y `total_sale_item_reservable`;
- o falla con `ORDER_REPLENISHMENT_STALE`.

## 23. Concurrencia entre edicion y confirmacion

Caso conceptual:

- A confirma `DRAFT 123`.
- B intenta insertar o editar una linea del mismo `DRAFT`.

Ambos deben adquirir primero `purchase_orders(123) FOR UPDATE`.

Si A obtiene primero el lock y confirma, B espera.

Despues del `COMMIT` de A, B adquiere el lock, observa `status = 'CONFIRMED'` y no puede editar.

Resultado: no aparece una phantom line despues del fingerprint ni despues de confirmar.

## 24. Concurrencia con devoluciones

Decision final: `CONFIRM_ORDER` debe adquirir explicitamente `sale_items FOR KEY SHARE` antes de bloquear cualquier `replenishment_positions`.

Motivo: `replenishment_allocations.sale_item_id` referencia `sale_items`. El `INSERT` de allocations puede requerir un lock de referencia sobre `sale_items`; si ese lock se adquiriera por primera vez despues de tener `replenishment_positions`, podria producir deadlock con `CONFIRMAR DEVOLUCION`.

Orden compatible de `CONFIRMAR DEVOLUCION`:

```text
sale_items FOR UPDATE -> replenishment_positions
```

Orden compatible de `CONFIRM_ORDER`:

```text
sale_items FOR KEY SHARE -> replenishment_positions
```

Si `CONFIRMAR DEVOLUCION` obtiene primero `sale_items FOR UPDATE`, `CONFIRM_ORDER` espera antes de tener `replenishment_positions`.

Si `CONFIRM_ORDER` obtiene primero `sale_items FOR KEY SHARE`, `CONFIRMAR DEVOLUCION` espera antes de tener `replenishment_positions`.

Asi ningun flujo puede tener `replenishment_positions` y despues esperar por primera vez un lock de `sale_items` del otro.

No usar `sale_items FOR UPDATE` en `CONFIRM_ORDER`: `FOR KEY SHARE` hace explicito el orden de referencia FK sin bloquear innecesariamente lectores debiles.

## 25. Concurrencia con ventas

Una venta concurrente puede crear nueva demanda.

Si `CONFIRMAR VENTA` obtiene la `replenishment_positions` y confirma antes, `CONFIRM_ORDER` observara esa demanda al obtener la posicion.

Si `CONFIRM_ORDER` obtiene la `replenishment_positions` primero, `CONFIRMAR VENTA` espera y su nueva demanda queda disponible para pedidos posteriores.

`CONFIRM_ORDER` no esta obligado a ampliar su conjunto prebloqueado con `sale_items` creados despues del prelock FIFO.

## 26. Invariante global de reposicion

Toda operacion que vaya a modificar, para un `branch/product/channel`:

- `replenishment_positions.demand_qty_base`;
- `replenishment_positions.committed_qty_base`;
- `replenishment_allocations.reserved_qty_base`;
- `replenishment_allocations.fulfilled_qty_base`;
- `replenishment_allocations.released_qty_base`;
- movimientos que materialicen esos cambios;

debe mantener bloqueada la `replenishment_positions` correspondiente antes de realizar esas mutaciones.

Esto no significa que `replenishment_positions` sea siempre el primer lock de toda operacion. Otros locks pueden precederla segun el flujo.

Ejemplos validos:

- `CONFIRMAR DEVOLUCION`: `sale_items -> replenishment_positions`;
- `CONFIRM_ORDER`: `sale_items FOR KEY SHARE -> replenishment_positions`.

## 27. Orden final de locks v0.1

Orden explicito final:

1. `idempotency_keys` para `CONFIRM_ORDER`.
2. `purchase_orders(id)`.
3. `purchase_order_items` del pedido en orden `line_number ASC, id ASC`.
4. `sale_items` candidatos `FOR KEY SHARE`, en orden:
   - `sales.confirmed_at ASC`;
   - `sales.id ASC`;
   - `sale_items.line_number ASC`;
   - `sale_items.id ASC`.
5. `replenishment_positions` afectados en orden `product_id ASC, channel ASC`.

Despues vienen las escrituras:

- `replenishment_allocations`;
- `replenishment_positions.committed_qty_base`;
- `replenishment_movements ORDER_RESERVE`;
- `purchase_orders.status = 'CONFIRMED'`;
- `audit_log`;
- `idempotency_keys COMPLETED`.

Los `INSERT` pueden tomar locks implicitos por FK. Los `sale_items` relevantes ya fueron prebloqueados antes de `replenishment_positions`.

El lock sobre `purchase_orders(id)` serializa la confirmacion con cualquier edicion del mismo `DRAFT`.

El bloqueo/lectura de `purchase_order_items` se mantiene como defensa adicional, estabilizacion del trabajo sobre lineas existentes y orden determinista. La proteccion contra phantom lines depende del mutex `purchase_orders(id)`; no debe dependerse solamente de locks sobre lineas existentes.

### Candidatos FIFO prebloqueados

Para cada `branch/product/channel` que el `DRAFT` pretende cubrir como reposicion, antes de bloquear `replenishment_positions`:

1. identificar `sale_items` actualmente candidatos FIFO;
2. considerar su demanda reservable actual conceptualmente;
3. adquirir `FOR KEY SHARE` sobre todos los `sale_items` actualmente FIFO-reservables de esos productos/canales afectados.

Para MVP se usa este conjunto conservador en lugar de bloquear solamente la cantidad exacta requerida.

El calculo previo al lock de `replenishment_positions` sirve para definir el conjunto seguro de `sale_items` que se puede usar despues. Todavia no autoriza la reserva.

Despues de tomar `replenishment_positions` debe recomputarse el estado autoritativo necesario para confirmar. Bajo `READ COMMITTED` pueden haber ocurrido cambios entre ambas etapas; eso es esperado.

Despues de adquirir la primera `replenishment_positions`, `CONFIRM_ORDER` no puede:

- ampliar el conjunto FIFO;
- ejecutar `FOR KEY SHARE` tardio;
- depender de que un `INSERT` FK adquiera por primera vez lock sobre un `sale_item` no prebloqueado.

Todo `sale_item` que reciba una nueva `replenishment_allocation` debe pertenecer al conjunto prebloqueado.

Si una venta concurrente crea nueva demanda despues del prelock y antes de que `CONFIRM_ORDER` obtenga `replenishment_positions`, `CONFIRM_ORDER` no debe bloquear esos nuevos `sale_items` tardiamente.

Si los candidatos prebloqueados siguen alcanzando para el `DRAFT`, puede confirmar usando el conjunto prebloqueado y FIFO correspondiente.

Si los candidatos prebloqueados ya no alcanzan, devolver `ORDER_REPLENISHMENT_STALE`.

No hay retry interno automatico de FASE B. La ejecucion hace `ROLLBACK`, FASE C persiste `FAILED` con `ORDER_REPLENISHMENT_STALE`, y para volver a intentar se usa la politica ya definida de nueva key/fingerprint.

### Lecturas sin lock fuerte

Lecturas sin lock fuerte:

- `branches`;
- `suppliers`;
- `products`;
- `product_units`;
- `sales` para orden/metadata;
- `returns`;
- `return_items`;
- `replenishment_allocations` existentes;
- otros catalogos estrictamente necesarios.

`sale_items` candidatos FIFO afectados ya no son simple lectura sin lock: deben prebloquearse con `FOR KEY SHARE`.

Puede haber lecturas normales de otros `sale_items` no relevantes si existen.

`replenishment_allocations` existentes se leen bajo la seguridad logica de `replenishment_positions` como mutex antes de materializar efectos.

No incluir `document_sequences`.

### Restricciones para flujos futuros

`CANCEL_ORDER` que modifique allocations, `committed_qty_base` u `ORDER_RELEASE` debe respetar `replenishment_positions` como mutex de mutacion. Si necesita interactuar con `sale_items`, no puede introducir un orden inverso `replenishment_positions -> sale_items` incompatible con este contrato.

`CONFIRM_PURCHASE` debe respetar `replenishment_positions` antes de mutar:

- `fulfilled_qty_base`;
- `released_qty_base`;
- `committed_qty_base`;
- demanda/cobertura relacionada.

No debe invertir el orden `purchase_orders -> purchase_order_items -> sale_items si aplica -> replenishment_positions` cuando participe de estos mismos recursos.

No se disena el orden de locks de inventario de `CONFIRM_PURCHASE` en este documento.

### Cambio fisico

Este contrato de concurrencia no requiere:

- columna;
- constraint;
- trigger;
- indice obligatorio para correctitud;
- db-4.

Un indice para acelerar la seleccion FIFO puede evaluarse posteriormente con datos reales y `EXPLAIN`; seria una optimizacion de performance, no condicion de correctitud.

## 28. Flujo transaccional inicial

### FASE A - Reserva idempotente

La reserva idempotente ocurre en una transaccion corta dedicada a `idempotency_keys`, con el lifecycle definido en la seccion de idempotencia de `CONFIRM_ORDER`.

### FASE B - Confirmar pedido transaccional

Dentro de un unico `BEGIN` / `COMMIT` operativo:

1. Bloquear y verificar la `idempotency_key` reservada.
2. Localizar y bloquear `purchase_orders(id)`; si no existe o no es visible/valido para la operacion, rechazar con `PURCHASE_ORDER_NOT_FOUND`. Este lock serializa la confirmacion con cualquier edicion del mismo `DRAFT`.
3. Validar que el pedido pertenece al `business_id` esperado o aplicar frontera segura de no divulgacion como `PURCHASE_ORDER_NOT_FOUND` si corresponde.
4. Validar `purchase_orders.branch_id = branch_id` esperado; si no coincide, rechazar con `PURCHASE_ORDER_BRANCH_MISMATCH`.
5. Validar sucursal/business: sucursal operativa (`BRANCH_INACTIVE`) y `branch_id` pertenece al `business_id` del contexto (`BRANCH_BUSINESS_MISMATCH`).
6. Validar usuario `ACTIVE`; si no, rechazar con `USER_INACTIVE`.
7. Validar acceso explicito a `branch_id`; si no, rechazar con `USER_BRANCH_FORBIDDEN`.
8. Validar permiso `PURCHASE_ORDERS_CONFIRM`; si no, rechazar con `USER_PERMISSION_DENIED`.
9. Si esta `CONFIRMED`, reconciliar idempotencia hacia `COMPLETED` y devolver sin efectos nuevos.
10. Si esta `CLOSED` o `CANCELLED` con `confirmed_at IS NOT NULL` y `confirmed_by_user_id IS NOT NULL`, reconciliar como confirmacion historicamente completada y devolver sin efectos nuevos.
11. Si esta `CLOSED` o `CANCELLED` sin evidencia autoritativa de confirmacion previa, rechazar con `PURCHASE_ORDER_STATUS_INVALID`.
12. Si esta `DRAFT`, revalidar estado y continuar.
13. Bloquear/leer `purchase_order_items`.
14. Si no existe ninguna linea, rechazar con `PURCHASE_ORDER_EMPTY`.
15. Recalcular `expected_draft_fingerprint` autoritativo.
16. Comparar contra el `expected_draft_fingerprint` recibido; si no coincide, rechazar con `ORDER_DRAFT_STALE`.
17. Validar cabecera, lineas, canal, proveedor, productos y unidades, incluyendo `SUPPLIER_INACTIVE`, `SUPPLIER_BUSINESS_MISMATCH`, `PRODUCT_INACTIVE`, `PRODUCT_BUSINESS_MISMATCH` y `PRODUCT_UNIT_INVALID` cuando apliquen.
18. Agregar `replenishment_qty_base` requerido por producto/canal.
19. Identificar candidatos FIFO actuales para los productos/canales afectados.
20. Adquirir `sale_items FOR KEY SHARE` sobre todos los candidatos actualmente reservables de esos productos/canales, en orden FIFO global: `sales.confirmed_at ASC`, `sales.id ASC`, `sale_items.line_number ASC`, `sale_items.id ASC`.
21. Bloquear `replenishment_positions` en orden estable `product_id ASC, channel ASC`.
22. Recomputar `available_to_order_base`.
23. Recomputar `total_sale_item_reservable` usando solo el conjunto de `sale_items` prebloqueados y el estado committed visible bajo las barreras correspondientes.
24. Calcular conceptualmente `confirmable_cap = LEAST(available_to_order_base, total_sale_item_reservable)`.
25. Rechazar con `ORDER_REPLENISHMENT_STALE` si `replenishment_qty_base` requerido excede `available_to_order_base`, `total_sale_item_reservable` o `confirmable_cap`.
26. Seleccionar demanda FIFO usando solo `sale_items` prebloqueados.
27. Crear `replenishment_allocations`.
28. Incrementar `committed_qty_base`.
29. Crear `ORDER_RESERVE`.
30. Marcar `purchase_orders.status = 'CONFIRMED'`.
31. Establecer `confirmed_by_user_id`.
32. Establecer `confirmed_at`.
33. Insertar `audit_log` con `action = 'PURCHASE_ORDER_CONFIRMED'` segun la politica de auditoria definida para la transicion real `DRAFT -> CONFIRMED`.
34. Marcar idempotencia como `COMPLETED` dentro del mismo `COMMIT`.
35. Hacer `COMMIT`.

No reescribir `purchase_order_items`.

### FASE C - Fallo de dominio deterministico

Si FASE B falla por error de dominio deterministico:

1. Hacer `ROLLBACK` completo de FASE B.
2. Abrir una transaccion corta.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` de dominio estable.
7. Guardar `error_message` seguro, breve, sin secretos, hashes completos, SQL ni stack traces.
8. Establecer `locked_until = NULL`.
9. Establecer `expires_at = now() + 30 dias`.
10. Hacer `COMMIT`.

Fallos tecnicos no deterministicos no usan FASE C automaticamente.

Los errores deterministicos que pueden persistirse como `FAILED` durante una ejecucion real de FASE B son:

- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`;
- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`;
- `PURCHASE_ORDER_NOT_FOUND`;
- `PURCHASE_ORDER_BRANCH_MISMATCH`;
- `PURCHASE_ORDER_STATUS_INVALID`;
- `PURCHASE_ORDER_EMPTY`;
- `ORDER_DRAFT_STALE`;
- `ORDER_REPLENISHMENT_STALE`;
- `SUPPLIER_INACTIVE`;
- `SUPPLIER_BUSINESS_MISMATCH`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_BUSINESS_MISMATCH`;
- `PRODUCT_UNIT_INVALID`.

FASE C persiste `FAILED` con el codigo original; no transforma estos errores en un codigo generico.

## 29. Atomicidad

En el mismo `COMMIT` deben quedar consistentes:

- `purchase_orders.status = 'CONFIRMED'`;
- `confirmed_by_user_id`;
- `confirmed_at`;
- `replenishment_positions.committed_qty_base`;
- `replenishment_movements ORDER_RESERVE`;
- `replenishment_allocations`;
- `audit_log`;
- `idempotency_keys COMPLETED`.

`purchase_order_items` permanece sin reescritura durante confirmacion.

Si hay `ROLLBACK`, no debe quedar:

- pedido `CONFIRMED` sin reservas;
- `committed_qty_base` incrementado sin pedido confirmado;
- `ORDER_RESERVE` aislado;
- allocation aislada;
- auditoria aislada;
- idempotencia `COMPLETED` apuntando a confirmacion inexistente.

## 30. Inventario

`CONFIRMAR PEDIDO` no modifica:

- `inventory_balances`;
- `inventory_movements`.

El pedido no aumenta inventario.

El inventario cambia posteriormente en `CONFIRMAR COMPRA`.

## 31. Aislamiento

Decision definitiva MVP:

```text
READ COMMITTED + locks explicitos
```

No usar `REPEATABLE READ` ni `SERIALIZABLE` por defecto para `CONFIRM_ORDER v0.1`.

Justificacion:

- `purchase_orders(id)` serializa el agregado `DRAFT`;
- `sale_items FOR KEY SHARE` establece orden compatible con devoluciones;
- `replenishment_positions` serializa estado agregado y mutaciones de reposicion;
- la recomputacion ocurre despues de adquirir las barreras;
- el flujo no depende de snapshot unico de transaccion.

La regla de mutex de cabecera no agrega `version`, columnas, triggers ni constraints, y no requiere db-4. Es contrato de servicio/transaccion sobre db-3.

## 32. Pruebas de concurrencia futuras

La implementacion futura debe cubrir, como minimo:

1. dos confirmaciones del mismo `DRAFT`;
2. confirmacion vs edicion de linea;
3. confirmacion vs cancelacion de `DRAFT`;
4. dos pedidos sobre la ultima demanda disponible;
5. pedido multiproducto con orden inverso entre transacciones;
6. `CONFIRM_ORDER` vs devolucion `RESTOCK`;
7. `CONFIRM_ORDER` vs venta sobre la misma posicion;
8. `available_to_order_base > total_sale_item_reservable`;
9. `available_to_order_base < total_sale_item_reservable`;
10. nuevo `sale_item` entre prelock FIFO y lock de posicion;
11. retry tecnico despues de commit desconocido;
12. segunda `idempotency_key` para el mismo pedido.

## 33. Estado final de CONFIRM_ORDER v0.1

No quedan decisiones funcionales o de concurrencia abiertas para `CONFIRM_ORDER v0.1`.

No quedan cambios fisicos requeridos y no se requiere db-4.

La auditoria final de consistencia concluyo APTO PARA FREEZE.

`CONFIRM_ORDER v0.1` queda VALIDADO / CONGELADO.

Los errores `ORDER_IDEMPOTENCY_KEY_REUSED` y `ORDER_IDEMPOTENCY_IN_PROGRESS` quedan cerrados en este contrato v0.1.

No quedan pendientes sobre db-4, `client_operation_id`, folio, FIFO, autoridad del `DRAFT`, mutex de cabecera para edicion vs confirmacion, mecanismo `expected_draft_fingerprint`, lifecycle exacto de idempotencia, comportamiento de demanda cambiante, `CASH`/`TRANSFER`, `ORDER_RESERVE`, allocations ni `committed_qty_base` para este contrato v0.1.
