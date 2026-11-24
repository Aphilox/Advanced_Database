-- Question 9: Farmer Cooperative Maize Deliveries
-- Mugaba Banda 202400136
CREATE TABLE farmers (farmer_id SERIAL PRIMARY KEY, farmer_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE deliveries (
    delivery_id SERIAL PRIMARY KEY, farmer_id INT REFERENCES farmers(farmer_id),
    grade CHAR(1), weight_kg NUMERIC CHECK (weight_kg > 0), unit_rate NUMERIC, total_value NUMERIC,
    delivered_on DATE, is_paid BOOLEAN DEFAULT FALSE
);
CREATE TABLE daily_purchases (purchase_date DATE PRIMARY KEY, total_weight NUMERIC, total_value NUMERIC);
-- Seed Data
INSERT INTO farmers (farmer_number, full_name) VALUES ('F1','John'), ('F2','Jane'), ('F3','Jim');
-- Inserts handle by trigger
INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid) VALUES 
(1,'A', 100, '2023-10-01', FALSE), (1,'B', 50, '2023-10-01', TRUE),
(2,'C', 200, '2023-10-02', FALSE), (2,'A', 80, '2023-10-02', FALSE),
(3,'B', 120, '2023-10-03', TRUE), (3,'C', 60, '2023-10-03', FALSE);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade CHAR) RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN
    CASE p_grade
        WHEN 'A' THEN RETURN 5.00;
        WHEN 'B' THEN RETURN 4.00;
        WHEN 'C' THEN RETURN 3.00;
        ELSE RAISE EXCEPTION 'Invalid grade';
    END CASE;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INT, p_grade CHAR, p_weight NUMERIC, p_date DATE) LANGUAGE plpgsql AS $$
BEGIN
    IF p_weight <= 0 THEN RAISE EXCEPTION 'Weight > 0'; END IF;
    INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid) VALUES (p_farmer_id, p_grade, p_weight, p_date, FALSE);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_maize_calc() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.weight_kg <= 0 THEN RAISE EXCEPTION 'Weight > 0'; END IF;
    NEW.unit_rate := fn_maize_rate(NEW.grade);
    NEW.total_value := NEW.weight_kg * NEW.unit_rate;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_maize_calc BEFORE INSERT OR UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION trg_fn_maize_calc();

-- (e) View
CREATE OR REPLACE VIEW v_farmer_amount_due AS
SELECT f.farmer_number, f.full_name, COALESCE(SUM(d.total_value), 0) as amount_due
FROM farmers f LEFT JOIN deliveries d ON f.farmer_id = d.farmer_id AND d.is_paid = FALSE
GROUP BY f.farmer_id, f.farmer_number, f.full_name;

-- (f) Index
CREATE INDEX idx_deliv_farmer_date ON deliveries (farmer_id, delivered_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO daily_purchases (purchase_date, total_weight, total_value)
    SELECT p_day, COALESCE(SUM(weight_kg),0), COALESCE(SUM(total_value),0)
    FROM deliveries WHERE delivered_on = p_day
    ON CONFLICT (purchase_date) DO UPDATE SET total_weight = EXCLUDED.total_weight, total_value = EXCLUDED.total_value;
END; $$;
SELECT cron.schedule('maize_purchases', '30 1 * * *', $$CALL pr_refresh_purchases(CURRENT_DATE - 1)$$);
