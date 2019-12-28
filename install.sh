#!/bin/bash
PG_DATA_DIR="`pwd`/data/postgres_data";
BENCHMARK_DATA_DIR="`pwd`/data/benchmark_data";
LOGFILE="`pwd`/install.log";
BENCHMARK="";
SF=1
OSM_DB='los_angeles_county'
ITERATIONS=100
INSTALL=1
IMPORT=1
RERUN=1

FILENAME="demo.json"
FILENAME_DB="demo.dbfeatures"
FILENAME_MACHINE="demo.machine"

LA_COUNTY_BBOX="-118.8927,33.6964,-117.5078,34.8309"
NY_COUNTY_BBOX="-74.047225,40.679319,-73.906159,40.882463"
SL_CIUNTY_BBOX="-112.260184,40.414864,-111.560498,40.921879"
LA_BBOX="-118.6682,33.7036,118.1553,34.3373"
NYC_BBOX="-74.25909,40.477399,-73.700181,40.916178"
SLC_BBOX="-112.101607,40.699893,-111.739476,40.85297"


usage()
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
    echo -e "\t--osmdb=$OSM_DB  # los_angeles_county/new_york_county/salt_lake_county"
    echo -e ""
}

prepare_rerun()
{
    sudo systemctl stop postgresql
    echo "CHANGE DATABASE CONFIGS"
    echo "" > /var/log/postgresql/postgresql-10-main.log
    python scripts/change_config.py -i dbconfigs --config /etc/postgresql/10/main/postgresql.conf
    sleep 5
    sudo systemctl start postgresql
}

configure_for_execution()
{
    echo "#######################################################################"
    echo "RECONFIGURING postgres FOR STATS"
    echo "#######################################################################"
    sudo systemctl stop postgresql
    sleep 5
    sudo cp configs/postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
    sudo systemctl start postgresql
    sleep 5
}

update_log()
{
    sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
    sudo -u postgres psql -t -A -d $1 -c "SELECT json_agg(json_build_object('relname',relname,'attname',attname,'reltuples', reltuples,'relpages', relpages,'relfilenode', relfilenode,'relam', relam,'n_distinct', n_distinct,'distinct_values',  CASE WHEN n_distinct > 0 THEN n_distinct ELSE -1.0 * n_distinct *reltuples END, 'selectivity', CASE WHEN n_distinct =0 THEN 0 WHEN n_distinct > 0 THEN reltuples/n_distinct ELSE -1.0 / n_distinct END, 'avg_width', avg_width, 'correlation', correlation)) FROM pg_class, pg_stats WHERE relname=tablename  and schemaname='public';"  > $FILENAME_DB
    sudo -u postgres psql -t -A -d $1 -c "SELECT json_agg(json_build_object('name',name, 'setting', setting, 'unit', unit, 'min_val', min_val, 'max_val',max_val,'vartype', vartype)) FROM pg_settings where name in ('checkpoint_completion_target','bgwriter_lru_multiplier','random_page_cost','max_stack_depth','work_mem','effective_cache_size','bgwriter_lru_maxpages','join_collapse_limit','checkpoint_timeout','effective_io_concurrency','bgwriter_delay','maintenance_work_mem','from_collapse_limit','default_statistics_target','wal_buffers','cpu_tuple_cost','shared_buffers','deadlock_timeout');"  >> $FILENAME_DB
    sudo scripts/os_stats.sh > ${FILENAME_MACHINE}
    curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
    curl -F "file=@${FILENAME_DB}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
    curl -F "file=@${FILENAME_MACHINE}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
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
        --osmdb)
            OSM_DB=$VALUE
            ;;
        --epoch)
            ITERATIONS=$VALUE
            ;;
        --rerun)
            RERUN=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

chmod -R +x scripts
sudo apt-get install python-pip -y > /dev/null 2>&1
pip install argparse hurry.filesize pyDOE pathlib2 numpy >> $LOGFILE 2>&1
python scripts/config_generator.py -i configs/postgres_knobs.json -o dbconfigs -n 1000

mkdir -p $BENCHMARK_DATA_DIR
echo "#######################################################################"
echo "UPDATING DATABASE CONFIGURATION FILE"
echo "#######################################################################"
if [ -f "/etc/postgresql/10/main/postgresql.conf" ]; then
    sudo cp /etc/postgresql/10/main/postgresql.conf /etc/postgresql/10/main/postgresql.conf.bak
fi
if [ -f "configs/postgresql.conf" ]; then
    echo "UPDATING postgresql.conf CONFIG FILE "
    sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' configs/postgresql.conf
    sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' configs/postgresql_execute.conf
    sudo cp configs/postgresql.conf /etc/postgresql/10/main/postgresql.conf
    echo "#######################################################################"
fi


