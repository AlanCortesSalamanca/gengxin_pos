-- Validaciones minimas para schema v0.5-db-4.
-- Ejecutar solo en base de prueba con el schema ya creado.
-- El script usa una transaccion descartable y termina con ROLLBACK.

BEGIN;

DO $$
DECLARE
  v_failures TEXT[] := ARRAY[]::TEXT[];
  v_business_id BIGINT;
  v_branch_id BIGINT;
  v_price_list_id BIGINT;
  v_user_id BIGINT;
  v_unit_id BIGINT;
  v_product_id BIGINT;
  v_product_unit_id BIGINT;
  v_supplier_id BIGINT;
  v_cash_register_id BIGINT;
  v_terminal_id BIGINT;
  v_cash_session_id BIGINT;
  v_customer_id BIGINT;
  v_sale_id BIGINT;
  v_sale_item_a_id BIGINT;
  v_sale_item_b_id BIGINT;
  v_sale_item_c_id BIGINT;
  v_sale_item_partial_id BIGINT;
  v_sale_item_zero_id BIGINT;
  v_sale_item_rf_id BIGINT;
  v_purchase_order_id BIGINT;
  v_purchase_order_item_x_id BIGINT;
  v_purchase_order_item_y_id BIGINT;
  v_purchase_order_item_rf_id BIGINT;
  v_purchase_id BIGINT;
  v_purchase_item_p1_id BIGINT;
  v_purchase_item_p2_id BIGINT;
  v_purchase_item_y_id BIGINT;
  v_purchase_item_unordered_id BIGINT;
  v_purchase_item_partial1_id BIGINT;
  v_purchase_item_partial2_id BIGINT;
  v_purchase_item_rf1_id BIGINT;
  v_purchase_item_rf2_id BIGINT;
  v_allocation_a_id BIGINT;
  v_allocation_b_id BIGINT;
  v_allocation_c_id BIGINT;
  v_allocation_partial_id BIGINT;
  v_allocation_zero_id BIGINT;
  v_allocation_rf_id BIGINT;
  v_count INTEGER;
  v_bad_count INTEGER;
  v_sum NUMERIC(18,4);
  v_constraint_name TEXT;
  v_pass_many_to_many BOOLEAN := FALSE;
  v_pass_one_purchase_item_many_allocations BOOLEAN := FALSE;
  v_pass_one_allocation_many_purchase_items BOOLEAN := FALSE;
  v_pass_sum_allocation BOOLEAN := FALSE;
  v_pass_sum_purchase_item BOOLEAN := FALSE;
  v_pass_multiple_purchase_items_same_order_item BOOLEAN := FALSE;
  v_pass_partial BOOLEAN := FALSE;
  v_pass_zero BOOLEAN := FALSE;
  v_pass_rf BOOLEAN := FALSE;
