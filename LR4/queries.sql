-- 1.1 Multiple conditions: approved appointments of the week, daytime,
--     expensive services OR any "Checkup"
SELECT app.id, app.date, app.time, srv.name AS service_name, srv.price
FROM appointments app
INNER JOIN services srv ON srv.id = app.service_id
WHERE app.is_approved = TRUE
  AND app.date BETWEEN '2026-10-01' AND '2026-10-07'
  AND app.time BETWEEN '09:00' AND '15:00'
  AND (srv.price >= 100 OR srv.name ILIKE '%Checkup%')
ORDER BY app.date, app.time;

-- 1.2 Multiple conditions: active senior doctors (net experience >= 15 years)
--     with a medical degree, excluding the Eastside office
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

-- 1.3 Nested (scalar subquery): who booked a service pricier than the
--     average price of active services
SELECT acc.firstname, acc.lastname, srv.name AS service_name, srv.price
FROM appointments app
INNER JOIN patients pat ON pat.id = app.patient_id
INNER JOIN accounts acc ON acc.id = pat.account_id
INNER JOIN services srv ON srv.id = app.service_id
WHERE srv.price > (SELECT AVG(price) FROM services WHERE is_active = TRUE)
ORDER BY srv.price DESC;

-- 1.4 Nested (NOT IN): doctors with NO work shift on 2026-10-02
SELECT acc.firstname, acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE doc.id NOT IN (
    SELECT doctor_id FROM schedules WHERE date = '2026-10-02'
);

-- 1.5 Nested (CTE + subquery): doctors whose workload is above average
WITH doctor_load AS (
    SELECT doctor_id, COUNT(*) AS appointments_count
    FROM appointments
    GROUP BY doctor_id
)
SELECT acc.firstname, acc.lastname, dl.appointments_count
FROM doctor_load dl
INNER JOIN doctors doc ON doc.id = dl.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE dl.appointments_count >= (SELECT AVG(appointments_count) FROM doctor_load)
ORDER BY dl.appointments_count DESC;

-- 1.6 Correlated subquery: services pricier than the average price
--     inside their OWN specialization
SELECT srv.name, srv.price, spec.name AS specialization
FROM services srv
INNER JOIN specializations spec ON spec.id = srv.specialization_id
WHERE srv.price > (
    SELECT AVG(s2.price)
    FROM services s2
    WHERE s2.specialization_id = srv.specialization_id
);

-- 1.7 Nested with ALL: services more expensive than EVERY pediatric service
SELECT name, price
FROM services
WHERE price > ALL (
    SELECT price FROM services
    WHERE specialization_id = (SELECT id FROM specializations WHERE name = 'Pediatrics')
);


-- =====================================================================
-- 2. VIEWS (JOIN of all kinds)
-- =====================================================================

-- 2.1 INNER JOIN: full doctor card (name, specialization, office, experience)
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

-- 2.2 INNER + LEFT JOIN: full appointment info; diagnosis is NULL
--     if the result has not been entered yet
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

-- appointments that still have no examination result
SELECT * FROM v_appointments_full WHERE diagnosis IS NULL;

-- 2.3 LEFT OUTER JOIN: staffing of every office (offices without admins stay in the list)
CREATE OR REPLACE VIEW v_offices_staffing AS
SELECT offc.id AS office_id,
       offc.address,
       COUNT(DISTINCT doc.id) AS doctors_count,
       COUNT(DISTINCT adm.id) AS admins_count
FROM offices offc
LEFT JOIN doctors doc ON doc.office_id = offc.id
LEFT JOIN administrators adm ON adm.office_id = offc.id
GROUP BY offc.id, offc.address;

SELECT * FROM v_offices_staffing WHERE admins_count = 0;

-- 2.4 RIGHT OUTER JOIN: all specializations, including those with no doctors
CREATE OR REPLACE VIEW v_specializations_doctors AS
SELECT spec.name AS specialization,
       acc.firstname,
       acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
RIGHT JOIN specializations spec ON spec.id = doc.specialization_id;

-- specializations nobody works in
SELECT specialization FROM v_specializations_doctors WHERE lastname IS NULL;

-- 2.5 FULL OUTER JOIN: consistency check - specializations that have doctors,
--     services, or both
CREATE OR REPLACE VIEW v_specialization_coverage AS
SELECT sp.name AS specialization,
       (d.specialization_id IS NOT NULL) AS has_doctors,
       (s.specialization_id IS NOT NULL) AS has_services
FROM (SELECT DISTINCT specialization_id FROM doctors) d
FULL OUTER JOIN (SELECT DISTINCT specialization_id FROM services) s
       ON s.specialization_id = d.specialization_id
INNER JOIN specializations sp
       ON sp.id = COALESCE(d.specialization_id, s.specialization_id);

SELECT * FROM v_specialization_coverage WHERE NOT (has_doctors AND has_services);

-- 2.6 CROSS JOIN: every patient x every active service they have NOT booked yet
--     (base for "recommended services")
CREATE OR REPLACE VIEW v_patient_service_candidates AS
SELECT pat.id AS patient_id,
       acc.firstname,
       acc.lastname,
       srv.id AS service_id,
       srv.name AS service_name,
       srv.price
