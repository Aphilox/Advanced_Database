-- Question 10: Scholarship Application Assessment
-- Mugaba Banda 202400136

CREATE TABLE students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE applications (
    application_id SERIAL PRIMARY KEY, student_id INT REFERENCES students(student_id),
    age_at_application INT CHECK (age_at_application > 0), 
    monthly_income NUMERIC CHECK (monthly_income >= 0), 
    average_mark NUMERIC CHECK (average_mark >= 0 AND average_mark <= 100), 
    submitted_on DATE, status VARCHAR(20) CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')) DEFAULT 'PENDING'
);
CREATE TABLE decision_audit (audit_id SERIAL PRIMARY KEY, application_id INT, old_status VARCHAR, new_status VARCHAR, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
-- Seed Data
INSERT INTO students (student_number, full_name) VALUES ('S1','Alice'), ('S2','Bob'), ('S3','Charlie');
INSERT INTO applications (student_id, age_at_application, monthly_income, average_mark, submitted_on) VALUES 
(1, 20, 2000, 80, '2023-10-01'), (1, 18, 3000, 70, '2023-10-01'), -- Qualify & Boundary
(2, 26, 2000, 80, '2023-10-02'), (2, 20, 3001, 80, '2023-10-02'), -- Fail age & income
(3, 20, 2000, 69, '2023-10-03'), (3, 25, 1000, 90, '2023-10-03'); -- Fail mark & Qualify

-- (b) Function
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT, p_income NUMERIC, p_mark NUMERIC) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL OR p_income < 0 OR p_age <= 0 OR p_mark < 0 OR p_mark > 100 THEN
        RAISE EXCEPTION 'Invalid inputs';
    END IF;
    RETURN (p_age BETWEEN 18 AND 25) AND (p_income <= 3000) AND (p_mark >= 70);
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) LANGUAGE plpgsql AS $$
DECLARE v_age INT; v_inc NUMERIC; v_mark NUMERIC; v_stat VARCHAR;
BEGIN
    SELECT age_at_application, monthly_income, average_mark, status INTO STRICT v_age, v_inc, v_mark, v_stat FROM applications WHERE application_id = p_application_id FOR UPDATE;
    IF v_stat != 'PENDING' THEN RAISE EXCEPTION 'Already assessed'; END IF;
    IF fn_scholarship_eligible(v_age, v_inc, v_mark) THEN
        UPDATE applications SET status = 'APPROVED' WHERE application_id = p_application_id;
    ELSE
        UPDATE applications SET status = 'REJECTED' WHERE application_id = p_application_id;
    END IF;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_status_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO decision_audit (application_id, old_status, new_status) VALUES (NEW.application_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_status_audit AFTER UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION trg_fn_status_audit();

-- (e) View
CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number, s.full_name, a.average_mark, a.status
FROM applications a JOIN students s ON a.student_id = s.student_id
WHERE a.status = 'APPROVED';

-- (f) Index
CREATE INDEX idx_app_status_date ON applications (status, submitted_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE rec RECORD;
BEGIN
    FOR rec IN SELECT application_id FROM applications WHERE status = 'PENDING' LOOP
        CALL pr_assess_application(rec.application_id);
    END LOOP;
END; $$;
SELECT cron.schedule('weekly_scholarship', '0 8 * * 1', $$CALL pr_assess_pending()$$);