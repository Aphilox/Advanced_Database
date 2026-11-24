-- Question 4: Clinic Appointment Scheduling
-- Mugaba Banda 202400136
CREATE TABLE patients (patient_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE doctors (doctor_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY, patient_id INTEGER REFERENCES patients(patient_id),
    doctor_id INTEGER REFERENCES doctors(doctor_id), appointment_day DATE, slot_time TIME,
    status VARCHAR(20) CHECK (status IN ('BOOKED', 'ATTENDED', 'CANCELLED'))
);
CREATE TABLE clinic_summary (summary_date DATE PRIMARY KEY, booked_count INT, attended_count INT, cancelled_count INT);
-- Seed Data
INSERT INTO patients (full_name) VALUES ('P1'),('P2'),('P3');
INSERT INTO doctors (full_name) VALUES ('D1'),('D2'),('D3');
INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES
(1,1,'2023-11-01','09:00','BOOKED'), (2,1,'2023-11-01','10:00','BOOKED'), (3,2,'2023-11-01','09:00','CANCELLED'),
(1,2,'2023-11-02','09:00','BOOKED'), (2,3,'2023-11-02','11:00','BOOKED'), (3,3,'2023-11-02','12:00','BOOKED');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id INT, p_day DATE) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_count INT;
BEGIN
    SELECT doctor_id INTO STRICT v_id FROM doctors WHERE doctor_id = p_doctor_id;
    SELECT COUNT(*) INTO v_count FROM appointments WHERE doctor_id = p_doctor_id AND appointment_day = p_day AND status != 'CANCELLED';
    RETURN v_count;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id INT, p_doctor_id INT, p_day DATE, p_slot TIME) LANGUAGE plpgsql AS $$
BEGIN
    IF p_day < CURRENT_DATE THEN RAISE EXCEPTION 'Cannot book in past'; END IF;
    IF p_slot NOT IN ('09:00', '10:00', '11:00', '12:00') THEN RAISE EXCEPTION 'Invalid slot'; END IF;
    INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES (p_patient_id, p_doctor_id, p_day, p_slot, 'BOOKED');
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_clash() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status != 'CANCELLED' THEN
        IF EXISTS (SELECT 1 FROM appointments WHERE doctor_id = NEW.doctor_id AND appointment_day = NEW.appointment_day AND slot_time = NEW.slot_time AND status != 'CANCELLED' AND appointment_id != COALESCE(NEW.appointment_id, 0)) THEN
            RAISE EXCEPTION 'Slot clash';
        END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_clash BEFORE INSERT OR UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION trg_fn_clash();

-- (e) View
CREATE OR REPLACE VIEW v_today_appointments AS
SELECT p.full_name as patient, d.full_name as doctor, a.slot_time
FROM appointments a JOIN patients p ON a.patient_id = p.patient_id JOIN doctors d ON a.doctor_id = d.doctor_id
WHERE a.appointment_day = CURRENT_DATE AND a.status = 'BOOKED';

-- (f) Index
CREATE INDEX idx_app_day_doctor ON appointments (appointment_day, doctor_id);

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO clinic_summary (summary_date, booked_count, attended_count, cancelled_count)
    SELECT p_day, 
        COUNT(*) FILTER (WHERE status = 'BOOKED'), 
        COUNT(*) FILTER (WHERE status = 'ATTENDED'), 
        COUNT(*) FILTER (WHERE status = 'CANCELLED')
    FROM appointments WHERE appointment_day = p_day
    ON CONFLICT (summary_date) DO UPDATE SET booked_count = EXCLUDED.booked_count, attended_count = EXCLUDED.attended_count, cancelled_count = EXCLUDED.cancelled_count;
END; $$;
SELECT cron.schedule('clinic_summary', '0 1 * * *', $$CALL pr_refresh_clinic_summary(CURRENT_DATE - 1)$$);
