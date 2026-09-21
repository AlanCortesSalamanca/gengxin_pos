# CONFIRMAR COMPRA / RECEPCION v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica vigente:

- `docs/database/modelo-fisico-v0.5-db-3.md`.
- `database/schema-v0.5-db-3.sql`.

## Estado del diseno

- Estado: BORRADOR INICIAL
- Version: v0.1
- Implementacion: todavia no iniciada

Este documento disena conceptualmente la transaccion `CONFIRM_PURCHASE`.

No define todavia:

- endpoint;
- DTO;
- framework;
- servicio concreto;
- repositorio;
- SQL final;
- frontend;
- aplicacion de escritorio.

## 1. Alcance actual del borrador

Este primer borrador cierra para `CONFIRM_PURCHASE v0.1`:

- identidad;
- autoridad del `DRAFT`;
- inmutabilidad estructural;
- `expected_purchase_fingerprint`;
- `request_hash`;
- idempotencia;
- estados base;
- recuperacion historica;
- estructura FASE A / FASE B / FASE C hasta el punto seguro definido.

Este borrador todavia deja abiertos:

- permiso definitivo;
- autorizacion completa;
- catalogo final de errores;
- producto/unidad inactive;
- `difference_reason`;
- totales/impuestos;
- inventory effects;
- costo promedio;
- replenishment fulfillment/release detallado;
- orden global final de locks;
- isolation final;
- audit payload;
- atomicidad definitiva.

Este documento no queda validado ni congelado.

## 2. Objetivo de CONFIRM_PURCHASE

`CONFIRM_PURCHASE` confirma una `purchases` `DRAFT` ya existente.

`CONFIRM_PURCHASE` no crea:

- `purchase`;
- `purchase_order`;
- `purchase_order_items`;
- folio `COM`.

Debe impedir:

- doble confirmacion;
- doble inventario;
- doble fulfillment;
- doble release;
- doble cierre del pedido;
- efectos duplicados por timeout, retry o doble clic.

La compra confirmada representa lo realmente recibido. El pedido conserva lo solicitado y los motivos historicos originales.

## 3. Identidad primaria

Decision cerrada: `purchase_id` es la identidad primaria del agregado que `CONFIRM_PURCHASE` confirma.

`purchase_order_id`:

- valida relacion;
- valida estado;
- participa en locks;
- termina `CLOSED` al completarse correctamente la compra;
- no sustituye `purchase_id` como identidad primaria del comando.

`client_operation_id`:

- no es identidad de `CONFIRM_PURCHASE`;
- no es obligatorio para confirmar;
- es defensa secundaria/local de creacion del `DRAFT` cuando existe;
- no reemplaza `idempotency_key`;
- no reemplaza `request_hash`;
- no reemplaza `expected_purchase_fingerprint`.

## 4. Entradas conceptuales

La operacion requiere, como minimo:

- `purchase_id`;
- `idempotency_key`;
- `expected_purchase_fingerprint`;
- actor/user context;
- business/tenant context autenticado;
- cualquier precondicion explicita futura que realmente cambie la semantica del comando.

El cliente no envia `purchase_items` como autoridad de confirmacion.

Las filas persistidas son la autoridad del `DRAFT`:

- `purchases`;
- `purchase_items`.

## 5. Verificacion fisica relevante contra db-3

En `database/schema-v0.5-db-3.sql`, `purchases` tiene:

