# Functional Requirements Document

## 1. Project Identification

| Item | Information |
| --- | --- |
| Project title | E-commerce Order Tracking Dashboard |
| Prepared by | Bernardo Xie He & Henry Zhou |
| Course | 01:198:437:01 |
| Date | October 3, 2026 |
| Version | 1.3 |
| Repository | https://github.com/annberjin/E-commerce-tracking-dashboard |

## 2. Business Problem and Project Purpose

### 2.1 Business Problem

The project models an online retailer that stores order and inventory records in different spreadsheets and operational files. Staff must compile information from multiple sources to verify stock, determine order status, and identify record changes. This can result in the ordering of unavailable products, inconsistent status information, and incomplete transaction histories.

### 2.2 Project Purpose

The E-commerce Order Tracking Dashboard will provide a relational database system for managing orders, inventory, shipment information, user access, audit history, and sales reports. Customers will place and track their own orders. Staff will maintain products and inventory and process orders and shipments. Administrators will manage accounts and review sales and audit information.

The system will enforce stock availability, permitted status changes, and role-based access. It will preserve transaction history and support recovery after database interruption. A web dashboard will provide access to the authorized functions and reports.

## 3. Scope

### 3.1 In Scope

- User accounts and role-based access.
- Product and inventory management.
- Order placement, processing, cancellation, and tracking.
- Shipment records and tracking information.
- Audit history and operational and sales reports.
- Transaction integrity, recovery, and backup.
- A basic web dashboard.

### 3.2 Out of Scope

- Live payment processing.
- Automatic shipping carrier integration.
- Returns and refund processing.

## 4. Stakeholders and User Roles

| Role | Responsibilities |
| --- | --- |
| Customer | Browse products, place orders, and view their own order and shipment information. |
| Staff | Maintain products and inventory, prepare and ship orders, cancel eligible orders, and correct shipment tracking. |
| Administrator | Maintain accounts and customer profiles, control user access, and review sales and audit information. |

### 4.1 Access Permissions

| Capability | Customer | Staff | Administrator |
| --- | --- | --- | --- |
| Browse active products and availability | Yes | Yes | Yes |
| Submit an order | Own account only | No | No |
| View order details and tracking | Own orders only | All orders for fulfillment | All orders for review |
| Maintain products and available stock | No | Yes | No |
| Mark ready, dispatch, cancel, correct tracking | No | Yes, under the lifecycle rules | No |
| Create accounts/profiles, update account details, activate/deactivate accounts | No | No | Yes |
| View low-stock list | No | Yes | Yes |
| View monthly sales summary and full audit history | No | No | Yes |
| Delete orders or alter/delete existing audit entries | No | No | No |

## 5. Functional Requirements

