-- Integration test SQL

-- ================================================================
-- SIMPLE CROPSENSE TEST SCRIPT
-- ================================================================

SET SERVEROUTPUT ON
SET PAGESIZE 50
SET LINESIZE 100

PROMPT ========== CROPSENSE PROJECT TEST ==========
PROMPT

PROMPT 1. TABLE COUNTS:
PROMPT
SELECT 'Regions: ' || COUNT(*) FROM regions
UNION ALL
SELECT 'Crops: ' || COUNT(*) FROM crops
UNION ALL
SELECT 'Weather data: ' || COUNT(*) FROM weather_data
UNION ALL
SELECT 'Advisories: ' || COUNT(*) FROM advisories
UNION ALL
SELECT 'Errors: ' || COUNT(*) FROM cs_errors;

PROMPT
PROMPT 2. SAMPLE DATA FROM REGIONS:
PROMPT
SELECT * FROM regions WHERE ROWNUM <= 5 ORDER BY region_id;

PROMPT
PROMPT 3. SAMPLE DATA FROM CROPS:
PROMPT
SELECT * FROM crops WHERE ROWNUM <= 5 ORDER BY crop_id;

PROMPT
PROMPT 4. RECENT WEATHER DATA (last 5 days):
PROMPT
SELECT data_id, region_id, record_date, temperature, humidity, rainfall_mm
FROM weather_data 
WHERE record_date >= TRUNC(SYSDATE) - 5
AND ROWNUM <= 10
ORDER BY record_date DESC, region_id;

PROMPT
PROMPT 5. TESTING FN_AVG_RAIN FUNCTION:
PROMPT
BEGIN
    DBMS_OUTPUT.PUT_LINE('Avg rain region 1: ' || fn_avg_rain(1, 7));
END;
/

PROMPT
PROMPT 6. TESTING WEEKLY_SUMMARY:
PROMPT
BEGIN
    weekly_summary();
    DBMS_OUTPUT.PUT_LINE('Weekly summary completed.');
END;
/

PROMPT
PROMPT 7. CHECKING ADVISORIES:
PROMPT
SELECT COUNT(*) as "Total Advisories" FROM advisories;

PROMPT
PROMPT 8. TESTING FIND_NO_DATA:
PROMPT
BEGIN
    find_no_data(30);
END;
/

PROMPT ========== TEST COMPLETE ==========



-- ================================================================
-- ADDITIONAL COMPREHENSIVE TESTS
-- ================================================================

PROMPT
PROMPT ========== ADVANCED TESTS ==========
PROMPT

PROMPT Test 1: Insert weather data to trigger advisories...
DECLARE
    v_before NUMBER;
    v_after NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_before FROM advisories;
    
    -- Insert low rainfall (should trigger irrigation advisory)
    INSERT INTO weather_data(data_id, region_id, record_date, temperature, humidity, rainfall_mm)
    VALUES (seq_weather.NEXTVAL, 1, SYSDATE, 25, 70, 1);
    
    -- Insert high temperature (should trigger heat advisory)
    INSERT INTO weather_data(data_id, region_id, record_date, temperature, humidity, rainfall_mm)
    VALUES (seq_weather.NEXTVAL, 2, SYSDATE, 37, 50, 10);
    
    -- Insert normal data (should not trigger)
    INSERT INTO weather_data(data_id, region_id, record_date, temperature, humidity, rainfall_mm)
    VALUES (seq_weather.NEXTVAL, 3, SYSDATE, 28, 65, 25);
    
    COMMIT;
    
    SELECT COUNT(*) INTO v_after FROM advisories;
    DBMS_OUTPUT.PUT_LINE('Advisories before: ' || v_before || ', after: ' || v_after);
    DBMS_OUTPUT.PUT_LINE('New advisories created: ' || (v_after - v_before));
END;
/

PROMPT
PROMPT Test 2: View newly created advisories...
SELECT advisory_id, region_id, SUBSTR(message, 1, 50) || '...' as advisory_preview
FROM advisories 
WHERE ROWNUM <= 5
ORDER BY created_at DESC;

PROMPT
PROMPT Test 3: Test function with various inputs...
BEGIN
    DBMS_OUTPUT.PUT_LINE('Region 1 (7 days): ' || fn_avg_rain(1, 7) || ' mm');
    DBMS_OUTPUT.PUT_LINE('Region 2 (14 days): ' || fn_avg_rain(2, 14) || ' mm');
    DBMS_OUTPUT.PUT_LINE('Region 3 (30 days): ' || fn_avg_rain(3, 30) || ' mm');
END;
/

PROMPT
PROMPT Test 4: Check error handling with invalid inputs...
BEGIN
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Testing invalid region_id (-1):');
        DBMS_OUTPUT.PUT_LINE('Result: ' || fn_avg_rain(-1, 7));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error caught: ' || SQLERRM);
    END;
    
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Testing invalid days (0):');
        DBMS_OUTPUT.PUT_LINE('Result: ' || fn_avg_rain(1, 0));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error caught: ' || SQLERRM);
    END;