- `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`;
- `public_id UUID NOT NULL DEFAULT gen_random_uuid()`;
- `branch_id BIGINT NOT NULL REFERENCES branches(id)`;
- `purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders(id)`;
- `supplier_id BIGINT NOT NULL REFERENCES suppliers(id)`;
- `replenishment_channel replenishment_channel NOT NULL`;
- `folio TEXT NOT NULL`;
- `status purchase_status NOT NULL DEFAULT 'DRAFT'`;
- `received_by_user_id BIGINT NOT NULL REFERENCES users(id)`;
- `confirmed_by_user_id BIGINT REFERENCES users(id)`;
- `supplier_document_ref TEXT`;
- `subtotal NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `tax_total NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `total NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `notes TEXT`;
- `client_operation_id TEXT`;
- `confirmed_at TIMESTAMPTZ`;
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`;
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`.

Constraints relevantes:

- `uq_purchases_public_id UNIQUE (public_id)`;
- `uq_purchases_branch_folio UNIQUE (branch_id, folio)`;
- `uq_purchases_order UNIQUE (purchase_order_id)`;
- `uq_purchases_id_order UNIQUE (id, purchase_order_id)`;
- `uq_purchases_client_operation UNIQUE (branch_id, client_operation_id)`;
- `fk_purchases_order_inheritance FOREIGN KEY (purchase_order_id, branch_id, supplier_id, replenishment_channel) REFERENCES purchase_orders(id, branch_id, supplier_id, replenishment_channel)`;
- `ck_purchases_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL))`.

En `idempotency_keys`:

- `branch_id BIGINT REFERENCES branches(id)` es nullable;
- la unicidad real es `UNIQUE (business_id, operation_type, idempotency_key)`;
- `operation_type` es `TEXT NOT NULL` con `CHECK (operation_type ~ '^[A-Z_]+$')`, compatible con `CONFIRM_PURCHASE`.

## 6. Campos inmutables del purchase DRAFT

Una vez creada `purchases`, son inmutables a nivel de servicio:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`;
- `folio`.

`client_operation_id`:

- puede ser `NULL`;
- si ya existe un valor, no puede cambiarse.

Esto no agrega trigger ni constraint. Es contrato de servicio/transaccion sobre db-3.

## 7. Mutex del purchase DRAFT

`purchases(id) FOR UPDATE` es el mutex obligatorio del agregado:

- `purchase`;
- `purchase_items`.

Toda edicion futura del `DRAFT` debe:

1. bloquear `purchases(id) FOR UPDATE`;
2. exigir `status = 'DRAFT'`;
3. editar despues solo cabecera/lineas permitidas.

Esta regla es necesaria para impedir phantoms de `purchase_items` durante confirmacion.

Row locks sobre `purchase_items` por si solos no son suficientes bajo `READ COMMITTED` para impedir un `INSERT` concurrente de una linea nueva.

## 8. Mutex del purchase_order

`CONFIRM_PURCHASE` tambien debe usar `purchase_orders(id) FOR UPDATE` porque:

- valida que el pedido este `CONFIRMED`;
- serializa con cancelacion/cierre concurrente incompatible;
- al confirmar compra debe terminar `CLOSED`.

Orden canonico decidido entre parents:

```text
purchase_orders(id) -> purchases(id)
```

Este documento no define todavia locks posteriores globales de inventario, costo o reposicion.

## 9. Pre-read necesario

El comando entra mediante `purchase_id`, pero el orden canonico exige bloquear primero `purchase_orders(id)`.

Por tanto existe una resolucion preliminar no autoritativa.

PASO 0: leer de `purchases` por `purchase_id`:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Esta lectura sirve solo para descubrir recursos.

No sirve para:

- confirmar `status`;
- calcular fingerprint;
- ejecutar efectos;
- asumir que los datos siguen iguales.

Como `idempotency_keys.branch_id` es nullable y la unicidad de idempotencia no incluye branch, una key puede reservarse por `(business_id, operation_type, idempotency_key)` usando el `business_id` del contexto autenticado. Si el pre-read encuentra una `purchase` visible de forma segura, su `branch_id` puede registrarse como scope/diagnostico de la key; si no puede resolverse sin romper seguridad, `branch_id` puede permanecer `NULL` hasta que el flujo determine el error seguro correspondiente.

## 10. Revalidacion despues de locks

Despues de:

1. bloquear `purchase_orders(id) FOR UPDATE`;
2. bloquear `purchases(id) FOR UPDATE`;

se debe revalidar que la `purchase` bloqueada conserve exactamente los valores observados en el pre-read:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Si cambio alguno:

- no bloquear un `purchase_order` diferente tardiamente;
- no continuar;
- no producir efectos;
- tratar como `PURCHASE_DRAFT_STALE`.

Aunque esas columnas sean funcionalmente inmutables, esta defensa runtime es obligatoria.

## 11. purchase_items

Despues de los parent locks, bloquear/leer las `purchase_items` existentes en orden determinista:

1. `line_number ASC`;
2. `id ASC`.

Las lineas persistidas son la autoridad.

`CONFIRM_PURCHASE` no reconstruye el `DRAFT` desde lineas reenviadas por el cliente.

No existe error `PURCHASE_EMPTY` en este contrato. El negocio puede confirmar una recepcion donde nada llego. Puede existir una compra sin lineas recibidas persistidas o con lineas `received_qty = 0`, segun se cierre posteriormente la persistencia del DRAFT. `CONFIRM_PURCHASE` todavia debe poder cerrar el pedido y liberar todas las reservas si fisicamente no llego mercancia.

## 12. expected_purchase_fingerprint

`expected_purchase_fingerprint` es precondicion obligatoria del comando.

No es columna.

No requiere db-4.

Significado:

```text
confirma exactamente la version semantica del purchase DRAFT que el usuario reviso
```

Despues de bloquear parents + `purchase_items`:

1. recalcular fingerprint autoritativo;
2. comparar contra `expected_purchase_fingerprint`;
3. si difiere, rechazar con `PURCHASE_DRAFT_STALE`.

`updated_at` no sustituye al fingerprint. Es metadato tecnico/auditable y no garantiza por si solo la semantica revisada por el usuario.

## 13. Fingerprint header definitivo

El fingerprint de cabecera debe incluir exactamente:

- `purchase.id`;
- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`;
- `folio`;
- `status`;
- `received_by_user_id`;
- `supplier_document_ref`;
- `notes`;
- `subtotal`;
- `tax_total`;
- `total`.

No anadir campos nuevos sin justificar el cambio de semantica.

## 14. Fingerprint de lineas definitivo

Por cada `purchase_item`, incluir:

- `line_number`;
- `id`;
- `purchase_order_item_id`;
- `product_id`;
- `product_unit_id`;
- `factor_to_base_snapshot`;
- `received_qty`;
- `received_qty_base`;
- `actual_unit_cost_base`;
- `tax_snapshot`;
- `subtotal`;
- `tax_total`;
- `total`;
- `difference_reason`.

Ordenar lineas por:

1. `line_number ASC`;
2. `id ASC`.

## 15. Exclusiones del fingerprint

Excluir explicitamente:

- `public_id`;
- `client_operation_id`;
- `confirmed_by_user_id`;
- `confirmed_at`;
- `created_at`;
- `updated_at`;
- snapshots descriptivos de SKU/nombre/unidad que no cambien la semantica transaccional minima.

Razones:

- `public_id`: identidad publica estable, no define efectos de confirmacion.
- `client_operation_id`: defensa secundaria de creacion e inmutable tras creacion.
- `confirmed_by_user_id` / `confirmed_at`: se generan durante confirmacion.
- `created_at` / `updated_at`: metadatos tecnicos.
- snapshots descriptivos: no alteran efectos si IDs, factor, cantidades, costos, impuestos y totales ya forman parte del fingerprint.

## 16. Canonicalizacion

La canonicalizacion debe seguir la misma convencion conceptual de `CONFIRM_ORDER`.

Reglas:

- claves en orden determinista;
- lineas en orden `line_number ASC, id ASC`;
- `NULL` explicito;
- JSON/JSONB normalizado;
- NUMERIC normalizado semanticamente;
- `1`, `1.0` y `1.0000` representan el mismo valor semantico.

No se congela algoritmo criptografico especifico en este documento.

## 17. request_hash

`request_hash` representa el comando, no una copia completa del `DRAFT`.

Debe incluir conceptualmente:

- `operation_type = 'CONFIRM_PURCHASE'`;
- `purchase_id`;
- `expected_purchase_fingerprint`;
- cualquier otra precondicion explicita del comando que cambie su significado.

No duplicar todas las `purchase_items` en `request_hash`; el fingerprint ya representa la version semantica del `DRAFT` persistido.

No se define algoritmo criptografico concreto.

## 18. Idempotencia

`idempotency_key` es obligatoria.

Usar:

```text
operation_type = 'CONFIRM_PURCHASE'
```

No se agrega enum. `operation_type` es `TEXT` y el `CHECK` existente acepta `CONFIRM_PURCHASE`.

Defensa primaria:

- `idempotency_keys`;
- `idempotency_key` unica por `business_id` + `operation_type`;
- `request_hash` canonico para detectar payload/comando distinto.

`client_operation_id` no sustituye esta defensa.

`UNIQUE(purchase_order_id)` tampoco sustituye esta defensa.

## 19. Lifecycle temporal definitivo

Reutilizar exactamente la politica temporal de `CONFIRM_ORDER`.

`IN_PROGRESS`:

- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`.

