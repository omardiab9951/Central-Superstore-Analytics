-- Phase 3, step 1: create the project database and its warehouse schema.
-- Run this file with psql while connected to the built-in "postgres" database.
-- The conditional CREATE DATABASE makes this file safe to run more than once.

\set ON_ERROR_STOP on

-- Create the warehouse database only when it does not already exist.
SELECT 'CREATE DATABASE central_superstore_dw'
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'central_superstore_dw'
)\gexec

-- Switch this psql session to the project database before creating its schema.
\connect central_superstore_dw

-- Keep the project's tables together in a clearly named PostgreSQL schema.
CREATE SCHEMA IF NOT EXISTS warehouse;

-- Explain the purpose of this schema in PostgreSQL's own metadata.
COMMENT ON SCHEMA warehouse IS
    'Phase 3 structure for the Central Superstore analytics warehouse';