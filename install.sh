#!/bin/bash
PG_DATA_DIR="`pwd`/data/postgres_data";
BENCHMARK_DATA_DIR="`pwd`/data/benchmark_data";
LOGFILE="`pwd`/install.log";
BENCHMARK="";
SF=1
INSTALL=1
IMPORT=1

function usage()
{
    echo -e "INSTALL SCRIPT FOR postgresql AND benchmarks ON UBUNTU 16.04 AND 18.04"
    echo -e ""
    echo -e "sudo ./install.sh OR sudo bash install.sh"
    echo -e "\t-h --help"
    echo -e "\t-b --benchmark=$BENCHMARK # tpch/tpds/spatial/osm"
    echo -e "\t--pgdata=$PG_DATA_DIR # default"
    echo -e "\t--data=$BENCHMARK_DATA_DIR # default"
    echo -e "\t--sf=$SF # default 1 GB "
    echo -e "\t--install=$INSTALL # 0 for run only"
    echo -e "\t--import=$IMPORT # 0 for no data import"
    echo -e ""
}

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        --pgdata)
            PG_DATA_DIR=$VALUE
            ;;
        --data)
            BENCHMARK_DATA_DIR=$VALUE
            ;;
        -b | --benchmark)
            BENCHMARK=$VALUE
            ;;
        --sf)
            SF=$VALUE
            ;;
        --install)
            INSTALL=$VALUE
            ;;
        --import)
            IMPORT=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done


if [ "$INSTALL" = 1 ] ; then

    echo "#######################################################################"
    echo "UPGRADING PACKAGES"
    echo "LOGFILE: $LOGFILE"
    echo "#######################################################################"
    sudo apt-get update >> /dev/null 2>&1
    #sudo apt-get upgrade -y  >> $LOGFILE 2>&1

    mkdir -p $PG_DATA_DIR
    mkdir -p $BENCHMARK_DATA_DIR

    echo "#######################################################################"
    echo "Install PostgreSQL 10"
    echo "#######################################################################"
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt `lsb_release -c -s`-pgdg main" >> /etc/apt/sources.list'
    wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | sudo apt-key add -
    sudo apt-get update >> /dev/null 2>&1
    sudo apt-get install postgresql-10 postgresql-contrib-10 -y >> $LOGFILE 2>&1

    echo "CHANGING POSTGRESQL default DATA DIRECTORY TO $PG_DATA_DIR"
    sudo systemctl stop postgresql
    sleep 5
    if [ ! -d "$PG_DATA_DIR/10/main" ]; then
        sudo rsync -av /var/lib/postgresql/ $PG_DATA_DIR >> $LOGFILE 2>&1
    fi
    if [ -d "/var/lib/postgresql/10/main" ]; then
        echo "BACK UP OLD DATA DIR"
        sudo mv /var/lib/postgresql/10/main /var/lib/postgresql/10/main.bak
    fi

    echo "UPDATING CONFIGURATION FILE"
    if [ -f "/etc/postgresql/10/main/postgresql.conf" ]; then
        sudo cp /etc/postgresql/10/main/postgresql.conf /etc/postgresql/10/main/postgresql.conf.bak
    fi
    if [ -f "configs/postgresql.conf" ]; then
        echo "UPDATING postgresql.conf CONFIG FILE "
        sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' configs/postgresql.conf
        sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' configs/postgresql_execute.conf
        sudo cp configs/postgresql.conf /etc/postgresql/10/main/postgresql.conf
    fi
    sudo usermod -a -G `id -g -n` postgres
    sudo chown -R  postgres:`id -g -n` $PG_DATA_DIR
    sudo systemctl start postgresql


    echo "#######################################################################"
    echo "INSTALLING PostGIS"
    echo "#######################################################################"
    sudo apt update >> $LOGFILE 2>&1
    sudo apt install postgresql-10-postgis-2.4 -y >> $LOGFILE 2>&1
    sudo apt install postgresql-10-postgis-scripts -y >> $LOGFILE 2>&1
    sudo apt install postgis -y >> $LOGFILE 2>&1
    sudo apt install postgresql-10-pgrouting -y >> $LOGFILE 2>&1
    sudo -u postgres psql -f sqls/postgis_install.sql >> $LOGFILE 2>&1
