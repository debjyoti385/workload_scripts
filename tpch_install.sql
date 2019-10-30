\connect postgres;
CREATE DATABASE tpch_db;
CREATE USER tpch WITH PASSWORD 'tpch';
GRANT ALL PRIVILEGES ON DATABASE "tpch_db" to tpch;
