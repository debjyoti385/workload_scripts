# Workload Scripts
These scripts installs PostgreSQL 10, PostGIS 2.4 and Oltpbenchmark on AWS Ubuntu 18.04 or 16.04 instances. It also upload benchmark runs and experiment data to server. 

## Quickstart 
```
curl -L0k https://github.com/debjyoti385/workload_scripts/archive/master.zip -o master.zip
sudo apt-get install unzip 
unzip -j master.zip
rm master.zip
chmod +x install.sh
sudo ./install.sh
```