| ID | Functional Requirement | Role |
| --- | --- | --- |
| FR-01 | The system will require authentication for protected operations and will enforce current account status and role. Access to protected operations shall not be granted to invalid credentials, inactive accounts, or signed out sessions. | All roles |
| FR-02 | The system will allow an administrator to create accounts with one permitted role, maintain names and contact details, and activate or deactivate accounts. Creating a customer account will also create its profile. All changes will be audited. | Administrator |
| FR-03 | The system will allow staff to create, update, or deactivate products with a unique code, name, current price, and low-stock threshold. Customers will be able to view active products and their prices and availability. Inactive products will remain in historical orders. | Staff, Customer |
| FR-04 | The system will allow staff to adjust a product's stock under BR-06 and BR-16. The system will record the reason for the adjustment, the adjustment reference, and the quantities before and after the adjustment. Staff will be able to retrieve their own adjustment results by reference. | Staff |
| FR-05 | The system will accept valid customer orders with delivery details, a submission reference, and one or more distinct product lines. It will store the accepted quantities and prices, the address, and the initial pending status. It will also reduce the available stock and record the merchandise value and return the order reference. | Customer |
| FR-06 | The system will allow customers to view their order list, line details, merchandise value, status timeline, and shipment tracking, if available. | Customer |
| FR-07 | The system will allow staff to list and filter orders by status. They will also be able to retrieve an order by reference and access its customer and delivery details, lines, current status, and shipment information. | Staff |
| FR-08 | The system will allow staff to move an order from "Pending" to "Ready to Ship," recording the user and time. Other preparation transitions will be rejected. | Staff |
| FR-09 | The system will allow staff to cancel pending or ready-to-ship orders without shipping them and with a recorded reason. This will restore every ordered quantity exactly once. | Staff |
| FR-10 | The system will allow staff to dispatch a ready-to-ship order by recording a carrier and tracking number, creating a shipment, recording the dispatch time, and setting the order's status to "Shipped." | Staff |
| FR-11 | The system will allow staff to correct the carrier/tracking details of a shipped order with an explanation and previous/new audit values. The order, items, address, and dispatch time will not change. | Staff |
| FR-12 | The system must commit each business operation and its required audit records together or roll back all of that operation’s changes. | System |
| FR-13 | The system will prevent duplicate orders and stock updates on retries. It will also reject changes that would result in overselling inventory, losing a stock update, creating a second shipment, or both shipping and canceling an order. | System |
| FR-14 | The system will audit the events and content defined in Section 9, as well as preserve an order's status history. | System |
| FR-15 | The system shall let an Administrator retrieve the audit history of a selected order or other affected record using RQ-04. | Administrator |
| FR-16 | The system will provide the monthly summary of shipped merchandise defined in RQ-03. | Administrator |
| FR-17 | The system will provide the low-stock list defined in RQ-02. | Staff, Administrator |
| FR-18 | The system will provide an online interface for authorized operations and reports. This interface will include confirmation messages for successful operations and clear validation or service unavailability messages. | All roles |
| FR-19 | Following an unexpected database shutdown or power outage, the system will preserve committed business transactions and audit records, and eliminate the effects of incomplete transactions under Section 9.3. | System |
| FR-20 | The system should accurately report database unavailability and unconfirmed transaction results. After reconnection, authorized users should be able to view saved results and retry without creating duplicate orders, stock, or shipments. | All roles |
| FR-21 | An authorized maintainer shall be able to create a consistent backup of the schema, business data, and audit history, store a protected copy separately, and verify restoration into an empty database under Section 9.3. | Authorized maintainer |

## 6. Transaction Flows and Use Cases

Each modifying action constitutes a separate transaction. If an action fails before it is committed, it is rolled back. An uncertain result follows FR-20 and BR-21.

### UC-01 Place an Order

Actor/Trigger: Customer submits the order entry form.
Preconditions: Active customer account/profile, required delivery details, product quantities, and submission reference supplied.
Related requirements: FR-05, FR-12, FR-13, and FR-14.

1. Verify the customer's identity and reject any submission reference that has already been used under BR-16.
2. Validate all lines, delivery fields, active products, and current stock. Obtain current product prices.
3. Create one pending order and its lines using the submitted address snapshot and current accepted prices.
4. Deduct the ordered quantity of each product and record the linked order, stock, and status audit events.
5. Commit the order and return the order reference, status, and calculated value.

Exceptions: An invalid line, insufficient stock, unauthorized action, or known write failure will reject the entire order, without partial records, stock deductions, or successful audit events. Concurrent purchases cannot exceed the available stock.

Postcondition: One pending order has been accepted, the accepted price and address have been retained, and the stock has been deducted once.

### UC-02 Prepare and Ship an Order

Actor/Trigger: Staff selects a pending order.
Preconditions: Authorized staff account and an existing order.
Related requirements: FR-07, FR-08, FR-10, FR-11, FR-12, FR-13, and FR-14.

1. The staff reviews the order lines and delivery information, and then marks the order as ready to ship. The transition and audit events are committed together.
2. When the order is dispatched, staff provide the carrier and tracking details.
3. The system rechecks that the order is ready to ship and has no shipments.
4. The system creates the shipment, records the dispatch time, changes the order to "Shipped," logs audit events, and commits. No further stock deduction occurs.
5. The customer can retrieve the shipment information. Any later tracking typos can be corrected under FR-11 as a separate audited operation.

Exceptions: Rejection without changes occurs if there is missing tracking data, an invalid state, or an existing shipment. If a cancellation is committed first, the dispatch is rejected and the order remains canceled.

