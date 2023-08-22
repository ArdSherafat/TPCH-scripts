# TPCH-scripts
Scripts to set up and run the TPC-H benchmark.

1. Run the setup.sh script to install all the necassry tools.
 ```
sudo ./setup.sh
 ```

Note: MSSQL only supports hard drives with up to 4k physical sector size, check your hard drive phical and logical sector size using the following commands to make sure they are not higher than 4k.
 ```
lsblk -o NAME,LOG-SEC
lsblk -o NAME,PHY-SEC
 ```

if higher, use the following command to create a virtual drive on top of your hard drive formatted to xfs and 4k physical and logical sector size.
 ```
sudo ./setup.sh -v -s {size of virtual drive} -p {path}
 ```

2. Run the run-tpch.sh script for generating the data, queries, loading the data into the database and running the benchmarks. (NOTE: Edit the MSSQL_DATA_DIR to specify where the MSSQL Database needs to be stored)
 ```    
      -d                    : generate data - scale d
      -q                    : generate query - number of queries q
      -l                    : load the data into database
      -w                    : warm up the database
      -p                    : run the Power test
      -t                    : run the Throughput Test 
 ```