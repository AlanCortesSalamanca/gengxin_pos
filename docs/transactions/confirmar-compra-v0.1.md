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
- permiso definitivo;
- autorizacion completa;
- estados base;
- recuperacion historica;
- estructura FASE A / FASE B / FASE C hasta el punto seguro definido.

Este borrador todavia deja abiertos:

- catalogo final de errores;
- supplier inactive;
- product inactive;
- unidad operativa;
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

## 19.1. Autorizacion, tenant y sucursal

Permiso funcional definitivo para ejecutar una nueva `CONFIRM_PURCHASE` o recuperar/reconciliar una ejecucion mediante nueva key / `IN_PROGRESS` recuperable:

```text
PURCHASES_CONFIRM
```

No se crea seed en este documento. La carga futura de `permissions.code = 'PURCHASES_CONFIRM'` es configuracion/implementacion y no requiere cambio de schema.

Una nueva ejecucion de `CONFIRM_PURCHASE` exige:

1. usuario actual con `users.status = 'ACTIVE'`;
2. acceso explicito a `purchases.branch_id` mediante `user_branches(user_id, branch_id)`;
3. al menos un rol valido/activo del mismo `business_id` que otorgue `permissions.code = 'PURCHASES_CONFIRM'` mediante la relacion fisica real `user_roles -> roles -> role_permissions -> permissions`.

No autorizan por si solos:

- `ADMIN`;
- `MANAGER`;
- `OWNER`;
- nombre textual de `roles.code` o `roles.name`;
- usuario que creo el `DRAFT`;
- `purchases.received_by_user_id`;
- cualquier privilegio implicito no modelado.

La autorizacion funcional depende del permiso real `PURCHASES_CONFIRM`.

`purchases.received_by_user_id` es dato historico del documento de recepcion. No autoriza confirmar, no obliga a que esa persona confirme, no sustituye al actor actual y no sustituye permiso.

Al confirmar exitosamente, `purchases.confirmed_by_user_id` debe recibir el `user_id` del actor actual autorizado.

La cadena autoritativa de tenant es:

```text
purchases.branch_id -> branches.business_id
```

El `business_id` de la operacion proviene del contexto autenticado y debe coincidir con la branch persistida. No se confia en un `business_id` libre enviado por cliente.

`PURCHASE_NOT_FOUND` es la frontera segura de no divulgacion cuando `purchase_id` no existe o pertenece a otro tenant/business no visible para el actor/contexto. No se crea `PURCHASE_BUSINESS_MISMATCH` para ese caso.

No se introduce `PURCHASE_BRANCH_MISMATCH` en `CONFIRM_PURCHASE v0.1`. `branch_id` no es una entrada independiente del comando; la branch autoritativa se deriva de `purchases.branch_id`. No se copia mecanicamente `PURCHASE_ORDER_BRANCH_MISMATCH`.

Para una nueva ejecucion o `IN_PROGRESS` recuperable, la branch debe estar operativa/activa segun `branches.active`. Si no, devolver `BRANCH_INACTIVE`. Un replay historico `COMPLETED` con misma `idempotency_key` y mismo `request_hash` no debe fallar porque la branch quedo inactiva despues.

`BRANCH_BUSINESS_MISMATCH` se usa solo cuando la branch ya pudo resolverse de forma segura dentro del contexto visible pero existe inconsistencia entre `branches.business_id` y el `business_id` autenticado esperado. Para recursos de otro tenant que no deben revelarse, usar `PURCHASE_NOT_FOUND`.

`suppliers.business_id` debe coincidir con el business de `purchases.branch_id`. Si existe inconsistencia visible y segura, devolver `SUPPLIER_BUSINESS_MISMATCH`. Este micro-hito no cierra `SUPPLIER_INACTIVE`.

Para cada `purchase_item`, `products.business_id` debe coincidir con el business de `purchases.branch_id`. Si no, devolver `PRODUCT_BUSINESS_MISMATCH`. Este micro-hito no cierra `PRODUCT_INACTIVE`.

La FK fisica `purchase_items(product_unit_id, product_id) -> product_units(id, product_id)` protege que la unidad pertenezca al mismo producto. No se cierra todavia un error funcional definitivo por unidad inactive/operativa y no se agrega `PRODUCT_UNIT_INVALID` al catalogo cerrado.

## 20. Catalogo de errores cerrado hasta este micro-hito

Este borrador define los errores cerrados hasta este micro-hito. El catalogo final sigue incompleto porque faltan decisiones sobre supplier inactive, product inactive, unidad operativa, `difference_reason`, totales/impuestos, inventario, costo y replenishment.

