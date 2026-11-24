-- Question 2: University Fee Payments
-- Mugaba Banda 202400136

CREATE TABLE students (
    student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL, fee_due NUMERIC(10,2) NOT NULL CHECK (fee_due >= 0)
);
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY, student_id INTEGER REFERENCES students(student_id),
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0), paid_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE payment_audit (
    audit_id SERIAL PRIMARY KEY, payment_id INTEGER REFERENCES payments(payment_id),
    student_id INTEGER REFERENCES students(student_id), amount NUMERIC(10,2), logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_collections (
    collection_date DATE PRIMARY KEY, payment_count INTEGER DEFAULT 0, total_amount NUMERIC(12,2) DEFAULT 0
);
-- Seed Data
INSERT INTO students (student_number, full_name, fee_due) VALUES ('STU1','Alice',5000),('STU2','Bob',4500),('STU3','Charlie',6000);
INSERT INTO payments (student_id, amount) VALUES (1,1500),(1,1500),(1,2000),(2,1000),(2,2000),(2,500); -- STU3 has none

-- (b) Function
CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INTEGER) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_due NUMERIC; v_paid NUMERIC;
BEGIN
    SELECT fee_due INTO STRICT v_due FROM students WHERE student_id = p_student_id;
    SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE student_id = p_student_id;
    RETURN v_due - v_paid;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INTEGER, p_amount NUMERIC, p_paid_on TIMESTAMP) LANGUAGE plpgsql AS $$
DECLARE v_bal NUMERIC;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
    v_bal := fn_fee_balance(p_student_id);
    IF p_amount > v_bal THEN RAISE EXCEPTION 'Exceeds outstanding balance'; END IF;
    INSERT INTO payments (student_id, amount, paid_on) VALUES (p_student_id, p_amount, p_paid_on);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_pay_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO payment_audit (payment_id, student_id, amount) VALUES (NEW.payment_id, NEW.student_id, NEW.amount);
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_pay_audit AFTER INSERT ON payments FOR EACH ROW EXECUTE FUNCTION trg_fn_pay_audit();

-- (e) View
CREATE OR REPLACE VIEW v_fee_balances AS 
SELECT s.student_number, s.full_name, (s.fee_due - COALESCE(SUM(p.amount),0)) as balance
FROM students s LEFT JOIN payments p ON s.student_id = p.student_id
GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due HAVING (s.fee_due - COALESCE(SUM(p.amount),0)) > 0;

-- (f) Index
CREATE INDEX idx_pay_stud_date ON payments (student_id, paid_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO daily_collections (collection_date, payment_count, total_amount)
    SELECT p_day, COUNT(*), COALESCE(SUM(amount),0) FROM payments WHERE paid_on::date = p_day
    ON CONFLICT (collection_date) DO UPDATE SET payment_count = EXCLUDED.payment_count, total_amount = EXCLUDED.total_amount;
END; $$;
SELECT cron.schedule('daily_coll', '0 1 * * *', $$CALL pr_refresh_collections(CURRENT_DATE - 1)$$);
