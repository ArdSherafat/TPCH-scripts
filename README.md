# TPCH-scripts
This repository contains scripts to set up and execute the TPC-H benchmark.

## 1. SETUP
Execute the `setup.sh` script to install the necessary tools:
 ```
sudo ./setup.sh
 ```

**Note:** MSSQL supports hard drives with a maximum of 4k physical sector size. Ensure your hard drive's physical and logical sector sizes are not larger than 4k using these commands:
 ```
lsblk -o NAME,LOG-SEC
lsblk -o NAME,PHY-SEC
 ```

If the sizes are greater than 4k, you can use the following options with setup.sh to create a virtual drive formatted to xfs with 4k physical and logical sector sizes:
```
      -v                    : create a virtual drive
      -s                    : size of the virtual drive
      -p                    : path for mounting the virtual drive
``` 
**Example:**
To create a 10GB virtual drive mounted to the nvme1 directory, use:
```
sudo ./setup.sh -v -s 10 -p /nvme1
```
For more information about data and query generation, refer to the readme file inside the `dbgen` folder.

## 2. Running the TPC-H Benchmark
Execute `run-tpch.sh` to generate data, queries, load data into the database, and execute benchmarks.

**NOTE:** Modify MSSQL_DATA_DIR in the script to specify where the MSSQL Database should reside.
 ```    
      -d                    : generate data - scale d
      -q                    : generate query - number of queries q
      -l                    : load the data into database
      -w                    : warm up the database
      -p                    : run the Power test
      -t                    : run the Throughput Test 
 ```

 **Example:**
 To generate 100GB of data, a set of queries (22 in total), load the data into the database, warm up the database, and run both the power and throughput tests, use:
 ```
 sudo ./run-tpch.sh -d 100 -q 1 -l -w -p -t
 ```
 **NOTE:** The resulting database, post data loading, will be approximately 3 times larger than the generated data. Ensure adequate storage space is available.

 Executing run-tpch.sh will automatically start the Prometheus SQL Exporter, which exposes metrics from DBMSs for Prometheus monitoring on port 9399. Remember to add this exporter to your Prometheus configuration and adjust the hostname to match your setup:

 **NOTE:** By default, Docker is configured to use the standard gateway for the Docker bridge network, associated with the IP address 172.17.0.1. Should there be any alterations to this setup, the sql_exporter configuration file will require modifications.
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

 Additionally, the script provides an option to initiate the cAdvisor exporter, granting insights into container resource utilization and performance. This daemon aggregates and exports data about active containers on port 8082. Add this exporter to your Prometheus configuration and adjust the hostname to match your setup:
 
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
 