Postcondition: One shipment is linked to the shipped order, and its dispatch and status history are retained.

### UC-03 Cancel an Unshipped Order

Actor/Trigger: Staff requests a cancellation and provides a reason.
Preconditions: Pending or Ready to Ship order with no shipment.
Related requirements: FR-09, FR-12, FR-13, and FR-14.

1. Verify staff permission, a non-blank reason, the current status, and the absence of a shipment.
2. Restore the ordered quantity to available stock.
3. Change the order to "Cancelled" and record the reason, actor, time, status change, and stock effects.
4. Commit and confirm the cancellation.

Exceptions: An unauthorized user, missing reason, "Shipped/Cancelled" status, or a dispatch that was committed first will cause rejection. Repeated cancellations never restore stock twice.

Postcondition: The order and lines are stored as canceled, the inventory is restored once, and the history remains readable.

## 7. Data Requirements

| Data Subject | Required Information and Relationship |
| --- | --- |
| UserAccount | Each account has a unique login and display name, as well as protected authentication information and an active state. An account may have zero or one customer profile. |
| Role | There are three fixed role codes and their meanings. One role can belong to multiple accounts, but each account has only one role. |
| Customer | Name and contact email. Each customer belongs to exactly one customer account. A customer can have zero or more orders. |
| Product | Each product has a unique code, name, current unit price, and active state. One product can appear on multiple order lines. |
| Inventory | Available quantity and low-stock threshold. There is exactly one record per product. |
| OrderHeader | Each order has a unique order reference, customer submission reference, submission time, current status, recipient/address snapshot, and, when applicable, cancellation reason and time. Each order belongs to one customer. |
| OrderLine | Parent order, line number, product, quantity, and accepted unit price. Each line belongs to one order and one product. |
| OrderStatus | Fixed Pending, Ready to Ship, Shipped, and Cancelled codes and meanings; each order has one current status. |
| Shipment | Parent order, carrier, tracking number, and dispatch time. Each shipment belongs to one order, and each order has either zero or one shipment. |
| AuditLog | The required fields are actor, event type, time, affected record, context reference, previous/new values, and reason. Stock adjustments also retain their unique adjustment reference. Order events link back to their respective orders. |

An accepted order has at least one line. The OrderLine entity resolves the many-to-many relationship between orders and products. It is a weak entity identified by its parent order and a line number that is meaningful only within that order. The Account/Customer and Product/Inventory entities provide one-to-one relationships, while the Customer/Order entity provides a one-to-many relationship.

The audit log will retain the order status timeline and manual stock adjustment history, as well as support authorized history queries.

Required delivery data: recipient, street address, city/locality, postal code, and country; region/state is optional.

## 8. Business Rules and Validation

