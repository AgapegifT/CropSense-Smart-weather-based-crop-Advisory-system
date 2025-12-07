-- Phase 2 SQL


-- cropsense_project/03_phase1_mappings.sql
-- PHASE 1: USER-CROP-REGION MAPPING

SET SERVEROUTPUT ON

BEGIN
    DBMS_OUTPUT.PUT_LINE('Starting Phase 1: Creating user-crop-region mappings...');
    
    -- Table: Which crops each farmer grows
    EXECUTE IMMEDIATE '
    CREATE TABLE farmer_crops (
        mapping_id NUMBER PRIMARY KEY,
        farmer_id NUMBER REFERENCES users(user_id),
        crop_id NUMBER REFERENCES crops(crop_id),
        planting_date DATE,
        harvest_date DATE,
        area_hectares NUMBER(5,2),
        status VARCHAR2(20) DEFAULT ''ACTIVE'',
        created_at TIMESTAMP DEFAULT SYSTIMESTAMP
    )';
    
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_farmer_crop START WITH 1 INCREMENT BY 1 NOCACHE';
    
    -- Table: Regional managers assignment
    EXECUTE IMMEDIATE '
    CREATE TABLE region_managers (
        assignment_id NUMBER PRIMARY KEY,
        manager_id NUMBER REFERENCES users(user_id),
        region_id NUMBER REFERENCES regions(region_id),
        start_date DATE DEFAULT SYSDATE,
        end_date DATE,
        is_active CHAR(1) DEFAULT ''Y'',
        created_at TIMESTAMP DEFAULT SYSTIMESTAMP
    )';
    
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_region_manager START WITH 1 INCREMENT BY 1 NOCACHE';
    
    DBMS_OUTPUT.PUT_LINE('Tables created successfully.');
END;
/

-- Populate data
BEGIN
    -- Assign crops to farmers
    DECLARE
        v_farmer_count NUMBER;
        v_crop_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_farmer_count FROM users WHERE role = 'FARMER';
        SELECT COUNT(*) INTO v_crop_count FROM crops;
        
        DBMS_OUTPUT.PUT_LINE('Assigning crops to ' || v_farmer_count || ' farmers...');
        
        FOR farmer_rec IN (SELECT user_id FROM users WHERE role = 'FARMER') LOOP
            FOR i IN 1..(TRUNC(DBMS_RANDOM.VALUE(2, 5))) LOOP
                INSERT INTO farmer_crops (
                    mapping_id,
                    farmer_id,
                    crop_id,
                    planting_date,
                    harvest_date,
                    area_hectares,
                    status
                ) VALUES (
                    seq_farmer_crop.NEXTVAL,
                    farmer_rec.user_id,
                    TRUNC(DBMS_RANDOM.VALUE(1, v_crop_count + 1)),
                    TRUNC(SYSDATE) - TRUNC(DBMS_RANDOM.VALUE(30, 180)),
                    TRUNC(SYSDATE) + TRUNC(DBMS_RANDOM.VALUE(60, 240)),
                    ROUND(DBMS_RANDOM.VALUE(2, 50), 2),
                    CASE WHEN DBMS_RANDOM.VALUE > 0.1 THEN 'ACTIVE' ELSE 'HARVESTED' END
                );
            END LOOP;
        END LOOP;
        
        -- Assign managers to regions
        DBMS_OUTPUT.PUT_LINE('Assigning managers to regions...');
        
        FOR i IN 1..10 LOOP
            INSERT INTO region_managers (
                assignment_id,
                manager_id,
                region_id,
                start_date
            ) VALUES (
                seq_region_manager.NEXTVAL,
                (SELECT user_id FROM users WHERE role = 'MANAGER' AND ROWNUM = 1),
                i,
                SYSDATE - TRUNC(DBMS_RANDOM.VALUE(0, 365))
            );
        END LOOP;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✅ Phase 1 complete: ' || v_farmer_count || ' farmers mapped to crops.');
    END;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in Phase 1: ' || SQLERRM);
        ROLLBACK;
END;
/

-- Verify
SELECT 'Farmer-Crop Mappings: ' || COUNT(*) FROM farmer_crops
UNION ALL
SELECT 'Region Manager Assignments: ' || COUNT(*) FROM region_managers;
