# ��� CropSense – Smart Weather-Based Crop Advisory System  
**PDB Name:** AG_27320_CROP_SENSE_PROJECT  
**NAMES:** Agape Gift  ID: 27320

---

## ��� Project Overview
CropSense is a PL/SQL-powered intelligent crop advisory system that analyzes weather patterns, soil moisture, and temperature to automatically generate irrigation and crop protection recommendations for farmers.

The system uses advanced PL/SQL features including:
- Procedures  
- Functions  
- Triggers  
- Packages  
- Batch inserts  
- Analytical calculations  
- Notification logic  

All components are included in the folders below.

---

## ��� Folder Structure  
### ���️ 1. Base Schema  
Contains table creation scripts.  
➡️ [01_schema/base_system.sql](01_schema/base_system.sql)

### ��� 2. Sample Data  
Contains scripts to insert 100+ dummy weather & farm records.  
➡️ [02_sample_data/sample_data.sql](02_sample_data/sample_data.sql)

### ��� 3. Phase 1 – Data Mapping  
➡️ [03_phase1_mappings/phase1_mappings.sql](03_phase1_mappings/phase1_mappings.sql)

### ��� 4. Phase 2 – Advisory Engine  
➡️ [04_phase2_advisor/phase2_advisor.sql](04_phase2_advisor/phase2_advisor.sql)

### ��� 5. Phase 3 – Notification Service  
➡️ [05_phase3_notifications/phase3_notifications.sql](05_phase3_notifications/phase3_notifications.sql)

### ��� 6. Phase 4 – Dashboard + Views  
➡️ [06_phase4_dashboard/phase4_dashboard.sql](06_phase4_dashboard/phase4_dashboard.sql)

### ��� 7. Integration Tests  
➡️ [07_integration_test/run_all.sql](07_integration_test/run_all.sql)

### ��� 8. Daily Operations  
➡️ [08_daily_operations/daily_ops.sql](08_daily_operations/daily_ops.sql)

---



<img width="1024" height="1536" alt="Cropsense ERD" src="https://github.com/user-attachments/assets/37a5104e-a757-4c1c-ac56-ee3d52061cf2" />
