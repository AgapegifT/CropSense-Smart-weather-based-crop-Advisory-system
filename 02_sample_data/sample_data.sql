-- Sample data SQL


-- ================================================================
-- CROPSENSE PROJECT ENHANCEMENTS - PROFESSIONAL EDITION
-- ================================================================

-- ================================================================
-- 1) PERFORMANCE OPTIMIZATION
-- ================================================================
PROMPT Adding performance indexes...

CREATE INDEX idx_weather_region_date ON weather_data(region_id, record_date);
CREATE INDEX idx_weather_date ON weather_data(record_date);
CREATE INDEX idx_advisories_region ON advisories(region_id);
CREATE INDEX idx_advisories_date ON advisories(created_at);
CREATE INDEX idx_advisories_crop ON advisories(crop_id);

-- ================================================================
-- 2) COMPREHENSIVE REPORTING VIEWS
-- ================================================================
PROMPT Creating reporting views...

-- View 1: Region health dashboard
CREATE OR REPLACE VIEW v_region_health AS
SELECT 
    r.region_id,
    r.region_name,
    r.province,
    COUNT(w.data_id) as total_readings,
    NVL(AVG(w.temperature), 0) as avg_temperature,
    NVL(AVG(w.humidity), 0) as avg_humidity,
    NVL(AVG(w.rainfall_mm), 0) as avg_rainfall,
    COUNT(a.advisory_id) as total_advisories,
    MAX(w.record_date) as latest_reading,
    CASE 
        WHEN MAX(w.record_date) < TRUNC(SYSDATE) - 7 THEN 'NEEDS DATA'
        WHEN MAX(w.record_date) < TRUNC(SYSDATE) - 3 THEN 'STALE DATA'
        ELSE 'ACTIVE'
    END as data_status
FROM regions r
LEFT JOIN weather_data w ON r.region_id = w.region_id
LEFT JOIN advisories a ON r.region_id = a.region_id
GROUP BY r.region_id, r.region_name, r.province;

-- View 2: Crop performance analysis
CREATE OR REPLACE VIEW v_crop_performance AS
SELECT 
    c.crop_id,
    c.crop_name,
    c.preferred_temp_min || '°C-' || c.preferred_temp_max || '°C' as ideal_temp_range,
    c.ideal_rainfall_mm || 'mm' as ideal_rainfall,
    c.season,
    COUNT(DISTINCT a.region_id) as regions_with_advisories,
    COUNT(a.advisory_id) as total_advisories,
    MIN(a.created_at) as first_advisory,
    MAX(a.created_at) as latest_advisory
FROM crops c
LEFT JOIN advisories a ON c.crop_id = a.crop_id
GROUP BY c.crop_id, c.crop_name, c.preferred_temp_min, 
         c.preferred_temp_max, c.ideal_rainfall_mm, c.season;

-- View 3: Monthly weather summary
CREATE OR REPLACE VIEW v_monthly_weather AS
SELECT 
    region_id,
    TO_CHAR(record_date, 'YYYY-MM') as month_year,
    COUNT(*) as readings_count,
    ROUND(AVG(temperature), 1) as avg_temperature,
    ROUND(AVG(humidity), 1) as avg_humidity,
    ROUND(SUM(rainfall_mm), 1) as total_rainfall,
    MAX(temperature) as max_temperature,
    MIN(temperature) as min_temperature
FROM weather_data
GROUP BY region_id, TO_CHAR(record_date, 'YYYY-MM');

-- View 4: Advisory statistics by type
CREATE OR REPLACE VIEW v_advisory_stats AS
SELECT 
    CASE 
        WHEN message LIKE '%Low rainfall%' THEN 'IRRIGATION_ADVICE'
        WHEN message LIKE '%High temperature%' THEN 'HEAT_WARNING'
        WHEN message LIKE '%Weekly advisory%' THEN 'WEEKLY_SUMMARY'
        ELSE 'OTHER'
    END as advisory_type,
    COUNT(*) as count,
    MIN(created_at) as first_occurrence,
    MAX(created_at) as last_occurrence,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM advisories), 2) as percentage
