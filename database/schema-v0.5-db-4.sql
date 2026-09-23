-- Sistema POS multisucursal - PostgreSQL schema v0.5-db-4
-- Fuente de verdad: especificacion_maestra_pos_multisucursal_v0.5.md
-- Alcance: modelo fisico inicial, sin seleccionar stack de aplicacion.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE terminal_status AS ENUM ('PENDING_ACTIVATION', 'ACTIVE', 'REVOKED');
CREATE TYPE user_status AS ENUM ('ACTIVE', 'INACTIVE');
CREATE TYPE cash_register_status AS ENUM ('ACTIVE', 'INACTIVE');
CREATE TYPE cash_session_status AS ENUM ('OPEN', 'CLOSED');
CREATE TYPE sale_status AS ENUM ('CONFIRMED', 'PARTIALLY_RETURNED', 'RETURNED', 'CANCELLED');
CREATE TYPE quotation_status AS ENUM ('DRAFT', 'ISSUED', 'CONVERTED', 'EXPIRED', 'CANCELLED');
CREATE TYPE return_status AS ENUM ('DRAFT', 'CONFIRMED', 'CANCELLED');
CREATE TYPE purchase_order_status AS ENUM ('DRAFT', 'CONFIRMED', 'CLOSED', 'CANCELLED');
CREATE TYPE purchase_status AS ENUM ('DRAFT', 'CONFIRMED', 'CANCELLED');
CREATE TYPE inventory_adjustment_status AS ENUM ('DRAFT', 'CONFIRMED', 'CANCELLED');
CREATE TYPE stock_transfer_status AS ENUM ('DRAFT', 'CONFIRMED', 'CANCELLED');
CREATE TYPE invoice_status AS ENUM ('PENDING', 'STAMPED', 'ERROR', 'CANCELLED');
CREATE TYPE idempotency_status AS ENUM ('IN_PROGRESS', 'COMPLETED', 'FAILED');

CREATE TYPE replenishment_channel AS ENUM ('CASH', 'TRANSFER');
CREATE TYPE product_unit_context AS ENUM ('BASE', 'SALE', 'PURCHASE', 'BOTH');
CREATE TYPE inventory_movement_type AS ENUM (
  'SALE',
  'PURCHASE_RECEIPT',
  'ADJUSTMENT_IN',
  'ADJUSTMENT_OUT',
  'SALE_RETURN',
  'TRANSFER_OUT',
  'TRANSFER_IN',
  'REVERSAL'
);
CREATE TYPE cash_movement_type AS ENUM (
  'OPENING_FLOAT',
  'SALE_CASH',
  'RETURN_CASH',
  'CASH_IN',
  'WITHDRAWAL',
  'EXPENSE',
  'ADJUSTMENT'
);
CREATE TYPE replenishment_movement_type AS ENUM (
  'SALE_DEMAND',
  'RETURN_RESTOCK',
  'ORDER_RESERVE',
  'ORDER_RELEASE',
  'PURCHASE_FULFILL',
  'MANUAL_CORRECTION'
);
CREATE TYPE return_item_disposition AS ENUM ('RESTOCK', 'DAMAGED');

CREATE OR REPLACE FUNCTION prevent_update_delete_on_ledger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; use a compensating movement/document instead', TG_TABLE_NAME;
END;
$$;

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_product_unit_base()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  expected_base_unit_id BIGINT;
BEGIN
  IF NEW.context = 'BASE' AND NEW.active THEN
    SELECT base_unit_id
    INTO expected_base_unit_id
    FROM products
    WHERE id = NEW.product_id;

    IF expected_base_unit_id IS NULL THEN
      RAISE EXCEPTION 'Product % does not exist for BASE product unit validation', NEW.product_id;
    END IF;

    IF NEW.unit_id <> expected_base_unit_id OR NEW.factor_to_base <> 1 THEN
      RAISE EXCEPTION 'Active BASE product unit must use products.base_unit_id and factor_to_base = 1';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_product_base_unit_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.base_unit_id <> OLD.base_unit_id AND EXISTS (
    SELECT 1
    FROM product_units
    WHERE product_id = NEW.id
      AND context = 'BASE'
      AND active
      AND unit_id <> NEW.base_unit_id
  ) THEN
    RAISE EXCEPTION 'Cannot change products.base_unit_id while an active BASE product_unit uses a different unit';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TABLE businesses (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  legal_name TEXT NOT NULL,
  commercial_name TEXT NOT NULL,
  tax_id TEXT,
  default_currency CHAR(3) NOT NULL DEFAULT 'MXN',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_businesses_public_id UNIQUE (public_id),
  CONSTRAINT ck_businesses_currency CHECK (default_currency ~ '^[A-Z]{3}$')
);

CREATE TABLE branches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  postal_code TEXT,
  place_of_issue TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_branches_public_id UNIQUE (public_id),
  CONSTRAINT uq_branches_business_code UNIQUE (business_id, code)
);

CREATE TABLE branch_settings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  setting_key TEXT NOT NULL,
  setting_value JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_branch_settings_key UNIQUE (branch_id, setting_key),
  CONSTRAINT ck_branch_settings_key CHECK (setting_key ~ '^[a-z0-9_.-]+$')
);

CREATE TABLE terminals (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  name TEXT NOT NULL,
  device_fingerprint_hash TEXT,
  token_hash TEXT,
  status terminal_status NOT NULL DEFAULT 'PENDING_ACTIVATION',
  last_seen_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_terminals_public_id UNIQUE (public_id),
  CONSTRAINT uq_terminals_id_branch UNIQUE (id, branch_id),
  CONSTRAINT ck_terminals_activation CHECK (status <> 'ACTIVE' OR activated_at IS NOT NULL)
);

CREATE TABLE users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  username TEXT NOT NULL,
  email TEXT,
  full_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  status user_status NOT NULL DEFAULT 'ACTIVE',
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_users_public_id UNIQUE (public_id),
  CONSTRAINT uq_users_username UNIQUE (username),
  CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE TABLE roles (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_roles_business_code UNIQUE (business_id, code)
);

CREATE TABLE permissions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_permissions_code UNIQUE (code)
);