BEGIN
  -- Metadata db-4: tabla detail exacta.
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'replenishment_allocation_fulfillments'
  ) THEN
    v_failures := array_append(v_failures, 'replenishment_allocation_fulfillments no existe');
  END IF;

  SELECT count(*)
  INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'replenishment_allocation_fulfillments';

  IF v_count <> 6 THEN
    v_failures := array_append(v_failures, 'replenishment_allocation_fulfillments no tiene exactamente seis columnas');
  END IF;

  SELECT count(*)
  INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'replenishment_allocation_fulfillments'
    AND column_name IN (
      'id',
      'replenishment_allocation_id',
      'purchase_item_id',
      'purchase_order_item_id',
      'fulfilled_qty_base',
      'created_at'
    );

  IF v_count <> 6 THEN
    v_failures := array_append(v_failures, 'columnas esperadas de replenishment_allocation_fulfillments incompletas');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'replenishment_allocation_fulfillments'
      AND column_name IN ('public_id', 'updated_at', 'product_id', 'purchase_id', 'purchase_order_id', 'branch_id', 'channel', 'actor_user_id')
  ) THEN
    v_failures := array_append(v_failures, 'replenishment_allocation_fulfillments tiene columnas extra no esperadas');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'replenishment_allocation_fulfillments'
      AND column_name = 'fulfilled_qty_base'
      AND data_type = 'numeric'
      AND numeric_precision = 18
      AND numeric_scale = 4
  ) THEN
    v_failures := array_append(v_failures, 'fulfilled_qty_base no es NUMERIC(18,4)');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'replenishment_allocations'
      AND column_name = 'purchase_item_id'
  ) THEN
    v_failures := array_append(v_failures, 'replenishment_allocations.purchase_item_id todavia existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_replenishment_allocations_sale_order') THEN
    v_failures := array_append(v_failures, 'uq_replenishment_allocations_sale_order no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_replenishment_allocations_id_order_item') THEN
    v_failures := array_append(v_failures, 'uq_replenishment_allocations_id_order_item no existe');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_replenishment_allocations_fulfilled_purchase') THEN
    v_failures := array_append(v_failures, 'ck_replenishment_allocations_fulfilled_purchase todavia existe');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_replenishment_allocations_terminal_qty'
      AND pg_get_constraintdef(oid) LIKE '%fulfilled_qty_base + released_qty_base%<=%reserved_qty_base%'
  ) THEN
    v_failures := array_append(v_failures, 'ck_replenishment_allocations_terminal_qty no protege fulfilled+released<=reserved');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_replenishment_allocations_reserved_order'
      AND pg_get_constraintdef(oid) LIKE '%purchase_order_item_id IS NOT NULL%'
  ) THEN
    v_failures := array_append(v_failures, 'ck_replenishment_allocations_reserved_order no protege reserved->order_item');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'purchase_items'
      AND column_name = 'purchase_order_item_id'
      AND is_nullable = 'YES'
  ) THEN
    v_failures := array_append(v_failures, 'purchase_items.purchase_order_item_id no sigue nullable');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_purchase_items_id_order_item') THEN
    v_failures := array_append(v_failures, 'uq_purchase_items_id_order_item no existe');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'purchase_items'::regclass
      AND contype = 'u'
      AND pg_get_constraintdef(oid) = 'UNIQUE (purchase_order_item_id)'
  ) THEN
    v_failures := array_append(v_failures, 'existe UNIQUE(purchase_order_item_id) aislado en purchase_items');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_replenishment_allocation_fulfillments_qty_positive') THEN
    v_failures := array_append(v_failures, 'CHECK qty positive de detail no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_replenishment_allocation_fulfillments_alloc_purchase_item') THEN
    v_failures := array_append(v_failures, 'UNIQUE detail allocation/purchase_item no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_replenishment_allocation_fulfillments_allocation') THEN
    v_failures := array_append(v_failures, 'FK simple allocation de detail no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_replenishment_allocation_fulfillments_purchase_item') THEN
    v_failures := array_append(v_failures, 'FK simple purchase_item de detail no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_replenishment_allocation_fulfillments_allocation_order_item') THEN
    v_failures := array_append(v_failures, 'FK compuesta allocation/order_item de detail no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_replenishment_allocation_fulfillments_purchase_item_order') THEN
    v_failures := array_append(v_failures, 'FK compuesta purchase_item/order_item de detail no existe');
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_constraint
  WHERE conrelid = 'replenishment_allocation_fulfillments'::regclass
    AND contype = 'f'
    AND convalidated
    AND conname IN (
      'fk_replenishment_allocation_fulfillments_allocation',
      'fk_replenishment_allocation_fulfillments_purchase_item',
      'fk_replenishment_allocation_fulfillments_allocation_order_item',
      'fk_replenishment_allocation_fulfillments_purchase_item_order'
    );

  IF v_count <> 4 THEN
    v_failures := array_append(v_failures, 'no todas las FKs de detail estan validated');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'replenishment_allocation_fulfillments'::regclass
      AND contype = 'f'
      AND confdeltype = 'c'
  ) THEN
    v_failures := array_append(v_failures, 'alguna FK detail usa ON DELETE CASCADE');
  END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ix_replenishment_allocations_purchase_item') THEN
    v_failures := array_append(v_failures, 'indice viejo replenishment_allocations(purchase_item_id) existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ix_replenishment_allocation_fulfillments_purchase_item') THEN
    v_failures := array_append(v_failures, 'indice detail purchase_item no existe');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_replenishment_allocation_fulfillments_alloc_purchase_item') THEN
    v_failures := array_append(v_failures, 'indice implicito UNIQUE detail no existe con nombre esperado');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
      AND event_object_table = 'replenishment_allocation_fulfillments'
  ) THEN
    v_failures := array_append(v_failures, 'replenishment_allocation_fulfillments tiene triggers no esperados');
  END IF;

  -- Fixture minimo controlado para validar la representacion fisica db-4.
  INSERT INTO businesses (legal_name, commercial_name, tax_id)
  VALUES ('Empresa Test DB4 SA de CV', 'Empresa Test DB4', 'XAXX010101000')
  RETURNING id INTO v_business_id;

  INSERT INTO branches (business_id, code, name, postal_code, place_of_issue)
  VALUES (v_business_id, 'DB4', 'Sucursal DB4', '00000', '00000')
  RETURNING id INTO v_branch_id;

  INSERT INTO price_lists (business_id, code, name, is_default)
  VALUES (v_business_id, 'PUBLICO', 'Publico General', TRUE)
  RETURNING id INTO v_price_list_id;

  INSERT INTO users (username, full_name, password_hash)
  VALUES ('alan.db4', 'Alan DB4', 'hash-test')
  RETURNING id INTO v_user_id;

  INSERT INTO units (code, name, decimal_places)
  VALUES ('PZA-DB4', 'Pieza DB4', 0)
  RETURNING id INTO v_unit_id;

  INSERT INTO products (business_id, sku, name, base_unit_id, sat_product_service_key)
  VALUES (v_business_id, 'SKU-DB4', 'Producto DB4', v_unit_id, '01010101')
  RETURNING id INTO v_product_id;

  INSERT INTO product_units (product_id, unit_id, context, factor_to_base, sat_unit_key, is_default_sale, is_default_purchase)
  VALUES (v_product_id, v_unit_id, 'BASE', 1, 'H87', TRUE, TRUE)
  RETURNING id INTO v_product_unit_id;

  INSERT INTO suppliers (business_id, name)
  VALUES (v_business_id, 'Proveedor DB4')
  RETURNING id INTO v_supplier_id;

  INSERT INTO cash_registers (branch_id, code, name)
  VALUES (v_branch_id, 'CAJA-DB4', 'Caja DB4')
  RETURNING id INTO v_cash_register_id;

  INSERT INTO terminals (branch_id, name, status, activated_at)
  VALUES (v_branch_id, 'Terminal DB4', 'ACTIVE', now())
  RETURNING id INTO v_terminal_id;

  INSERT INTO cash_sessions (branch_id, cash_register_id, terminal_id, opened_by_user_id, opening_amount)
  VALUES (v_branch_id, v_cash_register_id, v_terminal_id, v_user_id, 100)
  RETURNING id INTO v_cash_session_id;

  INSERT INTO customers (business_id, price_list_id, display_name)
  VALUES (v_business_id, v_price_list_id, 'Cliente DB4')
  RETURNING id INTO v_customer_id;

  INSERT INTO sales (
    branch_id, terminal_id, cash_session_id, user_id, customer_id, price_list_id,
    folio, replenishment_channel, subtotal, total, client_operation_id
  ) VALUES (
    v_branch_id, v_terminal_id, v_cash_session_id, v_user_id, v_customer_id, v_price_list_id,
    'VEN-DB4-001', 'CASH', 100, 100, 'sale-db4-001'
  )
  RETURNING id INTO v_sale_id;

  INSERT INTO sale_items (
    sale_id, line_number, product_id, product_unit_id,
    product_sku_snapshot, description_snapshot, unit_code_snapshot, unit_name_snapshot,
    factor_to_base_snapshot, quantity, quantity_base, unit_price_snapshot, unit_cost_snapshot,
    subtotal, total
  ) VALUES
    (v_sale_id, 1, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 3, 3, 10, 5, 30, 30),
    (v_sale_id, 2, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 4, 4, 10, 5, 40, 40),
    (v_sale_id, 3, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 3, 3, 10, 5, 30, 30),
    (v_sale_id, 4, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 10, 10, 10, 5, 100, 100),
    (v_sale_id, 5, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 10, 10, 10, 5, 100, 100),
    (v_sale_id, 6, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 5, 5, 10, 5, 50, 50);

  SELECT id INTO v_sale_item_a_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 1;
  SELECT id INTO v_sale_item_b_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 2;
  SELECT id INTO v_sale_item_c_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 3;
  SELECT id INTO v_sale_item_partial_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 4;
  SELECT id INTO v_sale_item_zero_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 5;
  SELECT id INTO v_sale_item_rf_id FROM sale_items WHERE sale_id = v_sale_id AND line_number = 6;

  INSERT INTO purchase_orders (branch_id, supplier_id, replenishment_channel, folio, created_by_user_id)
  VALUES (v_branch_id, v_supplier_id, 'CASH', 'PED-DB4-001', v_user_id)
  RETURNING id INTO v_purchase_order_id;

  INSERT INTO purchase_order_items (
    purchase_order_id, line_number, product_id, product_unit_id,
    product_sku_snapshot, description_snapshot, unit_code_snapshot, unit_name_snapshot,
    factor_to_base_snapshot, ordered_qty, ordered_qty_base, replenishment_qty_base, stock_extra_qty_base
  ) VALUES
    (v_purchase_order_id, 1, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 20, 20, 20, 0),
    (v_purchase_order_id, 2, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 1, 1, 1, 0),
    (v_purchase_order_id, 3, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 10, 10, 5, 5);

  SELECT id INTO v_purchase_order_item_x_id FROM purchase_order_items WHERE purchase_order_id = v_purchase_order_id AND line_number = 1;
  SELECT id INTO v_purchase_order_item_y_id FROM purchase_order_items WHERE purchase_order_id = v_purchase_order_id AND line_number = 2;
  SELECT id INTO v_purchase_order_item_rf_id FROM purchase_order_items WHERE purchase_order_id = v_purchase_order_id AND line_number = 3;

  INSERT INTO purchases (branch_id, purchase_order_id, supplier_id, replenishment_channel, folio, received_by_user_id)
  VALUES (v_branch_id, v_purchase_order_id, v_supplier_id, 'CASH', 'COM-DB4-001', v_user_id)
  RETURNING id INTO v_purchase_id;

  INSERT INTO purchase_items (
    purchase_id, purchase_order_id, purchase_order_item_id, line_number,
    product_id, product_unit_id, product_sku_snapshot, description_snapshot,
    unit_code_snapshot, unit_name_snapshot, factor_to_base_snapshot,
    received_qty, received_qty_base, actual_unit_cost_base
  ) VALUES
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_x_id, 1, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 5, 5, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_x_id, 2, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 5, 5, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_y_id, 3, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 1, 1, 10),
    (v_purchase_id, v_purchase_order_id, NULL, 4, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 1, 1, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_rf_id, 5, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 3, 3, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_rf_id, 6, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 7, 7, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_x_id, 7, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 3, 3, 10),
    (v_purchase_id, v_purchase_order_id, v_purchase_order_item_x_id, 8, v_product_id, v_product_unit_id, 'SKU-DB4', 'Producto DB4', 'PZA-DB4', 'Pieza DB4', 1, 3, 3, 10);

  SELECT id INTO v_purchase_item_p1_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 1;
  SELECT id INTO v_purchase_item_p2_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 2;
  SELECT id INTO v_purchase_item_y_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 3;
  SELECT id INTO v_purchase_item_unordered_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 4;
  SELECT id INTO v_purchase_item_rf1_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 5;
  SELECT id INTO v_purchase_item_rf2_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 6;
  SELECT id INTO v_purchase_item_partial1_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 7;
  SELECT id INTO v_purchase_item_partial2_id FROM purchase_items WHERE purchase_id = v_purchase_id AND line_number = 8;

  SELECT count(*)
  INTO v_count
  FROM purchase_items
  WHERE purchase_order_item_id = v_purchase_order_item_x_id;

  IF v_count >= 2 THEN
    v_pass_multiple_purchase_items_same_order_item := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'no se permitieron multiples purchase_items para el mismo purchase_order_item');
  END IF;

  INSERT INTO replenishment_allocations (branch_id, product_id, channel, sale_item_id, purchase_order_item_id, reserved_qty_base, fulfilled_qty_base)
  VALUES
    (v_branch_id, v_product_id, 'CASH', v_sale_item_a_id, v_purchase_order_item_x_id, 3, 3),
    (v_branch_id, v_product_id, 'CASH', v_sale_item_b_id, v_purchase_order_item_x_id, 4, 4),
    (v_branch_id, v_product_id, 'CASH', v_sale_item_c_id, v_purchase_order_item_x_id, 3, 3),
    (v_branch_id, v_product_id, 'CASH', v_sale_item_partial_id, v_purchase_order_item_x_id, 10, 6),
    (v_branch_id, v_product_id, 'CASH', v_sale_item_zero_id, v_purchase_order_item_x_id, 10, 0),
    (v_branch_id, v_product_id, 'CASH', v_sale_item_rf_id, v_purchase_order_item_rf_id, 5, 5);

  SELECT id INTO v_allocation_a_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_a_id;
  SELECT id INTO v_allocation_b_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_b_id;
  SELECT id INTO v_allocation_c_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_c_id;
  SELECT id INTO v_allocation_partial_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_partial_id;
  SELECT id INTO v_allocation_zero_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_zero_id;
  SELECT id INTO v_allocation_rf_id FROM replenishment_allocations WHERE sale_item_id = v_sale_item_rf_id;

  UPDATE replenishment_allocations
  SET released_qty_base = 4
  WHERE id = v_allocation_partial_id;

  UPDATE replenishment_allocations
  SET released_qty_base = 10
  WHERE id = v_allocation_zero_id;

  -- SUM(detail)=fulfilled es invariante de servicio/transaccion + validation, no constraint agregado DB-enforced.
  INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
  VALUES
    (v_allocation_a_id, v_purchase_item_p1_id, v_purchase_order_item_x_id, 3),
    (v_allocation_b_id, v_purchase_item_p1_id, v_purchase_order_item_x_id, 2),
    (v_allocation_b_id, v_purchase_item_p2_id, v_purchase_order_item_x_id, 2),
    (v_allocation_c_id, v_purchase_item_p2_id, v_purchase_order_item_x_id, 3),
    (v_allocation_partial_id, v_purchase_item_partial1_id, v_purchase_order_item_x_id, 3),
    (v_allocation_partial_id, v_purchase_item_partial2_id, v_purchase_order_item_x_id, 3),
    (v_allocation_rf_id, v_purchase_item_rf1_id, v_purchase_order_item_rf_id, 3),
    (v_allocation_rf_id, v_purchase_item_rf2_id, v_purchase_order_item_rf_id, 2);

  -- Caso principal many-to-many.
  SELECT count(*)
  INTO v_count
  FROM replenishment_allocation_fulfillments
  WHERE replenishment_allocation_id IN (v_allocation_a_id, v_allocation_b_id, v_allocation_c_id);

  IF v_count = 4 THEN
    v_pass_many_to_many := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'caso many-to-many principal no produjo 4 details');
  END IF;

  SELECT count(DISTINCT replenishment_allocation_id)
  INTO v_count
  FROM replenishment_allocation_fulfillments
  WHERE purchase_item_id = v_purchase_item_p1_id;

  IF v_count >= 2 THEN
    v_pass_one_purchase_item_many_allocations := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'una purchase_item no cubrio multiples allocations');
  END IF;

  SELECT count(DISTINCT purchase_item_id)
  INTO v_count
  FROM replenishment_allocation_fulfillments
  WHERE replenishment_allocation_id = v_allocation_b_id;

  IF v_count = 2 THEN
    v_pass_one_allocation_many_purchase_items := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'una allocation no recibio multiples purchase_items');
  END IF;

  SELECT count(*)
  INTO v_bad_count
  FROM replenishment_allocations ra
  LEFT JOIN (
    SELECT replenishment_allocation_id, SUM(fulfilled_qty_base) AS detail_qty
    FROM replenishment_allocation_fulfillments
    GROUP BY replenishment_allocation_id
  ) raf ON raf.replenishment_allocation_id = ra.id
  WHERE ra.id IN (v_allocation_a_id, v_allocation_b_id, v_allocation_c_id, v_allocation_partial_id, v_allocation_zero_id, v_allocation_rf_id)
    AND COALESCE(raf.detail_qty, 0) <> ra.fulfilled_qty_base;

  IF v_bad_count = 0 THEN
    v_pass_sum_allocation := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'SUM(detail) != fulfilled_qty_base para alguna allocation fixture');
  END IF;

  SELECT count(*)
  INTO v_bad_count
  FROM (
    SELECT pi.id, pi.received_qty_base, COALESCE(SUM(raf.fulfilled_qty_base), 0) AS detail_qty
    FROM purchase_items pi
    LEFT JOIN replenishment_allocation_fulfillments raf ON raf.purchase_item_id = pi.id
    WHERE pi.id IN (v_purchase_item_p1_id, v_purchase_item_p2_id, v_purchase_item_y_id, v_purchase_item_partial1_id, v_purchase_item_partial2_id, v_purchase_item_rf1_id, v_purchase_item_rf2_id)
    GROUP BY pi.id, pi.received_qty_base
  ) q
  WHERE q.detail_qty > q.received_qty_base;

  IF v_bad_count = 0 THEN
    v_pass_sum_purchase_item := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'SUM(detail) supera received_qty_base para algun purchase_item fixture');
  END IF;

  SELECT COALESCE(SUM(fulfilled_qty_base), 0)
  INTO v_sum
  FROM replenishment_allocation_fulfillments
  WHERE replenishment_allocation_id = v_allocation_partial_id;

  IF v_sum = 6 AND EXISTS (
    SELECT 1
    FROM replenishment_allocations
    WHERE id = v_allocation_partial_id
      AND fulfilled_qty_base = 6
      AND released_qty_base = 4
      AND reserved_qty_base = 10
      AND fulfilled_qty_base + released_qty_base = reserved_qty_base
  ) THEN
    v_pass_partial := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'partial fulfillment no reconcilia fulfilled=6 released=4 reserved=10');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM replenishment_allocation_fulfillments
    WHERE replenishment_allocation_id = v_allocation_zero_id
  ) AND EXISTS (
    SELECT 1
    FROM replenishment_allocations
    WHERE id = v_allocation_zero_id
      AND reserved_qty_base = 10
      AND fulfilled_qty_base = 0
      AND released_qty_base = 10
  ) THEN
    v_pass_zero := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'zero fulfillment tiene detail o allocation inconsistente');
  END IF;

  SELECT COALESCE(SUM(fulfilled_qty_base), 0)
  INTO v_sum
  FROM replenishment_allocation_fulfillments
  WHERE replenishment_allocation_id = v_allocation_rf_id;

  IF v_sum = 5
     AND EXISTS (SELECT 1 FROM replenishment_allocation_fulfillments WHERE replenishment_allocation_id = v_allocation_rf_id AND purchase_item_id = v_purchase_item_rf1_id AND fulfilled_qty_base = 3)
     AND EXISTS (SELECT 1 FROM replenishment_allocation_fulfillments WHERE replenishment_allocation_id = v_allocation_rf_id AND purchase_item_id = v_purchase_item_rf2_id AND fulfilled_qty_base = 2)
     AND EXISTS (SELECT 1 FROM purchase_items WHERE id = v_purchase_item_rf2_id AND received_qty_base = 7) THEN
    v_pass_rf := TRUE;
  ELSE
    v_failures := array_append(v_failures, 'representacion REPLENISHMENT-FIRST no dejo solo 5 en detail');
  END IF;

  -- qty=0 rechazada por CHECK.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_zero_id, v_purchase_item_p1_id, v_purchase_order_item_x_id, 0);
    v_failures := array_append(v_failures, 'fulfilled_qty_base=0 no fue rechazado');
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'ck_replenishment_allocation_fulfillments_qty_positive' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'fulfilled_qty_base=0 rechazo con constraint inesperado');
    END IF;
  END;

  -- qty negativa rechazada por CHECK.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_zero_id, v_purchase_item_p1_id, v_purchase_order_item_x_id, -1);
    v_failures := array_append(v_failures, 'fulfilled_qty_base negativa no fue rechazada');
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'ck_replenishment_allocation_fulfillments_qty_positive' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'fulfilled_qty_base negativa rechazo con constraint inesperado');
    END IF;
  END;

  -- Duplicado allocation/source rechazado por UNIQUE detail.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_a_id, v_purchase_item_p1_id, v_purchase_order_item_x_id, 1);
    v_failures := array_append(v_failures, 'duplicado allocation/purchase_item no fue rechazado');
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'uq_replenishment_allocation_fulfillments_alloc_purchase_item' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'duplicado allocation/purchase_item rechazo con constraint inesperado');
    END IF;
  END;

  -- Cross-order variant 1: allocation X + purchase_item Y + order_item X rechazada por FK compuesta hacia purchase_items.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_a_id, v_purchase_item_y_id, v_purchase_order_item_x_id, 1);
    v_failures := array_append(v_failures, 'cross-order variant 1 no fue rechazada');
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'fk_replenishment_allocation_fulfillments_purchase_item_order' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'cross-order variant 1 rechazo con constraint inesperado');
    END IF;
  END;

  -- Cross-order variant 2: allocation X + purchase_item Y + order_item Y rechazada por FK compuesta hacia allocations.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_a_id, v_purchase_item_y_id, v_purchase_order_item_y_id, 1);
    v_failures := array_append(v_failures, 'cross-order variant 2 no fue rechazada');
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'fk_replenishment_allocation_fulfillments_allocation_order_item' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'cross-order variant 2 rechazo con constraint inesperado');
    END IF;
  END;

  -- Purchase item no pedida con purchase_order_item_id NULL no puede ser source detail.
  BEGIN
    INSERT INTO replenishment_allocation_fulfillments (replenishment_allocation_id, purchase_item_id, purchase_order_item_id, fulfilled_qty_base)
    VALUES (v_allocation_zero_id, v_purchase_item_unordered_id, v_purchase_order_item_x_id, 1);
    v_failures := array_append(v_failures, 'purchase_item no pedida fue aceptada como source detail');
  EXCEPTION WHEN foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'fk_replenishment_allocation_fulfillments_purchase_item_order' THEN
      NULL;
    ELSE
      v_failures := array_append(v_failures, 'purchase_item no pedida rechazo con constraint inesperado');
    END IF;
  END;

  IF NOT v_pass_multiple_purchase_items_same_order_item THEN
    v_failures := array_append(v_failures, 'multiple purchase_items same order_item FAIL');
  END IF;

  IF NOT v_pass_many_to_many THEN
    v_failures := array_append(v_failures, 'many-to-many principal FAIL');
  END IF;

  IF NOT v_pass_one_purchase_item_many_allocations THEN
    v_failures := array_append(v_failures, '1 purchase_item -> multiples allocations FAIL');
  END IF;

  IF NOT v_pass_one_allocation_many_purchase_items THEN
    v_failures := array_append(v_failures, '1 allocation -> multiples purchase_items FAIL');
  END IF;

  IF NOT v_pass_sum_allocation THEN
    v_failures := array_append(v_failures, 'SUM(detail)=fulfilled FAIL');
  END IF;

  IF NOT v_pass_sum_purchase_item THEN
    v_failures := array_append(v_failures, 'SUM(detail)<=received FAIL');
  END IF;

  IF NOT v_pass_partial THEN
    v_failures := array_append(v_failures, 'partial fulfillment FAIL');
  END IF;

  IF NOT v_pass_zero THEN
    v_failures := array_append(v_failures, 'zero fulfillment FAIL');
  END IF;

  IF NOT v_pass_rf THEN
    v_failures := array_append(v_failures, 'REPLENISHMENT-FIRST representation FAIL');
  END IF;

  -- Conteos estructurales esperados para db-4.
  IF (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') <> 52 THEN
    v_failures := array_append(v_failures, 'conteo de tablas distinto de 52');
  END IF;

  IF (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND t.typtype = 'e') <> 19 THEN
    v_failures := array_append(v_failures, 'conteo de enums distinto de 19');
  END IF;

  IF (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND c.contype = 'f') <> 145 THEN
    v_failures := array_append(v_failures, 'conteo de FKs distinto de 145');
  END IF;

  IF (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'public' AND c.contype = 'c') <> 82 THEN
    v_failures := array_append(v_failures, 'conteo de CHECKs distinto de 82');
  END IF;

  IF (
    SELECT count(*)
    FROM pg_trigger tr
    JOIN pg_class cl ON cl.oid = tr.tgrelid
    JOIN pg_namespace n ON n.oid = cl.relnamespace
    WHERE n.nspname = 'public'
      AND NOT tr.tgisinternal
  ) <> 40 THEN
    v_failures := array_append(v_failures, 'conteo de triggers no internos distinto de 40');
  END IF;

  RAISE NOTICE 'PASS metadata db-4 detail/allocation/purchase_items';
  RAISE NOTICE 'PASS many-to-many allocation fulfillment detail';
  RAISE NOTICE 'PASS negative constraints and FK cross-order checks';
  RAISE NOTICE 'PASS aggregate validation fixtures: SUM(detail)=fulfilled and SUM(detail)<=received';
  RAISE NOTICE 'INFO indexes count: %', (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public');

  IF array_length(v_failures, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'Validaciones db-4 fallidas: %', array_to_string(v_failures, '; ');
  END IF;
END;
$$;

ROLLBACK;