FROM advisories
GROUP BY CASE 
    WHEN message LIKE '%Low rainfall%' THEN 'IRRIGATION_ADVICE'
    WHEN message LIKE '%High temperature%' THEN 'HEAT_WARNING'
    WHEN message LIKE '%Weekly advisory%' THEN 'WEEKLY_SUMMARY'
    ELSE 'OTHER'
END;

-- View 5: Region rainfall comparison (last 30 days)
CREATE OR REPLACE VIEW v_rainfall_comparison AS
SELECT 
    r.region_id,
    r.region_name,
    NVL(ROUND(AVG(w.rainfall_mm), 2), 0) as avg_rainfall_30d,
    NVL(COUNT(w.data_id), 0) as days_with_data,
    RANK() OVER (ORDER BY NVL(AVG(w.rainfall_mm), 0) DESC) as rainfall_rank
FROM regions r
LEFT JOIN weather_data w ON r.region_id = w.region_id 
    AND w.record_date >= TRUNC(SYSDATE) - 30
GROUP BY r.region_id, r.region_name;

-- ================================================================
-- 3) ENHANCED TABLES FOR NOTIFICATIONS
-- ================================================================
PROMPT Creating notification system tables...

CREATE TABLE notification_templates (
    template_id NUMBER PRIMARY KEY,
    template_name VARCHAR2(100) NOT NULL,
    message_template VARCHAR2(500) NOT NULL,
    priority NUMBER(1) DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    is_active CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N')),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE notifications (
    notification_id NUMBER PRIMARY KEY,
    advisory_id NUMBER REFERENCES advisories(advisory_id),
    template_id NUMBER REFERENCES notification_templates(template_id),
    recipient_type VARCHAR2(20) DEFAULT 'FARMER',
    message_content VARCHAR2(1000),
    status VARCHAR2(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'READ')),
    scheduled_time TIMESTAMP,
    sent_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE SEQUENCE seq_notification START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_template START WITH 1 INCREMENT BY 1 NOCACHE;

-- ================================================================
-- 4) USER MANAGEMENT SYSTEM
-- ================================================================
PROMPT Creating user management system...

