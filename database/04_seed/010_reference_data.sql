START TRANSACTION;
INSERT INTO Role VALUES('CUSTOMER','Customer'),('STAFF','Staff'),('ADMINISTRATOR','Administrator');
INSERT INTO OrderStatus VALUES('PENDING','Pending'),('READY_TO_SHIP','Ready to Ship'),('SHIPPED','Shipped'),('CANCELLED','Cancelled');
COMMIT;