| ID | Rule |
| --- | --- |
| BR-01 | The required records and parent relationships must exist. After trimming and case-insensitive comparison, login identifiers and product codes are unique. Identifiers and account/customer ownership links cannot be reassigned. Required text must not be blank. |
| BR-02 | Protected actions require an active account with one permitted role assigned at the time the account is created. This role cannot be changed. Customer accounts require a linked profile. |
| BR-03 | Each order contains one or more distinct products, each with a positive whole-number quantity. Each order has unique line numbers, and a product cannot appear twice in the same order. |
| BR-04 | A new order requires active products and sufficient stock. The system uses the current prices of the products at the time of acceptance to calculate totals, and client-supplied values cannot override them. |
| BR-05 | Prices are positive amounts in USD with a maximum of two decimal places. Line value is the quantity multiplied by the accepted unit price, and order value is the sum of the line values. Accepted prices are not affected by later product-price changes. |
| BR-06 | Stock and low-stock thresholds are nonnegative whole numbers. New products start with a stock value of zero. Manual adjustments require a change of a non-zero whole number and a reason. They must not produce negative stock and must retain the before and after values. |
| BR-07 | Order acceptance deducts stock once, and an eligible cancellation restores it. Corrections to the ready, shipping, and tracking statuses do not change stock. Available stock represents uncommitted, sellable units. |
| BR-08 | Acceptance is all-or-nothing across all product lines, stock changes, and required audit events. If one product is unavailable, the entire order is rejected. |
| BR-09 | Only the following lifecycle transitions are permitted: "Shipped" and "Cancelled" have no outgoing status transitions. Unknown values, skipped stages, and backward moves are rejected. |
| BR-10 | A shipment requires a "Ready to Ship" order, non-blank carrier/tracking details, and no existing shipment. Each order can have only one shipment. |
| BR-11 | Only pending or ready-to-ship orders with no shipment and a reason can be canceled by staff. Keep the order and its lines, but never reopen or restore its stock again. |
| BR-12 | The accepted customer, submission time, address, products, quantities, and prices are fixed. To correct an unshipped order, issue an eligible cancellation and create a new customer submission. |
| BR-13 | Staff can only correct the carrier and tracking information for a shipped order with a reason and the new values. The dispatch time and all other finalized order facts are immutable. |
| BR-14 | Business users cannot delete orders, shipments, referenced accounts or products, or audit events. Deactivation prevents future access and purchases without canceling accepted orders or erasing history. |
| BR-15 | Each modification operation is an atomic process that includes the necessary successful audit writes. This includes account/profile creation, product/inventory creation, adjustments, status changes, dispatch, and cancellation. A required audit failure causes a rollback. |
| BR-16 | Order references uniquely identify orders. Submission references are unique to each customer, and adjustment references are unique to each staff account that initiates them. Reusing a committed submission or adjustment reference that has already been processed will not produce any new effects, even if its content differs. The authorized user can retrieve the existing result. A fully rolled-back request may be retried. |
| BR-17 | Concurrent actions must not result in overselling, losing stock changes, duplicating shipments, or dispatching and canceling an order. Any conflicting requests are rejected or safely reevaluated against the current state. |
| BR-18 | The system records event times in UTC. Dispatch cannot precede acceptance or readiness. Date filters include the entire selected start and end date range, and the start date must not follow the end date. |
| BR-19 | A product is considered to be in low stock when its available quantity is at or below its configured threshold. |
| BR-20 | Sales are calculated from accepted line prices and represent the value of shipped merchandise, grouped by dispatch month. Only include shipped orders and count each order once. The totals represent merchandise value only. |
| BR-21 | Only show success after the commit is confirmed. If the connection is lost, the outcome is unconfirmed until the saved reference, status, and history are checked. Only retry using the original reference after the prior attempt is resolved. An unresolved attempt must not start a duplicate operation. |

| Current state | Action and next state | Role and condition |
| --- | --- | --- |
| No order | Submit -> Pending | Customer; valid complete order |
| Pending | Mark ready -> Ready to Ship | Staff; order preparation complete |
| Ready to Ship | Dispatch -> Shipped | Staff; one valid shipment created atomically |
| Pending or Ready to Ship | Cancel -> Cancelled | Staff; no shipment and reason provided |
| Shipped or Cancelled | No status change | Authorized viewing remains available; FR-11 permits audited tracking correction on Shipped |

## 9. Security, Entitlements, Auditing, and Recovery

### 9.1 Security Requirements

| ID | Requirement |
| --- | --- |
| SEC-01 | Verify identity, account status, role, and ownership for every protected request. Deactivation or signing out blocks subsequent requests, including those from an already open page. |
| SEC-02 | Access to customer orders and shipments is limited to owned records. When changing request identifiers, do not expose another customer's information. Customer timelines contain statuses and times, not staff identities or internal audit details. |
| SEC-03 | Enforce Section 4 permissions in the database, the controlled backend, or a documented combination of the two. Authorization must be enforced for every protected operation. Block unlisted protected actions and attempts by clients to impersonate other users. |
| SEC-04 | Only store application passwords as salted password hashes using an established password-handling library. Never store plaintext or reversibly encrypted passwords. Keep secrets out of source code, reports, and logs. Protect authentication sessions, and use encrypted connections for non-local access. |
| SEC-05 | Runtime business roles, including the administrator role, cannot alter or delete existing audit records or bypass finalized-record rules. Keep unrestricted build credentials separate from runtime access. |
| SEC-06 | Safely record failed sign-ins, denied protected operations, and failed critical transactions. Return useful error messages without revealing SQL internals, secrets, or another user's data. |
| SEC-07 | User-supplied input should be treated as data. It should not change the structure of database commands, bypass sign-in, or expand access. Validate inputs against business rules, and apply the same checks to direct requests as to forms. |

