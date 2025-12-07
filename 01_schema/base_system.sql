--Base Project.sql---

-- ================================================================
-- 1) Drop existing objects (clean start)
-- ================================================================
BEGIN
    -- Drop in correct order (due to foreign key constraints)
    EXECUTE IMMEDIATE 'DROP TABLE cs_errors CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE advisories CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE weather_data CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE crops CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE regions CASCADE CONSTRAINTS';
    
    -- Drop sequences
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_region';
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_crop';
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_weather';
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_advisory';
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_error';
    
    DBMS_OUTPUT.PUT_LINE('All existing objects dropped.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Some objects may not exist, continuing...');
END;
/

-- ================================================================
-- 2) Sequences
-- ================================================================
CREATE SEQUENCE seq_region START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_crop START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_weather START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_advisory START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_error START WITH 1 INCREMENT BY 1 NOCACHE;

-- ================================================================
-- 3) Tables
-- ================================================================
CREATE TABLE regions (
    region_id   NUMBER PRIMARY KEY,
    region_name VARCHAR2(100) NOT NULL,
    province    VARCHAR2(100)
);

CREATE TABLE crops (
    crop_id              NUMBER PRIMARY KEY,
    crop_name            VARCHAR2(100) NOT NULL,
    preferred_temp_min   NUMBER(5,2),
    preferred_temp_max   NUMBER(5,2),
    ideal_rainfall_mm    NUMBER(5,2),
    season               VARCHAR2(50)
);

CREATE TABLE weather_data (
    data_id      NUMBER PRIMARY KEY,
    region_id    NUMBER REFERENCES regions(region_id),
    record_date  DATE NOT NULL,
    temperature  NUMBER(5,2),
    humidity     NUMBER(5,2),
    rainfall_mm  NUMBER(5,2)
);

CREATE TABLE advisories (
    advisory_id NUMBER PRIMARY KEY,
    region_id   NUMBER REFERENCES regions(region_id),
    crop_id     NUMBER REFERENCES crops(crop_id),
    message     VARCHAR2(1000),
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE cs_errors (
    err_id         NUMBER PRIMARY KEY,
    err_msg        VARCHAR2(4000),
    err_code       NUMBER,
    err_timestamp  TIMESTAMP DEFAULT SYSTIMESTAMP,
    module_name    VARCHAR2(100)
);

-- ================================================================
-- 4) Insert sample data using PL/SQL loops
-- ================================================================
DECLARE
  v_region_name VARCHAR2(100);
  v_province VARCHAR2(100);
  v_crop_name VARCHAR2(100);
  v_seed NUMBER := 1;
  v_days_back NUMBER := 120;
  v_date DATE;
  v_temp NUMBER;
  v_hum NUMBER;
  v_rain NUMBER;
  v_err_msg VARCHAR2(4000);
BEGIN
  DBMS_OUTPUT.PUT_LINE('Inserting sample regions...');
  FOR i IN 1 .. 10 LOOP
    v_region_name := 'Region_' || TO_CHAR(i);
    v_province := 'Province_' || TO_CHAR(CEIL(i/3));
    BEGIN
      INSERT INTO regions(region_id, region_name, province)
      VALUES(seq_region.NEXTVAL, v_region_name, v_province);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Regions inserted.');

  DBMS_OUTPUT.PUT_LINE('Inserting sample crops...');
  FOR i IN 1 .. 10 LOOP
    v_crop_name := CASE i
      WHEN 1 THEN 'Maize'
      WHEN 2 THEN 'Beans'
      WHEN 3 THEN 'Wheat'
      WHEN 4 THEN 'Potato'
      WHEN 5 THEN 'Tomato'
      WHEN 6 THEN 'Onion'
      WHEN 7 THEN 'Rice'
      WHEN 8 THEN 'Banana'
      WHEN 9 THEN 'Cassava'
      ELSE 'Sorghum' END;

    INSERT INTO crops(crop_id, crop_name, preferred_temp_min, preferred_temp_max, ideal_rainfall_mm, season)
    VALUES(seq_crop.NEXTVAL, v_crop_name,
           CASE WHEN i IN (1,3,7,9) THEN 18 ELSE 15 END,
           CASE WHEN i IN (1,3,7,9) THEN 32 ELSE 28 END,
           CASE WHEN i IN (1,4,5) THEN 20 ELSE 15 END,
           CASE WHEN i IN (1,2,3) THEN 'Long rains' ELSE 'Short rains' END);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Crops inserted.');

  DBMS_OUTPUT.PUT_LINE('Inserting weather data for many days (this may take a few seconds)...');
  FOR d IN 0 .. v_days_back LOOP
    v_date := TRUNC(SYSDATE) - d;
    FOR r IN 1 .. 10 LOOP
      v_temp := ROUND(DBMS_RANDOM.VALUE(12, 35), 1);
      v_hum := ROUND(DBMS_RANDOM.VALUE(30, 95), 1);
      IF MOD(d + r, 7) = 0 THEN
        v_rain := ROUND(DBMS_RANDOM.VALUE(10, 80), 1);
      ELSE
        v_rain := ROUND(DBMS_RANDOM.VALUE(0, 15), 1);
      END IF;

      INSERT INTO weather_data(data_id, region_id, record_date, temperature, humidity, rainfall_mm)
      VALUES(seq_weather.NEXTVAL, r, v_date, v_temp, v_hum, v_rain);
    END LOOP;

    IF MOD(d,20)=0 THEN
      COMMIT;
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Weather data inserted (approx ' || ((v_days_back+1)*10) || ' rows).');

