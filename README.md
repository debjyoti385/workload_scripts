# Workload Scripts
These scripts installs PostgreSQL 10, PostGIS 2.4 and Oltpbenchmark on AWS Ubuntu 18.04 or 16.04 instances. It also upload benchmark runs and experiment data to server. 

## Quickstart  
Run TPC-H benchmark (Use `screen` in terminal)
```
curl -L0k https://github.com/debjyoti385/workload_scripts/archive/master.zip -o master.zip
sudo apt-get install unzip -y
unzip -j master.zip
rm master.zip
chmod +x install.sh
sudo ./install.sh -b=tpch 
```

Run TPC-DS benchmark (Use `screen` in terminal)
```
curl -L0k https://github.com/debjyoti385/workload_scripts/archive/master.zip -o master.zip
sudo apt-get install unzip -y
unzip -j master.zip
rm master.zip
chmod +x install.sh
sudo ./install.sh -b=tpcds
```


## Options
```
sudo ./install.sh
    -h --help
    --bench=tpch                               # Benchmark: tpch (default), tpcds  
    --pgdata=/home/ubuntu/data/postgres_data   # PostgreSQL Data Directory (default)
    --tpchdata=/home/ubuntu/data/tpch_data     # TPC-H Data Directory (default)
    --tpcdsdata=/home/ubuntu/data/tpcds_data   # TPC-DS Data Directory (default)
    --sf=1                                     # Scale Factor in GBs (default 1 GB)
```
