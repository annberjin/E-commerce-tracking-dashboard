CREATE TABLE UserAccount (
  AccountID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  LoginName VARCHAR(100) COLLATE utf8mb4_0900_as_ci NOT NULL,
  DisplayName VARCHAR(100) NOT NULL,
  ContactEmail VARCHAR(254) NOT NULL,
  PasswordHash VARCHAR(255) NOT NULL,
  RoleCode VARCHAR(16) NOT NULL,
  IsActive BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (AccountID),
  UNIQUE KEY uq_useraccount_loginname (LoginName),
  CONSTRAINT fk_useraccount_rolecode FOREIGN KEY (RoleCode) REFERENCES Role (RoleCode) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_useraccount_01 CHECK (IsActive IN (0,1)),
  CONSTRAINT ck_useraccount_02 CHECK (CHAR_LENGTH(TRIM(LoginName)) > 0 AND OCTET_LENGTH(LoginName) = OCTET_LENGTH(TRIM(LoginName))),
  CONSTRAINT ck_useraccount_03 CHECK (CHAR_LENGTH(TRIM(DisplayName)) > 0 AND OCTET_LENGTH(DisplayName) = OCTET_LENGTH(TRIM(DisplayName))),
  CONSTRAINT ck_useraccount_04 CHECK (CHAR_LENGTH(TRIM(ContactEmail)) > 0 AND OCTET_LENGTH(ContactEmail) = OCTET_LENGTH(TRIM(ContactEmail))),
  CONSTRAINT ck_useraccount_05 CHECK (CHAR_LENGTH(TRIM(PasswordHash)) > 0 AND OCTET_LENGTH(PasswordHash) = OCTET_LENGTH(TRIM(PasswordHash))),
  CONSTRAINT ck_useraccount_06 CHECK (CHAR_LENGTH(TRIM(RoleCode)) > 0 AND OCTET_LENGTH(RoleCode) = OCTET_LENGTH(TRIM(RoleCode)))
) ENGINE=InnoDB;

CREATE TABLE Customer (
  CustomerID INT UNSIGNED NOT NULL,
  CustomerName VARCHAR(100) NOT NULL,
  PRIMARY KEY (CustomerID),
  CONSTRAINT fk_customer_customerid FOREIGN KEY (CustomerID) REFERENCES UserAccount (AccountID) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_customer_01 CHECK (CHAR_LENGTH(TRIM(CustomerName)) > 0 AND OCTET_LENGTH(CustomerName) = OCTET_LENGTH(TRIM(CustomerName)))
) ENGINE=InnoDB;

CREATE TABLE Product (
  ProductID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ProductCode VARCHAR(40) COLLATE utf8mb4_0900_as_ci NOT NULL,
  ProductName VARCHAR(150) NOT NULL,
  CurrentUnitPrice DECIMAL(10,2) NOT NULL,
  IsActive BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (ProductID),
  UNIQUE KEY uq_product_productcode (ProductCode),
  CONSTRAINT ck_product_01 CHECK (IsActive IN (0,1)),
  CONSTRAINT ck_product_02 CHECK (CurrentUnitPrice > 0),
  CONSTRAINT ck_product_03 CHECK (CHAR_LENGTH(TRIM(ProductCode)) > 0 AND OCTET_LENGTH(ProductCode) = OCTET_LENGTH(TRIM(ProductCode))),
  CONSTRAINT ck_product_04 CHECK (CHAR_LENGTH(TRIM(ProductName)) > 0 AND OCTET_LENGTH(ProductName) = OCTET_LENGTH(TRIM(ProductName)))
) ENGINE=InnoDB;

CREATE TABLE Inventory (
  ProductID INT UNSIGNED NOT NULL,
  AvailableQuantity INT NOT NULL DEFAULT 0,
  LowStockThreshold INT NOT NULL,
  PRIMARY KEY (ProductID),
  CONSTRAINT fk_inventory_productid FOREIGN KEY (ProductID) REFERENCES Product (ProductID) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_inventory_01 CHECK (AvailableQuantity >= 0),
  CONSTRAINT ck_inventory_02 CHECK (LowStockThreshold >= 0)
) ENGINE=InnoDB;