CREATE TABLE user_roles (
  user_id BIGINT NOT NULL REFERENCES users(id),
  role_id BIGINT NOT NULL REFERENCES roles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE role_permissions (
  role_id BIGINT NOT NULL REFERENCES roles(id),
  permission_id BIGINT NOT NULL REFERENCES permissions(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_branches (
  user_id BIGINT NOT NULL REFERENCES users(id),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, branch_id)
);

CREATE TABLE price_lists (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'MXN',
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_price_lists_public_id UNIQUE (public_id),
  CONSTRAINT uq_price_lists_business_code UNIQUE (business_id, code),
  CONSTRAINT ck_price_lists_currency CHECK (currency ~ '^[A-Z]{3}$')
);

CREATE UNIQUE INDEX uq_price_lists_one_default_per_business
  ON price_lists (business_id)
  WHERE is_default AND active;

CREATE TABLE customers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  price_list_id BIGINT NOT NULL REFERENCES price_lists(id),
  display_name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  whatsapp TEXT,
  notes TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_customers_public_id UNIQUE (public_id)
);

CREATE TABLE customer_fiscal_profiles (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  customer_id BIGINT NOT NULL REFERENCES customers(id),
  rfc TEXT NOT NULL,
  legal_name TEXT NOT NULL,
  fiscal_zip TEXT NOT NULL,
  tax_regime TEXT NOT NULL,
  cfdi_use TEXT NOT NULL,
  billing_email TEXT,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  validated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_customer_fiscal_profiles_public_id UNIQUE (public_id)
);

CREATE UNIQUE INDEX uq_customer_fiscal_profiles_one_default
  ON customer_fiscal_profiles (customer_id)
  WHERE is_default AND active;

CREATE TABLE categories (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  parent_id BIGINT REFERENCES categories(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_categories_public_id UNIQUE (public_id),
  CONSTRAINT uq_categories_business_code UNIQUE (business_id, code),
  CONSTRAINT ck_categories_not_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE TABLE units (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  decimal_places SMALLINT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_units_code UNIQUE (code),
  CONSTRAINT ck_units_decimal_places CHECK (decimal_places BETWEEN 0 AND 6)
);

CREATE TABLE tax_profiles (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id BIGINT REFERENCES businesses(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  tax_object TEXT,
  tax_rules JSONB NOT NULL DEFAULT '{}'::jsonb,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_tax_profiles_scope_code
  ON tax_profiles (COALESCE(business_id, 0), code);

CREATE TABLE products (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  sku TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category_id BIGINT REFERENCES categories(id),
  base_unit_id BIGINT NOT NULL REFERENCES units(id),
  tax_profile_id BIGINT REFERENCES tax_profiles(id),
  sat_product_service_key TEXT,
  allow_fractional BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_products_public_id UNIQUE (public_id),
  CONSTRAINT uq_products_business_sku UNIQUE (business_id, sku)
);

CREATE TABLE product_units (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id),
  unit_id BIGINT NOT NULL REFERENCES units(id),
  context product_unit_context NOT NULL,
  factor_to_base NUMERIC(18,6) NOT NULL,
  sat_unit_key TEXT,
  is_default_sale BOOLEAN NOT NULL DEFAULT FALSE,
  is_default_purchase BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_product_units_id_product UNIQUE (id, product_id),
  CONSTRAINT uq_product_units_product_unit_context UNIQUE (product_id, unit_id, context),
  CONSTRAINT ck_product_units_factor_positive CHECK (factor_to_base > 0),
  CONSTRAINT ck_product_units_base_context CHECK (context <> 'BASE' OR factor_to_base = 1)
);

CREATE UNIQUE INDEX uq_product_units_default_sale
  ON product_units (product_id)
  WHERE is_default_sale AND active;

CREATE UNIQUE INDEX uq_product_units_default_purchase
  ON product_units (product_id)
  WHERE is_default_purchase AND active;

CREATE UNIQUE INDEX uq_product_units_one_active_base
  ON product_units (product_id)
  WHERE context = 'BASE' AND active;

CREATE TRIGGER trg_product_units_validate_base
BEFORE INSERT OR UPDATE ON product_units
FOR EACH ROW EXECUTE FUNCTION validate_product_unit_base();

CREATE TRIGGER trg_products_validate_base_unit_change
BEFORE UPDATE OF base_unit_id ON products
FOR EACH ROW EXECUTE FUNCTION validate_product_base_unit_change();

CREATE TABLE product_barcodes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT REFERENCES product_units(id),
  barcode TEXT NOT NULL,
  label TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_product_barcodes_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_product_barcodes_not_blank CHECK (length(trim(barcode)) > 0)
);

CREATE UNIQUE INDEX uq_product_barcodes_active_barcode
  ON product_barcodes (barcode)
  WHERE active;

CREATE TABLE product_prices (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  price_list_id BIGINT NOT NULL REFERENCES price_lists(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  price NUMERIC(18,2) NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_product_prices_list_product_unit UNIQUE (price_list_id, product_id, product_unit_id),
  CONSTRAINT fk_product_prices_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_product_prices_non_negative CHECK (price >= 0)
);

CREATE TABLE suppliers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  name TEXT NOT NULL,
  rfc TEXT,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_suppliers_public_id UNIQUE (public_id)
);

CREATE TABLE product_suppliers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id),
  supplier_id BIGINT NOT NULL REFERENCES suppliers(id),
  supplier_sku TEXT,
  purchase_product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  unit_cost_reference NUMERIC(18,6),
  minimum_order_qty NUMERIC(18,4),
  order_multiple NUMERIC(18,4),
  lead_time_days INTEGER,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_product_suppliers_product_supplier_unit UNIQUE (product_id, supplier_id, purchase_product_unit_id),
  CONSTRAINT fk_product_suppliers_unit_product FOREIGN KEY (purchase_product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_product_suppliers_cost_non_negative CHECK (unit_cost_reference IS NULL OR unit_cost_reference >= 0),
  CONSTRAINT ck_product_suppliers_min_positive CHECK (minimum_order_qty IS NULL OR minimum_order_qty > 0),
  CONSTRAINT ck_product_suppliers_multiple_positive CHECK (order_multiple IS NULL OR order_multiple > 0),
  CONSTRAINT ck_product_suppliers_lead_non_negative CHECK (lead_time_days IS NULL OR lead_time_days >= 0)
);

CREATE UNIQUE INDEX uq_product_suppliers_one_primary
  ON product_suppliers (product_id)
  WHERE is_primary AND active;

CREATE TABLE inventory_balances (
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  quantity_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  average_cost_base NUMERIC(18,6) NOT NULL DEFAULT 0,
  version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (branch_id, product_id),
  CONSTRAINT ck_inventory_balances_quantity_non_negative CHECK (quantity_base >= 0),
  CONSTRAINT ck_inventory_balances_average_cost_non_negative CHECK (average_cost_base >= 0),
  CONSTRAINT ck_inventory_balances_version_non_negative CHECK (version >= 0)
);

CREATE TABLE inventory_movements (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  movement_type inventory_movement_type NOT NULL,
  quantity_delta_base NUMERIC(18,4) NOT NULL,
  unit_cost_base NUMERIC(18,6),
  balance_after_base NUMERIC(18,4),
  reference_entity_type TEXT NOT NULL,
  reference_entity_id BIGINT NOT NULL,
  reason TEXT,
  actor_user_id BIGINT REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_inventory_movements_public_id UNIQUE (public_id),
  CONSTRAINT ck_inventory_movements_non_zero CHECK (quantity_delta_base <> 0),
  CONSTRAINT ck_inventory_movements_cost_non_negative CHECK (unit_cost_base IS NULL OR unit_cost_base >= 0),
  CONSTRAINT ck_inventory_movements_sign CHECK (
    (movement_type IN ('SALE', 'ADJUSTMENT_OUT', 'TRANSFER_OUT') AND quantity_delta_base < 0)
    OR (movement_type IN ('PURCHASE_RECEIPT', 'ADJUSTMENT_IN', 'SALE_RETURN', 'TRANSFER_IN') AND quantity_delta_base > 0)
    OR movement_type = 'REVERSAL'
  )
);

CREATE TRIGGER trg_inventory_movements_append_only
BEFORE UPDATE OR DELETE ON inventory_movements
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete_on_ledger();

CREATE TABLE cash_registers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  status cash_register_status NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_cash_registers_public_id UNIQUE (public_id),
  CONSTRAINT uq_cash_registers_branch_code UNIQUE (branch_id, code),
  CONSTRAINT uq_cash_registers_id_branch UNIQUE (id, branch_id)
);

CREATE TABLE cash_sessions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  cash_register_id BIGINT NOT NULL,
  terminal_id BIGINT NOT NULL,
  opened_by_user_id BIGINT NOT NULL REFERENCES users(id),
  closed_by_user_id BIGINT REFERENCES users(id),
  opening_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  expected_cash_amount NUMERIC(18,2),
  declared_cash_amount NUMERIC(18,2),
  difference_amount NUMERIC(18,2),
  status cash_session_status NOT NULL DEFAULT 'OPEN',
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_cash_sessions_public_id UNIQUE (public_id),
  CONSTRAINT uq_cash_sessions_id_branch UNIQUE (id, branch_id),
  CONSTRAINT uq_cash_sessions_id_branch_terminal UNIQUE (id, branch_id, terminal_id),
  CONSTRAINT fk_cash_sessions_register_branch FOREIGN KEY (cash_register_id, branch_id) REFERENCES cash_registers(id, branch_id),
  CONSTRAINT fk_cash_sessions_terminal_branch FOREIGN KEY (terminal_id, branch_id) REFERENCES terminals(id, branch_id),
  CONSTRAINT ck_cash_sessions_opening_non_negative CHECK (opening_amount >= 0),
  CONSTRAINT ck_cash_sessions_closed_fields CHECK (
    (status = 'OPEN' AND closed_at IS NULL)
    OR (status = 'CLOSED' AND closed_at IS NOT NULL AND closed_by_user_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX uq_cash_sessions_one_open_per_register
  ON cash_sessions (cash_register_id)
  WHERE status = 'OPEN';

CREATE TABLE cash_movements (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  cash_session_id BIGINT NOT NULL REFERENCES cash_sessions(id),
  movement_type cash_movement_type NOT NULL,
  amount_delta NUMERIC(18,2) NOT NULL,
  reference_entity_type TEXT,
  reference_entity_id BIGINT,
  reason TEXT,
  actor_user_id BIGINT NOT NULL REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_cash_movements_public_id UNIQUE (public_id),
  CONSTRAINT ck_cash_movements_non_zero CHECK (amount_delta <> 0),
  CONSTRAINT ck_cash_movements_sign CHECK (
    (movement_type IN ('OPENING_FLOAT', 'SALE_CASH', 'CASH_IN') AND amount_delta > 0)
    OR (movement_type IN ('RETURN_CASH', 'WITHDRAWAL', 'EXPENSE') AND amount_delta < 0)
    OR movement_type = 'ADJUSTMENT'
  ),
  CONSTRAINT ck_cash_movements_reason_required CHECK (
    movement_type NOT IN ('CASH_IN', 'WITHDRAWAL', 'EXPENSE', 'ADJUSTMENT') OR reason IS NOT NULL
  )
);

CREATE TRIGGER trg_cash_movements_append_only
BEFORE UPDATE OR DELETE ON cash_movements
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete_on_ledger();

CREATE TABLE payment_methods (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  replenishment_channel replenishment_channel NOT NULL,
  affects_cash BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_payment_methods_business_code UNIQUE (business_id, code)
);

CREATE TABLE quotations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  terminal_id BIGINT REFERENCES terminals(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  customer_id BIGINT REFERENCES customers(id),
  price_list_id BIGINT NOT NULL REFERENCES price_lists(id),
  converted_sale_id BIGINT,
  folio TEXT NOT NULL,
  status quotation_status NOT NULL DEFAULT 'DRAFT',
  issued_at TIMESTAMPTZ,
  valid_until TIMESTAMPTZ,
  customer_snapshot JSONB,
  price_list_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  notes TEXT,
  terms TEXT,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  discount_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL DEFAULT 0,
  currency CHAR(3) NOT NULL DEFAULT 'MXN',
  idempotency_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_quotations_public_id UNIQUE (public_id),
  CONSTRAINT uq_quotations_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT uq_quotations_converted_sale UNIQUE (converted_sale_id),
  CONSTRAINT fk_quotations_terminal_branch FOREIGN KEY (terminal_id, branch_id) REFERENCES terminals(id, branch_id),
  CONSTRAINT ck_quotations_amounts_non_negative CHECK (subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT ck_quotations_currency CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT ck_quotations_issued_fields CHECK (status <> 'ISSUED' OR (issued_at IS NOT NULL AND valid_until IS NOT NULL)),
  CONSTRAINT ck_quotations_converted_sale_required CHECK (status <> 'CONVERTED' OR converted_sale_id IS NOT NULL)
);

CREATE TABLE quotation_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  quotation_id BIGINT NOT NULL REFERENCES quotations(id),
  line_number INTEGER NOT NULL,
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  product_sku_snapshot TEXT NOT NULL,
  description_snapshot TEXT NOT NULL,
  sat_product_service_key_snapshot TEXT,
  unit_code_snapshot TEXT NOT NULL,
  unit_name_snapshot TEXT NOT NULL,
  sat_unit_key_snapshot TEXT,
  factor_to_base_snapshot NUMERIC(18,6) NOT NULL,
  quantity NUMERIC(18,4) NOT NULL,
  quantity_base NUMERIC(18,4) NOT NULL,
  unit_price_snapshot NUMERIC(18,2) NOT NULL,
  discount_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  subtotal NUMERIC(18,2) NOT NULL,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_quotation_items_line UNIQUE (quotation_id, line_number),
  CONSTRAINT fk_quotation_items_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_quotation_items_quantities_positive CHECK (quantity > 0 AND quantity_base > 0 AND factor_to_base_snapshot > 0),
  CONSTRAINT ck_quotation_items_amounts_non_negative CHECK (unit_price_snapshot >= 0 AND discount_amount >= 0 AND subtotal >= 0 AND tax_total >= 0 AND total >= 0)
);

CREATE TABLE sales (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  terminal_id BIGINT NOT NULL,
  cash_session_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users(id),
  customer_id BIGINT REFERENCES customers(id),
  price_list_id BIGINT NOT NULL REFERENCES price_lists(id),
  folio TEXT NOT NULL,
  status sale_status NOT NULL DEFAULT 'CONFIRMED',
  replenishment_channel replenishment_channel NOT NULL,
  customer_snapshot JSONB,
  price_list_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  subtotal NUMERIC(18,2) NOT NULL,
  discount_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'MXN',
  client_operation_id TEXT NOT NULL,
  confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_sales_public_id UNIQUE (public_id),
  CONSTRAINT uq_sales_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT uq_sales_client_operation UNIQUE (branch_id, client_operation_id),
  CONSTRAINT uq_sales_id_branch UNIQUE (id, branch_id),
  CONSTRAINT fk_sales_terminal_branch FOREIGN KEY (terminal_id, branch_id) REFERENCES terminals(id, branch_id),
  CONSTRAINT fk_sales_cash_session_branch_terminal FOREIGN KEY (cash_session_id, branch_id, terminal_id) REFERENCES cash_sessions(id, branch_id, terminal_id),
  CONSTRAINT ck_sales_amounts_non_negative CHECK (subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT ck_sales_currency CHECK (currency ~ '^[A-Z]{3}$')
);

ALTER TABLE quotations
  ADD CONSTRAINT fk_quotations_converted_sale_branch FOREIGN KEY (converted_sale_id, branch_id) REFERENCES sales(id, branch_id);

CREATE TABLE sale_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sale_id BIGINT NOT NULL REFERENCES sales(id),
  line_number INTEGER NOT NULL,
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  product_sku_snapshot TEXT NOT NULL,
  description_snapshot TEXT NOT NULL,
  sat_product_service_key_snapshot TEXT,
  unit_code_snapshot TEXT NOT NULL,
  unit_name_snapshot TEXT NOT NULL,
  sat_unit_key_snapshot TEXT,
  factor_to_base_snapshot NUMERIC(18,6) NOT NULL,
  quantity NUMERIC(18,4) NOT NULL,
  quantity_base NUMERIC(18,4) NOT NULL,
  unit_price_snapshot NUMERIC(18,2) NOT NULL,
  discount_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  unit_cost_snapshot NUMERIC(18,6) NOT NULL,
  subtotal NUMERIC(18,2) NOT NULL,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_sale_items_line UNIQUE (sale_id, line_number),
  CONSTRAINT uq_sale_items_id_sale UNIQUE (id, sale_id),
  CONSTRAINT fk_sale_items_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_sale_items_quantities_positive CHECK (quantity > 0 AND quantity_base > 0 AND factor_to_base_snapshot > 0),
  CONSTRAINT ck_sale_items_amounts_non_negative CHECK (unit_price_snapshot >= 0 AND discount_amount >= 0 AND unit_cost_snapshot >= 0 AND subtotal >= 0 AND tax_total >= 0 AND total >= 0)
);

CREATE TABLE sale_payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sale_id BIGINT NOT NULL REFERENCES sales(id),
  payment_method_id BIGINT NOT NULL REFERENCES payment_methods(id),
  amount NUMERIC(18,2) NOT NULL,
  reference TEXT,
  payment_method_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  replenishment_channel_snapshot replenishment_channel NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_sale_payments_amount_positive CHECK (amount > 0)
);

CREATE TABLE returns (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  sale_id BIGINT NOT NULL,
  cash_session_id BIGINT REFERENCES cash_sessions(id),
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  confirmed_by_user_id BIGINT REFERENCES users(id),
  folio TEXT NOT NULL,
  client_operation_id TEXT NOT NULL,
  status return_status NOT NULL DEFAULT 'DRAFT',
  reason TEXT NOT NULL,
  refund_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  refund_payment_method_id BIGINT REFERENCES payment_methods(id),
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_returns_public_id UNIQUE (public_id),
  CONSTRAINT uq_returns_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT uq_returns_client_operation UNIQUE (branch_id, client_operation_id),
  CONSTRAINT uq_returns_id_sale UNIQUE (id, sale_id),
  CONSTRAINT fk_returns_sale_branch FOREIGN KEY (sale_id, branch_id) REFERENCES sales(id, branch_id),
  CONSTRAINT fk_returns_cash_session_branch FOREIGN KEY (cash_session_id, branch_id) REFERENCES cash_sessions(id, branch_id),
  CONSTRAINT ck_returns_refund_non_negative CHECK (refund_amount >= 0),
  CONSTRAINT ck_returns_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL))
);

