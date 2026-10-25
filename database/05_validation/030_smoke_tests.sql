DELIMITER $$
CREATE PROCEDURE sp_validate_reports()
BEGIN
IF (SELECT COUNT(*) FROM v_shipped_order_value)<>2 OR (SELECT SUM(OrderValue) FROM v_shipped_order_value)<>95.00 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='validation:sales'; END IF;
IF (SELECT COUNT(*) FROM v_low_stock)<>1 OR NOT EXISTS(SELECT 1 FROM v_low_stock WHERE ProductCode='PLOW' AND AvailableQuantity=3) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='validation:low_stock'; END IF;
END$$
DELIMITER ;
CALL sp_validate_reports();
DROP PROCEDURE sp_validate_reports;
SELECT OrderID,StatusCode,OrderValue FROM v_order_summary ORDER BY OrderID;
SELECT * FROM v_low_stock;
SELECT DATE_FORMAT(DispatchedAt,'%Y-%m') AS Month,COUNT(*) AS Orders,SUM(OrderValue) AS Sales FROM v_shipped_order_value GROUP BY DATE_FORMAT(DispatchedAt,'%Y-%m');
EXPLAIN SELECT * FROM OrderHeader WHERE CustomerID=4 ORDER BY SubmittedAt DESC,OrderID DESC;
SELECT 'Smoke tests passed' AS Result;