### 9.2 Audit Requirements

Track audit account/profile creation and updates, activation/deactivation, product creation, price/status/threshold changes, manual stock adjustments, order acceptance and deductions, readiness, cancellations and restorations, dispatch, and tracking corrections.

Each successful event retains the identified actor, UTC timestamp, event type, affected record, shared transaction/context reference, and meaningful prior and new values. Reasons are required for adjustments, cancellations, and tracking corrections. Linked events allow reconstruction of an order's lifecycle and stock effects.

Successful audit events are committed with their business transactions. A required audit write failure causes a rollback. Known failures shall be recorded separately in a protected log after rollback when logging storage is available. Uncertain outcomes shall be labeled as unconfirmed. Unidentified actors in security failures shall be labeled as unknown.

### 9.3 Recovery Requirements

| Situation | Required outcome |
| --- | --- |
| Known failure before commit | Undo the entire operation, including stock effects and successful audit events, while retaining previously committed work. |
| Unexpected database stop or power loss | After a restart, retain the committed changes and remove the effects of incomplete transactions. |
| Commit response lost | Report an unconfirmed result. Check the saved reference or history before retrying to avoid duplicate effects. |
| Database unavailable | Report the temporary unavailability of database-dependent operations. Preserve authorization, and do not confirm unsaved changes or present unavailable data as empty results. |
| Primary storage lost or corrupt | Restore the last verified backup and use its timestamp as the recovery point. Any changes made after that point may be lost. |

Crash recovery requires persistent data and log storage that remains intact and honors durable writes. The TDD will specify the durability configuration.

Manual backups should include the schema, business data, and audit history with a timestamp, as well as a restricted copy on a separate device or service. Verify the contents, relationships, audit history, and access controls when restoring to a separate empty database.

## 10. Reports and Queries

Reports should enforce role and ownership restrictions, display USD amounts to two decimal places, accommodate empty results, and reject date ranges for which the start date follows the end date.

| ID | Report and Audience | Required Output |
| --- | --- | --- |
| RQ-01 | Order List and Tracking; Customer: owned orders. Staff/Administrator: all orders. | The list includes the order reference, submission time, status, and merchandise value. Staff and administrators can also see the customer reference and name. There is an optional status filter. Sort by submission time in descending order, then by order reference in descending order. Look up by order reference to see lines in line number order, accepted prices, quantities, address, status timeline, and carrier, tracking, and dispatch time, if present. Customers can also use their original submission reference to check an uncertain result. The customer timeline omits the internal actor and reason fields. |
| RQ-02 | Low-Stock Report; Staff/Administrator. | Include active product code/name, available quantity, and threshold. Include stock at or below the threshold. Sort by quantity in ascending order, then by code in ascending order. |
| RQ-03 | Monthly Sales Summary; Administrator. | For the selected UTC dispatch date range, group by year/month. Show the distinct order count and the total value of shipped merchandise. Sort by month in ascending order. Exclude unshipped and canceled orders, counting each order and its value only once. If there are no matches, there will be no monthly rows, and the overall count and value will be zero. |
| RQ-04 | Audit History Report; Administrator. | The affected record, the optional actor, and the optional UTC date range can all be used as filters. For an order, include related stock and shipment events. Show the event type, actor, time, context, and reason, if applicable, as well as the previous and new values. Sort by time, then by audit identifier in ascending order. |

## 11. Assumptions and Constraints

### 11.1 Operating Assumptions

- One retailer has one inventory location. Prices and reports are in USD, and timestamps are in UTC.
- Administrators set up accounts and customers place their own orders.
- Shipment information is entered manually. The status is 'shipped' rather than 'confirmed delivery'.
- The application has one backend, which is divided into separate functional responsibilities, and one MySQL database.

### 11.2 Project Constraints

