-- 01_create_users_and_db.sql
-- Create user and database

-- Drop existing user and database if they exist (safe for first run)
DROP DATABASE IF EXISTS mydb;
DROP ROLE IF EXISTS myuser;

-- Create Postgres role and database
CREATE ROLE myuser LOGIN PASSWORD 'mypassword';
CREATE DATABASE mydb OWNER postgres;

-- Connect to the database
\c mydb

-- Create schema
CREATE SCHEMA IF NOT EXISTS public;

-- Grant privileges for tables and sequences to ETL user
GRANT CONNECT ON DATABASE mydb TO myuser;
GRANT USAGE ON SCHEMA public TO myuser;