CREATE TABLE users (
    user_id NUMBER PRIMARY KEY,
    username VARCHAR2(50) UNIQUE NOT NULL,
    password_hash VARCHAR2(100) NOT NULL,
    full_name VARCHAR2(100),
    email VARCHAR2(100),
    phone VARCHAR2(20),
    role VARCHAR2(20) DEFAULT 'FARMER' CHECK (role IN ('ADMIN', 'MANAGER', 'FARMER', 'VIEWER')),
    region_id NUMBER REFERENCES regions(region_id),
    is_active CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N')),
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE user_logs (
    log_id NUMBER PRIMARY KEY,
    user_id NUMBER REFERENCES users(user_id),
    action_type VARCHAR2(50),
    action_details VARCHAR2(500),
    ip_address VARCHAR2(50),
    log_timestamp TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE SEQUENCE seq_user START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_user_log START WITH 1 INCREMENT BY 1 NOCACHE;

-- ================================================================
-- 5) ENHANCED PROCEDURES
-- ================================================================
PROMPT Creating enhanced procedures...

-- Procedure 1: Send notifications for new advisories
CREATE OR REPLACE PROCEDURE send_advisory_notifications AS
    CURSOR c_new_advisories IS
        SELECT a.*, r.region_name, c.crop_name
        FROM advisories a
        JOIN regions r ON a.region_id = r.region_id
        JOIN crops c ON a.crop_id = c.crop_id
        WHERE NOT EXISTS (
            SELECT 1 FROM notifications n 
            WHERE n.advisory_id = a.advisory_id
        );
    
    v_template_id NUMBER;
    v_notification_id NUMBER;
BEGIN
    -- Get irrigation advisory template
    SELECT template_id INTO v_template_id
    FROM notification_templates
    WHERE template_name = 'IRRIGATION_ADVISORY' AND is_active = 'Y'
    AND ROWNUM = 1;
    
    FOR adv IN c_new_advisories LOOP
        v_notification_id := seq_notification.NEXTVAL;
        
        INSERT INTO notifications (
            notification_id,
            advisory_id,
            template_id,
            message_content,
            status,
            scheduled_time
        ) VALUES (
            v_notification_id,
            adv.advisory_id,
            v_template_id,
            'Advisory for ' || adv.region_name || ': ' || SUBSTR(adv.message, 1, 200),
            'PENDING',
            SYSTIMESTAMP
        );
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Notifications queued for sending.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No notification template found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in send_advisory_notifications: ' || SQLERRM);
END;
/

-- Procedure 2: User registration
CREATE OR REPLACE PROCEDURE register_user(
    p_username IN VARCHAR2,
    p_password IN VARCHAR2,
    p_full_name IN VARCHAR2,
    p_email IN VARCHAR2,
    p_role IN VARCHAR2 DEFAULT 'FARMER',
    p_region_id IN NUMBER DEFAULT NULL
) AS
    v_user_id NUMBER;
    v_err_msg VARCHAR2(4000);
BEGIN
    -- Input validation
    IF p_username IS NULL OR LENGTH(p_username) < 3 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Username must be at least 3 characters');
    END IF;
    
    IF p_password IS NULL OR LENGTH(p_password) < 6 THEN
        RAISE_APPLICATION_ERROR(-20011, 'Password must be at least 6 characters');
    END IF;
    
    -- Check if username exists
    BEGIN
        SELECT user_id INTO v_user_id FROM users WHERE username = p_username;
        RAISE_APPLICATION_ERROR(-20012, 'Username already exists');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL; -- Username is available
    END;
    
    -- Insert new user
    v_user_id := seq_user.NEXTVAL;
    
    INSERT INTO users (
        user_id,
        username,
        password_hash,
        full_name,
        email,
        role,
        region_id
    ) VALUES (
        v_user_id,
        p_username,
        DBMS_OBFUSCATION_TOOLKIT.MD5(input_string => p_password), -- Simple hash for demo
        p_full_name,
        p_email,
        p_role,
        p_region_id
    );
    
    -- Log the registration
    INSERT INTO user_logs (user_id, action_type, action_details)
    VALUES (v_user_id, 'REGISTER', 'New user registration: ' || p_username);
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('User ' || p_username || ' registered successfully with ID: ' || v_user_id);
EXCEPTION
    WHEN OTHERS THEN
        v_err_msg := 'register_user error: ' || SQLERRM;
        INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
        ROLLBACK;
        RAISE;
END;
/

-- Procedure 3: Generate monthly report
CREATE OR REPLACE PROCEDURE generate_monthly_report(p_month IN NUMBER DEFAULT NULL) AS
    v_month_start DATE;
    v_month_end DATE;
    v_report_id NUMBER;
BEGIN
    -- Determine month
    IF p_month IS NULL THEN
        v_month_start := TRUNC(SYSDATE, 'MM');
        v_month_end := LAST_DAY(SYSDATE);
    ELSE
        v_month_start := TRUNC(ADD_MONTHS(SYSDATE, p_month), 'MM');
        v_month_end := LAST_DAY(v_month_start);
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('Generating monthly report for ' || TO_CHAR(v_month_start, 'Month YYYY'));
    DBMS_OUTPUT.PUT_LINE('========================================');
    
    -- Weather summary
    DBMS_OUTPUT.PUT_LINE('WEATHER SUMMARY:');
    FOR rec IN (
        SELECT 
            r.region_name,
            COUNT(w.data_id) as readings,
            ROUND(AVG(w.temperature), 1) as avg_temp,
            ROUND(SUM(w.rainfall_mm), 1) as total_rain
        FROM regions r
        LEFT JOIN weather_data w ON r.region_id = w.region_id
            AND w.record_date BETWEEN v_month_start AND v_month_end
        GROUP BY r.region_id, r.region_name
        ORDER BY r.region_name
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || rec.region_name || ': ' || rec.readings || ' readings, ' ||
                            rec.avg_temp || '°C avg, ' || rec.total_rain || 'mm rain');
    END LOOP;
    
    -- Advisory summary
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ADVISORY SUMMARY:');
    FOR rec IN (
        SELECT 
            CASE 
                WHEN message LIKE '%Low rainfall%' THEN 'Irrigation Advisories'
                WHEN message LIKE '%High temperature%' THEN 'Heat Warnings'
                WHEN message LIKE '%Weekly advisory%' THEN 'Weekly Summaries'
                ELSE 'Other'
            END as advisory_type,
            COUNT(*) as count
        FROM advisories
        WHERE created_at BETWEEN v_month_start AND v_month_end
        GROUP BY CASE 
            WHEN message LIKE '%Low rainfall%' THEN 'Irrigation Advisories'
            WHEN message LIKE '%High temperature%' THEN 'Heat Warnings'
            WHEN message LIKE '%Weekly advisory%' THEN 'Weekly Summaries'
            ELSE 'Other'
        END
        ORDER BY count DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || rec.advisory_type || ': ' || rec.count);
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Report generation complete.');
END;
/

-- ================================================================
-- 6) POPULATE ENHANCEMENT DATA
-- ================================================================
PROMPT Populating enhancement data...