Idempotencia:

- `PURCHASE_IDEMPOTENCY_KEY_REUSED`;
- `PURCHASE_IDEMPOTENCY_IN_PROGRESS`.

Purchase:

- `PURCHASE_NOT_FOUND`;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`.

Purchase order:

- `PURCHASE_ORDER_STATUS_INVALID`.

Autorizacion:

- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`.

Branch / business:

- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`.

Supplier / business:

- `SUPPLIER_BUSINESS_MISMATCH`.

Product / business:

- `PRODUCT_BUSINESS_MISMATCH`.

No se crean todavia errores de:

- `PURCHASE_BRANCH_MISMATCH`;
- `PURCHASE_BUSINESS_MISMATCH`;
- `SUPPLIER_INACTIVE`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_UNIT_INVALID`;
- `difference_reason`;
- totales;
- inventario;
- costo;
- replenishment.

No se crea `PURCHASE_EMPTY` ni equivalente.

## 21. Semantica de errores minimos

`PURCHASE_IDEMPOTENCY_KEY_REUSED` ocurre cuando la misma `idempotency_key` llega con `request_hash` diferente. Aplica para cualquier estado de la key y se evalua antes de cualquier semantica por estado.

`PURCHASE_IDEMPOTENCY_IN_PROGRESS` ocurre cuando existe la misma key/hash con lease vigente.

`PURCHASE_NOT_FOUND` ocurre cuando `purchase_id` no corresponde a una `purchase` visible/valida para la operacion. Tambien se usa como frontera segura de no divulgacion cuando el recurso pertenece a otro tenant/business no visible para el actor/contexto.

`PURCHASE_STATUS_INVALID` ocurre cuando la `purchase` existe pero su estado no es confirmable y no corresponde a reconciliacion historica segura. Ejemplo directo: `CANCELLED`.

`PURCHASE_DRAFT_STALE` ocurre ante cualquier cambio semantico respecto del `DRAFT` esperado, incluyendo:

- fingerprint diferente;
- identidad/herencia distinta entre pre-read y locks.

`PURCHASE_ORDER_STATUS_INVALID` ocurre cuando la `purchase` esta `DRAFT` pero el `purchase_order` relacionado no esta en `CONFIRMED`, que es el estado requerido para ejecutar una nueva confirmacion.

`USER_INACTIVE` ocurre cuando el actor actual no cumple `users.status = 'ACTIVE'` para una ejecucion nueva o recuperable. No aplica a replay historico de misma key/hash en `COMPLETED` o `FAILED`.

`USER_BRANCH_FORBIDDEN` ocurre cuando el actor no tiene acceso explicito a `purchases.branch_id` mediante `user_branches`. Es autorizacion del usuario y no debe confundirse con `BRANCH_BUSINESS_MISMATCH`.

`USER_PERMISSION_DENIED` ocurre cuando el usuario tiene acceso a la branch pero no posee `PURCHASES_CONFIRM` mediante un rol valido del mismo business. No existe bypass por nombre de rol.

`BRANCH_INACTIVE` ocurre cuando la branch de la `purchase` no esta operativa/activa para una ejecucion nueva o recuperable. No aplica a replay historico de misma key/hash en `COMPLETED`.

`BRANCH_BUSINESS_MISMATCH` ocurre cuando la branch ya pudo resolverse de forma segura dentro del contexto visible, pero `branches.business_id` no coincide con el `business_id` autenticado esperado. Para recursos de otro tenant no visible, usar `PURCHASE_NOT_FOUND`.

`SUPPLIER_BUSINESS_MISMATCH` ocurre cuando la `purchase`/pedido referencia un supplier cuya pertenencia empresarial no coincide con el business autoritativo de la branch. Es inconsistencia multiempresa y no debe confundirse con supplier inactive.

`PRODUCT_BUSINESS_MISMATCH` ocurre cuando al menos una `purchase_item` referencia un producto cuyo business no coincide con el business de la branch de la `purchase`. Es inconsistencia multiempresa y no debe confundirse con product inactive.

Los errores de idempotencia se resuelven por contrato de la key. No deben mezclarse mecanicamente con errores operativos de FASE B.

No se crea `PURCHASE_BRANCH_MISMATCH` porque `branch_id` no es entrada independiente del comando.

No se crean todavia `SUPPLIER_INACTIVE`, `PRODUCT_INACTIVE` ni `PRODUCT_UNIT_INVALID`.

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

