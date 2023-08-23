# TPCH-scripts
Scripts to set up and run the TPC-H benchmark.

## 1. SETUP
Run the setup.sh script to install all the necassry tools.
 ```
sudo ./setup.sh
 ```

Note: MSSQL only supports hard drives with up to 4k physical sector size, check your hard drive physical and logical sector size using the following commands to make sure they are not higher than 4k.
 ```
lsblk -o NAME,LOG-SEC
lsblk -o NAME,PHY-SEC
 ```

if higher, use the following command to create a virtual drive on top of your hard drive formatted to xfs and 4k physical and logical sector size.
```
      -v                    : create a virtual drive
      -s                    : size of the virtual drive
      -p                    : path for mounting the virtual drive
``` 
Example:
To create a virtual drive with the size of 10GB in the directory nvme1:
```
sudo ./setup.sh -v -s 10 -p /nvme1
```

## 2. Running the TPC-H Benchmark
Run the run-tpch.sh script for generating the data, queries, loading the data into the database and running the benchmarks. (NOTE: Edit the MSSQL_DATA_DIR to specify where the MSSQL Database needs to be stored)
 ```    
      -d                    : generate data - scale d
      -q                    : generate query - number of queries q
      -l                    : load the data into database
      -w                    : warm up the database
      -p                    : run the Power test
      -t                    : run the Throughput Test 
 ```

 Example:
 To generate 100GB data, 1 set of querries(22 query), load the data into database, warm up the database, and run the power and throughput test
 ```
 sudo ./run-tpch.sh -d 100 -q 1 -l -w -p -t
 ```

 Running the run-tpch.sh script, will activate the Prometheus SQL Exporter automatically. This exporter exposes metrics gathered from DBMSs, for use by the Prometheus monitoring system through the port 9399. You will need to add this exporter to the Prometheus config file.
 Note: It is assumed that the docker is using the default gateway for the Docker bridge network IP address 172.17.0.1. If changed, the sql_exporter config file needs to be modifeid.
 Example:
 ```
  # sql exporter metrics exporter scrape
  - job_name: “sql-exporter-server"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["genoa4.eng.memverge.com:9399"]
        labels:
          group: "cxl"
 ```
 For more information about this exporter, check the following link:
 [Prometheus SQL Exporter](https://github.com/free/sql_exporter)

 Additionally, this script comes with the option to start cAdvisor exporter which provides container users an understanding of the resource usage and performance characteristics of their running containers. It is a running daemon that collects, aggregates, processes, and exports information about running containers thorugh the port 8082. You can add this exporter to the Prometheus config file.
 ```
  # cAdvisor metrics exporter scrape
  - job_name: “cadvisor-server"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["genoa4.eng.memverge.com:8082"]
        labels:
          group: "cxl"
 ```
 For more information about this exporter, check the following link:
 [cAdvisor (Container Advisor)](https://github.com/google/cadvisor)
 