if [ "$INSTALL" = 1 ] ; then

    echo "#######################################################################"
    echo "UPGRADING PACKAGES"
    echo "LOGFILE: $LOGFILE"
    echo "#######################################################################"
    sudo apt-get update >> /dev/null 2>&1
    #sudo apt-get upgrade -y  >> $LOGFILE 2>&1

    mkdir -p $PG_DATA_DIR

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

    echo "" > /var/log/postgresql/postgresql-10-main.log

    configure_for_execution

    echo "#######################################################################"
    echo "EXECUTING TPCH QUERIES "
    echo "#######################################################################"
    cd oltpbench && ./oltpbenchmark --execute=true -c tpch_config.xml -b tpch >> $LOGFILE 2>&1 & disown

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

        update_log tpch_db
        
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

    RCOUNTER=0
    while :
    do
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

        if [ $RCOUNTER -eq 0 ]; then
            configure_for_execution
        fi

        echo "#######################################################################"
        echo "RUNNING TPC-DS AND COLLECTING DATA AFTER EVERY BATCH RUN IN $FILENAME"
        echo "PRESS [CTRL+C] to stop.."
        echo "#######################################################################"

        echo "" > /var/log/postgresql/postgresql-10-main.log

        while :
        do
            cd tpcds-kit/tools
            ./dsqgen -DIRECTORY ../query_templates -INPUT ../query_templates/templates.lst -VERBOSE Y -QUALIFY Y -SCALE 1 -DIALECT netezza -OUTPUT_DIR $TPCDS_QUERIES -RNGSEED `date +%s` >> $LOGFILE 2>&1
            sudo -u postgres psql tpcds_db -f $TPCDS_QUERIES/query_0.sql >> $LOGFILE 2>&1
            cd - > /dev/null 2>&1

            update_log tpcds_db

            echo -ne "BATCH: $COUNTER"\\r
            if [ $COUNTER -gt $ITERATIONS ]; then
                break
            fi
            let COUNTER=COUNTER+1
            sleep 2
        done

        if [ $RCOUNTER -gt $RERUN ]; then
            break
        fi
        let RCOUNTER=RCOUNTER+1
        prepare_rerun
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
    sudo sed -i 's,'"DATABASE_NAME"','"spatial_db"',' jackpine/config/connection_postgresql_spatial.properties
    RESULT_DIR=jackpine/results
    mkdir -p $RESULT_DIR
    cd jackpine
    ant clean compile jar
    cd -
    sudo chmod -R 777 jackpine

    sudo apt-get install python-pip -y > /dev/null 2>&1
    pip install argparse


    RCOUNTER=0
    while :
    do
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

        if [ $RCOUNTER -eq 0 ]; then
            configure_for_execution
        fi

        echo "#######################################################################"
        echo "RUNNING SPATIAL BENCHMARK AND COLLECTING DATA IN $FILENAME"
        echo "PRESS [CTRL+C] to stop.."
        echo "#######################################################################"
        echo "" > /var/log/postgresql/postgresql-10-main.log


        COUNTER=0
        while :
        do
            cd jackpine
            chmod +x jackpine.sh
            sudo -u postgres ./jackpine.sh -i connection_postgresql_spatial.properties
            cd -

            update_log spatial_db

            echo -ne "UPLOAD: $COUNTER"\\r
            if [ $COUNTER -gt $ITERATIONS ]; then
                break
            fi
            let COUNTER=COUNTER+1
            sleep 5
        done

        if [ $RCOUNTER -gt $RERUN ]; then
            break
        fi
        let RCOUNTER=RCOUNTER+1
        prepare_rerun
    done


