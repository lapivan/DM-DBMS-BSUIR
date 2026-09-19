-- View system logs with pagination (page 2, 3 records per page)
SELECT * FROM audit_logs 
ORDER BY timestamp DESC 
OFFSET 3 LIMIT 3;

-- Count total number of active patients in the clinic
SELECT COUNT(*) FROM accounts 
WHERE role = 0 AND is_active = TRUE;

-- Search services by partial name match
SELECT id, name, price 
FROM services 
WHERE name ILIKE '%Checkup%';

-- Get all services belonging to the "Cardiology" specialization
SELECT id, name, price 
FROM services 
WHERE specialization_id IN (
    SELECT id FROM specializations WHERE name = 'Cardiology'
);

-- Find available schedule slots for all pediatricians on a specific date
SELECT id, doctor_id, start_time, end_time 
FROM schedules 
WHERE date = '2026-10-01' AND doctor_id IN (
    SELECT id FROM doctors WHERE specialization_id = (
        SELECT id FROM specializations WHERE name = 'Pediatrics'
    )
);

-- Get full info about upcoming appointments of a specific patient
SELECT 
    app.date, 
    app.time, 
    srv.name AS service_name, 
    srv.price, 
    app.is_approved
FROM appointments app
INNER JOIN services srv ON app.service_id = srv.id
INNER JOIN patients pat ON app.patient_id = pat.id
WHERE pat.id = '88888888-0000-0000-0000-000000000001'
ORDER BY app.date ASC, app.time ASC;

-- List doctors with their specialization and office address
SELECT 
    acc.firstname, 
    acc.lastname, 
    spec.name AS specialization, 
    offc.address
FROM doctors doc
INNER JOIN accounts acc ON doc.account_id = acc.id
INNER JOIN specializations spec ON doc.specialization_id = spec.id
INNER JOIN offices offc ON doc.office_id = offc.id
WHERE acc.is_active = TRUE;

-- User changes password in profile settings
UPDATE accounts 
SET password_hash = '$2a$12$new.secure.hash.generated.here.890' 
WHERE email = 'john.doe@gmail.com';

-- Admin increases price by 5% for all diagnostic procedures
UPDATE services 
SET price = price * 1.05 
WHERE service_category_id = (
    SELECT id FROM service_categories WHERE name = 'Diagnostic Procedures'
);

-- Find doctors with the longest work experience
SELECT account_id, career_start_date, gap_in_months
FROM doctors
ORDER BY (CURRENT_DATE - career_start_date - (gap_in_months * 30)) DESC
LIMIT 5;

-- Delete past work shifts from the schedule
DELETE FROM schedules 
WHERE date < CURRENT_DATE;

-- Cancel (delete) appointments not approved by admin before the appointment date
DELETE FROM appointments 
WHERE is_approved = FALSE AND date <= CURRENT_DATE;