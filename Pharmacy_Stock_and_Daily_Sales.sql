--Question 1: Pharmacy Stock and Daily Sales
-- Mugaba Banda 202400136

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    stock_qty INTEGER NOT NULL CHECK (stock_qty >= 0)
);
CREATE TABLE sales (
    sale_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL,
    sold_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE stock_audit (
    audit_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    old_qty INTEGER NOT NULL,
    new_qty INTEGER NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_sales (
    sales_date DATE PRIMARY KEY,
    total_qty INTEGER NOT NULL DEFAULT 0,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00
);
-- Seed Data
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES 
('Paracetamol', 2.50, 100), ('Amoxicillin', 15.00, 50), ('Ibuprofen', 5.75, 200);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INTEGER, p_quantity INTEGER)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC(10,2);
BEGIN
    IF p_quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
    SELECT unit_price INTO STRICT v_price FROM medicines WHERE medicine_id = p_medicine_id;
    RETURN v_price * p_quantity;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INTEGER, p_quantity INTEGER, p_sold_on TIMESTAMP)
LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER; v_price NUMERIC(10,2);
BEGIN
    SELECT stock_qty, unit_price INTO v_stock, v_price FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;
    IF v_stock < p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on) VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);
    UPDATE medicines SET stock_qty = stock_qty - p_quantity WHERE medicine_id = p_medicine_id;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_audit_stock() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN
        INSERT INTO stock_audit (medicine_id, old_qty, new_qty) VALUES (NEW.medicine_id, OLD.stock_qty, NEW.stock_qty);
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_audit_stock AFTER UPDATE ON medicines FOR EACH ROW EXECUTE FUNCTION trg_fn_audit_stock();

-- Seed 6 Sales via Procedure
CALL pr_record_sale(1, 10, CURRENT_TIMESTAMP);
CALL pr_record_sale(2, 5, CURRENT_TIMESTAMP);
CALL pr_record_sale(1, 20, CURRENT_TIMESTAMP);
CALL pr_record_sale(3, 15, CURRENT_TIMESTAMP);
CALL pr_record_sale(2, 10, CURRENT_TIMESTAMP);
CALL pr_record_sale(3, 5, CURRENT_TIMESTAMP);

-- (e) View
CREATE OR REPLACE VIEW v_low_stock AS SELECT medicine_name, unit_price, stock_qty AS remaining_stock FROM medicines WHERE stock_qty < 10;

-- (f) Index
CREATE INDEX idx_sales_medicine_date ON sales (medicine_id, sold_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO daily_sales (sales_date, total_qty, total_amount)
    SELECT p_day, COALESCE(SUM(quantity),0), COALESCE(SUM(quantity * unit_price),0) FROM sales WHERE sold_on::date = p_day
    ON CONFLICT (sales_date) DO UPDATE SET total_qty = EXCLUDED.total_qty, total_amount = EXCLUDED.total_amount;
END; $$;
SELECT cron.schedule('daily_sales', '15 0 * * *', $$CALL pr_refresh_sales(CURRENT_DATE - 1)$$);