elif [ "$BENCHMARK" = "OSM" ] || [ "$BENCHMARK" = "osm" ] ; then

    echo "#######################################################################"
    echo "INSTALLING JAVA"
    echo "#######################################################################"
    sudo apt-get update >> $LOGFILE 2>&1
    sudo apt-get install software-properties-common python-software-properties -y  >> $LOGFILE 2>&1
    sudo apt-get install openjdk-8-jre  openjdk-8-jdk ant ivy git osmosis osm2pgsql -y >> $LOGFILE 2>&1

    if [ "$IMPORT" = 1 ] ; then
        echo "#######################################################################"
        echo "DOWNLOADING OSM DATA"
        echo "#######################################################################"

        wget https://download.geofabrik.de/north-america/us/california-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/california-latest.osm.pbf
        wget https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf
        wget https://download.geofabrik.de/north-america/us/utah-latest.osm.pbf -O ${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf

        echo "#######################################################################"
        echo "IMPORT OSM DATA"
        echo "#######################################################################"
        if [[ $OSM_DB == *"los_angeles_county"* ]]; then
          LA_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/la_county.osm
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/california-latest.osm.pbf --tf reject-relations  --bounding-box left=-118.8927 bottom=33.6964 right=-117.5078 top=34.8309 clipIncompleteEntities=true --write-xml file=$LA_COUNTY_OSM_FILE
          sudo scripts/create_db_osm.sh los_angeles_county $LA_COUNTY_OSM_FILE
        elif [[ $OSM_DB == *"new_york_county"* ]]; then
          NY_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/ny_county.osm
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf --tf reject-relations  --bounding-box left=-74.047225  bottom=40.679319 right=-73.906159 top=40.882463 clipIncompleteEntities=true --write-xml file=$NY_COUNTY_OSM_FILE
          sudo scripts/create_db_osm.sh new_york_county $NY_COUNTY_OSM_FILE
        elif [[ $OSM_DB == *"salt_lake_county"* ]]; then
          SL_COUNTY_OSM_FILE=${BENCHMARK_DATA_DIR}/sl_county.osm
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf --tf reject-relations  --bounding-box left=-112.260184 bottom=40.414864 right=-111.560498 top=40.921879 clipIncompleteEntities=true --write-xml file=$SL_COUNTY_OSM_FILE
          sudo scripts/create_db_osm.sh salt_lake_county $SL_COUNTY_OSM_FILE
        elif [[ $OSM_DB == *"los_angeles_city"* ]]; then
          LA_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/la.osm
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/california-latest.osm.pbf --tf reject-relations  --bounding-box left=-118.6682 bottom=33.7036 right=-118.1553 top=34.3373 clipIncompleteEntities=true --write-xml file=$LA_CITY_OSM_FILE
          sudo scripts/create_db_osm.sh los_angeles_city $LA_CITY_OSM_FILE
        elif [[ $OSM_DB == *"new_york_city"* ]]; then
          NY_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/nyc.osm
          mkdir -p $NY_CITY_OSM_FILE
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/new-york-latest.osm.pbf --tf reject-relations  --bounding-box left=-74.25909  bottom=40.477399 right=-73.700181 top=40.916178 clipIncompleteEntities=true --write-xml file=$NY_CITY_OSM_FILE
          sudo scripts/create_db_osm.sh new_york_city $NY_CITY_OSM_FILE
        elif [[ $OSM_DB == *"salt_lake_city"* ]]; then
          SL_CITY_OSM_FILE=${BENCHMARK_DATA_DIR}/slc.osm
          osmosis --read-pbf file=${BENCHMARK_DATA_DIR}/utah-latest.osm.pbf --tf reject-relations  --bounding-box left=-112.101607 bottom=40.699893 right=-111.739476 top=40.85297 clipIncompleteEntities=true --write-xml file=$SL_CITY_OSM_FILE
          sudo scripts/create_db_osm.sh salt_lake_city $SL_CITY_OSM_FILE
        fi

        git clone https://github.com/debjyoti385/osm_benchmark.git
        chmod -R +x osm_benchmark
        cd osm_benchmark
        ./prepare_routing.sh $OSM_DB
        cd -
    fi

    rerun_counter=0
    while :
    do
        if [[ $OSM_DB == *"los_angeles_county"* ]]; then
          BBOX=$LA_COUNTY_BBOX
        elif [[ $OSM_DB == *"new_york_county"* ]]; then
          BBOX=$NY_COUNTY_BBOX
        elif [[ $OSM_DB == *"salt_lake_county"* ]]; then
          BBOX=$SL_COUNTY_BBOX
        elif [[ $OSM_DB == *"los_angeles_city"* ]]; then
          BBOX=$LA_BBOX
        elif [[ $OSM_DB == *"new_york_city"* ]]; then
          BBOX=$NYC_BBOX
        elif [[ $OSM_DB == *"salt_lake_city"* ]]; then
          BBOX=$SLC_BBOX
        fi

        echo "" > /var/log/postgresql/postgresql-10-main.log
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

        FILENAME="${TIER}_${PROC}_${MEMORY}_${OSM_DB}_OSM_${INS_ID}.json"
        FILENAME_DB="${TIER}_${PROC}_${MEMORY}_${OSM_DB}_OSM_${INS_ID}.dbfeatures"
        FILENAME_MACHINE="${TIER}_${PROC}_${MEMORY}_${OSM_DB}_OSM_${INS_ID}.machine"


        if [ $COUNTER -eq 0 ]; then
            configure_for_execution
        if
        echo "#######################################################################"
        echo "RUNNING SPATIAL BENCHMARK AND COLLECTING DATA IN $FILENAME"
        echo "PRESS [CTRL+C] to stop.."
        echo "#######################################################################"

        while :
        do
            cd osm_benchmark
              ./run_benchmark.sh $OSM_DB $BBOX $ITERATIONS
            cd -

            update_log $OSM_DB

            echo -ne "UPLOAD: $COUNTER"\\r

            if [ $COUNTER -gt $RERUN ]; then
                break
            fi
            let COUNTER=COUNTER+1
            prepare_rerun
        done
    done

else
  echo "NO BENCHMARK SPECIFIED, use --benchmark=[tpch/tpcds/spatial/osm] as options"
fi
