-- Question 8: Transport Fleet Maintenance
-- Mugaba Banda 202400136
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY, registration VARCHAR(20) UNIQUE,
    current_odometer NUMERIC CHECK (current_odometer >= 0),
    last_service_odometer NUMERIC CHECK (last_service_odometer >= 0),
    CHECK (last_service_odometer <= current_odometer)
);
CREATE TABLE trips (
    trip_id SERIAL PRIMARY KEY, vehicle_id INT REFERENCES vehicles(vehicle_id),
    trip_on DATE, start_odometer NUMERIC, end_odometer NUMERIC
);
CREATE TABLE service_alerts (vehicle_id INT PRIMARY KEY REFERENCES vehicles(vehicle_id), km_since_service NUMERIC, flagged_on DATE);
-- Seed Data
INSERT INTO vehicles (registration, current_odometer, last_service_odometer) VALUES 
('ABC', 10000, 4000), ('XYZ', 5000, 5000), ('DEF', 20000, 10000);
INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer) VALUES 
(1, '2023-10-01', 10000, 10500), (1, '2023-10-02', 10500, 11000),
(2, '2023-10-01', 5000, 5500), (2, '2023-10-02', 5500, 6000),
(3, '2023-10-01', 20000, 21000), (3, '2023-10-02', 21000, 22000);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_curr NUMERIC; v_last NUMERIC;
BEGIN
    SELECT current_odometer, last_service_odometer INTO STRICT v_curr, v_last FROM vehicles WHERE vehicle_id = p_vehicle_id;
    RETURN (v_curr - v_last) >= 5000;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INT, p_trip_on DATE, p_start NUMERIC, p_end NUMERIC) LANGUAGE plpgsql AS $$
BEGIN
    IF p_end <= p_start THEN RAISE EXCEPTION 'End > Start required'; END IF;
    INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer) VALUES (p_vehicle_id, p_trip_on, p_start, p_end);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_trip_check() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_curr NUMERIC;
BEGIN
    SELECT current_odometer INTO v_curr FROM vehicles WHERE vehicle_id = NEW.vehicle_id;
    IF NEW.start_odometer != v_curr THEN RAISE EXCEPTION 'Start odometer must match current'; END IF;
    UPDATE vehicles SET current_odometer = NEW.end_odometer WHERE vehicle_id = NEW.vehicle_id;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_trip_check BEFORE INSERT ON trips FOR EACH ROW EXECUTE FUNCTION trg_fn_trip_check();

-- (e) View
CREATE OR REPLACE VIEW v_service_due AS
SELECT registration, (current_odometer - last_service_odometer) as km_since
FROM vehicles WHERE (current_odometer - last_service_odometer) >= 5000;

-- (f) Index
CREATE INDEX idx_trips_vehicle_date ON trips (vehicle_id, trip_on);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO service_alerts (vehicle_id, km_since_service, flagged_on)
    SELECT vehicle_id, current_odometer - last_service_odometer, CURRENT_DATE
    FROM vehicles WHERE current_odometer - last_service_odometer >= 5000
    ON CONFLICT (vehicle_id) DO UPDATE SET km_since_service = EXCLUDED.km_since_service, flagged_on = EXCLUDED.flagged_on;
    
    DELETE FROM service_alerts WHERE vehicle_id IN (SELECT vehicle_id FROM vehicles WHERE current_odometer - last_service_odometer < 5000);
END; $$;
SELECT cron.schedule('weekly_alerts', '0 6 * * 1', $$CALL pr_refresh_service_alerts()$$);