CREATE TABLE return_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  return_id BIGINT NOT NULL REFERENCES returns(id),
  sale_id BIGINT NOT NULL,
  sale_item_id BIGINT NOT NULL REFERENCES sale_items(id),
  disposition return_item_disposition NOT NULL,
  quantity_base NUMERIC(18,4) NOT NULL,
  refund_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_return_items_return_sale FOREIGN KEY (return_id, sale_id) REFERENCES returns(id, sale_id),
  CONSTRAINT fk_return_items_sale_item_sale FOREIGN KEY (sale_item_id, sale_id) REFERENCES sale_items(id, sale_id),
  CONSTRAINT ck_return_items_quantity_positive CHECK (quantity_base > 0),
  CONSTRAINT ck_return_items_refund_non_negative CHECK (refund_amount >= 0)
);

CREATE TABLE replenishment_positions (
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  channel replenishment_channel NOT NULL,
  demand_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  committed_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  available_to_order_base NUMERIC(18,4) GENERATED ALWAYS AS (GREATEST(demand_qty_base - committed_qty_base, 0::numeric)) STORED,
  version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (branch_id, product_id, channel),
  CONSTRAINT ck_replenishment_positions_non_negative CHECK (demand_qty_base >= 0 AND committed_qty_base >= 0),
  CONSTRAINT ck_replenishment_positions_version_non_negative CHECK (version >= 0)
);

