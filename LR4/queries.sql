-- COMPLEX DATABASE SELECTIONS

-- Select approved appointments of the week, daytime, expensive services OR any "Checkup"
SELECT app.id, app.date, app.time, srv.name AS service_name, srv.price
FROM appointments app
INNER JOIN services srv ON srv.id = app.service_id
WHERE app.is_approved = TRUE
  AND app.date BETWEEN '2026-10-01' AND '2026-10-07'
  AND app.time BETWEEN '09:00' AND '15:00'
  AND (srv.price >= 100 OR srv.name ILIKE '%Checkup%')
ORDER BY app.date, app.time;

-- Select active senior doctors (net experience >= 15 years) with a medical degree, excluding one of the offices
SELECT acc.firstname, acc.lastname, doc.degree,
       ROUND((CURRENT_DATE - doc.career_start_date) / 365.25
             - doc.gap_in_months / 12.0, 1) AS experience_years
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE acc.is_active = TRUE
  AND doc.office_id <> '44444444-0000-0000-0000-000000000003'
  AND (doc.degree ILIKE 'MD%' OR doc.degree ILIKE 'Ph.D%')
  AND (CURRENT_DATE - doc.career_start_date) / 365.25
      - doc.gap_in_months / 12.0 >= 15
ORDER BY experience_years DESC;

-- Who booked a service pricier than the average price of active services
SELECT acc.firstname, acc.lastname, srv.name AS service_name, srv.price
FROM appointments app
INNER JOIN patients pat ON pat.id = app.patient_id
INNER JOIN accounts acc ON acc.id = pat.account_id
INNER JOIN services srv ON srv.id = app.service_id
WHERE srv.price > (SELECT AVG(price) FROM services WHERE is_active = TRUE)
ORDER BY srv.price DESC;

-- Select doctors with NO work shift on 2026-10-02
SELECT acc.firstname, acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE doc.id NOT IN (
    SELECT doctor_id FROM schedules WHERE date = '2026-10-02'
);

-- Select services pricier than the average price inside their OWN specialization
SELECT srv.name, srv.price, spec.name AS specialization
FROM services srv
INNER JOIN specializations spec ON spec.id = srv.specialization_id
WHERE srv.price > (
    SELECT AVG(s2.price)
    FROM services s2
    WHERE s2.specialization_id = srv.specialization_id
);

-- Select services more expensive than EVERY pediatric service
SELECT name, price
FROM services
WHERE price > ALL (
    SELECT price FROM services
    WHERE specialization_id = (SELECT id FROM specializations WHERE name = 'Pediatrics')
);


