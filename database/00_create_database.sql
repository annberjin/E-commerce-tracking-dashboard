-- Names and secrets are supplied by build/build_database.sh.
CREATE DATABASE `{{DB}}` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin;
USE `{{DB}}`;
CREATE TABLE BuildLog (
  BuildID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  RunID VARCHAR(64) NOT NULL,
  VersionTag VARCHAR(100) NOT NULL,
  CommitSHA CHAR(40) NOT NULL,
  ScriptPath VARCHAR(255) NOT NULL,
  StartedAt DATETIME(6) NOT NULL,
  FinishedAt DATETIME(6) NULL,
  Outcome VARCHAR(16) NOT NULL,
  ErrorMessage TEXT NULL
) ENGINE=InnoDB;
-- MySQL identities exist before routines refer to their definer.
CREATE USER '{{DEFINER}}'@'localhost' ACCOUNT LOCK;
CREATE ROLE '{{RUNTIME_ROLE}}';
CREATE USER '{{APP_USER}}'@'{{APP_HOST}}' IDENTIFIED BY '{{APP_PASSWORD_SQL}}';