CREATE TABLE replenishment_movements (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  channel replenishment_channel NOT NULL,
  movement_type replenishment_movement_type NOT NULL,
  demand_delta_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  committed_delta_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  reference_entity_type TEXT NOT NULL,
  reference_entity_id BIGINT NOT NULL,
  actor_user_id BIGINT REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_replenishment_movements_public_id UNIQUE (public_id),
  CONSTRAINT ck_replenishment_movements_non_zero CHECK (demand_delta_base <> 0 OR committed_delta_base <> 0)
);

CREATE TRIGGER trg_replenishment_movements_append_only
BEFORE UPDATE OR DELETE ON replenishment_movements
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete_on_ledger();

CREATE TABLE purchase_orders (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  supplier_id BIGINT NOT NULL REFERENCES suppliers(id),
  replenishment_channel replenishment_channel NOT NULL,
  folio TEXT NOT NULL,
  status purchase_order_status NOT NULL DEFAULT 'DRAFT',
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  confirmed_by_user_id BIGINT REFERENCES users(id),
  cancelled_by_user_id BIGINT REFERENCES users(id),
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL DEFAULT 0,
  notes TEXT,
  confirmed_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_purchase_orders_public_id UNIQUE (public_id),
  CONSTRAINT uq_purchase_orders_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT uq_purchase_orders_inheritance UNIQUE (id, branch_id, supplier_id, replenishment_channel),
  CONSTRAINT ck_purchase_orders_amounts_non_negative CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT ck_purchase_orders_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL)),
  CONSTRAINT ck_purchase_orders_closed_fields CHECK (status <> 'CLOSED' OR closed_at IS NOT NULL),
  CONSTRAINT ck_purchase_orders_cancelled_fields CHECK (status <> 'CANCELLED' OR (cancelled_at IS NOT NULL AND cancelled_by_user_id IS NOT NULL))
);