| ID | Constraint |
| --- | --- |
| C-01 | Use MySQL with fictional data. In the README and TDD, document the server/client versions, prerequisites and configuration. |
| C-02 | Provide the FRD, TDD, ERD and schema scripts, as well as the repository build/initialisation script. Maintain Markdown documentation for each diagram, including the .drawio source, .svg export and explanatory Markdown under the 'docs' folder. The data model should depict the data requirements in Section 7 using meaningful entities, 3NF, one-to-one, one-to-many and many-to-many relationships, a weak entity, keys, cardinality and optionality. |
| C-03 | Build from a verified Git tag and record its commit SHA. Use the 'build/', 'database/', and 'docs/' directories, as well as an ordered manifest for schema, programmability, security, seed data, and validation. Provide a Bash or PowerShell build script. Check the tools, configuration, connectivity and manifest contents before making any changes to the database. Require explicit authorisation before replacing an existing database. Stop on script or validation failure. Record the tag, commit and timestamps, as well as the script results and errors, in file logs and, where permitted, in a build-log table. Keep credentials out of source code and logs. |
| C-04 | Show the transactions that were successful and those that were not, as well as the key/relationship/uniqueness/null/domain constraints, role and ownership controls, audit history, the trigger that makes an update and transaction rollback. Include joins, updates, subqueries, aggregates and exception handling. Provide realistic sample data, justified indexes and denormalised reporting views, as well as EXPLAIN evidence. Address batch, read, update, delete, high transaction volume and large extract workloads in the TDD. |
| C-05 | Provide a web interface that is connected to the backend and database. Document the system architecture, APIs, data flow, interface wireframes, security controls, encrypted connections and considerations for growth. |

## 12. Acceptance Criteria and Traceability

### 12.1 Acceptance Criteria

