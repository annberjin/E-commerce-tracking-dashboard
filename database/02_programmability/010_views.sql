CREATE SQL SECURITY INVOKER VIEW v_order_value AS
SELECT OrderID, SUM(Quantity * AcceptedUnitPrice) AS OrderValue
FROM OrderLine GROUP BY OrderID;

CREATE SQL SECURITY INVOKER VIEW v_order_summary AS
SELECT h.OrderID, h.CustomerID, c.CustomerName, h.SubmissionReference,
       h.SubmittedAt, h.StatusCode, s.StatusName, v.OrderValue,
       sh.Carrier, sh.TrackingNumber, sh.DispatchedAt
FROM OrderHeader h
JOIN Customer c ON c.CustomerID=h.CustomerID
JOIN OrderStatus s ON s.StatusCode=h.StatusCode
JOIN v_order_value v ON v.OrderID=h.OrderID
LEFT JOIN Shipment sh ON sh.OrderID=h.OrderID;

CREATE SQL SECURITY INVOKER VIEW v_low_stock AS
SELECT p.ProductID,p.ProductCode,p.ProductName,i.AvailableQuantity,i.LowStockThreshold
FROM Product p JOIN Inventory i ON i.ProductID=p.ProductID
WHERE p.IsActive=1 AND i.AvailableQuantity<=i.LowStockThreshold;

CREATE SQL SECURITY INVOKER VIEW v_shipped_order_value AS
SELECT h.OrderID, sh.DispatchedAt, v.OrderValue
FROM OrderHeader h JOIN Shipment sh ON sh.OrderID=h.OrderID
JOIN v_order_value v ON v.OrderID=h.OrderID
WHERE h.StatusCode='SHIPPED';