CREATE TABLE purchase_order_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders(id),
  line_number INTEGER NOT NULL,
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  product_sku_snapshot TEXT NOT NULL,
  description_snapshot TEXT NOT NULL,
  sat_product_service_key_snapshot TEXT,
  unit_code_snapshot TEXT NOT NULL,
  unit_name_snapshot TEXT NOT NULL,
  sat_unit_key_snapshot TEXT,
  factor_to_base_snapshot NUMERIC(18,6) NOT NULL,
  ordered_qty NUMERIC(18,4) NOT NULL,
  ordered_qty_base NUMERIC(18,4) NOT NULL,
  replenishment_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  customer_special_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  stock_extra_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  expected_unit_cost_base NUMERIC(18,6),
  tax_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL DEFAULT 0,
  customer_special_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_purchase_order_items_line UNIQUE (purchase_order_id, line_number),
  CONSTRAINT uq_purchase_order_items_id_product UNIQUE (id, product_id),
  CONSTRAINT uq_purchase_order_items_id_order_product UNIQUE (id, purchase_order_id, product_id),
  CONSTRAINT fk_purchase_order_items_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT ck_purchase_order_items_quantities_positive CHECK (ordered_qty > 0 AND ordered_qty_base > 0 AND factor_to_base_snapshot > 0),
  CONSTRAINT ck_purchase_order_items_reason_quantities CHECK (replenishment_qty_base >= 0 AND customer_special_qty_base >= 0 AND stock_extra_qty_base >= 0),
  CONSTRAINT ck_purchase_order_items_reason_sum CHECK (ordered_qty_base = replenishment_qty_base + customer_special_qty_base + stock_extra_qty_base),
  CONSTRAINT ck_purchase_order_items_cost_non_negative CHECK (expected_unit_cost_base IS NULL OR expected_unit_cost_base >= 0),
  CONSTRAINT ck_purchase_order_items_amounts_non_negative CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0)
);

CREATE TABLE purchases (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders(id),
  supplier_id BIGINT NOT NULL REFERENCES suppliers(id),
  replenishment_channel replenishment_channel NOT NULL,
  folio TEXT NOT NULL,
  status purchase_status NOT NULL DEFAULT 'DRAFT',
  received_by_user_id BIGINT NOT NULL REFERENCES users(id),
  confirmed_by_user_id BIGINT REFERENCES users(id),
  supplier_document_ref TEXT,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL DEFAULT 0,
  notes TEXT,
  client_operation_id TEXT,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_purchases_public_id UNIQUE (public_id),
  CONSTRAINT uq_purchases_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT uq_purchases_order UNIQUE (purchase_order_id),
  CONSTRAINT uq_purchases_id_order UNIQUE (id, purchase_order_id),
  CONSTRAINT uq_purchases_client_operation UNIQUE (branch_id, client_operation_id),
  CONSTRAINT fk_purchases_order_inheritance FOREIGN KEY (purchase_order_id, branch_id, supplier_id, replenishment_channel) REFERENCES purchase_orders(id, branch_id, supplier_id, replenishment_channel),
  CONSTRAINT ck_purchases_amounts_non_negative CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT ck_purchases_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL))
);