-- JOIN`s

-- Full doctor card (name, specialization, office, experience)
CREATE OR REPLACE VIEW v_doctors_full AS
SELECT doc.id AS doctor_id,
       acc.firstname,
       acc.lastname,
       acc.email,
       spec.name AS specialization,
       offc.address AS office_address,
       doc.degree,
       ROUND((CURRENT_DATE - doc.career_start_date) / 365.25
             - doc.gap_in_months / 12.0, 1) AS experience_years
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
INNER JOIN specializations spec ON spec.id = doc.specialization_id
INNER JOIN offices offc ON offc.id = doc.office_id
WHERE acc.is_active = TRUE;

SELECT * FROM v_doctors_full ORDER BY experience_years DESC;

-- Full appointment info, diagnosis is NULL if the result has not been entered yet
CREATE OR REPLACE VIEW v_appointments_full AS
SELECT app.id AS appointment_id,
       app.date,
       app.time,
       pat_acc.firstname || ' ' || pat_acc.lastname AS patient,
       doc_acc.firstname || ' ' || doc_acc.lastname AS doctor,
       srv.name AS service,
       srv.price,
       app.is_approved,
       res.diagnosis
FROM appointments app
INNER JOIN patients pat ON pat.id = app.patient_id
INNER JOIN accounts pat_acc ON pat_acc.id = pat.account_id
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts doc_acc ON doc_acc.id = doc.account_id
INNER JOIN services srv ON srv.id = app.service_id
LEFT JOIN results res ON res.appointment_id = app.id;

-- Appointments that still have no examination result
SELECT * FROM v_appointments_full WHERE diagnosis IS NULL;

-- All specializations, including those with no doctors
CREATE OR REPLACE VIEW v_specializations_doctors AS
SELECT spec.name AS specialization,
       acc.firstname,
       acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
RIGHT JOIN specializations spec ON spec.id = doc.specialization_id;

-- Specializations nobody works in
SELECT specialization FROM v_specializations_doctors WHERE lastname IS NULL;

-- Doctors with their specializations
SELECT d.specialization_id AS doctor_spec,
       s.specialization_id AS service_spec
FROM doctors d
FULL OUTER JOIN services s
       ON s.specialization_id = d.specialization_id;

-- Doctors with offices all possible combinations
SELECT a.firstname AS doctor_name,
	   a.lastname AS doctor_lastname,
       o.address AS office_address
FROM doctors d
INNER JOIN accounts a ON d.account_id = a.id 
CROSS JOIN offices o;

-- Pairs of colleagues working in the same office
CREATE OR REPLACE VIEW v_doctor_colleagues AS
SELECT offc.address AS office_address,
       a1.lastname AS doctor_1,
       a2.lastname AS doctor_2
FROM doctors d1
INNER JOIN doctors d2 ON d1.office_id = d2.office_id AND d1.id < d2.id
INNER JOIN accounts a1 ON a1.id = d1.account_id
INNER JOIN accounts a2 ON a2.id = d2.account_id
INNER JOIN offices offc ON offc.id = d1.office_id;

SELECT * FROM v_doctor_colleagues;


-- GROUPED DATA

-- Statistics of approved appointments per specialization
SELECT spec.name AS specialization,
       COUNT(app.id) AS appointments_count,
       SUM(srv.price) AS revenue,
       ROUND(AVG(srv.price), 2) AS avg_price,
       MIN(srv.price) AS min_price,
       MAX(srv.price) AS max_price
FROM appointments app
INNER JOIN services srv ON srv.id = app.service_id
INNER JOIN specializations spec ON spec.id = srv.specialization_id
WHERE app.is_approved = TRUE
GROUP BY spec.name
ORDER BY revenue DESC;

-- Appointments per day, approved vs pending
SELECT app.date,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE app.is_approved) AS approved,
       COUNT(*) FILTER (WHERE NOT app.is_approved) AS pending
FROM appointments app
GROUP BY app.date
ORDER BY app.date;

-- Doctors with at least 2 approved appointments
SELECT acc.firstname, acc.lastname, COUNT(*) AS approved_count
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE app.is_approved = TRUE
GROUP BY doc.id, acc.firstname, acc.lastname
HAVING COUNT(*) >= 2;

-- Queue number of an appointment inside the doctor's day
SELECT acc.lastname AS doctor,
       app.date,
       app.time,
       ROW_NUMBER() OVER (PARTITION BY app.doctor_id, app.date
                          ORDER BY app.time) AS queue_number
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id;

-- Price rank of services inside their specialization
SELECT spec.name AS specialization,
       srv.name AS service,
       srv.price,
       RANK() OVER (PARTITION BY srv.specialization_id
                    ORDER BY srv.price DESC) AS price_rank
FROM services srv
INNER JOIN specializations spec ON spec.id = srv.specialization_id;

-- Doctors + administrators
SELECT acc.firstname, acc.lastname, 'Doctor' AS staff_type
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
UNION
SELECT acc.firstname, acc.lastname, 'Administrator'
FROM administrators adm
INNER JOIN accounts acc ON acc.id = adm.account_id;

-- Offices with doctors but without administrators, and offices that have both
SELECT office_id FROM doctors
EXCEPT
SELECT office_id FROM administrators;

SELECT office_id FROM doctors
INTERSECT
SELECT office_id FROM administrators;

-- COMPLEX OPERATIONS

-- Patients who already have at least one examination result
SELECT acc.firstname, acc.lastname
FROM patients pat
INNER JOIN accounts acc ON acc.id = pat.account_id
WHERE EXISTS (
    SELECT 1
    FROM appointments app
    INNER JOIN results res ON res.appointment_id = app.id
    WHERE app.patient_id = pat.id
);

-- Doctors without any appointment
SELECT acc.firstname, acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE NOT EXISTS (
    SELECT 1 FROM appointments app WHERE app.doctor_id = doc.id
);

-- New table: archive of past appointments
CREATE TABLE IF NOT EXISTS appointments_archive (
    LIKE appointments INCLUDING ALL,
    archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO appointments_archive (id, doctor_id, patient_id, service_id, date, time, is_approved)
SELECT id, doctor_id, patient_id, service_id, date, time, is_approved
FROM appointments
WHERE date < CURRENT_DATE
ON CONFLICT (id) DO NOTHING;

-- Price tiers of services
SELECT name, price,
       CASE
           WHEN price < 60  THEN 'Budget'
           WHEN price < 100 THEN 'Standard'
           ELSE 'Premium'
       END AS price_tier
FROM services
ORDER BY price;

-- EXPLAIN 

-- Filter by the indexed pair (doctor_id, date)
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE doctor_id = '77777777-0000-0000-0000-000000000001'
  AND date = '2026-10-01';

-- Filter by a column WITHOUT an index
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE service_id = '99999999-0000-0000-0000-000000000001';

-- Add an index and compare the plan(still seq)
CREATE INDEX IF NOT EXISTS idx_appointments_service ON appointments(service_id);
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE service_id = '99999999-0000-0000-0000-000000000001';

-- Plan of a JOIN + GROUP BY query
EXPLAIN ANALYZE
SELECT spec.name, COUNT(app.id), SUM(srv.price)
FROM appointments app
INNER JOIN services srv ON srv.id = app.service_id
INNER JOIN specializations spec ON spec.id = srv.specialization_id
GROUP BY spec.name;