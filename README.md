# Workload Scripts
These scripts installs PostgreSQL 10, PostGIS 2.4 and Oltpbenchmark on AWS Ubuntu 18.04 or 16.04 instances. It also upload benchmark runs and experiment data to server.

## Quickstart  
1. Download the script
```
curl -L0k https://github.com/debjyoti385/workload_scripts/archive/master.zip -o master.zip
sudo apt-get install bsdtar -y
bsdtar -xf master.zip -s'|[^/]*/||'
rm master.zip
chmod +x install.sh

```
2. Run Benchmarks: (Use `screen`)

TPC-H Benchmark: Scale Factor 3 GB
```
screen -S install
sudo ./install.sh --benchmark=tpch --pgdata=/home/ubuntu/data/postgres_data --data=/home/ubuntu/data/tpch_data  --sf=3
```

TPC-DS Benchmark: Scale Factor 5 GB
```
screen -S install
sudo ./install.sh --benchmark=tpcds --pgdata=/home/ubuntu/data/postgres_data --data=/home/ubuntu/data/tpcds_data --sf=5
```

Spatial Benchmark:
```
screen -S install
sudo ./install.sh --benchmark=spatial --pgdata=/home/ubuntu/data/postgres_data --data=/home/ubuntu/data/spatial_data
```

OSM Benchmark:
```
screen -S install
sudo ./install.sh --benchmark=osm --pgdata=/home/ubuntu/data/postgres_data --data=/home/ubuntu/data/osm_data --osmdb=los_angeles_county
```

## Options
```
sudo ./install.sh
    -h --help
    --benchmark=tpch                           # Benchmark: tpch (default), tpcds, spatial, osm
    --pgdata=/home/ubuntu/data/postgres_data   # PostgreSQL Data Directory (default)
    --data=/home/ubuntu/data/benchmark_data    # Benchmark Data Directory (default)
    --sf=1                                     # Scale Factor in GBs (default 1 GB)
    --install=1                                # install=1 to install prerequisite  
                                               # install=0 only run benchmark skip install
    --import=1                                 # import=1 perform data import
                                               # import=0 for no data import
    --osmdb=los_angeles_county                 # options los_angeles_county, new_york_county, salt_lake_county
                                               # los_angeles_city, new_york_city, salt_lake_city
```