CREATE TABLE purchase_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_id BIGINT NOT NULL REFERENCES purchases(id),
  purchase_order_id BIGINT NOT NULL,
  purchase_order_item_id BIGINT REFERENCES purchase_order_items(id),
  line_number INTEGER NOT NULL,
  product_id BIGINT NOT NULL REFERENCES products(id),
  product_unit_id BIGINT NOT NULL REFERENCES product_units(id),
  product_sku_snapshot TEXT NOT NULL,
  description_snapshot TEXT NOT NULL,
  sat_product_service_key_snapshot TEXT,
  unit_code_snapshot TEXT NOT NULL,
  unit_name_snapshot TEXT NOT NULL,
  sat_unit_key_snapshot TEXT,
  factor_to_base_snapshot NUMERIC(18,6) NOT NULL,
  received_qty NUMERIC(18,4) NOT NULL,
  received_qty_base NUMERIC(18,4) NOT NULL,
  actual_unit_cost_base NUMERIC(18,6) NOT NULL,
  tax_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  total NUMERIC(18,2) NOT NULL DEFAULT 0,
  difference_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_purchase_items_line UNIQUE (purchase_id, line_number),
  CONSTRAINT uq_purchase_items_id_order_item UNIQUE (id, purchase_order_item_id),
  CONSTRAINT fk_purchase_items_purchase_order FOREIGN KEY (purchase_id, purchase_order_id) REFERENCES purchases(id, purchase_order_id),
  CONSTRAINT fk_purchase_items_unit_product FOREIGN KEY (product_unit_id, product_id) REFERENCES product_units(id, product_id),
  CONSTRAINT fk_purchase_items_order_item_order_product FOREIGN KEY (purchase_order_item_id, purchase_order_id, product_id) REFERENCES purchase_order_items(id, purchase_order_id, product_id),
  CONSTRAINT ck_purchase_items_quantities_non_negative CHECK (received_qty >= 0 AND received_qty_base >= 0 AND factor_to_base_snapshot > 0),
  CONSTRAINT ck_purchase_items_cost_non_negative CHECK (actual_unit_cost_base >= 0),
  CONSTRAINT ck_purchase_items_amounts_non_negative CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0)
);

CREATE TABLE replenishment_allocations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  channel replenishment_channel NOT NULL,
  sale_item_id BIGINT NOT NULL REFERENCES sale_items(id),
  purchase_order_item_id BIGINT REFERENCES purchase_order_items(id),
  reserved_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  fulfilled_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  released_qty_base NUMERIC(18,4) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_replenishment_allocations_non_negative CHECK (reserved_qty_base >= 0 AND fulfilled_qty_base >= 0 AND released_qty_base >= 0),
  CONSTRAINT ck_replenishment_allocations_not_empty CHECK (reserved_qty_base > 0 OR fulfilled_qty_base > 0 OR released_qty_base > 0),
  CONSTRAINT ck_replenishment_allocations_terminal_qty CHECK (fulfilled_qty_base + released_qty_base <= reserved_qty_base),
  CONSTRAINT ck_replenishment_allocations_reserved_order CHECK (reserved_qty_base = 0 OR purchase_order_item_id IS NOT NULL),
  CONSTRAINT uq_replenishment_allocations_sale_order UNIQUE (sale_item_id, purchase_order_item_id),
  CONSTRAINT uq_replenishment_allocations_id_order_item UNIQUE (id, purchase_order_item_id)
);

CREATE TABLE replenishment_allocation_fulfillments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  replenishment_allocation_id BIGINT NOT NULL,
  purchase_item_id BIGINT NOT NULL,
  purchase_order_item_id BIGINT NOT NULL,
  fulfilled_qty_base NUMERIC(18,4) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_replenishment_allocation_fulfillments_alloc_purchase_item UNIQUE (replenishment_allocation_id, purchase_item_id),
  CONSTRAINT fk_replenishment_allocation_fulfillments_allocation FOREIGN KEY (replenishment_allocation_id) REFERENCES replenishment_allocations(id),
  CONSTRAINT fk_replenishment_allocation_fulfillments_purchase_item FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id),
  CONSTRAINT fk_replenishment_allocation_fulfillments_allocation_order_item FOREIGN KEY (replenishment_allocation_id, purchase_order_item_id) REFERENCES replenishment_allocations(id, purchase_order_item_id),
  CONSTRAINT fk_replenishment_allocation_fulfillments_purchase_item_order FOREIGN KEY (purchase_item_id, purchase_order_item_id) REFERENCES purchase_items(id, purchase_order_item_id),
  CONSTRAINT ck_replenishment_allocation_fulfillments_qty_positive CHECK (fulfilled_qty_base > 0)
);

CREATE TABLE inventory_adjustments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  folio TEXT NOT NULL,
  status inventory_adjustment_status NOT NULL DEFAULT 'DRAFT',
  reason TEXT NOT NULL,
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  approved_by_user_id BIGINT REFERENCES users(id),
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_inventory_adjustments_public_id UNIQUE (public_id),
  CONSTRAINT uq_inventory_adjustments_branch_folio UNIQUE (branch_id, folio),
  CONSTRAINT ck_inventory_adjustments_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND approved_by_user_id IS NOT NULL))
);

CREATE TABLE inventory_adjustment_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adjustment_id BIGINT NOT NULL REFERENCES inventory_adjustments(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  system_qty_base NUMERIC(18,4) NOT NULL,
  physical_qty_base NUMERIC(18,4) NOT NULL,
  difference_qty_base NUMERIC(18,4) NOT NULL,
  unit_cost_snapshot NUMERIC(18,6),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_inventory_adjustment_items_product UNIQUE (adjustment_id, product_id),
  CONSTRAINT ck_inventory_adjustment_items_quantities_non_negative CHECK (system_qty_base >= 0 AND physical_qty_base >= 0),
  CONSTRAINT ck_inventory_adjustment_items_difference CHECK (difference_qty_base = physical_qty_base - system_qty_base),
  CONSTRAINT ck_inventory_adjustment_items_cost_non_negative CHECK (unit_cost_snapshot IS NULL OR unit_cost_snapshot >= 0)
);

CREATE TABLE stock_transfers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  origin_branch_id BIGINT NOT NULL REFERENCES branches(id),
  destination_branch_id BIGINT NOT NULL REFERENCES branches(id),
  folio TEXT NOT NULL,
  status stock_transfer_status NOT NULL DEFAULT 'DRAFT',
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  confirmed_by_user_id BIGINT REFERENCES users(id),
  notes TEXT,
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock_transfers_public_id UNIQUE (public_id),
  CONSTRAINT uq_stock_transfers_origin_folio UNIQUE (origin_branch_id, folio),
  CONSTRAINT ck_stock_transfers_distinct_branches CHECK (origin_branch_id <> destination_branch_id),
  CONSTRAINT ck_stock_transfers_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL))
);