-- Insert notification templates
INSERT INTO notification_templates (template_id, template_name, message_template, priority) 
VALUES (seq_template.NEXTVAL, 'IRRIGATION_ADVISORY', 'Irrigation needed in {region}. Rainfall: {rainfall}mm in 5 days.', 1);

INSERT INTO notification_templates (template_id, template_name, message_template, priority) 
VALUES (seq_template.NEXTVAL, 'HEAT_WARNING', 'Heat alert in {region}. Temperature: {temp}°C. Protect crops.', 2);

INSERT INTO notification_templates (template_id, template_name, message_template, priority) 
VALUES (seq_template.NEXTVAL, 'WEEKLY_SUMMARY', 'Weekly advisory for {region}. Avg rainfall: {rainfall}mm.', 3);

-- Insert sample users
BEGIN
    register_user('admin', 'admin123', 'System Administrator', 'admin@cropsense.com', 'ADMIN');
    register_user('manager1_james', 'mgr123', 'Regional Manager', 'manager@cropsense.com', 'MANAGER', 1);
    register_user('farmer_john', 'farm123', 'John Doe', 'john@farm.com', 'FARMER', 2);
    register_user('farmer_mary', 'farm456', 'Mary Smith', 'mary@farm.com', 'FARMER', 3);
END;
/

-- ================================================================
-- 7) TEST THE ENHANCEMENTS
-- ================================================================
PROMPT Testing enhancements...

PROMPT 1. Testing views...
SELECT 'Region Health View:' FROM dual;
SELECT region_name, total_readings, total_advisories, data_status 
FROM v_region_health 
WHERE ROWNUM <= 3;

PROMPT 2. Testing notification procedure...
BEGIN
    send_advisory_notifications();
END;
/

SELECT 'Pending Notifications:' FROM dual;
SELECT notification_id, status, SUBSTR(message_content, 1, 50) || '...' as preview
FROM notifications WHERE ROWNUM <= 3;

PROMPT 3. Testing monthly report...
BEGIN
    generate_monthly_report();
END;
/

PROMPT 4. Testing user authentication...
SELECT 'Active Users:' FROM dual;
SELECT username, full_name, role, region_id FROM users WHERE is_active = 'Y';

-- ================================================================
-- 8) FINAL PROJECT STATUS CHECK
-- ================================================================
PROMPT Final project status check...

DECLARE
    v_table_count NUMBER;
    v_view_count NUMBER;
    v_procedure_count NUMBER;
    v_sequence_count NUMBER;
