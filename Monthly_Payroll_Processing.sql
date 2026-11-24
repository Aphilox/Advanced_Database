-- Question 6: Monthly Payroll Processing
-- Mugaba Banda 202400136
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY, full_name VARCHAR(100),
    basic_salary NUMERIC(10,2) CHECK (basic_salary >= 0), 
    allowance NUMERIC(10,2) CHECK (allowance >= 0), 
    deduction NUMERIC(10,2) CHECK (deduction >= 0), 
    active BOOLEAN DEFAULT TRUE
);
CREATE TABLE payroll (
    payroll_id SERIAL PRIMARY KEY, employee_id INT REFERENCES employees(employee_id),
    pay_month DATE, gross_pay NUMERIC(10,2), net_pay NUMERIC(10,2),
    UNIQUE (employee_id, pay_month)
);
CREATE TABLE salary_audit (audit_id SERIAL PRIMARY KEY, employee_id INT, old_salary NUMERIC, new_salary NUMERIC, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
-- Seed Data
INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES 
('Alice', 5000, 500, 200, TRUE), ('Bob', 4000, 400, 150, TRUE), ('Charlie', 3000, 0, 100, FALSE);
INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay) VALUES 
(1, '2023-09-01', 5500, 5300), (2, '2023-09-01', 4400, 4250);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_basic NUMERIC; v_allow NUMERIC; v_ded NUMERIC; v_net NUMERIC;
BEGIN
    SELECT basic_salary, allowance, deduction INTO STRICT v_basic, v_allow, v_ded FROM employees WHERE employee_id = p_employee_id;
    v_net := (v_basic + v_allow) - v_ded;
    IF v_net < 0 THEN RAISE EXCEPTION 'Negative net pay'; END IF;
    RETURN v_net;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE) LANGUAGE plpgsql AS $$
DECLARE rec RECORD;
BEGIN
    IF p_month != DATE_TRUNC('month', p_month)::DATE THEN RAISE EXCEPTION 'Must be month start'; END IF;
    FOR rec IN SELECT employee_id, basic_salary, allowance FROM employees WHERE active = TRUE LOOP
        INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay)
        VALUES (rec.employee_id, p_month, rec.basic_salary + rec.allowance, fn_net_pay(rec.employee_id))
        ON CONFLICT (employee_id, pay_month) DO NOTHING; -- Retain existing
    END LOOP;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_salary_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
        INSERT INTO salary_audit (employee_id, old_salary, new_salary) VALUES (NEW.employee_id, OLD.basic_salary, NEW.basic_salary);
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_salary_audit AFTER UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION trg_fn_salary_audit();

-- (e) View
CREATE OR REPLACE VIEW v_payroll_report AS
SELECT e.full_name, p.pay_month, p.gross_pay, p.net_pay
FROM payroll p JOIN employees e ON p.employee_id = e.employee_id;

-- (f) Index
CREATE INDEX idx_payroll_month ON payroll (pay_month);

-- (g) Job
SELECT cron.schedule('monthly_payroll', '0 2 1 * *', $$CALL pr_process_payroll((DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month')::DATE)$$);