FROM patients pat
INNER JOIN accounts acc ON acc.id = pat.account_id
CROSS JOIN services srv
WHERE srv.is_active = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM appointments app
      WHERE app.patient_id = pat.id AND app.service_id = srv.id
  );

SELECT * FROM v_patient_service_candidates
WHERE patient_id = '88888888-0000-0000-0000-000000000001';

-- 2.7 SELF JOIN: pairs of colleagues working in the same office
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


-- =====================================================================
-- 3. GROUPED DATA
-- =====================================================================

-- 3.1 GROUP BY + aggregates: statistics of approved appointments per specialization
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

-- 3.2 GROUP BY + LEFT JOIN: doctors count and average experience per office
SELECT offc.address,
       COUNT(doc.id) AS doctors_count,
       ROUND(AVG((CURRENT_DATE - doc.career_start_date) / 365.25
                 - doc.gap_in_months / 12.0), 1) AS avg_experience_years
FROM offices offc
LEFT JOIN doctors doc ON doc.office_id = offc.id
GROUP BY offc.id, offc.address
ORDER BY doctors_count DESC;

-- 3.3 GROUP BY + FILTER: appointments per day, approved vs pending
SELECT app.date,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE app.is_approved) AS approved,
       COUNT(*) FILTER (WHERE NOT app.is_approved) AS pending
FROM appointments app
GROUP BY app.date
ORDER BY app.date;

-- 3.4 HAVING: doctors with at least 2 approved appointments
SELECT acc.firstname, acc.lastname, COUNT(*) AS approved_count
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE app.is_approved = TRUE
GROUP BY doc.id, acc.firstname, acc.lastname
HAVING COUNT(*) >= 2;

-- 3.5 HAVING: service categories whose average service price exceeds 80
SELECT cat.name AS category,
       COUNT(srv.id) AS services_count,
       ROUND(AVG(srv.price), 2) AS avg_price
FROM service_categories cat
INNER JOIN services srv ON srv.service_category_id = cat.id
GROUP BY cat.id, cat.name
HAVING AVG(srv.price) > 80
ORDER BY avg_price DESC;

-- 3.6 Window: ROW_NUMBER - queue number of an appointment inside the doctor's day
SELECT acc.lastname AS doctor,
       app.date,
       app.time,
       ROW_NUMBER() OVER (PARTITION BY app.doctor_id, app.date
                          ORDER BY app.time) AS queue_number
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id;

-- 3.7 Window: RANK - price rank of services inside their specialization
SELECT spec.name AS specialization,
       srv.name AS service,
       srv.price,
       RANK() OVER (PARTITION BY srv.specialization_id
                    ORDER BY srv.price DESC) AS price_rank
FROM services srv
INNER JOIN specializations spec ON spec.id = srv.specialization_id;

-- 3.8 Window: running total of revenue per doctor
SELECT acc.lastname AS doctor,
       app.date,
       app.time,
       srv.price,
       SUM(srv.price) OVER (PARTITION BY app.doctor_id
                            ORDER BY app.date, app.time) AS running_revenue
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id
INNER JOIN services srv ON srv.id = app.service_id;

-- 3.9 Window: LAG - break between consecutive appointments of one doctor
SELECT app.doctor_id,
       app.date,
       app.time,
       LAG(app.time) OVER w AS prev_time,
       app.time - LAG(app.time) OVER w AS gap_since_previous
FROM appointments app
WINDOW w AS (PARTITION BY app.doctor_id, app.date ORDER BY app.time);

-- 3.10 GROUP BY + window: share of each doctor in the total clinic revenue
SELECT acc.lastname AS doctor,
       SUM(srv.price) AS revenue,
       ROUND(100.0 * SUM(srv.price) / SUM(SUM(srv.price)) OVER (), 1) AS revenue_share_pct
FROM appointments app
INNER JOIN doctors doc ON doc.id = app.doctor_id
INNER JOIN accounts acc ON acc.id = doc.account_id
INNER JOIN services srv ON srv.id = app.service_id
WHERE app.is_approved = TRUE
GROUP BY doc.id, acc.lastname
ORDER BY revenue DESC;

-- 3.11 UNION: unified staff directory (doctors + administrators)
SELECT acc.firstname, acc.lastname, 'Doctor' AS staff_type, doc.office_id
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
UNION
SELECT acc.firstname, acc.lastname, 'Administrator' AS staff_type, adm.office_id
FROM administrators adm
INNER JOIN accounts acc ON acc.id = adm.account_id
ORDER BY office_id, staff_type;

-- 3.12 EXCEPT / INTERSECT: offices with doctors but without administrators,
--      and offices that have both
SELECT office_id FROM doctors
EXCEPT
SELECT office_id FROM administrators;

SELECT office_id FROM doctors
INTERSECT
SELECT office_id FROM administrators;


-- =====================================================================
-- 4. COMPLEX OPERATIONS
-- =====================================================================