END;
/

PROMPT
PROMPT Test 5: Run find_no_data for different periods...
BEGIN
    DBMS_OUTPUT.PUT_LINE('Checking for regions with no data in 7 days:');
    find_no_data(7);
    
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Checking for regions with no data in 60 days:');
    find_no_data(60);
END;
/

PROMPT
PROMPT Test 6: Analyze advisory patterns...
SELECT 
    CASE 
        WHEN message LIKE '%Low rainfall%' THEN 'Irrigation Advisory'
        WHEN message LIKE '%High temperature%' THEN 'Heat Advisory'
        WHEN message LIKE '%Weekly advisory%' THEN 'Weekly Summary'
        ELSE 'Other'
    END as advisory_type,
    COUNT(*) as count,
    MIN(created_at) as first_occurrence,
    MAX(created_at) as last_occurrence
FROM advisories
GROUP BY 
    CASE 
        WHEN message LIKE '%Low rainfall%' THEN 'Irrigation Advisory'
        WHEN message LIKE '%High temperature%' THEN 'Heat Advisory'
        WHEN message LIKE '%Weekly advisory%' THEN 'Weekly Summary'
        ELSE 'Other'
    END
ORDER BY count DESC;

PROMPT
PROMPT Test 7: Region performance analysis...
SELECT 
    r.region_id,
    r.region_name,
    COUNT(DISTINCT w.record_date) as days_with_data,
    NVL(AVG(w.temperature), 0) as avg_temp,
    NVL(AVG(w.rainfall_mm), 0) as avg_rainfall,
    COUNT(a.advisory_id) as total_advisories
FROM regions r
LEFT JOIN weather_data w ON r.region_id = w.region_id
LEFT JOIN advisories a ON r.region_id = a.region_id
GROUP BY r.region_id, r.region_name
ORDER BY total_advisories DESC, r.region_id;

PROMPT
PROMPT Test 8: Crop suitability analysis...
SELECT 
    c.crop_name,
    c.season,
    COUNT(DISTINCT a.region_id) as regions_with_advisories,
    COUNT(a.advisory_id) as total_advisories
FROM crops c
LEFT JOIN advisories a ON c.crop_id = a.crop_id
GROUP BY c.crop_name, c.season
ORDER BY total_advisories DESC;

PROMPT
PROMPT Test 9: Check error log...
SELECT 
    TO_CHAR(err_timestamp, 'YYYY-MM-DD HH24:MI') as error_time,
    SUBSTR(err_msg, 1, 80) || '...' as error_message
FROM cs_errors
WHERE ROWNUM <= 5
ORDER BY err_timestamp DESC;

PROMPT
PROMPT ========== FINAL SUMMARY ==========
PROMPT

DECLARE
    v_weather_count NUMBER;
    v_advisory_count NUMBER;
    v_error_count NUMBER;
    v_coverage_percent NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_weather_count FROM weather_data;
    SELECT COUNT(*) INTO v_advisory_count FROM advisories;
    SELECT COUNT(*) INTO v_error_count FROM cs_errors;
    
    -- Calculate data coverage (regions with recent data)
    SELECT ROUND((COUNT(DISTINCT region_id) / 10) * 100, 2)
    INTO v_coverage_percent
    FROM weather_data 
    WHERE record_date >= TRUNC(SYSDATE) - 7;
    
    DBMS_OUTPUT.PUT_LINE('PROJECT STATUS SUMMARY:');
    DBMS_OUTPUT.PUT_LINE('========================');
    DBMS_OUTPUT.PUT_LINE('Weather Records: ' || v_weather_count);
    DBMS_OUTPUT.PUT_LINE('Advisories Generated: ' || v_advisory_count);
    DBMS_OUTPUT.PUT_LINE('Errors Logged: ' || v_error_count);
    DBMS_OUTPUT.PUT_LINE('Recent Data Coverage: ' || v_coverage_percent || '%');
    DBMS_OUTPUT.PUT_LINE('Advisory Rate: ' || 
        ROUND((v_advisory_count / NULLIF(v_weather_count, 0)) * 100, 2) || '%');
    DBMS_OUTPUT.PUT_LINE('');
    
    IF v_error_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ All systems operational - No errors detected');
    ELSE
        DBMS_OUTPUT.PUT_LINE('⚠ ' || v_error_count || ' errors detected in log');
    END IF;
    
    IF v_coverage_percent >= 80 THEN
        DBMS_OUTPUT.PUT_LINE('✓ Good data coverage across regions');
    ELSE
        DBMS_OUTPUT.PUT_LINE('⚠ Low data coverage - some regions may lack recent data');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('CropSense Project is running successfully!');
END;
/

PROMPT
PROMPT ========== ALL TESTS COMPLETED ==========
