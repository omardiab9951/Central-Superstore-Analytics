-- Phase 3, step 1: create the project database and its warehouse schema.
-- Run this file with psql while connected to the built-in "postgres" database.
-- The conditional CREATE DATABASE makes this file safe to run more than once.

\set ON_ERROR_STOP on

-- A psql variable can select a disposable test database; otherwise use the project database.
\if :{?warehouse_db}
\else
\set warehouse_db central_superstore_dw
\endif

-- Create the warehouse database only when it does not already exist.
SELECT format('CREATE DATABASE %I', :'warehouse_db')
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = :'warehouse_db'
)\gexec

-- Switch this psql session to the project database before creating its schema.
\connect :warehouse_db

-- Keep the project's tables together in a clearly named PostgreSQL schema.
CREATE SCHEMA IF NOT EXISTS warehouse;

-- Explain the purpose of this schema in PostgreSQL's own metadata.
COMMENT ON SCHEMA warehouse IS
    'Phase 3 structure for the Central Superstore analytics warehouse';