#!/bin/bash
PG_DATA_DIR="`pwd`/data/postgres_data";
TPCH_DATA_DIR="`pwd`/data/tpch_data";
TPCDS_DATA_DIR="`pwd`/data/tpcds_data";
LOGFILE="`pwd`/install.log";
BENCHMARK="TPCH";
SF=1


function usage()
{
    echo -e "INSTALL SCRIPT FOR postgresql AND benchmarks ON UBUNTU 16.04 AND 18.04"
    echo -e ""
    echo -e "sudo ./install.sh OR sudo bash install.sh"
    echo -e "\t-h --help"
    echo -e "\t-b --bench=$BENCHMARK"
    echo -e "\t--pgdata=$PG_DATA_DIR"
    echo -e "\t--tpchdata=$TPCH_DATA_DIR"
    echo -e "\t--tpcdsdata=$TPCDS_DATA_DIR"
    echo -e "\t--sf=$SF"
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
        --tpchdata)
            TPCH_DATA_DIR=$VALUE
            ;;
        --tpcdsdata)
            TPCDS_DATA_DIR=$VALUE
            ;;
        -b | --bench)
            BENCHMARK=$VALUE
            ;;
        --sf)
            SF=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done



echo "#######################################################################"
echo "UPGRADING PACKAGES"
echo "LOGFILE: $LOGFILE"
echo "#######################################################################"
sudo apt-get update >> /dev/null 2>&1
sudo apt-get upgrade -y  >> $LOGFILE 2>&1

mkdir -p $PG_DATA_DIR
mkdir -p $TPCH_DATA_DIR
mkdir -p $TPCDS_DATA_DIR

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
if [ -f "postgresql.conf" ]; then
    echo "UPDATING postgresql.conf CONFIG FILE "
    sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' postgresql.conf
    sudo sed -i 's,'"PG_DATA_DIR"','"$PG_DATA_DIR"',' postgresql_execute.conf
    sudo cp postgresql.conf /etc/postgresql/10/main/postgresql.conf
fi 
usermod -a -G `id -g -n` postgres
sudo systemctl start postgresql