`COMPLETED`:

- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

`FAILED`:

- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

No introducir otros tiempos.

## 20. Catalogo minimo de errores

Este borrador define solo errores ya cerrados.

Idempotencia:

- `PURCHASE_IDEMPOTENCY_KEY_REUSED`;
- `PURCHASE_IDEMPOTENCY_IN_PROGRESS`.

Purchase:

- `PURCHASE_NOT_FOUND`;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`.

Purchase order:

- `PURCHASE_ORDER_STATUS_INVALID`.

No se crean todavia errores de:

- autorizacion;
- branch/business;
- supplier;
- producto;
- unidad;
- `difference_reason`;
- totales;
- inventario;
- costo;
- replenishment.

No se crea `PURCHASE_EMPTY` ni equivalente.

## 21. Semantica de errores minimos

`PURCHASE_IDEMPOTENCY_KEY_REUSED` ocurre cuando la misma `idempotency_key` llega con `request_hash` diferente. Aplica para cualquier estado de la key y se evalua antes de cualquier semantica por estado.

`PURCHASE_IDEMPOTENCY_IN_PROGRESS` ocurre cuando existe la misma key/hash con lease vigente.

`PURCHASE_NOT_FOUND` ocurre cuando `purchase_id` no corresponde a una `purchase` visible/valida para la operacion segun la frontera de seguridad que se cierre despues. Este borrador no define autorizacion completa.

`PURCHASE_STATUS_INVALID` ocurre cuando la `purchase` existe pero su estado no es confirmable y no corresponde a reconciliacion historica segura. Ejemplo directo: `CANCELLED`.

`PURCHASE_DRAFT_STALE` ocurre ante cualquier cambio semantico respecto del `DRAFT` esperado, incluyendo:

- fingerprint diferente;
- identidad/herencia distinta entre pre-read y locks.

`PURCHASE_ORDER_STATUS_INVALID` ocurre cuando la `purchase` esta `DRAFT` pero el `purchase_order` relacionado no esta en `CONFIRMED`, que es el estado requerido para ejecutar una nueva confirmacion.

Los errores de idempotencia se resuelven por contrato de la key. No deben mezclarse mecanicamente con errores operativos de FASE B.

## 22. Estados purchases

Enum real `purchase_status`:

- `DRAFT`;
- `CONFIRMED`;
- `CANCELLED`.

Reglas actuales:

- `DRAFT`: camino normal de confirmacion.
- `CONFIRMED`: no repetir efectos.
- `CANCELLED`: no confirmable por `CONFIRM_PURCHASE`.

`CONFIRM_PURCHASE` no reactiva compras `CANCELLED`.

La politica completa de `CANCEL_PURCHASE_DRAFT` queda fuera de este micro-hito.

## 23. Estados purchase_orders relevantes

Estados relevantes de `purchase_orders` para este borrador:

- `CONFIRMED`: estado requerido para confirmar una `purchase DRAFT`.
- `CLOSED`: estado historico esperado despues de compra confirmada.
- `DRAFT`: no valido para `CONFIRM_PURCHASE`.
- `CANCELLED`: no valido para una nueva `CONFIRM_PURCHASE`.

Este documento no redisena `CANCEL_ORDER`.

## 24. Matriz minima de estado

| purchase status | order status | Resultado conceptual |
|-----------------|--------------|----------------------|
| `DRAFT` | `CONFIRMED` | Camino normal. |
| `CONFIRMED` | `CLOSED` | Confirmacion historica completa; puede reconciliarse sin efectos si cumple evidencia. |
| `CANCELLED` | cualquiera | `PURCHASE_STATUS_INVALID`. |
| `DRAFT` | `DRAFT` / `CANCELLED` / `CLOSED` | `PURCHASE_ORDER_STATUS_INVALID`. |
| `CONFIRMED` | distinto de `CLOSED` | Estado inconsistente; no ejecutar efectos y no fingir exito. |

No crear todavia un error publico adicional solo para corrupcion/integridad interna. El nombre final de un eventual error de integridad puede cerrarse despues si realmente se necesita.

## 25. Result entity y response_body

Al completar o reconciliar:

- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`.