CREATE TABLE stock_transfer_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stock_transfer_id BIGINT NOT NULL REFERENCES stock_transfers(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  quantity_base NUMERIC(18,4) NOT NULL,
  unit_cost_snapshot NUMERIC(18,6) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock_transfer_items_product UNIQUE (stock_transfer_id, product_id),
  CONSTRAINT ck_stock_transfer_items_quantity_positive CHECK (quantity_base > 0),
  CONSTRAINT ck_stock_transfer_items_cost_non_negative CHECK (unit_cost_snapshot >= 0)
);

CREATE TABLE invoices (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  sale_id BIGINT NOT NULL REFERENCES sales(id),
  replaces_invoice_id BIGINT REFERENCES invoices(id),
  branch_id BIGINT NOT NULL REFERENCES branches(id),
  customer_id BIGINT NOT NULL REFERENCES customers(id),
  fiscal_profile_id BIGINT REFERENCES customer_fiscal_profiles(id),
  status invoice_status NOT NULL DEFAULT 'PENDING',
  uuid UUID,
  pac_provider TEXT,
  pac_request_id TEXT,
  emitter_snapshot JSONB NOT NULL,
  receiver_snapshot JSONB NOT NULL,
  concepts_snapshot JSONB NOT NULL,
  payment_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  xml_storage_ref TEXT,
  pdf_storage_ref TEXT,
  xml_sha256 TEXT,
  pdf_sha256 TEXT,
  error_code TEXT,
  error_message TEXT,
  idempotency_key TEXT NOT NULL,
  stamped_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_invoices_public_id UNIQUE (public_id),
  CONSTRAINT uq_invoices_idempotency UNIQUE (sale_id, idempotency_key),
  CONSTRAINT fk_invoices_sale_branch FOREIGN KEY (sale_id, branch_id) REFERENCES sales(id, branch_id),
  CONSTRAINT ck_invoices_not_self_replacing CHECK (replaces_invoice_id IS NULL OR replaces_invoice_id <> id),
  CONSTRAINT ck_invoices_stamped_fields CHECK (status <> 'STAMPED' OR (uuid IS NOT NULL AND stamped_at IS NOT NULL AND xml_storage_ref IS NOT NULL)),
  CONSTRAINT ck_invoices_cancelled_fields CHECK (status <> 'CANCELLED' OR cancelled_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_invoices_uuid
  ON invoices (uuid)
  WHERE uuid IS NOT NULL;

CREATE INDEX ix_invoices_sale
  ON invoices (sale_id);

CREATE TABLE invoice_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id BIGINT NOT NULL REFERENCES invoices(id),
  event_type TEXT NOT NULL,
  status_from invoice_status,
  status_to invoice_status,
  pac_provider TEXT,
  pac_request_id TEXT,
  pac_response JSONB,
  error_code TEXT,
  error_message TEXT,
  actor_user_id BIGINT REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_invoice_events_type_not_blank CHECK (length(trim(event_type)) > 0)
);

CREATE TRIGGER trg_invoice_events_append_only
BEFORE UPDATE OR DELETE ON invoice_events
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete_on_ledger();

CREATE TABLE document_sequences (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  branch_id BIGINT REFERENCES branches(id),
  document_type TEXT NOT NULL,
  prefix TEXT NOT NULL,
  next_number BIGINT NOT NULL DEFAULT 1,
  padding SMALLINT NOT NULL DEFAULT 6,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_document_sequences_type CHECK (document_type ~ '^[A-Z_]+$'),
  CONSTRAINT ck_document_sequences_prefix CHECK (prefix ~ '^[A-Z0-9-]+$'),
  CONSTRAINT ck_document_sequences_next_positive CHECK (next_number > 0),
  CONSTRAINT ck_document_sequences_padding CHECK (padding BETWEEN 1 AND 12)
);

CREATE UNIQUE INDEX uq_document_sequences_scope_type
  ON document_sequences (business_id, COALESCE(branch_id, 0), document_type);

CREATE TABLE idempotency_keys (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES businesses(id),
  branch_id BIGINT REFERENCES branches(id),
  operation_type TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  status idempotency_status NOT NULL DEFAULT 'IN_PROGRESS',
  result_entity_type TEXT,
  result_entity_id BIGINT,
  response_body JSONB,
  error_code TEXT,
  error_message TEXT,
  locked_until TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_idempotency_keys_business_operation_key UNIQUE (business_id, operation_type, idempotency_key),
  CONSTRAINT ck_idempotency_keys_operation_type CHECK (operation_type ~ '^[A-Z_]+$'),
  CONSTRAINT ck_idempotency_keys_completed_result CHECK (status <> 'COMPLETED' OR (result_entity_type IS NOT NULL AND result_entity_id IS NOT NULL))
);

CREATE TABLE audit_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id UUID NOT NULL DEFAULT gen_random_uuid(),
  actor_user_id BIGINT REFERENCES users(id),
  branch_id BIGINT REFERENCES branches(id),
  terminal_id BIGINT REFERENCES terminals(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id BIGINT,
  entity_public_id UUID,
  before_data JSONB,
  after_data JSONB,
  context JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address INET,
  user_agent TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_audit_log_public_id UNIQUE (public_id),
  CONSTRAINT ck_audit_log_action CHECK (length(trim(action)) > 0),
  CONSTRAINT ck_audit_log_entity_type CHECK (length(trim(entity_type)) > 0)
);

CREATE TRIGGER trg_audit_log_append_only
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete_on_ledger();

CREATE INDEX ix_branches_business_active ON branches (business_id, active);
CREATE INDEX ix_terminals_branch_status ON terminals (branch_id, status);
CREATE INDEX ix_users_status ON users (status);
CREATE INDEX ix_user_roles_role ON user_roles (role_id);
CREATE INDEX ix_role_permissions_permission ON role_permissions (permission_id);
CREATE INDEX ix_user_branches_branch ON user_branches (branch_id);
CREATE INDEX ix_customers_business_name ON customers (business_id, display_name);
CREATE INDEX ix_customer_fiscal_profiles_customer ON customer_fiscal_profiles (customer_id);
CREATE INDEX ix_categories_business_active ON categories (business_id, active);
CREATE INDEX ix_products_business_name ON products (business_id, name);
CREATE INDEX ix_products_category ON products (category_id) WHERE active;
CREATE INDEX ix_product_barcodes_product ON product_barcodes (product_id);
CREATE INDEX ix_product_units_product_active ON product_units (product_id, active);
CREATE INDEX ix_suppliers_business_active ON suppliers (business_id, active);
CREATE INDEX ix_product_suppliers_supplier ON product_suppliers (supplier_id, active);

CREATE INDEX ix_inventory_movements_product_date ON inventory_movements (product_id, occurred_at DESC);
CREATE INDEX ix_inventory_movements_branch_product_date ON inventory_movements (branch_id, product_id, occurred_at DESC);
CREATE INDEX ix_inventory_movements_reference ON inventory_movements (reference_entity_type, reference_entity_id);

CREATE INDEX ix_cash_sessions_branch_status ON cash_sessions (branch_id, status);
CREATE INDEX ix_cash_movements_session_date ON cash_movements (cash_session_id, occurred_at DESC);
CREATE INDEX ix_cash_movements_reference ON cash_movements (reference_entity_type, reference_entity_id);

CREATE INDEX ix_sales_branch_date ON sales (branch_id, confirmed_at DESC);
CREATE INDEX ix_sales_customer_date ON sales (customer_id, confirmed_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX ix_sales_user_date ON sales (user_id, confirmed_at DESC);
CREATE INDEX ix_sale_items_product ON sale_items (product_id);
CREATE INDEX ix_sale_payments_sale ON sale_payments (sale_id);
CREATE INDEX ix_sale_payments_method ON sale_payments (payment_method_id);

CREATE INDEX ix_quotations_branch_status_date ON quotations (branch_id, status, created_at DESC);
CREATE INDEX ix_quotations_customer_date ON quotations (customer_id, created_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX ix_quotation_items_product ON quotation_items (product_id);

CREATE INDEX ix_returns_sale ON returns (sale_id);
CREATE INDEX ix_returns_branch_date ON returns (branch_id, created_at DESC);
CREATE INDEX ix_return_items_return ON return_items (return_id);
CREATE INDEX ix_return_items_sale_item ON return_items (sale_item_id);

CREATE INDEX ix_replenishment_positions_pending
  ON replenishment_positions (branch_id, channel, product_id)
  WHERE available_to_order_base > 0;
CREATE INDEX ix_replenishment_movements_branch_product_channel_date
  ON replenishment_movements (branch_id, product_id, channel, occurred_at DESC);
CREATE INDEX ix_replenishment_movements_reference
  ON replenishment_movements (reference_entity_type, reference_entity_id);
CREATE INDEX ix_replenishment_allocations_sale_item ON replenishment_allocations (sale_item_id);
CREATE INDEX ix_replenishment_allocations_order_item ON replenishment_allocations (purchase_order_item_id);
CREATE INDEX ix_replenishment_allocation_fulfillments_purchase_item ON replenishment_allocation_fulfillments (purchase_item_id);

CREATE INDEX ix_purchase_orders_supplier_status ON purchase_orders (supplier_id, status);
CREATE INDEX ix_purchase_orders_branch_channel_status ON purchase_orders (branch_id, replenishment_channel, status);
CREATE INDEX ix_purchase_order_items_product ON purchase_order_items (product_id);
CREATE INDEX ix_purchases_supplier_date ON purchases (supplier_id, created_at DESC);
CREATE INDEX ix_purchases_branch_date ON purchases (branch_id, created_at DESC);
CREATE INDEX ix_purchase_items_product ON purchase_items (product_id);

CREATE INDEX ix_inventory_adjustments_branch_status ON inventory_adjustments (branch_id, status);
CREATE INDEX ix_stock_transfers_origin_status ON stock_transfers (origin_branch_id, status);
CREATE INDEX ix_stock_transfers_destination_status ON stock_transfers (destination_branch_id, status);

CREATE INDEX ix_invoices_branch_status_date ON invoices (branch_id, status, created_at DESC);
CREATE INDEX ix_invoice_events_invoice_date ON invoice_events (invoice_id, occurred_at DESC);

CREATE INDEX ix_idempotency_keys_status ON idempotency_keys (status, locked_until);
CREATE INDEX ix_audit_log_entity ON audit_log (entity_type, entity_id, occurred_at DESC);
CREATE INDEX ix_audit_log_actor_date ON audit_log (actor_user_id, occurred_at DESC);
CREATE INDEX ix_audit_log_branch_date ON audit_log (branch_id, occurred_at DESC);

CREATE TRIGGER trg_businesses_touch_updated_at BEFORE UPDATE ON businesses FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_branches_touch_updated_at BEFORE UPDATE ON branches FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_branch_settings_touch_updated_at BEFORE UPDATE ON branch_settings FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_terminals_touch_updated_at BEFORE UPDATE ON terminals FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_users_touch_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_roles_touch_updated_at BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_price_lists_touch_updated_at BEFORE UPDATE ON price_lists FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_customers_touch_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_customer_fiscal_profiles_touch_updated_at BEFORE UPDATE ON customer_fiscal_profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_categories_touch_updated_at BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_units_touch_updated_at BEFORE UPDATE ON units FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_tax_profiles_touch_updated_at BEFORE UPDATE ON tax_profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_products_touch_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_product_units_touch_updated_at BEFORE UPDATE ON product_units FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_product_barcodes_touch_updated_at BEFORE UPDATE ON product_barcodes FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_product_prices_touch_updated_at BEFORE UPDATE ON product_prices FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_suppliers_touch_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_product_suppliers_touch_updated_at BEFORE UPDATE ON product_suppliers FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_inventory_balances_touch_updated_at BEFORE UPDATE ON inventory_balances FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_cash_registers_touch_updated_at BEFORE UPDATE ON cash_registers FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_cash_sessions_touch_updated_at BEFORE UPDATE ON cash_sessions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_payment_methods_touch_updated_at BEFORE UPDATE ON payment_methods FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_quotations_touch_updated_at BEFORE UPDATE ON quotations FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_returns_touch_updated_at BEFORE UPDATE ON returns FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_replenishment_positions_touch_updated_at BEFORE UPDATE ON replenishment_positions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_purchase_orders_touch_updated_at BEFORE UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_purchases_touch_updated_at BEFORE UPDATE ON purchases FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_replenishment_allocations_touch_updated_at BEFORE UPDATE ON replenishment_allocations FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_inventory_adjustments_touch_updated_at BEFORE UPDATE ON inventory_adjustments FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_stock_transfers_touch_updated_at BEFORE UPDATE ON stock_transfers FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_invoices_touch_updated_at BEFORE UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_document_sequences_touch_updated_at BEFORE UPDATE ON document_sequences FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_idempotency_keys_touch_updated_at BEFORE UPDATE ON idempotency_keys FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

COMMIT;