| ID | Related Requirements | Data and Controls | Expected Outcome |
| --- | --- | --- | --- |
| AC-01 | FR-01, FR-02; BR-01, BR-02; SEC-01, SEC-03 | UserAccount, Role, Customer; authentication and permissions | The creation of valid accounts/profiles and account updates are audited. Duplicate logins, invalid roles and incomplete required data are rejected. Invalid credentials, inactive accounts and signed-out sessions cannot perform protected actions, nor can unauthorised roles. Deactivation blocks the next protected request. |
| AC-02 | FR-03, FR-04; BR-01, BR-05, BR-06, BR-14, BR-16 | Product, Inventory, AuditLog; validation and adjustment references | Products start with a stock level of zero; only active products appear in the customer catalogue. Valid stock adjustments retain the quantities and reasons for the adjustment before and after. Invalid prices, quantities, duplicate codes/references and adjustments that would make stock negative are rejected. Deactivation retains historical records, and staff can retrieve their own adjustment results. |
| AC-03 | FR-05; UC-01; BR-03 through BR-08, BR-12 | OrderHeader, OrderLine, Product, Inventory; accepted prices and atomic writes | Ordering two items worth \$20 and one item worth \$15 creates one pending order worth \$55 and reduces stock by the accepted quantities. Orders containing empty lines, repeated products, missing delivery data, invalid quantities, inactive products or insufficient stock will fail without partial changes. Accepted prices are taken from the catalogue and later price/profile changes do not affect the order. |
| AC-04 | FR-06, FR-07; RQ-01; SEC-02, SEC-03 | Customer, OrderHeader, OrderLine, Shipment; ownership and scoped queries | Customers can retrieve their own order details, timeline and tracking information. Altered identifiers do not expose the records or internal audit details of other customers. Staff can retrieve orders by reference and status. The returned fields and ordering match RQ-01. |
| AC-05 | FR-08, FR-10, FR-11; UC-02; BR-09, BR-10, BR-12, BR-13 | OrderStatus, OrderHeader, Shipment, AuditLog; permitted transitions | 'Pending' can become 'Ready to Ship', and then 'Shipped', provided that there is one complete shipment and the stock remains unchanged. Invalid transitions, missing tracking data and duplicate shipments will fail. Tracking corrections retain the original reason and values; accepted order facts and dispatch time remain unchanged. |
| AC-06 | FR-09; UC-03; BR-07, BR-11 | OrderHeader, OrderLine, Inventory, AuditLog; cancellation transaction | Cancelling a pending or ready-to-ship order and providing a reason restores the stock for each line and retains the order/history. Repeated cancellations, cancellations without a reason, unauthorised users and cancellations after shipment do not result in any changes. |
| AC-07 | FR-12, FR-14; BR-08, BR-15; SEC-06 | Business records and AuditLog; transaction boundaries | Controlled failure during a multi-record operation, required audit-write failure and session termination before committing each leave behind no partial business changes or successful audit events. Failure logs distinguish between failure and success and contain no secrets. |
| AC-08 | FR-13; BR-16, BR-17 | Inventory, OrderHeader, Shipment; duplicate and concurrency controls | Reusing a submission/adjustment reference that has already been committed does not have any repeated effects. Two orders competing for the last unit result in one order being successful and the stock being reduced to zero. Concurrent stock updates do not lose any committed changes. Competing dispatch or cancellation requests produce one valid outcome. |
| AC-09 | FR-14, FR-15; BR-14, BR-15, BR-18; SEC-05, SEC-06; RQ-04 | AuditLog and affected records; protected history | Events relating to accounts, products, stock and orders retain the required information about the actor, time, context, reasons and prior/new values. An administrator can reconstruct an order's lifecycle and the effect on stock. Attempts to alter or delete audit history or protected finalised records at runtime fail. RQ-04 filters return matching events. |
| AC-10 | FR-16, FR-17; BR-18 through BR-20; RQ-01 through RQ-04 | Product, Inventory, OrderHeader, OrderLine, Shipment; report calculations | With a threshold of 3, stock quantities of 2 and 3 appear as 'low stock'; quantity 4 does not. Shipped orders worth \$55 and \$40 in the selected month count as 2 and have a value of \$95. Unshipped and cancelled orders are excluded. Report fields, date boundaries, ordering and empty results match those in Section 10; invalid date ranges are rejected. |
| AC-11 | FR-18; SEC-01 through SEC-07; C-05 | Web interface, backend, credentials, and sessions | Each role can complete its authorised workflows and reports, with clear confirmation or error messages. The same permissions and validation apply to forms and direct requests. SQL-like input cannot alter the behaviour or access of commands. Credentials, sessions and non-local connections comply with SEC-04. |
| AC-12 | FR-19, FR-20; BR-15 through BR-17, BR-21; Section 9.3 | Persistent business/audit data; recovery and result lookup | After a controlled, abrupt stop and restart of the database, committed records and audits remain, and uncommitted effects are absent. During an outage, the interface reports unavailability. A lost commit response can be resolved by referring to the original record; checking or retrying will not result in duplicate stock, orders or shipments. |
| AC-13 | FR-21; Section 9.3 | Protected backup and restored database | A consistent backup includes a timestamp and a restricted copy stored separately. The restoration process recreates the backed-up records, relationships, audit history and access controls in an empty database. The recovery point matches the backup. |
| AC-14 | C-01 through C-03 | Repository, manifest, build script, schema, and logs | The README instructions explain how to reproduce the database from a selected Git tag, including the recorded commit, required objects, seed data and passing validation. Missing prerequisites/files, repository/tag retrieval failure, tag mismatch, connection failure, empty/invalid/misordered manifests and script/validation failures will stop the build, providing useful logs. Existing databases are protected from unauthorised replacement and logs contain no sensitive information. |
| AC-15 | C-02, C-04, C-05 | ERD, TDD, schema objects, queries, and interface | The deliverables demonstrate the 3NF, the required relationship types and weak entity, the enforced constraints, the update trigger and the required SQL operations. Reproducible query data, index rationale and EXPLAIN evidence support performance analysis. The architecture, API/data flow, wireframes and security documentation match the implemented system. |

### 12.2 Traceability and Change Impact

The TDD should map the significant requirements and acceptance criteria to schema objects, enforcement methods, test scripts and demonstration evidence. The test plan should detail positive, negative, boundary and exception cases, including setup, executed actions or SQL, expected and actual results, and pass/fail evidence.

If a requirement changes, all linked rules, workflows, data, permissions, reports, implementation and tests must be reviewed and updated. Any affected tests must be repeated, and schema or build changes require fresh-build validation. All changes and verification results must be recorded in version control.