No usar `purchase_orders` como resultado principal.

`response_body` debe ser minimo y deliberadamente pequeno. Se conserva el limite conceptual de 16 KiB usado en contratos anteriores.

Conceptualmente puede contener o permitir reconstruir:

- purchase id;
- `public_id`;
- `folio`;
- `status`;
- `confirmed_at`;
- `purchase_order_id`;
- order status;
- `subtotal`;
- `tax_total`;
- `total`.

No se congela DTO/API.

## 26. Misma key / hash diferente

Para cualquier estado:

- `IN_PROGRESS`;
- `COMPLETED`;
- `FAILED`;

si la misma key tiene hash diferente, devolver `PURCHASE_IDEMPOTENCY_KEY_REUSED`.

Esta comprobacion ocurre antes de cualquier semantica por estado.

## 27. Misma key COMPLETED

Si existe:

- misma key;
- mismo hash;
- `status = 'COMPLETED'`;

devolver o reconstruir el resultado historico.

No:

- reautorizar para ese replay historico exacto;
- repetir locks de negocio innecesarios;
- repetir inventario;
- repetir fulfillment;
- repetir audit.

## 28. Misma key FAILED

Si existe:

- misma key;
- mismo hash;
- `status = 'FAILED'`;

devolver el error de dominio almacenado.

No reintentar automaticamente.

Una key `FAILED` historica nunca se transforma posteriormente en `COMPLETED` porque otra key haya confirmado la misma `purchase`.

Ejemplo:

1. `K1 + F1 -> PURCHASE_DRAFT_STALE -> FAILED`.
2. `K2 + F2` confirma correctamente.
3. Un retry posterior de `K1 + F1` sigue devolviendo el `FAILED` historico.

## 29. IN_PROGRESS activo

Si existe:

- `status = 'IN_PROGRESS'`;
- mismo hash;
- `locked_until > now()`;

devolver `PURCHASE_IDEMPOTENCY_IN_PROGRESS`.

No mantener la peticion HTTP esperando 30 segundos.

## 30. IN_PROGRESS expirado

Si existe:

- `status = 'IN_PROGRESS'`;
- mismo hash;
- `locked_until <= now()`;

la expiracion temporal por si sola no autoriza repetir efectos.

Debe recuperarse de forma segura:

- bloquear key;
- inspeccionar estado autoritativo de `purchase`/`purchase_order`;
- si ya existe confirmacion historica completa, reconciliar `COMPLETED`;
- si `purchase` sigue `DRAFT` y `purchase_order` sigue `CONFIRMED`, renovar lease y continuar solo si todas las precondiciones siguen siendo validas;
- si hay error deterministico, aplicar el flujo correspondiente;
- si existe incertidumbre tecnica, no inventar exito ni `FAILED`.

## 31. Autorizacion cross-key

Todavia no se define permiso exacto.

Regla congelada para este borrador:

- SAME TERMINAL KEY: `COMPLETED`/`FAILED` historica conserva su propio contrato.
- NUEVA KEY o `IN_PROGRESS` recuperable: si encuentra `purchase` ya `CONFIRMED` + `purchase_order` `CLOSED`, no puede reconciliar hacia `COMPLETED` hasta validar tenant/business, scope y autorizacion actual.

El detalle del permiso se cerrara despues.

## 32. FASE previa de resolucion

Antes de FASE A, el servicio puede necesitar una lectura preliminar por `purchase_id` para obtener:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Esta lectura es no autoritativa y solo descubre recursos/scope.

El schema real permite que `idempotency_keys.branch_id` sea `NULL` y la unicidad no depende de `branch_id`. Por tanto:

- `business_id` debe derivarse del contexto autenticado/tenant;
- `branch_id` puede derivarse del pre-read si la `purchase` se resuelve de forma segura;
- si no se puede resolver sin revelar informacion, la key puede reservarse con `branch_id = NULL` y despues fallar de forma segura segun el contrato de visibilidad que se cierre.

Esta fase no produce efectos de negocio.

## 33. FASE A - Reserva idempotente

FASE A es una transaccion corta dedicada a `idempotency_keys`.

Para key nueva, crear:

- `operation_type = 'CONFIRM_PURCHASE'`;
- `request_hash = hash canonico`;
- `status = 'IN_PROGRESS'`;
- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`;
- `business_id` desde contexto autenticado;
- `branch_id` segun scope fisico real validado o `NULL` si aun no puede resolverse de forma segura.

Para key existente:

1. comprobar hash;
2. si difiere, devolver `PURCHASE_IDEMPOTENCY_KEY_REUSED`;
3. si esta `COMPLETED`, replay;
4. si esta `FAILED`, replay del error;
5. si esta `IN_PROGRESS` con lease activo, devolver `PURCHASE_IDEMPOTENCY_IN_PROGRESS`;
6. si esta `IN_PROGRESS` expirado, tratar como candidato a recuperacion segura.

FASE A no produce efectos de negocio:

- no inventario;
- no fulfillment;
- no release;
- no cierre de pedido;
- no audit de confirmacion;
- no cambio de `purchases`;
- no cambio de `purchase_orders`.

## 34. FASE B - Estructura actual

FASE B aun no esta completa en este borrador.

Por ahora queda congelado solamente este prefijo:

1. Bloquear/verificar `idempotency_key` reservada.
2. Obtener metadata preleida necesaria del `purchase`.
3. Bloquear `purchase_orders(id) FOR UPDATE`.
4. Bloquear `purchases(id) FOR UPDATE`.
5. Revalidar `purchase_order_id`, `branch_id`, `supplier_id` y `replenishment_channel` contra el pre-read.
6. Validar estado `purchase`/`purchase_order`.
7. Resolver reconciliacion historica si corresponde.
8. Si camino normal: `purchase DRAFT + order CONFIRMED`.
9. Bloquear/leer `purchase_items` por `line_number ASC, id ASC`.
10. Recalcular purchase fingerprint autoritativo.
11. Comparar contra `expected_purchase_fingerprint`.
12. Si difiere, rechazar con `PURCHASE_DRAFT_STALE`.
13. Ejecutar posteriormente las validaciones de dominio todavia pendientes.
14. Ejecutar posteriormente effects/locks de inventario/reposicion todavia pendientes.
15. Solo despues de todos los efectos futuros correctamente definidos podra marcar `purchase CONFIRMED`, cerrar `purchase_order`, auditar, marcar idempotencia `COMPLETED` y hacer `COMMIT`.

No se rellenan ahora los pasos 13-15 con diseno inventado.

## 35. Reconciliacion historica

Para una nueva key o `IN_PROGRESS` recuperable, si despues de validar scope/autorizacion actual se encuentra:

```text
purchase.status = 'CONFIRMED'
AND purchase.confirmed_at IS NOT NULL
AND purchase.confirmed_by_user_id IS NOT NULL
AND purchase_order.status = 'CLOSED'
AND purchase_order.closed_at IS NOT NULL
```

entonces:

- no repetir efectos;
- reconciliar la key actual hacia `COMPLETED`;
- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`;
- guardar respuesta minima;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

