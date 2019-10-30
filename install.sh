#!/bin/bash
PG_DATA_DIR="`pwd`/data/postgres_data";
TPCH_DATA_DIR="`pwd`/data/tpch_data";
SF=1


function usage()
{
    echo -e "INSTALL SCRIPT FOR postgresql AND benchmarks ON UBUNTU 16.04 AND 18.04"
    echo -e ""
    echo -e "sudo ./install.sh OR sudo bash install.sh"
    echo -e "\t-h --help"
    echo -e "\t--pgdata=$PG_DATA_DIR"
    echo -e "\t--tpchdata=$TPCH_DATA_DIR"
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
echo "LOGFILE: install.log"
echo "#######################################################################"

sudo apt-get upgrade >> install.log 2>&1

mkdir -p $PG_DATA_DIR
mkdir -p $TPCH_DATA_DIR

echo "#######################################################################"
echo "Install PostgreSQL 10"
echo "#######################################################################"
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt `lsb_release -c -s`-pgdg main" >> /etc/apt/sources.list'
wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update >> /dev/null 2>&1
sudo apt-get install postgresql-10 postgresql-contrib-10 -y >> install.log 2>&1

echo "CHANGING POSTGRESQL default DATA DIRECTORY TO $PG_DATA_DIR"
sudo systemctl stop postgresql
sleep 5
if [ ! -d "$PG_DATA_DIR/10/main" ]; then
    sudo rsync -av /var/lib/postgresql/ $PG_DATA_DIR >> install.log 2>&1
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
sudo apt update >> install.log 2>&1
sudo apt install postgresql-10-postgis-2.4 -y >> install.log 2>&1 
sudo apt install postgresql-10-postgis-scripts -y >> install.log 2>&1
sudo apt install postgis -y >> install.log 2>&1
sudo apt install postgresql-10-pgrouting -y >> install.log 2>&1
sudo -u postgres psql -f postgis_install.sql >> install.log 2>&1

echo "#######################################################################"
echo "INSTALLING JAVA AND OLTPBENCH"
echo "#######################################################################"
sudo apt-get update >> install.log 2>&1
sudo apt-get install software-properties-common python-software-properties -y  >> install.log 2>&1
sudo apt-get install openjdk-8-jre  openjdk-8-jdk ant ivy git -y >> install.log 2>&1 
echo "CLONING OLTPBENCH GIT REPOSITORY"
git clone https://github.com/oltpbenchmark/oltpbench.git >> install.log 2>&1
echo "COMPILING oltpbench"
cd oltpbench &&  ant bootstrap >> install.log 2>&1 && ant resolve >> install.log 2>&1 && ant build >> install.log 2>&1 && cd -  

echo "#######################################################################"
echo "GENERATING TPC-H DATA"
echo "#######################################################################"
git clone https://github.com/electrum/tpch-dbgen $TPCH_DATA_DIR/dbgen >> install.log 2>&1
echo "COMPILING DATA GENERATION CODE"
sudo apt-get install build-essential -y >> install.log  2>&1 
cd $TPCH_DATA_DIR/dbgen && make >> install.log 2>&1 && cd -  
echo "#######################################################################"
echo "GENERATING TPC-H DATA WITH SCALE FACTOR "$SF [Takes time, Keep Patience]
echo "check install.log for details"
echo "#######################################################################"
mkdir -p $TPCH_DATA_DIR/raw/$SF
cd $TPCH_DATA_DIR/dbgen && sudo ./dbgen -s $SF -f -v >> install.log 2>&1  && cd - 
echo "STORING DATA AT LOCATION: " $TPCH_DATA_DIR/raw/$SF/
mv $TPCH_DATA_DIR/dbgen/*.tbl* $TPCH_DATA_DIR/raw/$SF/
TPCH_RAW_DATA=$TPCH_DATA_DIR/raw/$SF

echo "#######################################################################"
echo "LOAD DATA IN DATABASE WITH oltpbenchmark"
echo "#######################################################################"
sudo -u postgres psql -f tpch_install.sql >> install.log 2>&1
sudo sed -i 's,'"TPCH_RAW_DATA"','"$TPCH_RAW_DATA"',' tpch_config.xml
sudo sed -i 's,'"USERNAME"','"tpch"',' tpch_config.xml
sudo sed -i 's,'"PASSWORD"','"tpch"',' tpch_config.xml
cp tpch_config.xml oltpbench/
cd oltpbench && ./oltpbenchmark --create=true --load=true -c tpch_config.xml -b tpch && cd - 
echo "#######################################################################"
echo "LOAD COMPLETE IN DATABASE tpch, CREATING INDEXES"
echo "#######################################################################"
sudo -u postgres psql -f tpch_index.sql >> install.log 2>&1
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
cd oltpbench && ./oltpbenchmark --execute=true -c tpch_config.xml -b tpch >> ../install.log 2>&1 & disown 

echo "#######################################################################"
echo "COLLECTING DATA EVERY 5 MINS "
echo "#######################################################################"
sudo apt-get install python-pip -y > /dev/null 2>&1
pip install argparse
sleep 300
COUNTER=1
MEMORY=`free -m  | head -2 | tail -1 | awk '{print $2}'`
PROC=`nproc`
TIER=`curl http://169.254.169.254/latest/meta-data/instance-type`
FILENAME="${TIER}_${PROC}_${MEMORY}_TPCH.json"
while :
do
	sudo python extract_plans.py --input /var/log/postgresql/postgresql-10-main.log --type json > $FILENAME
	curl -F "file=@${FILENAME}" http://db03.cs.utah.edu:9000/ -v >> install.log 2>&1
	echo -e "\e[0K\r UPLOAD: $COUNTER"
	let COUNTER=COUNTER+1
	echo "Press [CTRL+C] to stop.."
	sleep 300
done