EXCEPTION
  WHEN OTHERS THEN
    v_err_msg := 'Sample insert error: ' || SQLERRM;
    DBMS_OUTPUT.PUT_LINE('Error during sample data insertion: ' || v_err_msg);
    INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
    ROLLBACK;
END;
/

-- ================================================================
-- 5) Trigger: AFTER INSERT ON weather_data (CREATE OR REPLACE)
-- ================================================================
CREATE OR REPLACE TRIGGER trg_after_weather_insert
AFTER INSERT ON weather_data
FOR EACH ROW
DECLARE
  v_total_rain NUMBER := 0;
  v_crop_id NUMBER;
  v_msg VARCHAR2(4000);
  v_err_msg VARCHAR2(4000);
BEGIN
  BEGIN
    SELECT NVL(SUM(rainfall_mm),0) INTO v_total_rain
      FROM weather_data
     WHERE region_id = :NEW.region_id
       AND record_date BETWEEN :NEW.record_date - 4 AND :NEW.record_date;
  EXCEPTION WHEN OTHERS THEN
    v_total_rain := 0;
  END;

  IF v_total_rain < 20 THEN
    SELECT crop_id INTO v_crop_id FROM (SELECT crop_id FROM crops ORDER BY crop_id) WHERE ROWNUM = 1;
    v_msg := 'Low rainfall (' || v_total_rain || 'mm in 5 days). Consider irrigation for region_id='
             || :NEW.region_id || '.';
    INSERT INTO advisories(advisory_id, region_id, crop_id, message)
      VALUES(seq_advisory.NEXTVAL, :NEW.region_id, v_crop_id, v_msg);
  END IF;

  IF :NEW.temperature > 34 THEN
    SELECT crop_id INTO v_crop_id FROM (SELECT crop_id FROM crops ORDER BY crop_id DESC) WHERE ROWNUM = 1;
    v_msg := 'High temperature (' || :NEW.temperature || '°C) detected. Protect seedlings and avoid fertilizer application.';
    INSERT INTO advisories(advisory_id, region_id, crop_id, message)
      VALUES(seq_advisory.NEXTVAL, :NEW.region_id, v_crop_id, v_msg);
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    v_err_msg := 'trg_after_weather_insert error: ' || SQLERRM;
    INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
END;
/

-- ================================================================
-- 6) Procedure: weekly_summary (CREATE OR REPLACE)
-- ================================================================
CREATE OR REPLACE PROCEDURE weekly_summary AS
  CURSOR c_regions IS SELECT region_id, region_name FROM regions;
  v_region_id regions.region_id%TYPE;
  v_avg_rain NUMBER;
  v_crop_id NUMBER;
  v_msg VARCHAR2(4000);
  v_err_msg VARCHAR2(4000);
