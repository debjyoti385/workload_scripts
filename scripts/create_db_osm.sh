#!/bin/sh
DBNAME=$1
IMPORTOSM=$2

echo "CREATE DATABASE $DBNAME"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DBNAME;"
sudo -u postgres psql -c "CREATE DATABASE $DBNAME"

echo "INSTALLING POSTGIS FUNCTIONS IN DATABASE $DBNAME"
sudo -u postgres psql -d $DBNAME -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d $DBNAME -f  /usr/share/postgresql/10/contrib/postgis-2.4/legacy.sql >> $LOGFILE 2>&1

echo "INSTALLING PGROUTING FUNCTIONS IN DATABASE $DBNAME"
sudo -u postgres psql -d $DBNAME -c 'CREATE EXTENSION pgRouting;'

echo "IMPORTING OSM FILE TO DATABASE"
find $IMPORTOSM -type d -exec chmod 755 {} \;
find $IMPORTOSM -type f -exec chmod 644 {} \;
sudo -u postgres osm2pgsql --slim --database $DBNAME --keep-coastlines --style /usr/share/osm2pgsql/default.style --latlong  --number-processes 2 $IMPORTOSM

sudo -u postgres psql -d $DBNAME -c "VACUUM"
