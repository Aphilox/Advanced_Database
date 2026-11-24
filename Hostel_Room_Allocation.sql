-- Question 5: Hostel Room Allocation
-- Mugaba Banda 202400136
CREATE TABLE students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE rooms (room_id SERIAL PRIMARY KEY, room_number VARCHAR(10) UNIQUE, capacity INT CHECK (capacity > 0));
CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY, student_id INT REFERENCES students(student_id),
    room_id INT REFERENCES rooms(room_id), allocated_on DATE, released_on DATE NULL,
    status VARCHAR(10) CHECK (status IN ('ACTIVE', 'ENDED')),
    CHECK ((status = 'ACTIVE' AND released_on IS NULL) OR (status = 'ENDED' AND released_on IS NOT NULL))
);
CREATE TABLE occupancy_snapshot (snapshot_date DATE, room_id INT REFERENCES rooms(room_id), occupied_beds INT, free_beds INT, PRIMARY KEY(snapshot_date, room_id));
-- Seed Data
INSERT INTO students (student_number, full_name) VALUES ('S1','Alice'),('S2','Bob'),('S3','Charlie');
INSERT INTO rooms (room_number, capacity) VALUES ('R1',2),('R2',1),('R3',3);
INSERT INTO allocations (student_id, room_id, allocated_on, status) VALUES 
(1,1,CURRENT_DATE,'ACTIVE'), (2,1,CURRENT_DATE,'ACTIVE'), -- Room 1 Full
(3,2,CURRENT_DATE,'ACTIVE'), -- Room 2 partly
(NULL,NULL,NULL,NULL); -- Room 3 empty

-- (b) Function
CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INT) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_cap INT; v_act INT;
BEGIN
    SELECT capacity INTO STRICT v_cap FROM rooms WHERE room_id = p_room_id;
    SELECT COUNT(*) INTO v_act FROM allocations WHERE room_id = p_room_id AND status = 'ACTIVE';
    RETURN v_cap - v_act;
END; $$;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INT, p_room_id INT, p_allocated_on DATE) LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM allocations WHERE student_id = p_student_id AND status = 'ACTIVE') THEN
        RAISE EXCEPTION 'Student already has active allocation';
    END IF;
    IF fn_free_beds(p_room_id) <= 0 THEN RAISE EXCEPTION 'Room full'; END IF;
    INSERT INTO allocations (student_id, room_id, allocated_on, status) VALUES (p_student_id, p_room_id, p_allocated_on, 'ACTIVE');
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_fn_room_check() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'ACTIVE' THEN
        IF (SELECT COUNT(*) FROM allocations WHERE room_id = NEW.room_id AND status = 'ACTIVE' AND allocation_id != COALESCE(NEW.allocation_id, 0)) >= (SELECT capacity FROM rooms WHERE room_id = NEW.room_id) THEN
            RAISE EXCEPTION 'Capacity exceeded';
        END IF;
        IF EXISTS (SELECT 1 FROM allocations WHERE student_id = NEW.student_id AND status = 'ACTIVE' AND allocation_id != COALESCE(NEW.allocation_id, 0)) THEN
            RAISE EXCEPTION 'Student already active';
        END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_room_check BEFORE INSERT OR UPDATE ON allocations FOR EACH ROW EXECUTE FUNCTION trg_fn_room_check();

-- (e) View
CREATE OR REPLACE VIEW v_room_occupancy AS
SELECT r.room_id, r.capacity, 
    (SELECT COUNT(*) FROM allocations a WHERE a.room_id = r.room_id AND a.status = 'ACTIVE') as occupied,
    r.capacity - (SELECT COUNT(*) FROM allocations a WHERE a.room_id = r.room_id AND a.status = 'ACTIVE') as free
FROM rooms r;

-- (f) Index
CREATE INDEX idx_active_alloc_room ON allocations (room_id) WHERE status = 'ACTIVE';

-- (g) Job
CREATE OR REPLACE PROCEDURE pr_refresh_occupancy() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO occupancy_snapshot (snapshot_date, room_id, occupied_beds, free_beds)
    SELECT CURRENT_DATE, room_id, 
        (SELECT COUNT(*) FROM allocations WHERE room_id = r.room_id AND status = 'ACTIVE'),
        capacity - (SELECT COUNT(*) FROM allocations WHERE room_id = r.room_id AND status = 'ACTIVE')
    FROM rooms r
    ON CONFLICT (snapshot_date, room_id) DO UPDATE SET occupied_beds = EXCLUDED.occupied_beds, free_beds = EXCLUDED.free_beds;
END; $$;
SELECT cron.schedule('hostel_occupancy', '55 23 * * *', $$CALL pr_refresh_occupancy()$$);