-- 4.1 EXISTS: patients who already have at least one examination result
SELECT acc.firstname, acc.lastname
FROM patients pat
INNER JOIN accounts acc ON acc.id = pat.account_id
WHERE EXISTS (
    SELECT 1
    FROM appointments app
    INNER JOIN results res ON res.appointment_id = app.id
    WHERE app.patient_id = pat.id
);

-- 4.2 NOT EXISTS: doctors without any appointment
SELECT acc.firstname, acc.lastname
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id
WHERE NOT EXISTS (
    SELECT 1 FROM appointments app WHERE app.doctor_id = doc.id
);

-- 4.3 NOT EXISTS: data validation - appointments outside the doctor's work shift
--     (expected: empty result)
SELECT app.id, app.doctor_id, app.date, app.time
FROM appointments app
WHERE NOT EXISTS (
    SELECT 1 FROM schedules sch
    WHERE sch.doctor_id = app.doctor_id
      AND sch.date = app.date
      AND app.time >= sch.start_time
      AND app.time < sch.end_time
);

-- 4.4 INSERT INTO SELECT: archive of past appointments
CREATE TABLE IF NOT EXISTS appointments_archive (
    LIKE appointments INCLUDING ALL,
    archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO appointments_archive (id, doctor_id, patient_id, service_id, date, time, is_approved)
SELECT id, doctor_id, patient_id, service_id, date, time, is_approved
FROM appointments
WHERE date < CURRENT_DATE
ON CONFLICT (id) DO NOTHING;

-- 4.5 INSERT INTO SELECT: copy all shifts of 2026-10-01 to the next week
--     (NOT EXISTS makes the script safe to run twice)
INSERT INTO schedules (id, doctor_id, date, start_time, end_time)
SELECT gen_random_uuid(), sch.doctor_id, sch.date + 7, sch.start_time, sch.end_time
FROM schedules sch
WHERE sch.date = '2026-10-01'
  AND NOT EXISTS (
      SELECT 1 FROM schedules s2
      WHERE s2.doctor_id = sch.doctor_id AND s2.date = sch.date + 7
  );

-- 4.6 CASE: price tiers of services
SELECT name, price,
       CASE
           WHEN price < 60  THEN 'Budget'
           WHEN price < 100 THEN 'Standard'
           ELSE 'Premium'
       END AS price_tier
FROM services
ORDER BY price;

-- 4.7 CASE: doctor seniority level
SELECT acc.lastname,
       ROUND((CURRENT_DATE - doc.career_start_date) / 365.25
             - doc.gap_in_months / 12.0, 1) AS experience_years,
       CASE
           WHEN (CURRENT_DATE - doc.career_start_date) / 365.25
                - doc.gap_in_months / 12.0 >= 20 THEN 'Senior'
           WHEN (CURRENT_DATE - doc.career_start_date) / 365.25
                - doc.gap_in_months / 12.0 >= 10 THEN 'Middle'
           ELSE 'Junior'
       END AS seniority
FROM doctors doc
INNER JOIN accounts acc ON acc.id = doc.account_id;

-- 4.8 CASE + LEFT JOIN: human-readable appointment status
SELECT app.id, app.date, app.time,
       CASE
           WHEN res.id IS NOT NULL THEN 'Completed'
           WHEN app.is_approved    THEN 'Approved, awaiting visit'
           ELSE 'Pending approval'
       END AS status
FROM appointments app
LEFT JOIN results res ON res.appointment_id = app.id
ORDER BY app.date, app.time;

-- 4.9 UPDATE with CASE: tiered price indexation
--     (in a transaction with ROLLBACK, so test data stays untouched)
BEGIN;
UPDATE services
SET price = ROUND(price * CASE
                              WHEN price < 60  THEN 1.10
                              WHEN price < 100 THEN 1.05
                              ELSE 1.03
                          END, 2)
WHERE is_active = TRUE
RETURNING id, name, price;
ROLLBACK;

-- 4.10 EXPLAIN: query plans
-- a) filter by the indexed pair (doctor_id, date)
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE doctor_id = '77777777-0000-0000-0000-000000000001'
  AND date = '2026-10-01';

-- b) the same, forcing the planner to avoid Seq Scan (tables are tiny, so by default
--    PostgreSQL prefers Seq Scan)
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE doctor_id = '77777777-0000-0000-0000-000000000001'
  AND date = '2026-10-01';
RESET enable_seqscan;

-- c) filter by a column WITHOUT an index (service_id) -> Seq Scan
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE service_id = '99999999-0000-0000-0000-000000000001';

-- d) add an index and compare the plan
CREATE INDEX IF NOT EXISTS idx_appointments_service ON appointments(service_id);
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT * FROM appointments
WHERE service_id = '99999999-0000-0000-0000-000000000001';
RESET enable_seqscan;

-- e) plan of a JOIN + GROUP BY query
EXPLAIN ANALYZE
SELECT spec.name, COUNT(app.id), SUM(srv.price)
FROM appointments app
INNER JOIN services srv ON srv.id = app.service_id
INNER JOIN specializations spec ON spec.id = srv.specialization_id
GROUP BY spec.name;
