\connect postgres;
CREATE DATABASE tpcds_db;
CREATE USER tpcds WITH PASSWORD 'tpcds';
GRANT ALL PRIVILEGES ON DATABASE "tpcds_db" to tpcds;