BEGIN
  FOR r IN c_regions LOOP
    v_region_id := r.region_id;
    SELECT NVL(AVG(rainfall_mm),0) INTO v_avg_rain
      FROM weather_data
     WHERE region_id = v_region_id AND record_date BETWEEN TRUNC(SYSDATE)-6 AND TRUNC(SYSDATE);

    IF v_avg_rain < 15 THEN
      SELECT crop_id INTO v_crop_id FROM (SELECT crop_id FROM crops ORDER BY crop_id) WHERE ROWNUM = 1;
      v_msg := 'Weekly advisory: low avg rainfall ' || TO_CHAR(v_avg_rain,'90.99') ||
               ' mm. Consider irrigation planning for region ' || v_region_id || '.';
      INSERT INTO advisories(advisory_id, region_id, crop_id, message)
        VALUES (seq_advisory.NEXTVAL, v_region_id, v_crop_id, v_msg);
    END IF;
  END LOOP;

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    v_err_msg := 'weekly_summary error: ' || SQLERRM;
    INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
    ROLLBACK;
END;
/

-- ================================================================
-- 7) Function: fn_avg_rain (CREATE OR REPLACE)
-- ================================================================
CREATE OR REPLACE FUNCTION fn_avg_rain(
    p_region_id IN NUMBER,
    p_days      IN NUMBER DEFAULT 7
) RETURN NUMBER 
IS
    v_avg NUMBER;
    v_err_msg VARCHAR2(4000);
    v_function_name VARCHAR2(30) := 'FN_AVG_RAIN';
    
    e_invalid_input EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_invalid_input, -20001);
    
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    IF p_region_id IS NULL OR p_region_id <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Invalid region_id: ' || p_region_id);
    END IF;
    
    IF p_days IS NULL OR p_days <= 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Invalid days parameter: ' || p_days);
    END IF;
    
    IF p_days > 365 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Days parameter too large (>365): ' || p_days);
    END IF;
    
    SELECT NVL(AVG(rainfall_mm), 0)
    INTO v_avg
    FROM weather_data
    WHERE region_id = p_region_id
      AND record_date BETWEEN TRUNC(SYSDATE) - (p_days - 1) AND TRUNC(SYSDATE);
    
    COMMIT;
    RETURN v_avg;
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        v_err_msg := v_function_name || ': No weather data found for region_id=' || 
                    p_region_id || ' in last ' || p_days || ' days';
        INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
        COMMIT;
        RETURN 0;
    
    WHEN TOO_MANY_ROWS THEN
        v_err_msg := v_function_name || ': Unexpected multiple rows for region_id=' || p_region_id;
        INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
        COMMIT;
        RETURN NULL;
    
    WHEN e_invalid_input THEN
        v_err_msg := v_function_name || ': ' || SQLERRM;
        INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
        COMMIT;
        RAISE;
    
    WHEN OTHERS THEN
        v_err_msg := v_function_name || ': ' || SQLERRM || 
                    ' [Error Code: ' || SQLCODE || ']' ||
                    ' for region_id=' || p_region_id || ', days=' || p_days;
        
        INSERT INTO cs_errors(err_msg) VALUES(v_err_msg);
        COMMIT;
        
        RETURN NULL;
END fn_avg_rain;
/


-- ================================================================
-- 8) Cursor/Procedure: find regions with no recent data
-- ================================================================
CREATE OR REPLACE PROCEDURE find_no_data(p_days IN NUMBER) IS
  CURSOR c_reg IS SELECT region_id, region_name FROM regions;
  v_last_date DATE;
  v_err_msg VARCHAR2(4000); -- Added for error handling
BEGIN
  FOR r IN c_reg LOOP
    SELECT NVL(MAX(record_date), TO_DATE('1900-01-01','YYYY-MM-DD')) INTO v_last_date
    FROM weather_data WHERE region_id = r.region_id;
    IF v_last_date < TRUNC(SYSDATE)-p_days THEN
      DBMS_OUTPUT.PUT_LINE('No data for region ' || r.region_name || ' in last ' || p_days || ' days.');
    END IF;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    v_err_msg := 'find_no_data error: ' || SQLERRM; -- Store SQLERRM in variable
    INSERT INTO cs_errors(err_msg) VALUES(v_err_msg); -- Use the variable
    RAISE;
END;
/

BEGIN
  DBMS_OUTPUT.ENABLE();
  find_no_data(30); -- Check for regions with no data in last 30 days
END;
/
