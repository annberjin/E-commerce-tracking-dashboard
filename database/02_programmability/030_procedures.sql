-- The authenticated backend supplies p_actor, UTC p_time and one context UUID.
-- Call each public procedure without an outer transaction. Helpers never commit.
DELIMITER $$
CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_append_audit(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_event VARCHAR(40),
IN p_entity VARCHAR(32), IN p_key VARCHAR(100), IN p_field VARCHAR(64),
IN p_old TEXT, IN p_new TEXT, IN p_reason VARCHAR(255), IN p_context VARCHAR(64),
IN p_order INT UNSIGNED, IN p_ref VARCHAR(64)
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_exists INT DEFAULT 0;
IF NOT ((p_entity='UserAccount' AND p_field IN ('AccountID','LoginName','DisplayName','ContactEmail','RoleCode','IsActive')) OR (p_entity='Customer' AND p_field IN ('CustomerID','CustomerName')) OR (p_entity='Product' AND p_field IN ('ProductID','ProductCode','ProductName','CurrentUnitPrice','IsActive')) OR (p_entity='Inventory' AND p_field IN ('ProductID','AvailableQuantity','LowStockThreshold')) OR (p_entity='OrderHeader' AND p_field IN ('OrderID','CustomerID','SubmissionReference','SubmittedAt','StatusCode','RecipientName','StreetAddress','City','Region','PostalCode','Country','CancellationReason','CancelledAt')) OR (p_entity='OrderLine' AND p_field IN ('OrderID','LineNumber','ProductID','Quantity','AcceptedUnitPrice')) OR (p_entity='Shipment' AND p_field IN ('OrderID','Carrier','TrackingNumber','DispatchedAt'))) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:audit_field'; END IF;
CASE p_entity
 WHEN 'UserAccount' THEN SELECT COUNT(*) INTO v_exists FROM UserAccount WHERE CAST(AccountID AS CHAR)=p_key;
 WHEN 'Customer' THEN SELECT COUNT(*) INTO v_exists FROM Customer WHERE CAST(CustomerID AS CHAR)=p_key;
 WHEN 'Product' THEN SELECT COUNT(*) INTO v_exists FROM Product WHERE CAST(ProductID AS CHAR)=p_key;
 WHEN 'Inventory' THEN SELECT COUNT(*) INTO v_exists FROM Inventory WHERE CAST(ProductID AS CHAR)=p_key;
 WHEN 'OrderHeader' THEN SELECT COUNT(*) INTO v_exists FROM OrderHeader WHERE CAST(OrderID AS CHAR)=p_key AND OrderID=p_order;
 WHEN 'OrderLine' THEN SELECT COUNT(*) INTO v_exists FROM OrderLine WHERE CONCAT(OrderID,':',LineNumber)=p_key AND OrderID=p_order;
 WHEN 'Shipment' THEN SELECT COUNT(*) INTO v_exists FROM Shipment WHERE CAST(OrderID AS CHAR)=p_key AND OrderID=p_order;
 ELSE SET v_exists=0;
END CASE;
IF v_exists<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:audit_target'; END IF;
IF p_entity NOT IN ('OrderHeader','OrderLine','Shipment') AND p_order IS NOT NULL THEN
 IF p_entity <> 'Inventory' OR NOT EXISTS(SELECT 1 FROM OrderLine WHERE OrderID=p_order AND CAST(ProductID AS CHAR)=p_key) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:audit_order_link';
 END IF;
END IF;
IF (p_event LIKE 'ORDER_%' AND NOT (p_entity='OrderHeader' AND p_field='StatusCode')) OR (p_event LIKE 'STOCK_%' AND NOT (p_entity='Inventory' AND p_field='AvailableQuantity')) OR (p_event='TRACKING_CORRECTED' AND NOT (p_entity='Shipment' AND p_field IN ('Carrier','TrackingNumber'))) OR (p_event IN ('STOCK_DEDUCTED','STOCK_RESTORED') AND p_order IS NULL) OR (p_event='STOCK_ADJUSTED' AND p_order IS NOT NULL) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:audit_event'; END IF;
IF p_old <=> p_new THEN LEAVE main; END IF;
INSERT INTO AuditLog(ActorAccountID,EventType,OccurredAt,EntityName,RecordKey,FieldName,OldValue,NewValue,Reason,ContextReference,OrderID,AdjustmentReference)
VALUES(p_actor,p_event,p_time,p_entity,p_key,p_field,p_old,p_new,p_reason,p_context,p_order,p_ref);

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_create_account(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_login TEXT, IN p_name TEXT, IN p_email TEXT, IN p_hash TEXT, IN p_role VARCHAR(16), IN p_customer_name TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_id INT UNSIGNED;
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'ADMINISTRATOR' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_login = TRIM(p_login);
IF p_login IS NULL OR CHAR_LENGTH(p_login)=0 OR CHAR_LENGTH(p_login) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:login'; END IF;
SET p_name = TRIM(p_name);
IF p_name IS NULL OR CHAR_LENGTH(p_name)=0 OR CHAR_LENGTH(p_name) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:name'; END IF;
SET p_email = TRIM(p_email);
IF p_email IS NULL OR CHAR_LENGTH(p_email)=0 OR CHAR_LENGTH(p_email) > 254 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:email'; END IF;
SET p_hash = TRIM(p_hash);
IF p_hash IS NULL OR CHAR_LENGTH(p_hash)=0 OR CHAR_LENGTH(p_hash) > 255 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:hash'; END IF;
SET p_customer_name = NULLIF(TRIM(p_customer_name),'');
IF CHAR_LENGTH(p_customer_name) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:customer_name'; END IF;
IF p_role IS NULL OR p_role NOT IN ('CUSTOMER','STAFF','ADMINISTRATOR') OR (p_role='CUSTOMER' AND p_customer_name IS NULL) OR (p_role<>'CUSTOMER' AND p_customer_name IS NOT NULL) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:role_profile'; END IF;
INSERT INTO UserAccount(LoginName,DisplayName,ContactEmail,PasswordHash,RoleCode) VALUES(p_login,p_name,p_email,p_hash,p_role);
SET v_id=LAST_INSERT_ID();
IF p_role='CUSTOMER' THEN INSERT INTO Customer VALUES(v_id,p_customer_name); END IF;
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'AccountID',NULL,v_id,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'LoginName',NULL,p_login,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'DisplayName',NULL,p_name,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'ContactEmail',NULL,p_email,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'RoleCode',NULL,p_role,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','UserAccount',CAST(v_id AS CHAR),'IsActive',NULL,1,NULL,p_context,NULL,NULL);
IF p_role='CUSTOMER' THEN
CALL sp_append_audit(p_actor,p_time,'CREATE','Customer',CAST(v_id AS CHAR),'CustomerID',NULL,v_id,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Customer',CAST(v_id AS CHAR),'CustomerName',NULL,p_customer_name,NULL,p_context,NULL,NULL);
END IF;
COMMIT;
SELECT v_id AS AccountID;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_update_account(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_target INT UNSIGNED, IN p_name TEXT, IN p_email TEXT, IN p_active TEXT, IN p_customer_name TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_id INT UNSIGNED;
DECLARE v_name VARCHAR(100); DECLARE v_email VARCHAR(254); DECLARE v_customer_name VARCHAR(100);
DECLARE v_target_role VARCHAR(16); DECLARE v_old_active BOOLEAN;
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;
IF p_target < p_actor THEN
 SELECT AccountID INTO v_id FROM UserAccount WHERE AccountID=p_target FOR UPDATE;
END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'ADMINISTRATOR' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_name = TRIM(p_name);
IF p_name IS NULL OR CHAR_LENGTH(p_name)=0 OR CHAR_LENGTH(p_name) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:name'; END IF;
SET p_email = TRIM(p_email);
IF p_email IS NULL OR CHAR_LENGTH(p_email)=0 OR CHAR_LENGTH(p_email) > 254 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:email'; END IF;
SET p_customer_name = NULLIF(TRIM(p_customer_name),'');
IF CHAR_LENGTH(p_customer_name) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:customer_name'; END IF;
IF p_active IS NULL OR NOT REGEXP_LIKE(p_active, '^-?[0-9]+$', 'c') OR CHAR_LENGTH(p_active)>11 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:active'; END IF;
IF CAST(p_active AS DECIMAL(20,0)) < 0 OR CAST(p_active AS DECIMAL(20,0)) > 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:active'; END IF;
SET v_id=NULL;
SELECT AccountID,DisplayName,ContactEmail,RoleCode,IsActive INTO v_id,v_name,v_email,v_target_role,v_old_active
FROM UserAccount WHERE AccountID=p_target FOR UPDATE;
IF v_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:account'; END IF;
IF (v_target_role='CUSTOMER' AND p_customer_name IS NULL) OR (v_target_role<>'CUSTOMER' AND p_customer_name IS NOT NULL) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:profile'; END IF;
IF v_target_role='CUSTOMER' THEN
 SELECT CustomerName INTO v_customer_name FROM Customer WHERE CustomerID=p_target;
 UPDATE Customer SET CustomerName=p_customer_name WHERE CustomerID=p_target;
CALL sp_append_audit(p_actor,p_time,'UPDATE','Customer',CAST(p_target AS CHAR),'CustomerName',v_customer_name,p_customer_name,NULL,p_context,NULL,NULL);
END IF;
UPDATE UserAccount SET DisplayName=p_name,ContactEmail=p_email,IsActive=CAST(p_active AS UNSIGNED) WHERE AccountID=p_target;
CALL sp_append_audit(p_actor,p_time,'UPDATE','UserAccount',CAST(p_target AS CHAR),'DisplayName',v_name,p_name,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'UPDATE','UserAccount',CAST(p_target AS CHAR),'ContactEmail',v_email,p_email,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,IF(CAST(p_active AS UNSIGNED)=1,'ACTIVATE','DEACTIVATE'),'UserAccount',CAST(p_target AS CHAR),'IsActive',v_old_active,CAST(p_active AS UNSIGNED),NULL,p_context,NULL,NULL);
COMMIT;
SELECT p_target AS AccountID;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_create_product(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_code TEXT, IN p_name TEXT, IN p_price TEXT, IN p_threshold TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_id INT UNSIGNED;
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_code = TRIM(p_code);
IF p_code IS NULL OR CHAR_LENGTH(p_code)=0 OR CHAR_LENGTH(p_code) > 40 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:code'; END IF;
SET p_name = TRIM(p_name);
IF p_name IS NULL OR CHAR_LENGTH(p_name)=0 OR CHAR_LENGTH(p_name) > 150 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:name'; END IF;
IF p_price IS NULL OR CHAR_LENGTH(p_price)>11 OR NOT REGEXP_LIKE(p_price, '^[0-9]+([.][0-9]{1,2})?$', 'c') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:price'; END IF;
IF CAST(p_price AS DECIMAL(12,2)) <= 0 OR CAST(p_price AS DECIMAL(12,2))>99999999.99 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:price'; END IF;
IF p_threshold IS NULL OR NOT REGEXP_LIKE(p_threshold, '^-?[0-9]+$', 'c') OR CHAR_LENGTH(p_threshold)>11 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:threshold'; END IF;
IF CAST(p_threshold AS DECIMAL(20,0)) < 0 OR CAST(p_threshold AS DECIMAL(20,0)) > 2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:threshold'; END IF;
INSERT INTO Product(ProductCode,ProductName,CurrentUnitPrice) VALUES(p_code,p_name,CAST(p_price AS DECIMAL(10,2)));
SET v_id=LAST_INSERT_ID();
INSERT INTO Inventory(ProductID,AvailableQuantity,LowStockThreshold) VALUES(v_id,0,CAST(p_threshold AS UNSIGNED));
CALL sp_append_audit(p_actor,p_time,'CREATE','Product',CAST(v_id AS CHAR),'ProductID',NULL,v_id,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Product',CAST(v_id AS CHAR),'ProductCode',NULL,p_code,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Product',CAST(v_id AS CHAR),'ProductName',NULL,p_name,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Product',CAST(v_id AS CHAR),'CurrentUnitPrice',NULL,CAST(p_price AS DECIMAL(10,2)),NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Product',CAST(v_id AS CHAR),'IsActive',NULL,1,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Inventory',CAST(v_id AS CHAR),'ProductID',NULL,v_id,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Inventory',CAST(v_id AS CHAR),'AvailableQuantity',NULL,0,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Inventory',CAST(v_id AS CHAR),'LowStockThreshold',NULL,CAST(p_threshold AS UNSIGNED),NULL,p_context,NULL,NULL);
COMMIT;
SELECT v_id AS ProductID;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_update_product(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_product INT UNSIGNED, IN p_name TEXT, IN p_price TEXT, IN p_threshold TEXT, IN p_active TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_name VARCHAR(150); DECLARE v_price DECIMAL(10,2);
DECLARE v_old_active BOOLEAN; DECLARE v_threshold INT;
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_name = TRIM(p_name);
IF p_name IS NULL OR CHAR_LENGTH(p_name)=0 OR CHAR_LENGTH(p_name) > 150 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:name'; END IF;
IF p_price IS NULL OR CHAR_LENGTH(p_price)>11 OR NOT REGEXP_LIKE(p_price, '^[0-9]+([.][0-9]{1,2})?$', 'c') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:price'; END IF;
IF CAST(p_price AS DECIMAL(12,2)) <= 0 OR CAST(p_price AS DECIMAL(12,2))>99999999.99 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:price'; END IF;
IF p_threshold IS NULL OR NOT REGEXP_LIKE(p_threshold, '^-?[0-9]+$', 'c') OR CHAR_LENGTH(p_threshold)>11 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:threshold'; END IF;
IF CAST(p_threshold AS DECIMAL(20,0)) < 0 OR CAST(p_threshold AS DECIMAL(20,0)) > 2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:threshold'; END IF;
IF p_active IS NULL OR NOT REGEXP_LIKE(p_active, '^-?[0-9]+$', 'c') OR CHAR_LENGTH(p_active)>11 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:active'; END IF;
IF CAST(p_active AS DECIMAL(20,0)) < 0 OR CAST(p_active AS DECIMAL(20,0)) > 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:active'; END IF;
SET v_name=NULL;
SELECT ProductName,CurrentUnitPrice,IsActive INTO v_name,v_price,v_old_active FROM Product WHERE ProductID=p_product FOR UPDATE;
IF v_name IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:product'; END IF;
SELECT LowStockThreshold INTO v_threshold FROM Inventory WHERE ProductID=p_product FOR UPDATE;
UPDATE Product SET ProductName=p_name,CurrentUnitPrice=CAST(p_price AS DECIMAL(10,2)),IsActive=CAST(p_active AS UNSIGNED) WHERE ProductID=p_product;
UPDATE Inventory SET LowStockThreshold=CAST(p_threshold AS UNSIGNED) WHERE ProductID=p_product;
CALL sp_append_audit(p_actor,p_time,'UPDATE','Product',CAST(p_product AS CHAR),'ProductName',v_name,p_name,NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'UPDATE','Product',CAST(p_product AS CHAR),'CurrentUnitPrice',v_price,CAST(p_price AS DECIMAL(10,2)),NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,IF(CAST(p_active AS UNSIGNED)=1,'ACTIVATE','DEACTIVATE'),'Product',CAST(p_product AS CHAR),'IsActive',v_old_active,CAST(p_active AS UNSIGNED),NULL,p_context,NULL,NULL);
CALL sp_append_audit(p_actor,p_time,'UPDATE','Inventory',CAST(p_product AS CHAR),'LowStockThreshold',v_threshold,CAST(p_threshold AS UNSIGNED),NULL,p_context,NULL,NULL);
COMMIT;
SELECT p_product AS ProductID;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_adjust_stock(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_product INT UNSIGNED, IN p_delta TEXT, IN p_reason TEXT, IN p_reference TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_audit BIGINT UNSIGNED; DECLARE v_id INT UNSIGNED; DECLARE v_key VARCHAR(100);
DECLARE v_before BIGINT; DECLARE v_after BIGINT; DECLARE v_reason VARCHAR(255);
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_reference = TRIM(p_reference);
IF p_reference IS NULL OR CHAR_LENGTH(p_reference)=0 OR CHAR_LENGTH(p_reference) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:reference'; END IF;
SET p_reason = TRIM(p_reason);
IF p_reason IS NULL OR CHAR_LENGTH(p_reason)=0 OR CHAR_LENGTH(p_reason) > 255 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:reason'; END IF;
IF p_delta IS NULL OR NOT REGEXP_LIKE(p_delta, '^-?[0-9]+$', 'c') OR CHAR_LENGTH(p_delta)>11 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:delta'; END IF;
IF CAST(p_delta AS DECIMAL(20,0)) < -2147483647 OR CAST(p_delta AS DECIMAL(20,0)) > 2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:delta'; END IF;
IF CAST(p_delta AS SIGNED)=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:zero_adjustment'; END IF;
SET v_audit=NULL;
SELECT AuditID,RecordKey,OldValue,NewValue,Reason INTO v_audit,v_key,v_before,v_after,v_reason
FROM AuditLog WHERE ActorAccountID=p_actor AND AdjustmentReference=p_reference FOR SHARE;
IF v_audit IS NOT NULL THEN
IF NOT (v_key <=> CAST(p_product AS CHAR)) OR BINARY v_reason<>BINARY p_reason OR v_after-v_before<>CAST(p_delta AS SIGNED) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:reference'; END IF;
 COMMIT;
 SELECT v_before AS BeforeQuantity,v_after AS AfterQuantity,1 AS Replayed;
 LEAVE main;
END IF;
SET v_id=NULL;
SELECT ProductID INTO v_id FROM Product WHERE ProductID=p_product FOR UPDATE;
IF v_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:product'; END IF;
SELECT AvailableQuantity INTO v_before FROM Inventory WHERE ProductID=p_product FOR UPDATE;
SET v_after=v_before+CAST(p_delta AS SIGNED);
IF v_after<0 OR v_after>2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:stock_range'; END IF;
UPDATE Inventory SET AvailableQuantity=v_after WHERE ProductID=p_product;
CALL sp_append_audit(p_actor,p_time,'STOCK_ADJUSTED','Inventory',CAST(p_product AS CHAR),'AvailableQuantity',v_before,v_after,p_reason,p_context,NULL,p_reference);
COMMIT;
SELECT v_before AS BeforeQuantity,v_after AS AfterQuantity,0 AS Replayed;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_place_order(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_reference TEXT, IN p_recipient TEXT, IN p_street TEXT, IN p_city TEXT, IN p_region TEXT, IN p_postal TEXT, IN p_country TEXT, IN p_lines JSON
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_order INT UNSIGNED; DECLARE v_i INT; DECLARE v_distinct INT;
DECLARE v_matches INT; DECLARE v_line_matches INT; DECLARE v_count INT;
DECLARE v_item JSON; DECLARE v_product_text TEXT; DECLARE v_qty_text TEXT;
DECLARE v_line INT UNSIGNED; DECLARE v_product INT UNSIGNED; DECLARE v_qty INT;
DECLARE v_price DECIMAL(10,2); DECLARE v_stock INT; DECLARE v_product_active BOOLEAN;
DECLARE v_value DECIMAL(32,2); DECLARE v_done BOOLEAN DEFAULT FALSE;

DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE cur_lines CURSOR FOR SELECT LineNumber,ProductID,Quantity FROM JSON_TABLE(p_lines,'$[*]' COLUMNS (LineNumber FOR ORDINALITY, ProductID INT UNSIGNED PATH '$.product_id' ERROR ON ERROR, Quantity INT PATH '$.quantity' ERROR ON ERROR)) j ORDER BY ProductID;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=TRUE;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'CUSTOMER' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_reference = TRIM(p_reference);
IF p_reference IS NULL OR CHAR_LENGTH(p_reference)=0 OR CHAR_LENGTH(p_reference) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:reference'; END IF;
SET p_recipient = TRIM(p_recipient);
IF p_recipient IS NULL OR CHAR_LENGTH(p_recipient)=0 OR CHAR_LENGTH(p_recipient) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:recipient'; END IF;
SET p_street = TRIM(p_street);
IF p_street IS NULL OR CHAR_LENGTH(p_street)=0 OR CHAR_LENGTH(p_street) > 255 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:street'; END IF;
SET p_city = TRIM(p_city);
IF p_city IS NULL OR CHAR_LENGTH(p_city)=0 OR CHAR_LENGTH(p_city) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:city'; END IF;
SET p_region = NULLIF(TRIM(p_region),'');
IF CHAR_LENGTH(p_region) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:region'; END IF;
SET p_postal = TRIM(p_postal);
IF p_postal IS NULL OR CHAR_LENGTH(p_postal)=0 OR CHAR_LENGTH(p_postal) > 20 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:postal'; END IF;
SET p_country = TRIM(p_country);
IF p_country IS NULL OR CHAR_LENGTH(p_country)=0 OR CHAR_LENGTH(p_country) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:country'; END IF;
IF p_lines IS NULL OR JSON_TYPE(p_lines) COLLATE utf8mb4_0900_bin<>'ARRAY' OR JSON_LENGTH(p_lines)=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:lines'; END IF;
SET v_i=0;
WHILE v_i<JSON_LENGTH(p_lines) DO
 SET v_item=JSON_EXTRACT(p_lines,CONCAT('$[',v_i,']'));
IF JSON_TYPE(v_item) COLLATE utf8mb4_0900_bin<>'OBJECT' OR JSON_LENGTH(v_item)<>2 OR COALESCE(JSON_TYPE(JSON_EXTRACT(v_item,'$.product_id')) COLLATE utf8mb4_0900_bin,'NULL')<>'INTEGER' OR COALESCE(JSON_TYPE(JSON_EXTRACT(v_item,'$.quantity')) COLLATE utf8mb4_0900_bin,'NULL')<>'INTEGER' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:line'; END IF;
 SET v_product_text=JSON_UNQUOTE(JSON_EXTRACT(v_item,'$.product_id'));
 SET v_qty_text=JSON_UNQUOTE(JSON_EXTRACT(v_item,'$.quantity'));
IF CAST(v_product_text AS DECIMAL(65,0))<1 OR CAST(v_product_text AS DECIMAL(65,0))>4294967295 OR CAST(v_qty_text AS DECIMAL(65,0))<1 OR CAST(v_qty_text AS DECIMAL(65,0))>2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:line_range'; END IF;
 SET v_i=v_i+1;
END WHILE;
SELECT COUNT(DISTINCT ProductID) INTO v_distinct FROM JSON_TABLE(p_lines,'$[*]' COLUMNS (LineNumber FOR ORDINALITY, ProductID INT UNSIGNED PATH '$.product_id' ERROR ON ERROR, Quantity INT PATH '$.quantity' ERROR ON ERROR)) j;
IF v_distinct<>JSON_LENGTH(p_lines) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:duplicate_product'; END IF;
SET v_order=NULL;
SELECT OrderID INTO v_order FROM OrderHeader WHERE CustomerID=p_actor AND SubmissionReference=p_reference FOR UPDATE;
IF v_order IS NOT NULL THEN
 SELECT COUNT(*) INTO v_matches FROM OrderHeader WHERE OrderID=v_order AND (RecipientName <=> p_recipient) AND (StreetAddress <=> p_street) AND (City <=> p_city) AND (Region <=> p_region) AND (PostalCode <=> p_postal) AND (Country <=> p_country);
 SELECT COUNT(*) INTO v_line_matches FROM OrderLine l JOIN JSON_TABLE(p_lines,'$[*]' COLUMNS (LineNumber FOR ORDINALITY, ProductID INT UNSIGNED PATH '$.product_id' ERROR ON ERROR, Quantity INT PATH '$.quantity' ERROR ON ERROR)) j
 ON l.ProductID=j.ProductID AND l.Quantity=j.Quantity WHERE l.OrderID=v_order;
 SELECT COUNT(*),SUM(Quantity*AcceptedUnitPrice) INTO v_count,v_value FROM OrderLine WHERE OrderID=v_order;
IF v_matches<>1 OR v_line_matches<>JSON_LENGTH(p_lines) OR v_count<>JSON_LENGTH(p_lines) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:reference'; END IF;
 COMMIT;
 SELECT v_order AS OrderID,v_value AS OrderValue,'PENDING' AS InitialStatus,1 AS Replayed;
 LEAVE main;
END IF;
INSERT INTO OrderHeader(CustomerID,SubmissionReference,SubmittedAt,RecipientName,StreetAddress,City,Region,PostalCode,Country)
VALUES(p_actor,p_reference,p_time,p_recipient,p_street,p_city,p_region,p_postal,p_country);
SET v_order=LAST_INSERT_ID();
SET v_done=FALSE;
OPEN cur_lines;
read_lines: LOOP
 FETCH cur_lines INTO v_line,v_product,v_qty;
 IF v_done THEN LEAVE read_lines; END IF;
 SET v_price=NULL;
 BEGIN
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_price=NULL;
  SELECT CurrentUnitPrice,IsActive INTO v_price,v_product_active FROM Product WHERE ProductID=v_product FOR UPDATE;
 END;
IF v_price IS NULL OR v_product_active<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:inactive_or_missing_product'; END IF;
 SELECT AvailableQuantity INTO v_stock FROM Inventory WHERE ProductID=v_product FOR UPDATE;
IF v_stock<v_qty THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:insufficient_stock'; END IF;
 INSERT INTO OrderLine VALUES(v_order,v_line,v_product,v_qty,v_price);
 UPDATE Inventory SET AvailableQuantity=AvailableQuantity-v_qty WHERE ProductID=v_product;
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderLine',CAST(CONCAT(v_order,':',v_line) AS CHAR),'OrderID',NULL,v_order,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderLine',CAST(CONCAT(v_order,':',v_line) AS CHAR),'LineNumber',NULL,v_line,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderLine',CAST(CONCAT(v_order,':',v_line) AS CHAR),'ProductID',NULL,v_product,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderLine',CAST(CONCAT(v_order,':',v_line) AS CHAR),'Quantity',NULL,v_qty,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderLine',CAST(CONCAT(v_order,':',v_line) AS CHAR),'AcceptedUnitPrice',NULL,v_price,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'STOCK_DEDUCTED','Inventory',CAST(v_product AS CHAR),'AvailableQuantity',v_stock,v_stock-v_qty,NULL,p_context,v_order,NULL);
END LOOP;
CLOSE cur_lines;
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'OrderID',NULL,v_order,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'CustomerID',NULL,p_actor,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'SubmissionReference',NULL,p_reference,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'SubmittedAt',NULL,p_time,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'RecipientName',NULL,p_recipient,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'StreetAddress',NULL,p_street,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'City',NULL,p_city,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'Region',NULL,p_region,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'PostalCode',NULL,p_postal,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','OrderHeader',CAST(v_order AS CHAR),'Country',NULL,p_country,NULL,p_context,v_order,NULL);
CALL sp_append_audit(p_actor,p_time,'ORDER_ACCEPTED','OrderHeader',CAST(v_order AS CHAR),'StatusCode',NULL,'PENDING',NULL,p_context,v_order,NULL);
SELECT SUM(Quantity*AcceptedUnitPrice) INTO v_value FROM OrderLine WHERE OrderID=v_order;
COMMIT;
SELECT v_order AS OrderID,v_value AS OrderValue,'PENDING' AS InitialStatus,0 AS Replayed;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_mark_ready(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_order INT UNSIGNED
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_status VARCHAR(16); DECLARE v_submitted DATETIME(6);
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET v_status=NULL;
SELECT StatusCode,SubmittedAt INTO v_status,v_submitted FROM OrderHeader WHERE OrderID=p_order FOR UPDATE;
IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:order'; END IF;
IF v_status<>'PENDING' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:status'; END IF;
IF p_time<v_submitted THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;
UPDATE OrderHeader SET StatusCode='READY_TO_SHIP' WHERE OrderID=p_order;
CALL sp_append_audit(p_actor,p_time,'ORDER_READY','OrderHeader',CAST(p_order AS CHAR),'StatusCode',v_status,'READY_TO_SHIP',NULL,p_context,p_order,NULL);
COMMIT;
SELECT p_order AS OrderID,'READY_TO_SHIP' AS StatusCode;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_dispatch_order(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_order INT UNSIGNED, IN p_carrier TEXT, IN p_tracking TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_status VARCHAR(16); DECLARE v_submitted DATETIME(6);
DECLARE v_ready DATETIME(6);
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_carrier = TRIM(p_carrier);
IF p_carrier IS NULL OR CHAR_LENGTH(p_carrier)=0 OR CHAR_LENGTH(p_carrier) > 80 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:carrier'; END IF;
SET p_tracking = TRIM(p_tracking);
IF p_tracking IS NULL OR CHAR_LENGTH(p_tracking)=0 OR CHAR_LENGTH(p_tracking) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:tracking'; END IF;
SET v_status=NULL;
SELECT StatusCode,SubmittedAt INTO v_status,v_submitted FROM OrderHeader WHERE OrderID=p_order FOR UPDATE;
IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:order'; END IF;
IF v_status<>'READY_TO_SHIP' OR EXISTS(SELECT 1 FROM Shipment WHERE OrderID=p_order) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:status'; END IF;
SELECT MAX(OccurredAt) INTO v_ready FROM AuditLog WHERE OrderID=p_order AND EventType='ORDER_READY';
IF v_ready IS NULL OR p_time<v_ready OR p_time<v_submitted THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:dispatch_time'; END IF;
INSERT INTO Shipment VALUES(p_order,p_carrier,p_tracking,p_time);
CALL sp_append_audit(p_actor,p_time,'CREATE','Shipment',CAST(p_order AS CHAR),'OrderID',NULL,p_order,NULL,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Shipment',CAST(p_order AS CHAR),'Carrier',NULL,p_carrier,NULL,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Shipment',CAST(p_order AS CHAR),'TrackingNumber',NULL,p_tracking,NULL,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'CREATE','Shipment',CAST(p_order AS CHAR),'DispatchedAt',NULL,p_time,NULL,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'ORDER_SHIPPED','OrderHeader',CAST(p_order AS CHAR),'StatusCode',v_status,'SHIPPED',NULL,p_context,p_order,NULL);
COMMIT;
SELECT p_order AS OrderID,'SHIPPED' AS StatusCode;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_cancel_order(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_order INT UNSIGNED, IN p_reason TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_status VARCHAR(16); DECLARE v_submitted DATETIME(6);
DECLARE v_id INT UNSIGNED; DECLARE v_product INT UNSIGNED; DECLARE v_qty INT;
DECLARE v_stock INT; DECLARE v_done BOOLEAN DEFAULT FALSE;
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE cur_lines CURSOR FOR SELECT ProductID,Quantity FROM OrderLine WHERE OrderID=p_order ORDER BY ProductID;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=TRUE;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_reason = TRIM(p_reason);
IF p_reason IS NULL OR CHAR_LENGTH(p_reason)=0 OR CHAR_LENGTH(p_reason) > 255 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:reason'; END IF;
SET v_status=NULL;
SELECT StatusCode,SubmittedAt INTO v_status,v_submitted FROM OrderHeader WHERE OrderID=p_order FOR UPDATE;
IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:order'; END IF;
IF v_status NOT IN ('PENDING','READY_TO_SHIP') OR EXISTS(SELECT 1 FROM Shipment WHERE OrderID=p_order) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:status'; END IF;
IF p_time<v_submitted THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;
SET v_done=FALSE;
OPEN cur_lines;
read_lines: LOOP
 FETCH cur_lines INTO v_product,v_qty;
 IF v_done THEN LEAVE read_lines; END IF;
 SELECT ProductID INTO v_id FROM Product WHERE ProductID=v_product FOR UPDATE;
 SELECT AvailableQuantity INTO v_stock FROM Inventory WHERE ProductID=v_product FOR UPDATE;
IF CAST(v_stock AS SIGNED)+v_qty>2147483647 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:stock_range'; END IF;
 UPDATE Inventory SET AvailableQuantity=AvailableQuantity+v_qty WHERE ProductID=v_product;
CALL sp_append_audit(p_actor,p_time,'STOCK_RESTORED','Inventory',CAST(v_product AS CHAR),'AvailableQuantity',v_stock,v_stock+v_qty,p_reason,p_context,p_order,NULL);
END LOOP;
CLOSE cur_lines;
UPDATE OrderHeader SET StatusCode='CANCELLED',CancellationReason=p_reason,CancelledAt=p_time WHERE OrderID=p_order;
CALL sp_append_audit(p_actor,p_time,'ORDER_CANCELLED','OrderHeader',CAST(p_order AS CHAR),'StatusCode',v_status,'CANCELLED',p_reason,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'UPDATE','OrderHeader',CAST(p_order AS CHAR),'CancellationReason',NULL,p_reason,p_reason,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'UPDATE','OrderHeader',CAST(p_order AS CHAR),'CancelledAt',NULL,p_time,p_reason,p_context,p_order,NULL);
COMMIT;
SELECT p_order AS OrderID,'CANCELLED' AS StatusCode;

END$$

CREATE DEFINER='{{DEFINER}}'@'localhost' PROCEDURE sp_correct_tracking(
IN p_actor INT UNSIGNED, IN p_time DATETIME(6), IN p_context TEXT, IN p_order INT UNSIGNED, IN p_carrier TEXT, IN p_tracking TEXT, IN p_reason TEXT
)
SQL SECURITY DEFINER
main: BEGIN
DECLARE v_status VARCHAR(16); DECLARE v_submitted DATETIME(6);
DECLARE v_carrier VARCHAR(80); DECLARE v_tracking VARCHAR(100); DECLARE v_dispatched DATETIME(6);
DECLARE v_role VARCHAR(16);
DECLARE v_active BOOLEAN;
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SET p_context = TRIM(p_context);
IF p_context IS NULL OR CHAR_LENGTH(p_context)=0 OR CHAR_LENGTH(p_context) > 64 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:context'; END IF;
IF p_time IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;

SET v_role=NULL;
SELECT RoleCode,IsActive INTO v_role,v_active FROM UserAccount WHERE AccountID=p_actor FOR UPDATE;
IF v_role IS NULL OR v_active<>1 OR v_role<>'STAFF' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='forbidden'; END IF;
SET p_reason = TRIM(p_reason);
IF p_reason IS NULL OR CHAR_LENGTH(p_reason)=0 OR CHAR_LENGTH(p_reason) > 255 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:reason'; END IF;
SET p_carrier = TRIM(p_carrier);
IF p_carrier IS NULL OR CHAR_LENGTH(p_carrier)=0 OR CHAR_LENGTH(p_carrier) > 80 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:carrier'; END IF;
SET p_tracking = TRIM(p_tracking);
IF p_tracking IS NULL OR CHAR_LENGTH(p_tracking)=0 OR CHAR_LENGTH(p_tracking) > 100 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:tracking'; END IF;
SET v_status=NULL;
SELECT StatusCode,SubmittedAt INTO v_status,v_submitted FROM OrderHeader WHERE OrderID=p_order FOR UPDATE;
IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='not_found:order'; END IF;
IF v_status<>'SHIPPED' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='conflict:status'; END IF;
SELECT Carrier,TrackingNumber,DispatchedAt INTO v_carrier,v_tracking,v_dispatched FROM Shipment WHERE OrderID=p_order;
IF (BINARY v_carrier=BINARY p_carrier AND BINARY v_tracking=BINARY p_tracking) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:unchanged_tracking'; END IF;
IF p_time<v_dispatched THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='invalid:time'; END IF;
UPDATE Shipment SET Carrier=p_carrier,TrackingNumber=p_tracking WHERE OrderID=p_order;
CALL sp_append_audit(p_actor,p_time,'TRACKING_CORRECTED','Shipment',CAST(p_order AS CHAR),'Carrier',v_carrier,p_carrier,p_reason,p_context,p_order,NULL);
CALL sp_append_audit(p_actor,p_time,'TRACKING_CORRECTED','Shipment',CAST(p_order AS CHAR),'TrackingNumber',v_tracking,p_tracking,p_reason,p_context,p_order,NULL);
COMMIT;
SELECT p_order AS OrderID,'SHIPPED' AS StatusCode;

END$$

DELIMITER ;
