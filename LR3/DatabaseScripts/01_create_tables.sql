CREATE TABLE IF NOT EXISTS photos (
	id UUID PRIMARY KEY,
	url VARCHAR(500) NOT NULL
);

CREATE TABLE IF NOT EXISTS service_categories (
	id UUID PRIMARY KEY,
	name VARCHAR(100) NOT NULL UNIQUE,
	duration INTERVAL NOT NULL
);

CREATE TABLE IF NOT EXISTS specializations (
	id UUID PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS offices (
	id UUID PRIMARY KEY,
    address VARCHAR(256) NOT NULL,
    phone_number VARCHAR(20) UNIQUE,
	photo_id UUID REFERENCES photos(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS accounts (
	id UUID PRIMARY KEY,
    email VARCHAR(256) NOT NULL UNIQUE,
    password_hash VARCHAR(256) NOT NULL,
    phone_number VARCHAR(20) UNIQUE,
    firstname VARCHAR(50) NOT NULL,
    lastname VARCHAR(50) NOT NULL,
	birthday DATE NOT NULL CHECK (birthday <= CURRENT_DATE),
	role INT NOT NULL CHECK(role IN (0, 1, 2)),
	photo_id UUID REFERENCES photos(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS patients (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS doctors (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
    specialization_id UUID NOT NULL REFERENCES specializations(id) ON DELETE RESTRICT,
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE RESTRICT,
    career_start_date DATE NOT NULL CHECK (career_start_date <= CURRENT_DATE),
    gap_in_months SMALLINT NOT NULL DEFAULT 0 CHECK (gap_in_months >= 0),
    degree VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS administrators (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE RESTRICT,
    career_start_date DATE NOT NULL CHECK (career_start_date <= CURRENT_DATE),
    gap_in_months SMALLINT NOT NULL DEFAULT 0 CHECK (gap_in_months >= 0)
);

CREATE TABLE IF NOT EXISTS services (
    id UUID PRIMARY KEY,
    specialization_id UUID NOT NULL REFERENCES specializations(id) ON DELETE RESTRICT,
    service_category_id UUID NOT NULL REFERENCES service_categories(id) ON DELETE RESTRICT,
    name VARCHAR(100) NOT NULL UNIQUE,
    price NUMERIC(18, 2) NOT NULL CHECK (price >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS schedules (
    id UUID PRIMARY KEY,
    doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    CONSTRAINT chk_schedule_times CHECK (end_time > start_time)
);

CREATE TABLE IF NOT EXISTS appointments (
    id UUID PRIMARY KEY,
    doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE RESTRICT,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
    service_id UUID NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
    date DATE NOT NULL,
    time TIME NOT NULL CHECK (time >= '00:00:00' AND time <= '23:59:59'),
    is_approved BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS results (
    id UUID PRIMARY KEY,
    appointment_id UUID NOT NULL UNIQUE REFERENCES appointments(id) ON DELETE CASCADE,
    complaints TEXT,
    diagnosis TEXT,
    recommendations TEXT
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY,
    account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_name VARCHAR(100),
    entity_id UUID,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email);
CREATE INDEX IF NOT EXISTS idx_accounts_phone ON accounts(phone_number);

CREATE INDEX IF NOT EXISTS idx_doctors_specialization ON doctors(specialization_id);
CREATE INDEX IF NOT EXISTS idx_doctors_office ON doctors(office_id);

CREATE INDEX IF NOT EXISTS idx_services_specialization ON services(specialization_id);
CREATE INDEX IF NOT EXISTS idx_services_category ON services(service_category_id);

CREATE INDEX IF NOT EXISTS idx_schedules_doctor_date ON schedules(doctor_id, date);

CREATE INDEX IF NOT EXISTS idx_appointments_doctor_date ON appointments(doctor_id, date);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_account ON audit_logs(account_id);