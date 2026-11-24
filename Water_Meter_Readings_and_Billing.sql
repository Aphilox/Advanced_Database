-- Question 7: Water Meter Readings and Billing
-- Mugaba Banda 202400136
CREATE TABLE customers (customer_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE readings (
    reading_id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(customer_id),
    reading_month DATE, previous_reading NUMERIC(10,2) CHECK (previous_reading >= 0), 
    current_reading NUMERIC(10,2) CHECK (current_reading >= 0),
    UNIQUE(customer_id, reading_month)
);
CREATE TABLE bills (
    bill_id SERIAL PRIMARY KEY, reading_id INT UNIQUE REFERENCES readings(reading_id),
    charge NUMERIC(10,2), amount_paid NUMERIC(10,2) CHECK (amount_paid >= 0), due_on DATE,
    CHECK (amount_paid <= charge)
);
CREATE TABLE receivable_snapshot (snapshot_date DATE PRIMARY KEY, total_due NUMERIC(12,2));
-- Seed Data
INSERT INTO customers (full_name) VALUES ('Cust1'), ('Cust2'), ('Cust3');
INSERT INTO readings (customer_id, reading_month, previous_reading, current_reading) VALUES 
(1, '2023-09-01', 0, 5),    -- 5 units
(1, '2023-10-01', 5, 15),   -- 10 units exactly
(2, '2023-09-01', 10, 22),  -- 12 units (above 10)
(2, '2023-10-01', 22, 22),  -- Zero units
(3, '2023-09-01', 100, 105),(3, '2023-10-01', 105, 115);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_water_charge(p_units NUMERIC) RETURNS NUMERIC(10,2) LANGUAGE plpgsql AS $$
BEGIN
    IF p_units IS NULL OR p_units < 0 THEN RAISE EXCEPTION 'Invalid units'; END IF;
    IF p_units <= 10 THEN RETURN p_units * 5.00;
    ELSE RETURN (10 * 5.00) + ((p_units - 10) * 8.00); END IF;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INT, p_due_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_cons NUMERIC; v_charge NUMERIC;
BEGIN
    IF EXISTS (SELECT 1 FROM bills WHERE reading_id = p_reading_id) THEN RAISE EXCEPTION 'Bill exists'; END IF;
    SELECT current_reading - previous_reading INTO STRICT v_cons FROM readings WHERE reading_id = p_reading_id;
    v_charge := fn_water_charge(v_cons);
    INSERT INTO bills (reading_id, charge, amount_paid, due_on) VALUES (p_reading_id, v_charge, 0, p_due_on);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_meter_check() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.current_reading < NEW.previous_reading THEN RAISE EXCEPTION 'Current < Previous'; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_meter_check BEFORE INSERT OR UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION trg_fn_meter_check();

-- (e) View
CREATE OR REPLACE VIEW v_overdue_bills AS
SELECT c.full_name, b.due_on, (b.charge - b.amount_paid) as outstanding
FROM bills b JOIN readings r ON b.reading_id = r.reading_id JOIN customers c ON r.customer_id = c.customer_id
WHERE b.due_on < CURRENT_DATE AND b.amount_paid < b.charge;

-- (f) Index
CREATE INDEX idx_bills_due_unpaid ON bills (due_on) WHERE amount_paid < charge;

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_receivables() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO receivable_snapshot (snapshot_date, total_due)
    SELECT CURRENT_DATE, COALESCE(SUM(charge - amount_paid), 0) FROM bills WHERE amount_paid < charge
    ON CONFLICT (snapshot_date) DO UPDATE SET total_due = EXCLUDED.total_due;
END; $$;
SELECT cron.schedule('daily_receivables', '30 0 * * *', $$CALL pr_refresh_receivables()$$);
