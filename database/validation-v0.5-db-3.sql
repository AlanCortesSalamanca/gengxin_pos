-- Validaciones minimas para schema v0.5-db-3.
-- Ejecutar solo en base de prueba con el schema ya creado.
-- El script usa una transaccion descartable y termina con ROLLBACK.

BEGIN;

DO $$
DECLARE
  v_failures TEXT[] := ARRAY[]::TEXT[];
  v_business_id BIGINT;
  v_branch_id BIGINT;
  v_branch_b_id BIGINT;
  v_price_list_id BIGINT;
  v_user_id BIGINT;
  v_unit_id BIGINT;
  v_product_id BIGINT;
  v_product_unit_id BIGINT;
  v_product_price_id BIGINT;
  v_cash_register_id BIGINT;
  v_cash_register_b_id BIGINT;
  v_terminal_1_id BIGINT;
  v_terminal_2_id BIGINT;
  v_terminal_b_id BIGINT;
  v_cash_session_id BIGINT;
  v_cash_session_b_id BIGINT;
  v_customer_id BIGINT;
  v_sale_id BIGINT;
  v_sale_b_id BIGINT;
  v_supplier_id BIGINT;
  v_purchase_order_a_id BIGINT;
  v_purchase_order_b_id BIGINT;
  v_purchase_order_item_a_id BIGINT;
  v_purchase_order_item_b_id BIGINT;
  v_purchase_a_id BIGINT;
  v_inventory_movement_id BIGINT;
  v_cash_movement_id BIGINT;
  v_replenishment_movement_id BIGINT;
  v_invoice_id BIGINT;
  v_invoice_event_id BIGINT;
  v_available NUMERIC(18,4);
