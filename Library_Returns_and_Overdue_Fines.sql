-- Question 3: Library Returns and Overdue Fines
-- Mugaba Banda 202400136
CREATE TABLE books (book_id SERIAL PRIMARY KEY, title VARCHAR(100) NOT NULL);
CREATE TABLE loans (
    loan_id SERIAL PRIMARY KEY, book_id INTEGER REFERENCES books(book_id),
    borrower_name VARCHAR(100), borrowed_on DATE NOT NULL, due_on DATE NOT NULL, 
    returned_on DATE NULL, fine_amount NUMERIC(10,2) DEFAULT 0,
    CHECK (due_on >= borrowed_on)
);
CREATE TABLE loan_audit (
    audit_id SERIAL PRIMARY KEY, loan_id INTEGER REFERENCES loans(loan_id),
    old_returned_on DATE NULL, new_returned_on DATE NULL, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE overdue_summary (snapshot_date DATE PRIMARY KEY, overdue_count INTEGER, total_fine NUMERIC(12,2));
-- Seed Data
INSERT INTO books (title) VALUES ('Book A'), ('Book B'), ('Book C');
INSERT INTO loans (book_id, borrower_name, borrowed_on, due_on, returned_on) VALUES 
(1,'Alice','2023-10-01','2023-10-10', NULL), -- Overdue open
(1,'Bob','2023-10-05','2023-10-12','2023-10-10'), -- Returned
(2,'Charlie','2023-10-15','2023-10-25', NULL), 
(2,'Dave','2023-10-01','2023-10-05','2023-10-05'), -- On time
(3,'Eve','2023-10-01','2023-10-08', NULL),
(3,'Frank','2023-10-10','2023-10-20', NULL);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INTEGER, p_as_of DATE) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_due DATE; v_ret DATE; v_calc_date DATE; v_days INT;
BEGIN
    SELECT due_on, returned_on INTO STRICT v_due, v_ret FROM loans WHERE loan_id = p_loan_id;
    v_calc_date := LEAST(p_as_of, COALESCE(v_ret, p_as_of));
    v_days := v_calc_date - v_due;
    IF v_days <= 0 THEN RETURN 0; END IF;
    RETURN v_days * 2.00;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INTEGER, p_returned_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_borrowed DATE; v_ret DATE;
BEGIN
    SELECT borrowed_on, returned_on INTO STRICT v_borrowed, v_ret FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
    IF v_ret IS NOT NULL THEN RAISE EXCEPTION 'Already returned'; END IF;
    IF p_returned_on < v_borrowed THEN RAISE EXCEPTION 'Return before borrow'; END IF;
    UPDATE loans SET returned_on = p_returned_on, fine_amount = fn_loan_fine(p_loan_id, p_returned_on) WHERE loan_id = p_loan_id;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_loan_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN
        INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on) VALUES (NEW.loan_id, OLD.returned_on, NEW.returned_on);
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_loan_audit AFTER UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION trg_fn_loan_audit();

-- (e) View
CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT b.title, l.borrower_name, l.due_on, fn_loan_fine(l.loan_id, CURRENT_DATE) as fine
FROM loans l JOIN books b ON l.book_id = b.book_id
WHERE l.returned_on IS NULL AND l.due_on < CURRENT_DATE;

-- (f) Index
CREATE INDEX idx_loans_book_unreturned ON loans (book_id, returned_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine)
    SELECT p_as_of, COUNT(*), COALESCE(SUM(fn_loan_fine(loan_id, p_as_of)),0)
    FROM loans WHERE returned_on IS NULL AND due_on < p_as_of
    ON CONFLICT (snapshot_date) DO UPDATE SET overdue_count = EXCLUDED.overdue_count, total_fine = EXCLUDED.total_fine;
END; $$;
SELECT cron.schedule('daily_overdue', '10 0 * * *', $$CALL pr_refresh_overdue(CURRENT_DATE)$$);