- revalidar `users.status = 'ACTIVE'`;
- revalidar `user_branches`;
- revalidar `PURCHASES_CONFIRM`;
- revalidar `branches.active`;
- revalidar supplier active;
- revalidar product active;
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

No reevaluar autorizacion actual, estado actual del `DRAFT` ni catalogos actuales.

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

Regla definitiva para este borrador:

- SAME TERMINAL KEY: `COMPLETED`/`FAILED` historica conserva su propio contrato.
- NUEVA KEY o `IN_PROGRESS` recuperable: antes de ejecutar efectos o reconciliar una `purchase` ya confirmada debe validar autorizacion actual.

Para una nueva `idempotency_key` o `IN_PROGRESS` recuperable, validar en este orden conceptual antes de continuar con `DRAFT` o reconciliar `CONFIRMED + CLOSED` historico:

1. tenant/business visible;
2. branch valida/activa cuando aplique;
3. `users.status = 'ACTIVE'`;
4. acceso mediante `user_branches`;
5. permiso funcional `PURCHASES_CONFIRM`.

Solo despues puede continuar con `purchase DRAFT + order CONFIRMED` o reconciliar una confirmacion historica `purchase CONFIRMED + order CLOSED`.

Esto impide usar una nueva key como bypass para leer o reconciliar una `purchase` a la que el actor ya no tiene acceso.

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
6. Validar tenant/business visible.
7. Validar branch: `branches.active` y pertenencia a `business_id` autenticado segun la frontera segura definida.
8. Validar `users.status = 'ACTIVE'`.
9. Validar acceso a `purchases.branch_id` mediante `user_branches`.
10. Validar permiso funcional `PURCHASES_CONFIRM` mediante `user_roles -> roles -> role_permissions -> permissions`.
11. Resolver estados/reconciliacion historica si corresponde.
12. Si camino normal: `purchase DRAFT + order CONFIRMED`.
13. Bloquear/leer `purchase_items` por `line_number ASC, id ASC`.
14. Validar `SUPPLIER_BUSINESS_MISMATCH` si el supplier no pertenece al business de la branch.
15. Validar `PRODUCT_BUSINESS_MISMATCH` si alguna linea referencia producto de otro business.
16. Recalcular purchase fingerprint autoritativo.
17. Comparar contra `expected_purchase_fingerprint`.
18. Ejecutar posteriormente las validaciones de dominio todavia pendientes.
19. Ejecutar posteriormente effects/locks de inventario/reposicion todavia pendientes.
20. Solo despues de todos los efectos futuros correctamente definidos podra marcar `purchase CONFIRMED`, cerrar `purchase_order`, auditar, marcar idempotencia `COMPLETED` y hacer `COMMIT`.

No se introducen todavia locks de inventario/reposicion. No se define todavia supplier active, product active, unidad operativa, `difference_reason` ni totales/impuestos.

La consistencia supplier/product business puede validarse antes del fingerprint porque protege tenant/integridad. Las politicas funcionales abiertas no se inventan en este prefijo.

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
- request_hash completo;
- datos que revelen otro tenant.

Errores deterministicos de este micro-hito que pueden llegar a FASE C:

- `PURCHASE_NOT_FOUND` cuando aplique despues de reservar key y el scope fisico permita representarlo;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`;
- `PURCHASE_ORDER_STATUS_INVALID`;
- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`;
- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`;
- `SUPPLIER_BUSINESS_MISMATCH`;
- `PRODUCT_BUSINESS_MISMATCH`.

`PURCHASE_IDEMPOTENCY_KEY_REUSED` y `PURCHASE_IDEMPOTENCY_IN_PROGRESS` pertenecen al contrato de la key y no son errores operativos de FASE B.

Tampoco pasan por FASE C:

- replay `COMPLETED`;
- replay `FAILED`;
- fallos tecnicos no deterministicos.

FASE C conserva el `error_code` original.

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
- FK;
- version;
- trigger;
- constraint;
- enum;
- `request_hash` en `purchases`;
- `client_operation_id NOT NULL`;
- indice obligatorio;
- db-4.

El seed futuro de `PURCHASES_CONFIRM` es configuracion/implementacion futura, no evolucion fisica del modelo.

## 43. Puntos pendientes antes del freeze

Antes de congelar `CONFIRM_PURCHASE v0.1`, faltan:

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
- autorizacion;
- permiso `PURCHASES_CONFIRM`;
- frontera tenant;
- acceso de sucursal;
- errores business cerrados en este micro-hito;
- folio de confirmacion;
- parent mutex;
- inmutabilidad purchase/order;
- Politica A.
