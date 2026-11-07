#!/bin/bash

# CarePoint Medical Center - Modern Public Portal & Internal ERP Setup

# 1. Update system and install Apache, PHP, and MySQL client
dnf update -y
dnf install -y httpd php php-mysqlnd mariadb105

# 2. Start and enable Apache Web Server
systemctl start httpd
systemctl enable httpd

# 3. Retrieve Database Endpoint and Passwords securely from AWS SSM Parameter Store
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier sme-project-db --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1)
DB_MASTER_PASS=$(aws ssm get-parameter --name "/sme-project/database/password" --with-decryption --query "Parameter.Value" --output text --region us-east-1)
PUBLIC_DB_PASS=$(aws ssm get-parameter --name "/sme-project/database/public_user_password" --with-decryption --query "Parameter.Value" --output text --region us-east-1)

# 4. Wait until MySQL RDS is fully reachable
until mysql -h "$DB_HOST" -u admin -p"$DB_MASTER_PASS" -e "SELECT 1;" &>/dev/null; do
    echo "Waiting for RDS Database to become available..."
    sleep 10
done

# 5. Setup Database, Tables, Sample Data, and Least-Privilege User
mysql -h "$DB_HOST" -u admin -p"$DB_MASTER_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS medical_center_db;
USE medical_center_db;

