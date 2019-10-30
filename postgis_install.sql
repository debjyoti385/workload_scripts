CREATE EXTENSION adminpack;

CREATE DATABASE gisdb;

\connect gisdb;
CREATE SCHEMA postgis;
ALTER DATABASE gisdb SET search_path=public, postgis, contrib;

\connect gisdb;  
CREATE EXTENSION postgis SCHEMA postgis;
SELECT postgis_full_version();

\connect gisdb;
CREATE  EXTENSION pgrouting SCHEMA postgis;
SELECT * FROM pgr_version();


