-- Only the build identity provisions the first administrator.
-- Hashes are generated from locally supplied passwords; no default password is committed.
SET @t=UTC_TIMESTAMP(6),@context=UUID();
START TRANSACTION;
INSERT INTO UserAccount(AccountID,LoginName,DisplayName,ContactEmail,PasswordHash,RoleCode)
VALUES(1,'admin','Demo Administrator','admin@example.invalid','{{ADMIN_HASH}}','ADMINISTRATOR');
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','AccountID',NULL,1,NULL,@context,NULL,NULL);
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','LoginName',NULL,'admin',NULL,@context,NULL,NULL);
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','DisplayName',NULL,'Demo Administrator',NULL,@context,NULL,NULL);
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','ContactEmail',NULL,'admin@example.invalid',NULL,@context,NULL,NULL);
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','RoleCode',NULL,'ADMINISTRATOR',NULL,@context,NULL,NULL);
CALL sp_append_audit(1,@t,'CREATE','UserAccount','1','IsActive',NULL,1,NULL,@context,NULL,NULL);
COMMIT;
CALL sp_create_account(1,UTC_TIMESTAMP(6),UUID(),'staff','Demo Staff','staff@example.invalid','{{DEMO_HASH}}','STAFF',NULL);
CALL sp_create_account(1,UTC_TIMESTAMP(6),UUID(),'staff2','Second Staff','staff2@example.invalid','{{DEMO_HASH}}','STAFF',NULL);
CALL sp_create_account(1,UTC_TIMESTAMP(6),UUID(),'customer','Demo Customer','customer@example.invalid','{{DEMO_HASH}}','CUSTOMER','Demo Customer');
CALL sp_create_account(1,UTC_TIMESTAMP(6),UUID(),'customer2','Second Customer','customer2@example.invalid','{{DEMO_HASH}}','CUSTOMER','Second Customer');
CALL sp_create_product(2,UTC_TIMESTAMP(6),UUID(),'P020','Desk Lamp','20.00','3');
CALL sp_create_product(2,UTC_TIMESTAMP(6),UUID(),'P015','Notebook Set','15.00','3');
CALL sp_create_product(2,UTC_TIMESTAMP(6),UUID(),'PLOW','Cable','5.00','3');
CALL sp_adjust_stock(2,UTC_TIMESTAMP(6),UUID(),1,'20','Opening stock','seed-stock-1');
CALL sp_adjust_stock(2,UTC_TIMESTAMP(6),UUID(),2,'20','Opening stock','seed-stock-2');
CALL sp_adjust_stock(2,UTC_TIMESTAMP(6),UUID(),3,'3','Opening stock','seed-stock-3');
CALL sp_place_order(4,UTC_TIMESTAMP(6),UUID(),'seed-55','Demo Customer','1 Sample Street','Sample City',NULL,'00001','USA',JSON_ARRAY(JSON_OBJECT('product_id',1,'quantity',2),JSON_OBJECT('product_id',2,'quantity',1)));
CALL sp_mark_ready(2,UTC_TIMESTAMP(6),UUID(),1);
CALL sp_dispatch_order(2,UTC_TIMESTAMP(6),UUID(),1,'Demo Carrier','DEMO-001');
CALL sp_place_order(5,UTC_TIMESTAMP(6),UUID(),'seed-40','Second Customer','2 Sample Street','Sample City',NULL,'00002','USA',JSON_ARRAY(JSON_OBJECT('product_id',1,'quantity',2)));
CALL sp_mark_ready(2,UTC_TIMESTAMP(6),UUID(),2);
CALL sp_dispatch_order(2,UTC_TIMESTAMP(6),UUID(),2,'Demo Carrier','DEMO-002');