fi

###########################################################
####   TPCH BENCHMARK
###########################################################

if [ "$BENCHMARK" = "TPCH" ] || [ "$BENCHMARK" = "tpch" ] ; then

    echo "#######################################################################"
    echo "INSTALLING JAVA AND OLTPBENCH"
    echo "#######################################################################"
    sudo apt-get update >> $LOGFILE 2>&1
    sudo apt-get install software-properties-common python-software-properties -y  >> $LOGFILE 2>&1
    sudo apt-get install openjdk-8-jre  openjdk-8-jdk ant ivy git -y >> $LOGFILE 2>&1
    echo "CLONING OLTPBENCH GIT REPOSITORY"
    git clone https://github.com/oltpbenchmark/oltpbench.git >> $LOGFILE 2>&1
    echo "COMPILING oltpbench"
    cd oltpbench &&  ant bootstrap >> $LOGFILE 2>&1 && ant resolve >> $LOGFILE 2>&1 && ant build >> $LOGFILE 2>&1 && cd -

    if [ "$IMPORT" = 1 ] ; then
        echo "#######################################################################"
        echo "GENERATING TPC-H DATA"
        echo "#######################################################################"
        git clone https://github.com/electrum/tpch-dbgen $BENCHMARK_DATA_DIR/dbgen >> $LOGFILE 2>&1
        echo "COMPILING DATA GENERATION CODE"
        sudo apt-get install build-essential -y >> $LOGFILE  2>&1
        cd $BENCHMARK_DATA_DIR/dbgen && make >> $LOGFILE 2>&1 && cd -
        echo "#######################################################################"
        echo "GENERATING TPC-H DATA WITH SCALE FACTOR "$SF [Takes time, Keep Patience]
        echo "check $LOGFILE for details"
        echo "#######################################################################"
        mkdir -p $BENCHMARK_DATA_DIR/raw/$SF
        cd $BENCHMARK_DATA_DIR/dbgen && sudo ./dbgen -s $SF -f -v >> $LOGFILE 2>&1  && cd -
        echo "STORING DATA AT LOCATION: " $BENCHMARK_DATA_DIR/raw/$SF/
        mv $BENCHMARK_DATA_DIR/dbgen/*.tbl* $BENCHMARK_DATA_DIR/raw/$SF/
        TPCH_RAW_DATA=$BENCHMARK_DATA_DIR/raw/$SF

        echo "#######################################################################"
        echo "LOAD DATA IN DATABASE WITH oltpbenchmark"
        echo "#######################################################################"
        sudo -u postgres psql -f sqls/tpch_install.sql >> $LOGFILE 2>&1
        sudo sed -i 's,'"TPCH_RAW_DATA"','"$TPCH_RAW_DATA"',' configs/tpch_config.xml
        sudo sed -i 's,'"USERNAME"','"tpch"',' configs/tpch_config.xml
        sudo sed -i 's,'"PASSWORD"','"tpch"',' configs/tpch_config.xml
        cp configs/tpch_config.xml oltpbench/
        cd oltpbench && ./oltpbenchmark --create=true --load=true -c tpch_config.xml -b tpch && cd -
        # REMOVE RAW DATA
        sudo rm -f TPCH_RAW_DATA/*
        echo "#######################################################################"
        echo "LOAD COMPLETE IN DATABASE tpch, CREATING INDEXES"
        echo "#######################################################################"
        sudo -u postgres psql -f sqls/tpch_index.sql >> $LOGFILE 2>&1
    fi

    echo "RECONFIGURING postgres FOR STATS"
    echo "#######################################################################"
    sudo systemctl stop postgresql
    sleep 5
    sudo cp configs/postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
    sudo systemctl start postgresql
    sleep 5
    echo "#######################################################################"
    echo "EXECUTING TPCH QUERIES "
    echo "#######################################################################"
    cd oltpbench && ./oltpbenchmark --execute=true -c tpch_config.xml -b tpch >> $LOGFILE 2>&1 & disown

    sudo apt-get install python-pip -y > /dev/null 2>&1
    pip install argparse
    COUNTER=1
    MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
    PROC=`nproc`

    if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
        TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
        INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
    elif [ `curl  --silent "http://100.100.100.200/latest/meta-data/instance-id" --connect-timeout 3 2>&1 | wc -c` -gt 1  ]; then
        TIER=`curl http://100.100.100.200/latest/meta-data/instance-type`
        INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id | tail -c4`
    else
        TIER="custom"
        INS_ID=`openssl rand -base64 3`
    fi


    FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_TPCH_${INS_ID}.json"
    FILENAME_DB="${TIER}_${PROC}_${MEMORY}_${SF}_TPCH_${INS_ID}.dbfeatures"
    FILENAME_MACHINE="${TIER}_${PROC}_${MEMORY}_${SF}_TPCH_${INS_ID}.machine"


    sudo chmod +x scripts/os_stats.sh

    echo "#######################################################################"
    echo "COLLECTING DATA EVERY 5 MINS IN $FILENAME"
    echo "PRESS [CTRL+C] to stop.."
    echo "#######################################################################"
    sleep 300
    while :
    do
        sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
        sudo -u postgres psql -t -A -d tpch_db -c "SELECT json_agg(json_build_object('relname',relname,'attname',attname,'reltuples', reltuples,'relpages', relpages,'relfilenode', relfilenode,'relam', relam,'n_distinct', n_distinct,'distinct_values',  CASE WHEN n_distinct > 0 THEN n_distinct ELSE -1.0 * n_distinct *reltuples END, 'selectivity', CASE WHEN n_distinct =0 THEN 0 WHEN n_distinct > 0 THEN reltuples/n_distinct ELSE -1.0 / n_distinct END, 'avg_width', avg_width, 'correlation', correlation)) FROM pg_class, pg_stats WHERE relname=tablename  and schemaname='public';"  > $FILENAME_DB
        sudo -u postgres psql -t -A -d tpch_db -c "SELECT json_agg(json_build_object('name',name, 'setting', setting, 'unit', unit, 'min_val', min_val, 'max_val',max_val,'vartype', vartype)) FROM pg_settings where name in ('checkpoint_completion_target','bgwriter_lru_multiplier','random_page_cost','max_stack_depth','work_mem','effective_cache_size','bgwriter_lru_maxpages','join_collapse_limit','checkpoint_timeout','effective_io_concurrency','bgwriter_delay','maintenance_work_mem','from_collapse_limit','default_statistics_target','wal_buffers','cpu_tuple_cost','shared_buffers','deadlock_timeout');"  >> $FILENAME_DB
        sudo scripts/os_stats.sh > ${FILENAME_MACHINE}
        curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        curl -F "file=@${FILENAME_DB}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        curl -F "file=@${FILENAME_MACHINE}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1

        echo -ne "UPLOAD: $COUNTER"\\r
        let COUNTER=COUNTER+1
        sleep 300
    done

elif [ "$BENCHMARK" = "TPCDS" ] || [ "$BENCHMARK" = "tpcds" ] ; then

###########################################################
####   TPC-DS BENCHMARK
###########################################################

    echo "#######################################################################"
    echo "INSTALLING PREREQUISITES FOR TPC-DS BENCHMARK"
    echo "#######################################################################"
    sudo apt-get install gcc make flex bison git  -y  >> $LOGFILE 2>&1
    git clone https://github.com/gregrahn/tpcds-kit.git >> $LOGFILE 2>&1
    cd tpcds-kit/tools && make OS=LINUX >> $LOGFILE 2>&1 && cd -
    echo "COPYING templates list TO templates DIRECTORY"
    cp configs/templates.lst tpcds-kit/query_templates/templates.lst

    if [ "$IMPORT" = 1 ] ; then
        echo "#######################################################################"
        echo "CREATING DATABASE tpcds_db"
        echo "#######################################################################"
        sudo -u postgres psql -f sqls/tpcds_install.sql >> $LOGFILE 2>&1
        sudo -u postgres psql tpcds_db -f tpcds-kit/tools/tpcds.sql >> $LOGFILE 2>&1

        echo "#######################################################################"
        echo "GENERATING TPC-DS DATA"
        echo "#######################################################################"
        cd tpcds-kit/tools
        TPCDS_RAW=${BENCHMARK_DATA_DIR}/raw
        mkdir -p $TPCDS_RAW
        ./dsdgen -SCALE $SF -FORCE -VERBOSE -DIR ${BENCHMARK_DATA_DIR}/raw
        cd -

        echo "#######################################################################"
        echo "LOADING TPC-DS DATA"
        echo "#######################################################################"

        mkdir -p $TPCDS_RAW/tmp
        cd $TPCDS_RAW
        for i in `ls *.dat`; do
            table=${i/.dat/}
            echo "Loading $table..."
            sed 's/|$//' $i > $TPCDS_RAW/tmp/$i
            sudo -u postgres psql tpcds_db -q -c "TRUNCATE $table"
            sudo -u postgres psql tpcds_db -c "\\copy $table FROM '$TPCDS_RAW/tmp/$i' CSV DELIMITER '|'"
            sudo rm -f $TPCDS_RAW/tmp/$i
            sudo rm -f $i
        done
        cd -
    fi

    TPCDS_QUERIES=${BENCHMARK_DATA_DIR}/queries
    mkdir -p $TPCDS_QUERIES

    sudo apt-get install python-pip -y > /dev/null 2>&1
    pip install argparse
    COUNTER=1
    MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
    PROC=`nproc`

    if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
        TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
        INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
    elif [ `curl  --silent "http://100.100.100.200/latest/meta-data/instance-id" --connect-timeout 3 2>&1 | wc -c` -gt 1  ]; then
        TIER=`curl http://100.100.100.200/latest/meta-data/instance-type`
        INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id`
    else
        TIER="custom"
        INS_ID=`openssl rand -base64 3`
    fi

    sudo chmod +x scripts/os_stats.sh

    FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_TPCDS_${INS_ID}.json"
    FILENAME_DB="${TIER}_${PROC}_${MEMORY}_${SF}_TPCDS_${INS_ID}.dbfeatures"
    FILENAME_MACHINE="${TIER}_${PROC}_${MEMORY}_${SF}_TPCDS_${INS_ID}.machine"

    sudo -u postgres psql tpcds_db -f sqls/tpcds_index.sql >> $LOGFILE 2>&1
    echo "RECONFIGURING postgres FOR STATS"
    echo "#######################################################################"
    sudo systemctl stop postgresql
    sleep 5
    sudo cp configs/postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
    sudo systemctl start postgresql
    sleep 5
    echo "#######################################################################"
    echo "RUNNING TPC-DS AND COLLECTING DATA AFTER EVERY BATCH RUN IN $FILENAME"
    echo "PRESS [CTRL+C] to stop.."
    echo "#######################################################################"

    while :
    do
        cd tpcds-kit/tools
        ./dsqgen -DIRECTORY ../query_templates -INPUT ../query_templates/templates.lst -VERBOSE Y -QUALIFY Y -SCALE 1 -DIALECT netezza -OUTPUT_DIR $TPCDS_QUERIES -RNGSEED `date +%s` >> $LOGFILE 2>&1
        sudo -u postgres psql tpcds_db -f $TPCDS_QUERIES/query_0.sql >> $LOGFILE 2>&1
        cd - > /dev/null 2>&1
        sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
        sudo -u postgres psql -t -A -d tpcds_db -c "SELECT json_agg(json_build_object('relname',relname,'attname',attname,'reltuples', reltuples,'relpages', relpages,'relfilenode', relfilenode,'relam', relam,'n_distinct', n_distinct,'distinct_values',  CASE WHEN n_distinct > 0 THEN n_distinct ELSE -1.0 * n_distinct *reltuples END, 'selectivity', CASE WHEN n_distinct =0 THEN 0 WHEN n_distinct > 0 THEN reltuples/n_distinct ELSE -1.0 / n_distinct END, 'avg_width', avg_width, 'correlation', correlation)) FROM pg_class, pg_stats WHERE relname=tablename  and schemaname='public';"  > $FILENAME_DB
        sudo -u postgres psql -t -A -d tpcds_db -c "SELECT json_agg(json_build_object('name',name, 'setting', setting, 'unit', unit, 'min_val', min_val, 'max_val',max_val,'vartype', vartype)) FROM pg_settings where name in ('checkpoint_completion_target','bgwriter_lru_multiplier','random_page_cost','max_stack_depth','work_mem','effective_cache_size','bgwriter_lru_maxpages','join_collapse_limit','checkpoint_timeout','effective_io_concurrency','bgwriter_delay','maintenance_work_mem','from_collapse_limit','default_statistics_target','wal_buffers','cpu_tuple_cost','shared_buffers','deadlock_timeout');"  >> $FILENAME_DB
        sudo scripts/os_stats.sh > ${FILENAME_MACHINE}
        curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        curl -F "file=@${FILENAME_DB}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        curl -F "file=@${FILENAME_MACHINE}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        echo -ne "BATCH: $COUNTER"\\r
        let COUNTER=COUNTER+1
        sleep 2
    done

###########################################################
####   SPATIAL BENCHMARK
###########################################################

elif [ "$BENCHMARK" = "SPATIAL" ] || [ "$BENCHMARK" = "spatial" ] ; then

        echo "#######################################################################"
        echo "INSTALLING JAVA"
        echo "#######################################################################"
        sudo apt-get update >> $LOGFILE 2>&1
        sudo apt-get install software-properties-common python-software-properties -y  >> $LOGFILE 2>&1
        sudo apt-get install openjdk-8-jre  openjdk-8-jdk ant ivy git osmosis osm2pgsql -y >> $LOGFILE 2>&1

        if [ "$IMPORT" = 1 ] ; then
            echo "#######################################################################"
            echo "DOWNLOADING SPATIAL DATA"
            echo "#######################################################################"
            wget http://db03.cs.utah.edu:5555/spatial_benchmark_sql.zip

            echo "EXTRACTING SPATIAL DATA"
            echo "#######################################################################"
            unzip spatial_benchmark_sql.zip -d $BENCHMARK_DATA_DIR >> $LOGFILE 2>&1
            sudo chmod -R 777 $BENCHMARK_DATA_DIR
            rm spatial_benchmark_sql.zip

            echo "CREATE DATABASE spatial_db"
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS spatial_db;"
            sudo -u postgres psql -c "CREATE DATABASE spatial_db"
            sudo -u postgres psql -d spatial_db -c "CREATE EXTENSION postgis;"
            sudo -u postgres psql -d spatial_db -f  /usr/share/postgresql/10/contrib/postgis-2.4/legacy.sql >> $LOGFILE 2>&1

            sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '1234';"


            find $BENCHMARK_DATA_DIR -name *_schema.sql | xargs -t -I {} sudo -u postgres psql -d spatial_db -f {}

            echo "#######################################################################"
            echo "INSERTING SPATIAL DATA IN TABLES"
            echo "#######################################################################"
            find $BENCHMARK_DATA_DIR -name *_data.sql | xargs -t -I {} sudo -u postgres psql -d spatial_db -f {} >> /dev/null
        fi

        git clone https://github.com/debjyoti385/jackpine.git
        sudo sed -i 's,'"DATABASE_NAME"','"spatial_db"',' jackpine/configs/connection_postgresql_spatial.properties
        RESULT_DIR=jackpine/results
        mkdir -p $RESULT_DIR
        cd jackpine
        ant clean compile jar
        cd -
        sudo chmod -R 777 jackpine

        sudo apt-get install python-pip -y > /dev/null 2>&1
        pip install argparse
        COUNTER=1
        MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
        PROC=`nproc`

        if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
            TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
            INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
        elif [ `curl  --silent "http://100.100.100.200/latest/meta-data/instance-id" --connect-timeout 3 2>&1 | wc -c` -gt 1  ]; then
            TIER=`curl http://100.100.100.200/latest/meta-data/instance-type`
            INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id`
        else
            TIER="custom"
            INS_ID=`openssl rand -base64 3`
        fi

        sudo chmod +x scripts/os_stats.sh

        FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.json"
        FILENAME_DB="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.dbfeatures"
        FILENAME_MACHINE="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.machine"


        echo "RECONFIGURING postgres FOR STATS"
        echo "#######################################################################"
        sudo systemctl stop postgresql
        sleep 5
        sudo cp configs/postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
        sudo systemctl start postgresql
        sleep 5
        echo "#######################################################################"
        echo "RUNNING SPATIAL BENCHMARK AND COLLECTING DATA IN $FILENAME"
        echo "PRESS [CTRL+C] to stop.."
        echo "#######################################################################"



        while :
        do
            cd jackpine
            chmod +x jackpine.sh
            sudo -u postgres ./jackpine.sh -i connection_postgresql_spatial.properties
            cd -
            sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
            sudo -u postgres psql -t -A -d spatial_db -c "SELECT json_agg(json_build_object('relname',relname,'attname',attname,'reltuples', reltuples,'relpages', relpages,'relfilenode', relfilenode,'relam', relam,'n_distinct', n_distinct,'distinct_values',  CASE WHEN n_distinct > 0 THEN n_distinct ELSE -1.0 * n_distinct *reltuples END, 'selectivity', CASE WHEN n_distinct =0 THEN 0 WHEN n_distinct > 0 THEN reltuples/n_distinct ELSE -1.0 / n_distinct END, 'avg_width', avg_width, 'correlation', correlation)) FROM pg_class, pg_stats WHERE relname=tablename  and schemaname='public';"  > $FILENAME_DB
            sudo -u postgres psql -t -A -d spatial_db -c "SELECT json_agg(json_build_object('name',name, 'setting', setting, 'unit', unit, 'min_val', min_val, 'max_val',max_val,'vartype', vartype)) FROM pg_settings where name in ('checkpoint_completion_target','bgwriter_lru_multiplier','random_page_cost','max_stack_depth','work_mem','effective_cache_size','bgwriter_lru_maxpages','join_collapse_limit','checkpoint_timeout','effective_io_concurrency','bgwriter_delay','maintenance_work_mem','from_collapse_limit','default_statistics_target','wal_buffers','cpu_tuple_cost','shared_buffers','deadlock_timeout');"  >> $FILENAME_DB
            sudo scripts/os_stats.sh > ${FILENAME_MACHINE}
            curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
            curl -F "file=@${FILENAME_DB}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
            curl -F "file=@${FILENAME_MACHINE}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1

            echo -ne "UPLOAD: $COUNTER"\\r
            let COUNTER=COUNTER+1
            sleep 5
        done


  elif [ "$BENCHMARK" = "OSM" ] || [ "$BENCHMARK" = "osm" ] ; then

          echo "#######################################################################"
          echo "INSTALLING JAVA"
          echo "#######################################################################"
          sudo apt-get update >> $LOGFILE 2>&1
          sudo apt-get install software-properties-common python-software-properties -y  >> $LOGFILE 2>&1
          sudo apt-get install openjdk-8-jre  openjdk-8-jdk ant ivy git -y >> $LOGFILE 2>&1

          if [ "$IMPORT" = 1 ] ; then
              echo "#######################################################################"
              echo "DOWNLOADING OSM DATA"
              echo "#######################################################################"
              wget https://download.geofabrik.de/north-america/us/california-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/california-latest.osm.pbf
              wget https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf
              wget https://download.geofabrik.de/north-america/us/utah-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf

              LA_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/la_county.osm
              NY_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/ny_county.osm
              SL_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/sl_county.osm
              LA_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/la.osm
              NY_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/nyc.osm
              SL_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/osm/slc.osm

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/california-latest.osm.pbf --tf reject-relations  --bounding-box left=-118.8927 bottom=33.6964 right=-117.5078 top=34.8309 clipIncompleteEntities=true --write-xml file=$LA_COUNTY_OSM_FILE

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf --tf reject-relations  --bounding-box left=-74.047225  bottom=40.679319 right=-73.906159 top=40.882463 clipIncompleteEntities=true --write-xml file=$NY_COUNTY_OSM_FILE

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf --tf reject-relations  --bounding-box left=-112.260184 bottom=40.414864 right=-111.560498 top=40.921879 clipIncompleteEntities=true --write-xml file=$SL_COUNTY_OSM_FILE

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/california-latest.osm.pbf --tf reject-relations  --bounding-box left=-118.6682 bottom=33.7036 right=-118.1553 top=34.3373 clipIncompleteEntities=true --write-xml file=$LA_CITY_OSM_FILE

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf --tf reject-relations  --bounding-box left=-74.25909  bottom=40.477399 right=-73.700181 top=40.916178 clipIncompleteEntities=true --write-xml file=$NY_CITY_OSM_FILE

              osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf --tf reject-relations  --bounding-box left=-112.101607 bottom=40.699893 right=-111.739476 top=40.85297 clipIncompleteEntities=true --write-xml file=$SL_CITY_OSM_FILE

              echo "IMPORT OSM DATA"
              echo "#######################################################################"

              echo "IMPORT NEW YORK CITY"
              echo "#######################################################################"
              sudo scripts/create_db_osm.sh los_angeles_county $LA_COUNTY_OSM_FILE
              sudo scripts/create_db_osm.sh new_york_county $NY_COUNTY_OSM_FILE
              sudo scripts/create_db_osm.sh salt_lake_county $SL_COUNTY_OSM_FILE
              sudo scripts/create_db_osm.sh los_angeles_city $LA_CITY_OSM_FILE
              sudo scripts/create_db_osm.sh new_york_city $NY_CITY_OSM_FILE
              sudo scripts/create_db_osm.sh salt_lake_city $SL_CITY_OSM_FILE
          fi


          sudo apt-get install python-pip -y > /dev/null 2>&1
          pip install argparse
          COUNTER=1
          MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
          PROC=`nproc`

          if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
              TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
              INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
          elif [ `curl  --silent "http://100.100.100.200/latest/meta-data/instance-id" --connect-timeout 3 2>&1 | wc -c` -gt 1  ]; then
              TIER=`curl http://100.100.100.200/latest/meta-data/instance-type`
              INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id`
          else
              TIER="custom"
              INS_ID=`openssl rand -base64 3`
          fi

          sudo chmod +x scripts/os_stats.sh

          FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.json"
          FILENAME_DB="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.dbfeatures"
          FILENAME_MACHINE="${TIER}_${PROC}_${MEMORY}_${SF}_SPATIAL_${INS_ID}.machine"


          echo "RECONFIGURING postgres FOR STATS"
          echo "#######################################################################"
          sudo systemctl stop postgresql
          sleep 5
          sudo cp configs/postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
          sudo systemctl start postgresql
          sleep 5
          echo "#######################################################################"
          echo "RUNNING SPATIAL BENCHMARK AND COLLECTING DATA IN $FILENAME"
          echo "PRESS [CTRL+C] to stop.."
          echo "#######################################################################"

          while :
          do
              cd jackpine
              chmod +x jackpine.sh
              sudo -u postgres ./jackpine.sh -i connection_postgresql_spatial.properties
              cd -
              sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
              sudo -u postgres psql -t -A -d spatial_db -c "SELECT json_agg(json_build_object('relname',relname,'attname',attname,'reltuples', reltuples,'relpages', relpages,'relfilenode', relfilenode,'relam', relam,'n_distinct', n_distinct,'distinct_values',  CASE WHEN n_distinct > 0 THEN n_distinct ELSE -1.0 * n_distinct *reltuples END, 'selectivity', CASE WHEN n_distinct =0 THEN 0 WHEN n_distinct > 0 THEN reltuples/n_distinct ELSE -1.0 / n_distinct END, 'avg_width', avg_width, 'correlation', correlation)) FROM pg_class, pg_stats WHERE relname=tablename  and schemaname='public';"  > $FILENAME_DB
              sudo -u postgres psql -t -A -d spatial_db -c "SELECT json_agg(json_build_object('name',name, 'setting', setting, 'unit', unit, 'min_val', min_val, 'max_val',max_val,'vartype', vartype)) FROM pg_settings where name in ('checkpoint_completion_target','bgwriter_lru_multiplier','random_page_cost','max_stack_depth','work_mem','effective_cache_size','bgwriter_lru_maxpages','join_collapse_limit','checkpoint_timeout','effective_io_concurrency','bgwriter_delay','maintenance_work_mem','from_collapse_limit','default_statistics_target','wal_buffers','cpu_tuple_cost','shared_buffers','deadlock_timeout');"  >> $FILENAME_DB
              sudo scripts/os_stats.sh > ${FILENAME_MACHINE}
              curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
              curl -F "file=@${FILENAME_DB}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
              curl -F "file=@${FILENAME_MACHINE}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1

              echo -ne "UPLOAD: $COUNTER"\\r
              let COUNTER=COUNTER+1
              sleep 5
          done

else
  echo "NO BENCHMARK SPECIFIED, use --benchmark=[tpch/tpcds/spatial] as options"
fi