BEGIN
  INSERT INTO businesses (legal_name, commercial_name, tax_id)
  VALUES ('Empresa Test SA de CV', 'Empresa Test', 'XAXX010101000')
  RETURNING id INTO v_business_id;

  INSERT INTO branches (business_id, code, name, postal_code, place_of_issue)
  VALUES (v_business_id, 'SUC1', 'Sucursal Test', '00000', '00000')
  RETURNING id INTO v_branch_id;

  INSERT INTO branches (business_id, code, name, postal_code, place_of_issue)
  VALUES (v_business_id, 'SUC2', 'Sucursal Test B', '00000', '00000')
  RETURNING id INTO v_branch_b_id;

  INSERT INTO price_lists (business_id, code, name, is_default)
  VALUES (v_business_id, 'PUBLICO', 'Publico General', TRUE)
  RETURNING id INTO v_price_list_id;

  INSERT INTO users (username, full_name, password_hash)
  VALUES ('alan.test', 'Alan Test', 'hash-test')
  RETURNING id INTO v_user_id;

  INSERT INTO units (code, name, decimal_places)
  VALUES ('PZA', 'Pieza', 0)
  RETURNING id INTO v_unit_id;

  INSERT INTO products (business_id, sku, name, base_unit_id, sat_product_service_key)
  VALUES (v_business_id, 'SKU-TEST', 'Producto Test', v_unit_id, '01010101')
  RETURNING id INTO v_product_id;

  INSERT INTO product_units (product_id, unit_id, context, factor_to_base, sat_unit_key, is_default_sale, is_default_purchase)
  VALUES (v_product_id, v_unit_id, 'BASE', 1, 'H87', TRUE, TRUE)
  RETURNING id INTO v_product_unit_id;

  INSERT INTO product_barcodes (product_id, product_unit_id, barcode)
  VALUES (v_product_id, v_product_unit_id, 'BARCODE-1');

  INSERT INTO product_prices (price_list_id, product_id, product_unit_id, price)
  VALUES (v_price_list_id, v_product_id, v_product_unit_id, 100)
  RETURNING id INTO v_product_price_id;

  INSERT INTO cash_registers (branch_id, code, name)
  VALUES (v_branch_id, 'CAJA1', 'Caja 1')
  RETURNING id INTO v_cash_register_id;

  INSERT INTO cash_registers (branch_id, code, name)
  VALUES (v_branch_b_id, 'CAJA1', 'Caja 1 B')
  RETURNING id INTO v_cash_register_b_id;

  INSERT INTO terminals (branch_id, name, status, activated_at)
  VALUES (v_branch_id, 'Terminal 1', 'ACTIVE', now())
  RETURNING id INTO v_terminal_1_id;

  INSERT INTO terminals (branch_id, name, status, activated_at)
  VALUES (v_branch_id, 'Terminal 2', 'ACTIVE', now())
  RETURNING id INTO v_terminal_2_id;

  INSERT INTO terminals (branch_id, name, status, activated_at)
  VALUES (v_branch_b_id, 'Terminal B', 'ACTIVE', now())
  RETURNING id INTO v_terminal_b_id;

  INSERT INTO cash_sessions (branch_id, cash_register_id, terminal_id, opened_by_user_id, opening_amount)
  VALUES (v_branch_id, v_cash_register_id, v_terminal_1_id, v_user_id, 100)
  RETURNING id INTO v_cash_session_id;

  INSERT INTO cash_sessions (branch_id, cash_register_id, terminal_id, opened_by_user_id, opening_amount)
  VALUES (v_branch_b_id, v_cash_register_b_id, v_terminal_b_id, v_user_id, 100)
  RETURNING id INTO v_cash_session_b_id;

  INSERT INTO customers (business_id, price_list_id, display_name)
  VALUES (v_business_id, v_price_list_id, 'Cliente Test')
  RETURNING id INTO v_customer_id;

  -- stock negativo rechazado
  BEGIN
    INSERT INTO inventory_balances (branch_id, product_id, quantity_base, average_cost_base)
    VALUES (v_branch_id, v_product_id, -1, 0);
    v_failures := array_append(v_failures, 'stock negativo no fue rechazado');
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO inventory_balances (branch_id, product_id, quantity_base, average_cost_base)
  VALUES (v_branch_id, v_product_id, 10, 20);

  -- codigo de barras duplicado rechazado
  BEGIN
    INSERT INTO product_barcodes (product_id, product_unit_id, barcode)
    VALUES (v_product_id, v_product_unit_id, 'BARCODE-1');
    v_failures := array_append(v_failures, 'codigo de barras duplicado no fue rechazado');
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- segunda sesion OPEN para la misma caja rechazada
  BEGIN
    INSERT INTO cash_sessions (branch_id, cash_register_id, terminal_id, opened_by_user_id, opening_amount)
    VALUES (v_branch_id, v_cash_register_id, v_terminal_2_id, v_user_id, 50);
    v_failures := array_append(v_failures, 'segunda sesion OPEN no fue rechazada');
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- venta con sesion de otra terminal rechazada
  BEGIN
    INSERT INTO sales (
      branch_id, terminal_id, cash_session_id, user_id, customer_id, price_list_id,
      folio, replenishment_channel, subtotal, total, client_operation_id
    ) VALUES (
      v_branch_id, v_terminal_2_id, v_cash_session_id, v_user_id, v_customer_id, v_price_list_id,
      'VEN-INVALIDA', 'CASH', 100, 100, 'op-invalid-session-terminal'
    );
    v_failures := array_append(v_failures, 'venta con sesion de otra terminal no fue rechazada');
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  -- precio negativo rechazado
  BEGIN
    UPDATE product_prices SET price = -1 WHERE id = v_product_price_id;
    v_failures := array_append(v_failures, 'precio negativo no fue rechazado');
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- cantidad negativa rechazada en posicion de reposicion
  BEGIN
    INSERT INTO replenishment_positions (branch_id, product_id, channel, demand_qty_base, committed_qty_base)
    VALUES (v_branch_id, v_product_id, 'CASH', -1, 0);
    v_failures := array_append(v_failures, 'cantidad negativa de reposicion no fue rechazada');
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- caso valido: demand 10, committed 10, luego demand 6 y committed 10, available 0
  INSERT INTO replenishment_positions (branch_id, product_id, channel, demand_qty_base, committed_qty_base)
  VALUES (v_branch_id, v_product_id, 'CASH', 10, 10);

  UPDATE replenishment_positions
  SET demand_qty_base = 6,
      committed_qty_base = 10
  WHERE branch_id = v_branch_id
    AND product_id = v_product_id
    AND channel = 'CASH';

  SELECT available_to_order_base
  INTO v_available
  FROM replenishment_positions
  WHERE branch_id = v_branch_id
    AND product_id = v_product_id
    AND channel = 'CASH';

  IF v_available <> 0 THEN
    v_failures := array_append(v_failures, 'available_to_order_base no quedo en 0 cuando committed > demand');
  END IF;

  -- lista default activa duplicada rechazada
  BEGIN
    INSERT INTO price_lists (business_id, code, name, is_default, active)
    VALUES (v_business_id, 'PUBLICO2', 'Publico 2', TRUE, TRUE);
    v_failures := array_append(v_failures, 'lista default activa duplicada no fue rechazada');
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- venta valida para pruebas fiscales
  INSERT INTO sales (
    branch_id, terminal_id, cash_session_id, user_id, customer_id, price_list_id,
    folio, replenishment_channel, subtotal, total, client_operation_id
  ) VALUES (
    v_branch_id, v_terminal_1_id, v_cash_session_id, v_user_id, v_customer_id, v_price_list_id,
    'VEN-000001', 'CASH', 100, 100, 'op-valid-sale'
  )
  RETURNING id INTO v_sale_id;

  INSERT INTO sales (
    branch_id, terminal_id, cash_session_id, user_id, customer_id, price_list_id,
    folio, replenishment_channel, subtotal, total, client_operation_id
  ) VALUES (
    v_branch_b_id, v_terminal_b_id, v_cash_session_b_id, v_user_id, v_customer_id, v_price_list_id,
    'VEN-000001', 'CASH', 100, 100, 'op-valid-sale-b'
  )
  RETURNING id INTO v_sale_b_id;

  -- returns.client_operation_id obligatorio
  BEGIN
    INSERT INTO returns (
      branch_id, sale_id, created_by_user_id, folio, reason
    ) VALUES (
      v_branch_id, v_sale_id, v_user_id, 'DEV-A-NULL', 'Prueba client_operation_id requerido'
    );
    v_failures := array_append(v_failures, 'returns.client_operation_id NULL no fue rechazado');
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  -- devolucion valida en sucursal A
  INSERT INTO returns (
    branch_id, sale_id, created_by_user_id, folio, client_operation_id, reason
  ) VALUES (
    v_branch_id, v_sale_id, v_user_id, 'DEV-A-001', 'return-op-shared', 'Prueba devolucion valida A'
  );

  -- client_operation_id duplicado en la misma sucursal rechazado
  BEGIN
    INSERT INTO returns (
      branch_id, sale_id, created_by_user_id, folio, client_operation_id, reason
    ) VALUES (
      v_branch_id, v_sale_id, v_user_id, 'DEV-A-002', 'return-op-shared', 'Prueba duplicado misma sucursal'
    );
    v_failures := array_append(v_failures, 'client_operation_id duplicado de returns en misma sucursal no fue rechazado');
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- mismo client_operation_id permitido en otra sucursal
  INSERT INTO returns (
    branch_id, sale_id, created_by_user_id, folio, client_operation_id, reason
  ) VALUES (
    v_branch_b_id, v_sale_b_id, v_user_id, 'DEV-B-001', 'return-op-shared', 'Prueba devolucion valida B'
  );

  -- cotizacion de sucursal A no puede convertirse en venta de sucursal B
  BEGIN
    INSERT INTO quotations (
      branch_id, terminal_id, user_id, customer_id, price_list_id,
      converted_sale_id, folio, status, subtotal, total
    ) VALUES (
      v_branch_id, v_terminal_1_id, v_user_id, v_customer_id, v_price_list_id,
      v_sale_b_id, 'COT-INVALIDA', 'CONVERTED', 100, 100
    );
    v_failures := array_append(v_failures, 'cotizacion de sucursal A convertida a venta de sucursal B no fue rechazada');
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  -- purchase_items debe pertenecer al mismo pedido de su compra
  INSERT INTO suppliers (business_id, name)
  VALUES (v_business_id, 'Proveedor Test')
  RETURNING id INTO v_supplier_id;

  INSERT INTO purchase_orders (branch_id, supplier_id, replenishment_channel, folio, created_by_user_id)
  VALUES (v_branch_id, v_supplier_id, 'CASH', 'PED-A', v_user_id)
  RETURNING id INTO v_purchase_order_a_id;

  INSERT INTO purchase_orders (branch_id, supplier_id, replenishment_channel, folio, created_by_user_id)
  VALUES (v_branch_id, v_supplier_id, 'CASH', 'PED-B', v_user_id)
  RETURNING id INTO v_purchase_order_b_id;

  INSERT INTO purchase_order_items (
    purchase_order_id, line_number, product_id, product_unit_id,
    product_sku_snapshot, description_snapshot, unit_code_snapshot, unit_name_snapshot,
    factor_to_base_snapshot, ordered_qty, ordered_qty_base, replenishment_qty_base
  ) VALUES (
    v_purchase_order_a_id, 1, v_product_id, v_product_unit_id,
    'SKU-TEST', 'Producto Test', 'PZA', 'Pieza',
    1, 1, 1, 1
  )
  RETURNING id INTO v_purchase_order_item_a_id;

  INSERT INTO purchase_order_items (
    purchase_order_id, line_number, product_id, product_unit_id,
    product_sku_snapshot, description_snapshot, unit_code_snapshot, unit_name_snapshot,
    factor_to_base_snapshot, ordered_qty, ordered_qty_base, replenishment_qty_base
  ) VALUES (
    v_purchase_order_b_id, 1, v_product_id, v_product_unit_id,
    'SKU-TEST', 'Producto Test', 'PZA', 'Pieza',
    1, 1, 1, 1
  )
  RETURNING id INTO v_purchase_order_item_b_id;

  INSERT INTO purchases (branch_id, purchase_order_id, supplier_id, replenishment_channel, folio, received_by_user_id)
  VALUES (v_branch_id, v_purchase_order_a_id, v_supplier_id, 'CASH', 'COM-A', v_user_id)
  RETURNING id INTO v_purchase_a_id;

  BEGIN
    INSERT INTO purchase_items (
      purchase_id, purchase_order_id, purchase_order_item_id, line_number,
      product_id, product_unit_id, product_sku_snapshot, description_snapshot,
      unit_code_snapshot, unit_name_snapshot, factor_to_base_snapshot,
      received_qty, received_qty_base, actual_unit_cost_base
    ) VALUES (
      v_purchase_a_id, v_purchase_order_a_id, v_purchase_order_item_b_id, 1,
      v_product_id, v_product_unit_id, 'SKU-TEST', 'Producto Test',
      'PZA', 'Pieza', 1,
      1, 1, 10
    );
    v_failures := array_append(v_failures, 'purchase_item de Compra A con linea de Pedido B no fue rechazado');
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  -- inventory_movements append-only
  INSERT INTO inventory_movements (
    branch_id, product_id, movement_type, quantity_delta_base, unit_cost_base,
    reference_entity_type, reference_entity_id, actor_user_id
  ) VALUES (
    v_branch_id, v_product_id, 'SALE', -1, 20, 'sales', v_sale_id, v_user_id
  )
  RETURNING id INTO v_inventory_movement_id;

  BEGIN
    UPDATE inventory_movements SET reason = 'invalid update' WHERE id = v_inventory_movement_id;
    v_failures := array_append(v_failures, 'UPDATE de inventory_movements no fue rechazado');
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;

  -- cash_movements append-only
  INSERT INTO cash_movements (cash_session_id, movement_type, amount_delta, reference_entity_type, reference_entity_id, actor_user_id)
  VALUES (v_cash_session_id, 'SALE_CASH', 100, 'sales', v_sale_id, v_user_id)
  RETURNING id INTO v_cash_movement_id;

  BEGIN
    DELETE FROM cash_movements WHERE id = v_cash_movement_id;
    v_failures := array_append(v_failures, 'DELETE de cash_movements no fue rechazado');
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;

  -- replenishment_movements append-only
  INSERT INTO replenishment_movements (
    branch_id, product_id, channel, movement_type, demand_delta_base,
    reference_entity_type, reference_entity_id, actor_user_id
  ) VALUES (
    v_branch_id, v_product_id, 'CASH', 'SALE_DEMAND', 1, 'sales', v_sale_id, v_user_id
  )
  RETURNING id INTO v_replenishment_movement_id;

  BEGIN
    UPDATE replenishment_movements SET demand_delta_base = 2 WHERE id = v_replenishment_movement_id;
    v_failures := array_append(v_failures, 'UPDATE de replenishment_movements no fue rechazado');
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;

  -- invoice_events append-only
  INSERT INTO invoices (
    sale_id, branch_id, customer_id, status, emitter_snapshot, receiver_snapshot,
    concepts_snapshot, idempotency_key, created_by_user_id
  ) VALUES (
    v_sale_id, v_branch_id, v_customer_id, 'PENDING', '{}'::jsonb, '{}'::jsonb,
    '[]'::jsonb, 'invoice-op-1', v_user_id
  )
  RETURNING id INTO v_invoice_id;

  INSERT INTO invoice_events (invoice_id, event_type, status_to, actor_user_id)
  VALUES (v_invoice_id, 'REQUESTED', 'PENDING', v_user_id)
  RETURNING id INTO v_invoice_event_id;

  BEGIN
    UPDATE invoice_events SET event_type = 'INVALID' WHERE id = v_invoice_event_id;
    v_failures := array_append(v_failures, 'UPDATE de invoice_events no fue rechazado');
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;

  BEGIN
    DELETE FROM invoice_events WHERE id = v_invoice_event_id;
    v_failures := array_append(v_failures, 'DELETE de invoice_events no fue rechazado');
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;

  IF array_length(v_failures, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'Validaciones fallidas: %', array_to_string(v_failures, '; ');
  END IF;
END;
$$;

ROLLBACK;
