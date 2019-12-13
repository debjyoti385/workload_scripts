# Workload Scripts
These scripts installs PostgreSQL 10, PostGIS 2.4 and Oltpbenchmark on AWS Ubuntu 18.04 or 16.04 instances. It also upload benchmark runs and experiment data to server.

## Quickstart  
1. Download the script
```
curl -L0k https://github.com/debjyoti385/workload_scripts/archive/master.zip -o master.zip
sudo apt-get install unzip -y
unzip -j master.zip
rm master.zip
chmod +x install.sh

```
2. Run Benchmarks: (Use `screen`)

TPC-H Benchmark: Scale Factor 3 GB
```
screen -S install
sudo ./install.sh --benchmark=tpch --pgdata=/home/ubuntu/data/postgres_data --tpchdata=/home/ubuntu/data/tpch_data  --sf=3
```

TPC-DS Benchmark: Scale Factor 5 GB
```
screen -S install
sudo ./install.sh --benchmark=tpcds --pgdata=/home/ubuntu/data/postgres_data --tpcdsdata=/home/ubuntu/data/tpcds_data --sf=5
```

Spatial Benchmark:
```
screen -S install
sudo ./install.sh --benchmark=spatial --pgdata=/home/ubuntu/data/postgres_data --spatialdata=/home/ubuntu/data/spatial_data
```

## Options
```
sudo ./install.sh
    -h --help
    --benchmark=tpch                               # Benchmark: tpch (default), tpcds  
    --pgdata=/home/ubuntu/data/postgres_data   # PostgreSQL Data Directory (default)
    --tpchdata=/home/ubuntu/data/tpch_data     # TPC-H Benchmark Data Directory (default)
    --tpcdsdata=/home/ubuntu/data/tpcds_data   # TPC-DS Benchmark Data Directory (default)
    --spatialdata=/users/deb/data/spatial_data # Spatial Benchmark Directory (default)
    --sf=1                                     # Scale Factor in GBs (default 1 GB)
    --install=1                                # install=1 to install prerequisite  
                                               # 0 only run benchmark skip install
```