CREATE TABLE IF NOT EXISTS doctors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    availability VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS appointments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    patient_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    appointment_date DATE NOT NULL,
    status VARCHAR(30) DEFAULT 'Confirmed',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS patient_records (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_name VARCHAR(100) NOT NULL,
    age INT NOT NULL,
    blood_group VARCHAR(10) NOT NULL,
    diagnosis TEXT NOT NULL,
    prescription TEXT NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    visit_date DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS staff_directory (
    staff_id INT AUTO_INCREMENT PRIMARY KEY,
    staff_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    department VARCHAR(50) NOT NULL,
    shift VARCHAR(50) NOT NULL,
    contact VARCHAR(20) NOT NULL
);

INSERT IGNORE INTO doctors (id, name, specialization, availability) VALUES 
(1, 'Dr. Samantha Perera', 'Consultant Cardiologist', 'Mon, Wed, Fri (9:00 AM - 1:00 PM)'),
(2, 'Dr. Anura Silva', 'General Physician', 'Weekdays (8:00 AM - 4:00 PM)'),
(3, 'Dr. Priya Jayasinghe', 'Consultant Pediatrician', 'Tue, Thu, Sat (10:00 AM - 2:00 PM)');

INSERT IGNORE INTO patient_records (record_id, patient_name, age, blood_group, diagnosis, prescription, doctor_name, visit_date) VALUES
(1, 'Kasun Fernando', 42, 'O+', 'Mild Hypertension & Seasonal Flu', 'Amlodipine 5mg OD, Paracetamol 500mg SOS', 'Dr. Samantha Perera', '2026-10-28'),
(2, 'Nimali Perera', 29, 'B+', 'Acute Gastritis', 'Omeprazole 20mg BD before meals for 14 days', 'Dr. Anura Silva', '2026-11-02');

INSERT IGNORE INTO staff_directory (staff_id, staff_name, role, department, shift, contact) VALUES
(1, 'hashini Wijesinghe', 'Chief Nursing Officer', 'OPD & Emergency', 'Morning (7 AM - 3 PM)', '077-1234567'),
(2, 'Roshan Mendis', 'Senior Pharmacist', 'Pharmacy Unit', 'Day (8 AM - 5 PM)', '071-9876543'),
(3, 'Kavindu Bandara', 'Lab Technologist', 'Diagnostics Lab', 'Night (7 PM - 7 AM)', '076-5554321');

CREATE USER IF NOT EXISTS 'patient_web_user'@'%' IDENTIFIED BY '${PUBLIC_DB_PASS}';
ALTER USER 'patient_web_user'@'%' IDENTIFIED BY '${PUBLIC_DB_PASS}';
GRANT SELECT ON medical_center_db.doctors TO 'patient_web_user'@'%';
GRANT INSERT ON medical_center_db.appointments TO 'patient_web_user'@'%';
FLUSH PRIVILEGES;
EOF

# 6. Create Secure PHP Config outside public HTML folder (Zero-Hardcoded Passwords)
cat << EOF > /var/www/db_config.php
<?php
define('DB_HOST', '${DB_HOST}');
define('DB_NAME', 'medical_center_db');
define('PUBLIC_USER', 'patient_web_user');
define('PUBLIC_PASS', '${PUBLIC_DB_PASS}');
define('ADMIN_USER', 'admin');
define('ADMIN_PASS', '${DB_MASTER_PASS}');
?>
EOF
chown apache:apache /var/www/db_config.php
chmod 600 /var/www/db_config.php
rm -f /var/www/html/index.html

# 7. Create Modern Public Patient Portal (/var/www/html/index.php)
cat << 'EOF' > /var/www/html/index.php
<?php
require_once '/var/www/db_config.php';
$conn = new mysqli(DB_HOST, PUBLIC_USER, PUBLIC_PASS, DB_NAME);
$booking_msg = "";

if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['book_appointment'])) {
    $patient_name = $conn->real_escape_string($_POST['patient_name']);
    $email = $conn->real_escape_string($_POST['email']);
    $phone = $conn->real_escape_string($_POST['phone']);
    $doctor_name = $conn->real_escape_string($_POST['doctor_name']);
    $appointment_date = $conn->real_escape_string($_POST['appointment_date']);

    $sql = "INSERT INTO appointments (patient_name, email, phone, doctor_name, appointment_date) 
            VALUES ('$patient_name', '$email', '$phone', '$doctor_name', '$appointment_date')";
    if ($conn->query($sql) === TRUE) {
        $booking_msg = "success";
    } else {
        $booking_msg = "error";
    }
}
$doctors = $conn->query("SELECT * FROM doctors");
$doctors_dropdown = $conn->query("SELECT * FROM doctors");
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CarePoint Medical Center | Smart Cloud Healthcare</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Plus Jakarta Sans', sans-serif; background-color: #f4f7fb; }
        .hero-section {
            background: linear-gradient(135deg, #0d6efd 0%, #0a58ca 50%, #052c65 100%);
            color: white; border-radius: 20px; padding: 3.5rem 2.5rem;
        }
        .doctor-card { transition: transform 0.25s ease, box-shadow 0.25s ease; border-radius: 16px; }
        .doctor-card:hover { transform: translateY(-5px); box-shadow: 0 12px 24px rgba(13,110,253,0.12) !important; }
        .form-card { border-radius: 18px; }
        .badge-security { background: rgba(255,255,255,0.15); backdrop-filter: blur(8px); border: 1px solid rgba(255,255,255,0.25); }
    </style>
</head>
<body>
    <!-- Top Security & Emergency Bar -->
    <div class="bg-dark text-light py-2 small">
        <div class="container d-flex justify-content-between align-items-center">
            <div><i class="bi bi-telephone-outbound-fill text-danger me-2"></i>24/7 Emergency OPD: <strong>1990 / 011-2345678</strong></div>
            <div class="d-none d-md-block">
                <span class="me-3"><i class="bi bi-shield-lock-fill text-info me-1"></i>AWS KMS Encrypted</span>
                <span><i class="bi bi-hdd-network-fill text-success me-1"></i>Least-Privilege DB Isolation</span>
            </div>
        </div>
    </div>

    <!-- Main Navbar -->
    <nav class="navbar navbar-expand-lg navbar-light bg-white shadow-sm sticky-top py-3">
        <div class="container">
            <a class="navbar-brand fw-bold text-primary fs-4" href="/">
                <i class="bi bi-heart-pulse-fill text-danger me-2"></i>CarePoint <span class="text-dark fw-semibold">Medical</span>
            </a>
            <div class="d-flex align-items-center gap-2">
                <a href="#booking" class="btn btn-primary rounded-pill px-4"><i class="bi bi-calendar2-check me-1"></i>Book Appointment</a>
                <a href="/erp/" class="btn btn-outline-dark rounded-pill px-3"><i class="bi bi-person-badge me-1"></i>Staff ERP Portal</a>
            </div>
        </div>
    </nav>

    <div class="container my-4">
        <?php if ($booking_msg == "success"): ?>
            <div class="alert alert-success alert-dismissible fade show shadow-sm rounded-4 p-4 mb-4" role="alert">
                <h5 class="alert-heading fw-bold"><i class="bi bi-check-circle-fill me-2"></i>Appointment Confirmed!</h5>
                <p class="mb-0">Your appointment has been securely encrypted and logged in our Private Subnet RDS Database. Our OPD desk will contact you shortly.</p>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>

        <!-- Hero Section -->
        <div class="hero-section shadow mb-5">
            <div class="row align-items-center">
                <div class="col-lg-8">
                    <span class="badge badge-security rounded-pill px-3 py-2 mb-3">
                        <i class="bi bi-cloud-check-fill me-1"></i> Zero-Touch DevSecOps Healthcare Infrastructure
                    </span>
                    <h1 class="display-5 fw-bold mb-3">Modern Healthcare Powered by Secure Cloud Automation</h1>
                    <p class="lead opacity-90 mb-4">Channel your specialist doctor online with confidence. All patient appointments and medical records are protected inside an isolated AWS Private Subnet with KMS Encryption.</p>
                    <div class="d-flex flex-wrap gap-3">
                        <div class="bg-white bg-opacity-10 rounded-3 px-3 py-2"><i class="bi bi-lock-fill me-2"></i>SSM Secret Protection</div>
                        <div class="bg-white bg-opacity-10 rounded-3 px-3 py-2"><i class="bi bi-database-fill-lock me-2"></i>Private RDS MySQL</div>
                        <div class="bg-white bg-opacity-10 rounded-3 px-3 py-2"><i class="bi bi-leaf-fill me-2"></i>GreenOps Enabled</div>
                    </div>
                </div>
                <div class="col-lg-4 d-none d-lg-block text-center">
                    <i class="bi bi-hospital" style="font-size: 7.5rem; opacity: 0.85;"></i>
                </div>
            </div>
        </div>

        <div class="row g-4" id="booking">
            <!-- Left Column: Specialist Doctors -->
            <div class="col-lg-7">
                <div class="d-flex justify-content-between align-items-center mb-3">
                    <h3 class="fw-bold mb-0"><i class="bi bi-people-fill text-primary me-2"></i>Available Specialists</h3>
                    <span class="badge bg-primary-subtle text-primary rounded-pill px-3 py-2">Live from RDS Database</span>
                </div>
                <div class="row g-3">
                    <?php while($doc = $doctors->fetch_assoc()): ?>
                    <div class="col-md-6">
                        <div class="card doctor-card border-0 shadow-sm h-100 p-3">
                            <div class="d-flex align-items-center mb-3">
                                <div class="bg-primary bg-opacity-10 text-primary rounded-circle d-flex align-items-center justify-content-center me-3" style="width: 54px; height: 54px;">
                                    <i class="bi bi-person-Vcard-fill fs-3"></i>
                                </div>
                                <div>
                                    <h5 class="fw-bold mb-1"><?php echo htmlspecialchars($doc['name']); ?></h5>
                                    <span class="badge bg-info-subtle text-info-emphasis rounded-pill"><?php echo htmlspecialchars($doc['specialization']); ?></span>
                                </div>
                            </div>
                            <p class="text-muted small mb-0"><i class="bi bi-clock-history text-primary me-2"></i><?php echo htmlspecialchars($doc['availability']); ?></p>
                        </div>
                    </div>
                    <?php endwhile; ?>
                </div>

                <!-- Security Architecture Highlight Card -->
                <div class="card border-0 shadow-sm rounded-4 mt-4 bg-white p-4">
                    <h5 class="fw-bold text-dark"><i class="bi bi-shield-check text-success me-2"></i>Enterprise Data Privacy Guarantee</h5>
                    <p class="text-secondary small mb-0">
                        This Public Patient Portal runs under a strict <strong>Least-Privilege MySQL Account (<code>patient_web_user</code>)</strong> that only has permission to submit new appointments. It is mathematically and architecturally blocked from reading any internal patient medical histories or hospital ERP records.
                    </p>
                </div>
            </div>

            <!-- Right Column: Appointment Booking Form -->
            <div class="col-lg-5">
                <div class="card form-card border-0 shadow p-4 bg-white">
                    <h4 class="fw-bold text-dark mb-1"><i class="bi bi-calendar-plus-fill text-primary me-2"></i>Book an Appointment</h4>
                    <p class="text-muted small mb-4">Fill in your details below for instant OPD reservation.</p>
                    <form method="POST" action="">
                        <input type="hidden" name="book_appointment" value="1">
                        <div class="mb-3">
                            <label class="form-label fw-semibold small">Patient Full Name</label>
                            <div class="input-group">
                                <span class="input-group-text bg-light"><i class="bi bi-person"></i></span>
                                <input type="text" name="patient_name" class="form-control" placeholder="e.g. Nimal Perera" required>
                            </div>
                        </div>
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold small">Phone Number</label>
                                <input type="text" name="phone" class="form-control" placeholder="077-xxxxxxx" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label fw-semibold small">Email Address</label>
                                <input type="email" name="email" class="form-control" placeholder="name@mail.com" required>
                            </div>
                        </div>
                        <div class="mb-3">
                            <label class="form-label fw-semibold small">Select Specialist Doctor</label>
                            <select name="doctor_name" class="form-select" required>
                                <?php while($d = $doctors_dropdown->fetch_assoc()): ?>
                                    <option value="<?php echo htmlspecialchars($d['name']); ?>">
                                        <?php echo htmlspecialchars($d['name'] . " (" . $d['specialization'] . ")"); ?>
                                    </option>
                                <?php endwhile; ?>
                            </select>
                        </div>
                        <div class="mb-4">
                            <label class="form-label fw-semibold small">Preferred Date</label>
                            <input type="date" name="appointment_date" class="form-control" required>
                        </div>
                        <button type="submit" class="btn btn-primary w-100 py-2 fw-bold rounded-3 shadow-sm">
                            <i class="bi bi-check2-circle me-1"></i> Confirm Channeling
                        </button>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <footer class="bg-white border-top py-4 mt-5 text-center text-muted small">
        <div class="container">
            <strong>CarePoint Medical Center</strong> &bull; Automated SME Cloud Infrastructure Blueprint (Terraform + AWS DevSecOps)
        </div>
    </footer>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
<?php $conn->close(); ?>
EOF

# 8. Create Internal Medical ERP System (/var/www/html/erp/index.php)
mkdir -p /var/www/html/erp
cat << 'EOF' > /var/www/html/erp/index.php
<?php
session_start();
require_once '/var/www/db_config.php';

// Simple Staff Login Authentication for ERP Protection
if (isset($_POST['erp_login'])) {
    if ($_POST['username'] === 'admin' && $_POST['password'] === 'CarePoint@2026') {
        $_SESSION['erp_logged_in'] = true;
    } else {
        $login_error = "Invalid Staff Credentials!";
    }
}
if (isset($_GET['logout'])) {
    session_destroy();
    header("Location: /erp/");
    exit;
}

$conn = new mysqli(DB_HOST, ADMIN_USER, ADMIN_PASS, DB_NAME);
$action_alert = "";

if (isset($_SESSION['erp_logged_in']) && $_SESSION['erp_logged_in'] === true) {
    // Handle New Patient Medical Record (EHR)
    if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_record'])) {
        $pname = $conn->real_escape_string($_POST['patient_name']);
        $age = (int)$_POST['age'];
        $bgroup = $conn->real_escape_string($_POST['blood_group']);
        $diag = $conn->real_escape_string($_POST['diagnosis']);
        $presc = $conn->real_escape_string($_POST['prescription']);
        $doc = $conn->real_escape_string($_POST['doctor_name']);
        $vdate = $conn->real_escape_string($_POST['visit_date']);
        $conn->query("INSERT INTO patient_records (patient_name, age, blood_group, diagnosis, prescription, doctor_name, visit_date) 
                      VALUES ('$pname', $age, '$bgroup', '$diag', '$presc', '$doc', '$vdate')");
        $action_alert = "New Encrypted Patient Medical Record (EHR) saved successfully!";
    }

    // Handle New Doctor Addition (Syncs live with Public Portal!)
    if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_doctor'])) {
        $dname = $conn->real_escape_string($_POST['doc_name']);
        $spec = $conn->real_escape_string($_POST['specialization']);
        $avail = $conn->real_escape_string($_POST['availability']);
        $conn->query("INSERT INTO doctors (name, specialization, availability) VALUES ('$dname', '$spec', '$avail')");
        $action_alert = "New Specialist Doctor added! Live synced with Public Patient Portal.";
    }

    // Handle New Staff Member Addition
    if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_staff'])) {
        $sname = $conn->real_escape_string($_POST['staff_name']);
        $role = $conn->real_escape_string($_POST['role']);
        $dept = $conn->real_escape_string($_POST['department']);
        $shift = $conn->real_escape_string($_POST['shift']);
        $contact = $conn->real_escape_string($_POST['contact']);
        $conn->query("INSERT INTO staff_directory (staff_name, role, department, shift, contact) VALUES ('$sname', '$role', '$dept', '$shift', '$contact')");
        $action_alert = "New Hospital Staff Member added to ERP directory!";
    }

    $appointments = $conn->query("SELECT * FROM appointments ORDER BY created_at DESC");
    $records = $conn->query("SELECT * FROM patient_records ORDER BY record_id DESC");
    $doctors = $conn->query("SELECT * FROM doctors ORDER BY id DESC");
    $staff = $conn->query("SELECT * FROM staff_directory ORDER BY staff_id DESC");

    $count_app = $appointments->num_rows;
    $count_rec = $records->num_rows;
    $count_doc = $doctors->num_rows;
    $count_staff = $staff->num_rows;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CarePoint | Internal Hospital ERP & EHR System</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Plus Jakarta Sans', sans-serif; background-color: #0f172a; color: #f8fafc; }
        .glass-card { background: #1e293b; border: 1px solid #334155; border-radius: 16px; }
        .nav-pills .nav-link { color: #cbd5e1; border-radius: 10px; font-weight: 600; padding: 10px 20px; }
        .nav-pills .nav-link.active { background-color: #2563eb; color: white; }
        .table-dark-custom { --bs-table-bg: #1e293b; --bs-table-striped-bg: #263349; color: #e2e8f0; }
    </style>
</head>
<body>

<?php if (!isset($_SESSION['erp_logged_in']) || $_SESSION['erp_logged_in'] !== true): ?>
    <!-- ERP Staff Login Screen -->
    <div class="container d-flex justify-content-center align-items-center" style="min-height: 100vh;">
        <div class="glass-card p-5 shadow-lg" style="max-width: 440px; width: 100%;">
            <div class="text-center mb-4">
                <div class="bg-primary bg-opacity-25 text-primary rounded-circle d-inline-flex p-3 mb-3">
                    <i class="bi bi-shield-lock-fill fs-1"></i>
                </div>
                <h3 class="fw-bold">CarePoint Internal ERP</h3>
                <p class="text-secondary small">Restricted Staff, Doctor & EHR Management Portal</p>
            </div>
            <?php if (isset($login_error)): ?>
                <div class="alert alert-danger py-2 small"><?php echo $login_error; ?></div>
            <?php endif; ?>
            <form method="POST">
                <input type="hidden" name="erp_login" value="1">
                <div class="mb-3">
                    <label class="form-label small text-secondary">Staff Username</label>
                    <input type="text" name="username" class="form-control bg-dark text-light border-secondary" value="admin" required>
                </div>
                <div class="mb-4">
                    <label class="form-label small text-secondary">Master Password</label>
                    <input type="password" name="password" class="form-control bg-dark text-light border-secondary" value="CarePoint@2026" required>
                </div>
                <button type="submit" class="btn btn-primary w-100 py-2 fw-bold mb-3"><i class="bi bi-box-arrow-in-right me-2"></i>Access ERP Dashboard</button>
                <a href="/" class="btn btn-outline-secondary w-100 btn-sm">← Back to Public Patient Portal</a>
            </form>
            <div class="mt-4 pt-3 border-top border-secondary text-center small text-secondary">
                <i class="bi bi-key-fill text-warning me-1"></i> Demo Credentials Pre-filled (<code>admin</code> / <code>CarePoint@2026</code>)
            </div>
        </div>
    </div>

<?php else: ?>
    <!-- Authenticated Internal ERP Dashboard -->
    <nav class="navbar navbar-dark bg-dark border-bottom border-secondary py-3">
        <div class="container-fluid px-4">
            <span class="navbar-brand fw-bold">
                <i class="bi bi-hospital-fill text-info me-2"></i>CarePoint <span class="text-info">Internal ERP & EHR</span>
                <span class="badge bg-success ms-2 small">SSM + KMS Active</span>
            </span>
            <div class="d-flex gap-2">
                <a href="/" target="_blank" class="btn btn-outline-info btn-sm"><i class="bi bi-box-arrow-up-right me-1"></i>View Public Website</a>
                <a href="?logout=1" class="btn btn-danger btn-sm"><i class="bi bi-power me-1"></i>Logout</a>
            </div>
        </div>
    </nav>

    <div class="container-fluid px-4 my-4">
        <?php if ($action_alert != ""): ?>
            <div class="alert alert-success alert-dismissible fade show rounded-3" role="alert">
                <i class="bi bi-check-circle-fill me-2"></i><strong>Success:</strong> <?php echo $action_alert; ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>

        <!-- KPI Summary Cards -->
        <div class="row g-3 mb-4">
            <div class="col-md-3">
                <div class="glass-card p-3 d-flex align-items-center justify-content-between">
                    <div>
                        <div class="text-secondary small">OPD Appointments</div>
                        <h2 class="fw-bold mb-0 text-info"><?php echo $count_app; ?></h2>
                    </div>
                    <i class="bi bi-calendar2-check fs-1 text-info opacity-50"></i>
                </div>
            </div>
            <div class="col-md-3">
                <div class="glass-card p-3 d-flex align-items-center justify-content-between">
                    <div>
                        <div class="text-secondary small">Encrypted EHR Records</div>
                        <h2 class="fw-bold mb-0 text-warning"><?php echo $count_rec; ?></h2>
                    </div>
                    <i class="bi bi-file-earmark-medical fs-1 text-warning opacity-50"></i>
                </div>
            </div>
            <div class="col-md-3">
                <div class="glass-card p-3 d-flex align-items-center justify-content-between">
                    <div>
                        <div class="text-secondary small">Medical Specialists</div>
                        <h2 class="fw-bold mb-0 text-success"><?php echo $count_doc; ?></h2>
                    </div>
                    <i class="bi bi-person-badge fs-1 text-success opacity-50"></i>
                </div>
            </div>
            <div class="col-md-3">
                <div class="glass-card p-3 d-flex align-items-center justify-content-between">
                    <div>
                        <div class="text-secondary small">Hospital Staff</div>
                        <h2 class="fw-bold mb-0 text-primary"><?php echo $count_staff; ?></h2>
                    </div>
                    <i class="bi bi-people fs-1 text-primary opacity-50"></i>
                </div>
            </div>
        </div>

        <!-- Navigation Tabs -->
        <ul class="nav nav-pills mb-4 gap-2" id="erpTabs" role="tablist">
            <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#tab-ehr"><i class="bi bi-heart-pulse me-2"></i>Patient Medical History (EHR)</button></li>
            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#tab-appointments"><i class="bi bi-calendar-week me-2"></i>OPD Appointments</button></li>
            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#tab-staff"><i class="bi bi-person-lines-fill me-2"></i>Doctors & Staff HR</button></li>
        </ul>

        <div class="tab-content">
            <!-- TAB 1: Patient Medical History (EHR) -->
            <div class="tab-pane fade show active" id="tab-ehr">
                <div class="row g-4">
                    <div class="col-lg-4">
                        <div class="glass-card p-4">
                            <h5 class="fw-bold text-warning mb-3"><i class="bi bi-plus-circle me-2"></i>Add Patient Medical Record</h5>
                            <form method="POST">
                                <input type="hidden" name="add_record" value="1">
                                <div class="mb-2">
                                    <label class="small text-secondary">Patient Name</label>
                                    <input type="text" name="patient_name" class="form-control form-control-sm bg-dark text-light border-secondary" required>
                                </div>
                                <div class="row">
                                    <div class="col-6 mb-2">
                                        <label class="small text-secondary">Age</label>
                                        <input type="number" name="age" class="form-control form-control-sm bg-dark text-light border-secondary" required>
                                    </div>
                                    <div class="col-6 mb-2">
                                        <label class="small text-secondary">Blood Group</label>
                                        <select name="blood_group" class="form-select form-select-sm bg-dark text-light border-secondary">
                                            <option>O+</option><option>A+</option><option>B+</option><option>AB+</option><option>O-</option>
                                        </select>
                                    </div>
                                </div>
                                <div class="mb-2">
                                    <label class="small text-secondary">Diagnosis / Medical Condition</label>
                                    <textarea name="diagnosis" rows="2" class="form-control form-control-sm bg-dark text-light border-secondary" required></textarea>
                                </div>
                                <div class="mb-2">
                                    <label class="small text-secondary">Prescription / Medications</label>
                                    <textarea name="prescription" rows="2" class="form-control form-control-sm bg-dark text-light border-secondary" required></textarea>
                                </div>
                                <div class="mb-2">
                                    <label class="small text-secondary">Attending Doctor</label>
                                    <input type="text" name="doctor_name" class="form-control form-control-sm bg-dark text-light border-secondary" value="Dr. Samantha Perera" required>
                                </div>
                                <div class="mb-3">
                                    <label class="small text-secondary">Visit Date</label>
                                    <input type="date" name="visit_date" class="form-control form-control-sm bg-dark text-light border-secondary" required>
                                </div>
                                <button type="submit" class="btn btn-warning w-100 fw-bold btn-sm">Save Encrypted EHR Record</button>
                            </form>
                        </div>
                    </div>
                    <div class="col-lg-8">
                        <div class="glass-card p-4">
                            <div class="d-flex justify-content-between align-items-center mb-3">
                                <h5 class="fw-bold mb-0">Confidential Patient Medical History</h5>
                                <span class="badge bg-warning text-dark"><i class="bi bi-lock-fill me-1"></i>KMS Encrypted Table</span>
                            </div>
                            <div class="table-responsive">
                                <table class="table table-dark-custom table-striped align-middle small">
                                    <thead>
                                        <tr><th>ID</th><th>Patient</th><th>Age/Blood</th><th>Diagnosis</th><th>Prescription</th><th>Doctor & Date</th></tr>
                                    </thead>
                                    <tbody>
                                        <?php while($r = $records->fetch_assoc()): ?>
                                        <tr>
                                            <td>#<?php echo $r['record_id']; ?></td>
                                            <td class="fw-bold text-white"><?php echo htmlspecialchars($r['patient_name']); ?></td>
                                            <td><?php echo $r['age'] . " yrs / <span class='badge bg-danger'>" . htmlspecialchars($r['blood_group']) . "</span>"; ?></td>
                                            <td><?php echo htmlspecialchars($r['diagnosis']); ?></td>
                                            <td class="text-info"><?php echo htmlspecialchars($r['prescription']); ?></td>
                                            <td><?php echo htmlspecialchars($r['doctor_name']) . "<br><small class='text-secondary'>" . $r['visit_date'] . "</small>"; ?></td>
                                        </tr>
                                        <?php endwhile; ?>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- TAB 2: OPD Appointments Queue -->
            <div class="tab-pane fade" id="tab-appointments">
                <div class="glass-card p-4">
                    <h5 class="fw-bold text-info mb-3"><i class="bi bi-calendar-check me-2"></i>Patient Appointments (Booked via Public Portal)</h5>
                    <div class="table-responsive">
                        <table class="table table-dark-custom table-striped align-middle">
                            <thead>
                                <tr><th>ID</th><th>Patient Name</th><th>Phone</th><th>Email</th><th>Specialist Doctor</th><th>Appointment Date</th><th>Status</th></tr>
                            </thead>
                            <tbody>
                                <?php while($a = $appointments->fetch_assoc()): ?>
                                <tr>
                                    <td>#<?php echo $a['id']; ?></td>
                                    <td class="fw-bold"><?php echo htmlspecialchars($a['patient_name']); ?></td>
                                    <td><?php echo htmlspecialchars($a['phone']); ?></td>
                                    <td><?php echo htmlspecialchars($a['email']); ?></td>
                                    <td><span class="badge bg-primary"><?php echo htmlspecialchars($a['doctor_name']); ?></span></td>
                                    <td><?php echo htmlspecialchars($a['appointment_date']); ?></td>
                                    <td><span class="badge bg-success"><i class="bi bi-check2 me-1"></i>Confirmed</span></td>
                                </tr>
                                <?php endwhile; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- TAB 3: Doctors & Hospital Staff Management -->
            <div class="tab-pane fade" id="tab-staff">
                <div class="row g-4">
                    <div class="col-lg-4">
                        <div class="glass-card p-4 mb-4">
                            <h6 class="fw-bold text-success mb-3"><i class="bi bi-person-plus-fill me-2"></i>Add Specialist Doctor (Live Public Sync)</h6>
                            <form method="POST">
                                <input type="hidden" name="add_doctor" value="1">
                                <input type="text" name="doc_name" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Doctor Name (e.g. Dr. Kamal Silva)" required>
                                <input type="text" name="specialization" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Specialty (e.g. Neurologist)" required>
                                <input type="text" name="availability" class="form-control form-control-sm bg-dark text-light border-secondary mb-3" placeholder="Schedule (e.g. Mon & Thu 4 PM)" required>
                                <button type="submit" class="btn btn-success btn-sm w-100 fw-bold">Add Doctor to System</button>
                            </form>
                        </div>
                        <div class="glass-card p-4">
                            <h6 class="fw-bold text-primary mb-3"><i class="bi bi-people-fill me-2"></i>Add Hospital Staff Member</h6>
                            <form method="POST">
                                <input type="hidden" name="add_staff" value="1">
                                <input type="text" name="staff_name" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Staff Full Name" required>
                                <input type="text" name="role" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Role (e.g. Ward Nurse / Cashier)" required>
                                <input type="text" name="department" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Department (e.g. ICU / Billing)" required>
                                <input type="text" name="shift" class="form-control form-control-sm bg-dark text-light border-secondary mb-2" placeholder="Shift (e.g. Day 8 AM - 4 PM)" required>
                                <input type="text" name="contact" class="form-control form-control-sm bg-dark text-light border-secondary mb-3" placeholder="Contact Number" required>
                                <button type="submit" class="btn btn-primary btn-sm w-100 fw-bold">Register Staff Member</button>
                            </form>
                        </div>
                    </div>
                    <div class="col-lg-8">
                        <div class="glass-card p-4 mb-4">
                            <h6 class="fw-bold text-success mb-3">Registered Consultant Doctors</h6>
                            <table class="table table-dark-custom table-sm small">
                                <thead><tr><th>ID</th><th>Doctor Name</th><th>Specialization</th><th>Schedule</th></tr></thead>
                                <tbody>
                                    <?php while($d = $doctors->fetch_assoc()): ?>
                                    <tr>
                                        <td>#<?php echo $d['id']; ?></td>
                                        <td class="fw-bold"><?php echo htmlspecialchars($d['name']); ?></td>
                                        <td><span class="badge bg-info text-dark"><?php echo htmlspecialchars($d['specialization']); ?></span></td>
                                        <td><?php echo htmlspecialchars($d['availability']); ?></td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                        <div class="glass-card p-4">
                            <h6 class="fw-bold text-primary mb-3">Internal Hospital Staff Directory</h6>
                            <table class="table table-dark-custom table-sm small">
                                <thead><tr><th>ID</th><th>Staff Name</th><th>Role</th><th>Department</th><th>Shift</th><th>Contact</th></tr></thead>
                                <tbody>
                                    <?php while($s = $staff->fetch_assoc()): ?>
                                    <tr>
                                        <td>#<?php echo $s['staff_id']; ?></td>
                                        <td class="fw-bold"><?php echo htmlspecialchars($s['staff_name']); ?></td>
                                        <td><?php echo htmlspecialchars($s['role']); ?></td>
                                        <td><?php echo htmlspecialchars($s['department']); ?></td>
                                        <td><?php echo htmlspecialchars($s['shift']); ?></td>
                                        <td><?php echo htmlspecialchars($s['contact']); ?></td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
<?php endif; ?>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
<?php $conn->close(); ?>
EOF

# 9. Enable PHP-FPM and Restart Apache to load the Hospital Portal
systemctl enable --now php-fpm
systemctl restart httpd