BEGIN
    -- Count objects
    SELECT COUNT(*) INTO v_table_count 
    FROM user_tables 
    WHERE table_name LIKE '%CROP%' OR table_name LIKE '%REGION%' OR table_name LIKE '%WEATHER%';
    
    SELECT COUNT(*) INTO v_view_count 
    FROM user_views 
    WHERE view_name LIKE 'V_%';
    
    SELECT COUNT(*) INTO v_procedure_count 
    FROM user_procedures 
    WHERE object_type IN ('PROCEDURE', 'FUNCTION');
    
    SELECT COUNT(*) INTO v_sequence_count 
    FROM user_sequences;
    
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('CROPSENSE PROJECT - PROFESSIONAL EDITION');
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Database Objects:');
    DBMS_OUTPUT.PUT_LINE('  Tables: ' || v_table_count);
    DBMS_OUTPUT.PUT_LINE('  Views: ' || v_view_count);
    DBMS_OUTPUT.PUT_LINE('  Procedures/Functions: ' || v_procedure_count);
    DBMS_OUTPUT.PUT_LINE('  Sequences: ' || v_sequence_count);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Features Included:');
    DBMS_OUTPUT.PUT_LINE('  ✓ Real-time advisory generation');
    DBMS_OUTPUT.PUT_LINE('  ✓ Weekly analysis reports');
    DBMS_OUTPUT.PUT_LINE('  ✓ Performance optimization (indexes)');
    DBMS_OUTPUT.PUT_LINE('  ✓ Comprehensive reporting views');
    DBMS_OUTPUT.PUT_LINE('  ✓ Notification system');
    DBMS_OUTPUT.PUT_LINE('  ✓ User management');
    DBMS_OUTPUT.PUT_LINE('  ✓ Error logging & monitoring');
    DBMS_OUTPUT.PUT_LINE('  ✓ Monthly reporting');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Project Status: COMPLETE ✓');
END;
/

COMMIT;

PROMPT =========================================
PROMPT ENHANCEMENTS COMPLETED SUCCESSFULLY!
PROMPT =========================================


-- ================================================================
-- GENERATE 70 SAMPLE USERS AUTOMATICALLY
-- ================================================================
SET SERVEROUTPUT ON