echo "#######################################################################"
echo "INSTALLING PostGIS"
echo "#######################################################################"
sudo apt update >> $LOGFILE 2>&1
sudo apt install postgresql-10-postgis-2.4 -y >> $LOGFILE 2>&1 
sudo apt install postgresql-10-postgis-scripts -y >> $LOGFILE 2>&1
sudo apt install postgis -y >> $LOGFILE 2>&1
sudo apt install postgresql-10-pgrouting -y >> $LOGFILE 2>&1
sudo -u postgres psql -f postgis_install.sql >> $LOGFILE 2>&1


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

    
    echo "#######################################################################"
    echo "GENERATING TPC-H DATA"
    echo "#######################################################################"
    git clone https://github.com/electrum/tpch-dbgen $TPCH_DATA_DIR/dbgen >> $LOGFILE 2>&1
    echo "COMPILING DATA GENERATION CODE"
    sudo apt-get install build-essential -y >> $LOGFILE  2>&1 
    cd $TPCH_DATA_DIR/dbgen && make >> $LOGFILE 2>&1 && cd -  
    echo "#######################################################################"
    echo "GENERATING TPC-H DATA WITH SCALE FACTOR "$SF [Takes time, Keep Patience]
    echo "check $LOGFILE for details"
    echo "#######################################################################"
    mkdir -p $TPCH_DATA_DIR/raw/$SF
    cd $TPCH_DATA_DIR/dbgen && sudo ./dbgen -s $SF -f -v >> $LOGFILE 2>&1  && cd - 
    echo "STORING DATA AT LOCATION: " $TPCH_DATA_DIR/raw/$SF/
    mv $TPCH_DATA_DIR/dbgen/*.tbl* $TPCH_DATA_DIR/raw/$SF/
    TPCH_RAW_DATA=$TPCH_DATA_DIR/raw/$SF
    
    echo "#######################################################################"
    echo "LOAD DATA IN DATABASE WITH oltpbenchmark"
    echo "#######################################################################"
    sudo -u postgres psql -f tpch_install.sql >> $LOGFILE 2>&1
    sudo sed -i 's,'"TPCH_RAW_DATA"','"$TPCH_RAW_DATA"',' tpch_config.xml
    sudo sed -i 's,'"USERNAME"','"tpch"',' tpch_config.xml
    sudo sed -i 's,'"PASSWORD"','"tpch"',' tpch_config.xml
    cp tpch_config.xml oltpbench/
    cd oltpbench && ./oltpbenchmark --create=true --load=true -c tpch_config.xml -b tpch && cd - 
    echo "#######################################################################"
    echo "LOAD COMPLETE IN DATABASE tpch, CREATING INDEXES"
    echo "#######################################################################"
    sudo -u postgres psql -f tpch_index.sql >> $LOGFILE 2>&1
    echo "RECONFIGURING postgres FOR STATS"
    echo "#######################################################################"
    sudo systemctl stop postgresql
    sleep 5
    sudo cp postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
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
        INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id`
    else
        TIER="custom"
        INS_ID="0000"
    fi


    FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_TPCH_${INS_ID}.json"
    echo "#######################################################################"
    echo "COLLECTING DATA EVERY 5 MINS IN $FILENAME"
    echo "PRESS [CTRL+C] to stop.."
    echo "#######################################################################"
    sleep 300
    while :
    do
        sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
        curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
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

    echo "#######################################################################"
    echo "CREATING DATABASE tpcds_db"
    echo "#######################################################################"
    sudo -u postgres psql -f tpcds_install.sql >> $LOGFILE 2>&1  
    sudo -u postgres psql tpcds_db -f tpcds-kit/tools/tpcds.sql >> $LOGFILE 2>&1  
     
    echo "#######################################################################"
    echo "GENERATING TPC-DS DATA"
    echo "#######################################################################"
    cd tpcds-kit/tools 
    TPCDS_RAW=${TPCDS_DATA_DIR}/raw
    mkdir -p $TPCDS_RAW
    ./dsdgen -SCALE $SF -FORCE -VERBOSE -DIR ${TPCDS_DATA_DIR}/raw
    cd -

    echo "#######################################################################"
    echo "LOADING TPC-DS DATA"
    echo "#######################################################################"

    cd $TPCDS_RAW 
    for i in `ls *.dat`; do
        table=${i/.dat/}
        echo "Loading $table..."
        sed 's/|$//' $i > /tmp/$i
        sudo -u postgres psql tpcds_db -q -c "TRUNCATE $table"
        sudo -u postgres psql tpcds_db -c "\\copy $table FROM '/tmp/$i' CSV DELIMITER '|'"
    done
    cd -
    TPCDS_QUERIES=${TPCDS_DATA_DIR}/queries
    mkdir -p $TPCDS_QUERIES

    sudo apt-get install python-pip -y > /dev/null 2>&1
    pip install argparse
    COUNTER=1
    MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
    PROC=`nproc`
    TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
    INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
    
    if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
        TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
        INS_ID=`curl http://169.254.169.254/latest/meta-data/instance-id | tail -c4`
    elif [ `curl  --silent "http://100.100.100.200/latest/meta-data/instance-id" --connect-timeout 3 2>&1 | wc -c` -gt 1  ]; then
        TIER=`curl http://100.100.100.200/latest/meta-data/instance-type`
        INS_ID=`curl http://100.100.100.200/latest/meta-data/instance-id`
    else
        TIER="custom"
        INS_ID="0000"
    fi

    FILENAME="${TIER}_${PROC}_${MEMORY}_${SF}_TPCDS_${INS_ID}.json"
    
    sudo -u postgres psql tpcds_db -f tpcds_index.sql >> $LOGFILE 2>&1
    echo "RECONFIGURING postgres FOR STATS"
    echo "#######################################################################"
    sudo systemctl stop postgresql
    sleep 5
    sudo cp postgresql_execute.conf /etc/postgresql/10/main/postgresql.conf
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
        curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> $LOGFILE 2>&1
        echo -ne "BATCH: $COUNTER"\\r
        let COUNTER=COUNTER+1
        sleep 2
    done
fi