No crear otro audit de confirmacion.

No modificar inventario/reposicion.

## 36. Estado inconsistente

No considerar exito historico si falta coherencia entre `purchase CONFIRMED` y `purchase_order CLOSED`.

Ejemplos:

- `purchase CONFIRMED + order CONFIRMED`;
- `purchase DRAFT + order CLOSED`.

No ejecutar efectos para arreglar silenciosamente el estado.

No inventar historia.

Documentar como inconsistencia que requiere rechazo/diagnostico. El catalogo definitivo de error de integridad puede decidirse en un micro-hito posterior.

## 37. FASE C - Error deterministico

Patron:

1. `ROLLBACK` completo de FASE B.
2. `BEGIN` corto.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` original.
7. Guardar `error_message` seguro y breve.
8. `locked_until = NULL`.
9. `expires_at = now() + 30 dias`.
10. `COMMIT`.

No guardar en `error_message`:

- SQL;
- stack trace;
- secretos;
- fingerprint completo;
- request_hash completo.

Errores deterministicos de este micro-hito que pueden llegar a FASE C:

- `PURCHASE_NOT_FOUND` cuando aplique despues de reservar key y el scope fisico permita representarlo;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`;
- `PURCHASE_ORDER_STATUS_INVALID`.

`PURCHASE_IDEMPOTENCY_KEY_REUSED` y `PURCHASE_IDEMPOTENCY_IN_PROGRESS` pertenecen al contrato de la key y no son errores operativos de FASE B.

## 38. Fallos tecnicos

Para:

- crash;
- timeout interno;
- perdida de conexion;
- error inesperado;
- estado de `COMMIT` desconocido;

no marcar `FAILED` automaticamente.

La key puede permanecer `IN_PROGRESS` hasta vencimiento del lease.

Despues se aplica recuperacion segura.

## 39. Folio y document_sequences

`CONFIRM_PURCHASE`:

- no crea folio;
- no cambia folio;
- no toca `document_sequences` por `COM`;
- no reserva secuencia;
- usa `purchases.folio` ya persistido.

La creacion del DRAFT es responsable de que exista el folio segun el modelo actual.

No se disena `CREATE_PURCHASE_DRAFT` aqui.

## 40. client_operation_id

`purchases.client_operation_id` es fisicamente nullable.

Para `CONFIRM_PURCHASE`:

- no es obligatorio;
- no reemplaza `idempotency_key`;
- no reemplaza `request_hash`;
- no reemplaza `expected_purchase_fingerprint`;
- si tiene valor, es inmutable a nivel de servicio.

No se solicita db-4.

## 41. UNIQUE(purchase_order_id)

`UNIQUE(purchase_order_id)` es defensa fisica de una `purchase` por `purchase_order`.

No sustituye idempotencia porque no guarda:

- `request_hash`;
- `IN_PROGRESS`;
- `FAILED`;
- lease;
- replay contractual.

## 42. Cambio fisico

Este micro-hito no requiere:

- columna;
- version;
- trigger;
- constraint;
- `request_hash` en `purchases`;
- `client_operation_id NOT NULL`;
- indice obligatorio;
- db-4.

## 43. Puntos pendientes antes del freeze

Antes de congelar `CONFIRM_PURCHASE v0.1`, faltan:

- autorizacion/permiso;
- catalogo completo de errores;
- reglas de productos/unidades;
- `difference_reason`;
- autoridad/revalidacion de totales;
- fulfillment/release;
- inventory effects;
- costo promedio;
- orden global de locks;
- `READ COMMITTED` final;
- audit;
- atomicidad completa;
- pruebas de concurrencia.

No quedan como pendientes en este borrador:

- identidad;
- fingerprint;
- idempotencia;
- folio de confirmacion;
- parent mutex;
- inmutabilidad purchase/order;
- Politica A.