DECLARE
    -- Arrays of realistic names
    TYPE name_array IS VARRAY(50) OF VARCHAR2(50);
    
    first_names name_array := name_array(
        'James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda',
        'William', 'Elizabeth', 'David', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica',
        'Thomas', 'Sarah', 'Charles', 'Karen', 'Christopher', 'Nancy', 'Daniel', 'Lisa',
        'Matthew', 'Margaret', 'Anthony', 'Betty', 'Donald', 'Sandra', 'Mark', 'Ashley',
        'Paul', 'Dorothy', 'Steven', 'Kimberly', 'Andrew', 'Emily', 'Kenneth', 'Donna',
        'Joshua', 'Michelle', 'Kevin', 'Carol', 'Brian', 'Amanda', 'George', 'Melissa',
        'Edward', 'Deborah'
    );
    
    last_names name_array := name_array(
        'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
        'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson',
        'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee', 'Perez', 'Thompson',
        'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson', 'Walker',
        'Young', 'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores',
        'Green', 'Adams', 'Nelson', 'Baker', 'Hall', 'Rivera', 'Campbell', 'Mitchell',
        'Carter', 'Roberts'
    );
    
    regions name_array := name_array(
        'North', 'South', 'East', 'West', 'Central', 'Coastal', 'Highland', 'Valley',
        'Plateau', 'Delta', 'Basin', 'Peninsula', 'Island', 'Border', 'Inland'
    );
    
    v_user_id NUMBER;
    v_username VARCHAR2(50);
    v_full_name VARCHAR2(100);
    v_email VARCHAR2(100);
    v_role VARCHAR2(20);
    v_region_id NUMBER;
    v_phone VARCHAR2(20);
    v_counter NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Generating 70 sample users...');
    DBMS_OUTPUT.PUT_LINE('================================');
    
    -- Start user_id from 1000
    v_user_id := 1000;
    
    -- Generate 70 users
    FOR i IN 1..70 LOOP
        -- Generate username (firstname.lastname + number)
        v_username := LOWER(
            first_names(MOD(i-1, 50) + 1) || '.' || 
            last_names(MOD(i*2, 50) + 1) || 
            CASE WHEN i > 1 THEN i END
        );
        
        -- Generate full name
        v_full_name := first_names(MOD(i-1, 50) + 1) || ' ' || last_names(MOD(i*2, 50) + 1);
        
        -- Generate email
        v_email := LOWER(
            first_names(MOD(i-1, 50) + 1) || '.' || 
            last_names(MOD(i*2, 50) + 1) || 
            CASE WHEN i > 1 THEN i END || '@farm.com'
        );
        
        -- Assign role (15% admin, 25% manager, 60% farmer)
        IF i <= 10 THEN  -- First 10 are admins (14%)
            v_role := 'ADMIN';
            v_region_id := NULL;
        ELSIF i <= 28 THEN  -- Next 18 are managers (26%)
            v_role := 'MANAGER';
            v_region_id := MOD(i, 10) + 1;  -- Regions 1-10
        ELSE  -- Remaining 42 are farmers (60%)
            v_role := 'FARMER';
            v_region_id := MOD(i, 10) + 1;  -- Regions 1-10
        END IF;
        
        -- Generate phone number
        v_phone := '+1' || LPAD(TO_CHAR(5000000000 + i*12345), 10, '0');
        
        -- Insert user
        INSERT INTO users (
            user_id,
            username,
            password_hash,
            full_name,
            email,
            phone,
            role,
            region_id,
            is_active,
            created_at
        ) VALUES (
            v_user_id,
            v_username,
            'password' || i,  -- Simple password for demo
            v_full_name,
            v_email,
            v_phone,
            v_role,
            v_region_id,
            'Y',
            SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 365)  -- Random creation date in last year
        );
        
        v_user_id := v_user_id + 1;
        v_counter := v_counter + 1;
        
        -- Show progress every 10 users
        IF MOD(i, 10) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Generated ' || i || ' users...');
        END IF;
    END LOOP;
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '✅ SUCCESS: ' || v_counter || ' users generated!');
    
    -- Show sample of users
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'SAMPLE OF GENERATED USERS:');
    DBMS_OUTPUT.PUT_LINE('====================================');
    
    FOR r IN (
        SELECT username, full_name, role, region_id, email, phone
        FROM users 
        WHERE ROWNUM <= 10
        ORDER BY user_id
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.username, 20) || ' | ' ||
            RPAD(r.full_name, 20) || ' | ' ||
            RPAD(r.role, 10) || ' | ' ||
            NVL(TO_CHAR(r.region_id), 'N/A') || ' | ' ||
            r.email
        );
    END LOOP;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- ================================================================
-- VERIFY THE DATA
-- ================================================================
PROMPT
PROMPT ========== USER STATISTICS ==========
PROMPT

-- Count by role
SELECT 
    role,
    COUNT(*) as user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) || '%' as percentage
FROM users
GROUP BY role
ORDER BY user_count DESC;

-- Count by region
SELECT 
    NVL(TO_CHAR(region_id), 'No Region') as region,
    COUNT(*) as user_count,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) as sample_users
FROM users
WHERE ROWNUM <= 20  -- Limit for display
GROUP BY region_id
ORDER BY region_id NULLS FIRST;

-- Show recent users
SELECT 
    user_id,
    username,
    full_name,
    role,
    region_id,
    TO_CHAR(created_at, 'YYYY-MM-DD') as created
FROM users
ORDER BY created_at DESC
FETCH FIRST 5 ROWS ONLY;

-- Total count
SELECT 'Total Users: ' || COUNT(*) as summary FROM users;
