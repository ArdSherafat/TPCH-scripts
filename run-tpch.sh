#!/bin/bash

export SA_PASSWORD="Memverge#123"

SCRIPT_DIR_NAME=$( dirname $( readlink -f $0 ))
DATA_DIR="${SCRIPT_DIR_NAME}/dbgen"
MSSQL_DATA_DIR="/nvme1/data"

function wait-for-sql()
{
    # Wait for SQL Server to be ready (max 20 attempts)
    attempts=0
    max_attempts=20
    while true; do
        if sudo docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -Q "SELECT 1;" > /dev/null 2>&1; then
            echo "SQL Server is ready"
            break
        else
            attempts=$((attempts+1))
            if [ $attempts -eq $max_attempts ]; then
                echo "SQL Server is not ready after $max_attempts attempts, exiting"
                exit 1
            fi
            echo "Waiting for SQL Server to be ready ($attempts/$max_attempts)"
            sleep 5
        fi
    done
}


function generate-data()
{
    if [ -z ${DATA_SIZE} ];
    then
        return
    fi
    echo "Generating the data..."
    cd dbgen
    # for((i=1;i<=8;i++));
    # do
    #    sudo ./dbgen -s "${DATA_SIZE}" -S "${i}" -C 8 -f &
    # done

    sudo ./dbgen -s "${DATA_SIZE}"
    cd ..
    echo "DONE"
}


function generate-queries()
{
    if [ -z ${QUERY_NUM} ];
    then
        return
    fi
    echo "Genereting the queries..."
    export DSS_QUERY=./queries_original
    python3 gen_run_queries.py --num_queries "${QUERY_NUM}" --generate_queries
    echo "DONE"
}


function start-mssql()
{
    # Check if mssql container is running
    if sudo docker ps | grep -q mssql; then
        echo "MSSQL container is running!"
        return
    fi

    echo "Starting MSSQL..."
    # add mssql image
    local mssql_image="mcr.microsoft.com/mssql/server:2022-latest"
    if [[ -z $(docker images -q "${mssql_image}") ]]; then
        sudo docker pull "${mssql_image}"
    fi

    sudo mkdir -p "${MSSQL_DATA_DIR}/mssql"
    sudo chmod 777 "${MSSQL_DATA_DIR}/mssql"
    #start ms-sql server
    sudo docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=${SA_PASSWORD}" \
          -p 1433:1433 --name mssql --hostname mssql \
          -v ${DATA_DIR}/:/data/tpch-data/ \
          -v ${SCRIPT_DIR_NAME}/:/data/tpch-schema/ \
          -v /${MSSQL_DATA_DIR}/mssql/:/var/opt/mssql/ \
          -d \
          mcr.microsoft.com/mssql/server:2022-latest

    wait-for-sql
}


function start-sql-exporter()
{
    # Check if sql-exporter container is running
    if sudo docker ps | grep -q sql-exporter; then
        echo "SQL-Exporter container is running!"
        return
    fi

    echo "Starting SQL-Exporter..."
    # add sql-exporter image
    local sql_exporter_image="githubfree/sql_exporter"
    if [[ -z $(docker images -q "${sql_exporter_image}") ]]; then
        sudo docker pull "${sql_exporter_image}"
    fi

    sudo docker run -d -p 9399:9399 --name=sql-exporter -v $(pwd)/cnfs/sql_exporter.yml:/sql_exporter.yml:ro githubfree/sql_exporter:latest

}

#Resource usage and performance characteristics of the running containers
function start-cadvisor()
{
    # Check if sql-exporter container is running
    if sudo docker ps | grep -q cadvisor; then
        echo "Cadvisor container is running!"
        return
    fi

    echo "Starting Cadvisor..."
   
    sudo docker run \
    --volume=/:/rootfs:ro \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --volume=/dev/disk/:/dev/disk:ro \
    --publish=8082:8080 \
    --detach=true \
    --name=cadvisor \
    --privileged \
    --device=/dev/kmsg \
    gcr.io/cadvisor/cadvisor:v0.47.2
}

function load-data()
{
    if [ -z ${LOAD_DATA} ];
    then
        return
    fi
    # Check if mssql container is running
    if ! sudo docker ps | grep -q mssql; then
        echo "MSSQL container is not running!"
        exit 1
    fi

    echo "Loading the data into database..."
    # Create the schema and load the data into the database
    sudo docker exec mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -i /data/tpch-schema/schema/tpch.sql
    # Create primary keys and foreign keys
    sudo docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -i /data/tpch-schema/schema/tpch_fk.sql
    
}

function check-mssql() {
    # Check if mssql container is running
    if ! sudo docker ps | grep -q mssql; then
        echo "MSSQL container is not running!"
        exit 1
    fi

    # Check for the existence of TPCH database
    DB_CHECK="SELECT name FROM master.sys.databases WHERE name = 'TPCH';"
    if ! sudo docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -Q "$DB_CHECK" | grep "TPCH"; then
        echo "TPCH database does not exist."
        exit 1
    fi

    echo "TPCH database exists."
    return 0
}

function calculate_variance_and_transpose() {
    local file_name="$1"
    local -a total_times=("${@:2}")

    local sum=0
    for t in "${total_times[@]}"; do
        sum=$((sum + t))
    done

    local mean=$(echo "$sum / ${#total_times[@]}" | bc -l)
    local variance_sum=0

    for t in "${total_times[@]}"; do
        local diff=$(echo "$t - $mean" | bc -l)
        local diff_squared=$(echo "$diff^2" | bc -l)
        variance_sum=$(echo "$variance_sum + $diff_squared" | bc -l)
    done

    local variance=$(echo "$variance_sum / (${#total_times[@]}-1)" | bc -l) # sample variance
    local stdev=$(echo "sqrt($variance)" | bc -l)

    for t in "${total_times[@]}"; do
        local percentage_deviation=$(echo "scale=2; (($t - $mean) * 100) / $mean" | bc -l)
        sed -i "/${t}$/s/$/,${percentage_deviation}%/" tmp.csv
    done

    awk '
    BEGIN { FS=OFS="," }
    {
        for (i=1; i<=NF; i++) {
            a[NR,i] = $i
        }
    }
    NF>p { p=NF }
    END {
        for (j=1; j<=p; j++) {
            str=a[1,j]
            for (i=2; i<=NR; i++) {
                str=str OFS a[i,j]
            }
            print str
        }
    }' tmp.csv > "$file_name"
    sudo rm tmp.csv
}

function warm-the-database()
{
    if [ -z ${WARM_DB} ];
    then
        return
    fi
    echo "Warming up the database..."
    for i in $(seq 1 2); do
        for q in $(seq 1 22); do
            if ! docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -d TPCH -i /data/tpch-schema/dbgen/generated_queries/${q}/0.sql >/dev/null; then
                echo "Failed to run query for q${q}. Exiting."
                return 1
            fi
        done
    done
    echo "DONE"
}

function power-test() 
{
    if [ -z ${POWER_TEST} ];
    then
        return
    fi

    local NUM_RUNS=3 # Set your desired number of runs here

    echo "Runnung TPC-H Power test..."
    echo "Run,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,Total,Percentage Deviation" > tmp.csv

    declare -a total_times

    for i in $(seq 1 $NUM_RUNS); do
        total_time_for_run=0
        row="Run ${i}"

        for q in 14 2 9 20 6 17 18 8 21 13 3 22 16 4 11 15 1 10 19 5 7 12; do

            start=$(date +%s%3N)

            if ! docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -d TPCH -i /data/tpch-schema/dbgen/generated_queries/${q}/0.sql >/dev/null; then
                echo "Failed to run query for q${q}. Exiting."
                return 1
            fi

            endt=$(date +%s%3N)
            query_time=$((endt - start))
            total_time_for_run=$((total_time_for_run + query_time))

            row="${row},${query_time}"
        done

        total_times+=($total_time_for_run)
        row="${row},${total_time_for_run}"
        echo "${row}" >> tmp.csv
    done
    echo "DONE"
    calculate_variance_and_transpose "power-test.csv" "${total_times[@]}"
}


function throughput-test()
{
    if [ -z ${THROUGHPUT_TEST} ];
    then
        return
    fi

    echo "Runnung TPC-H Throughput test..."
    echo "Run,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,Total,Percentage Deviation" > tmp.csv


    arr1=(21 3 18 5 11 7 6 20 17 12 16 15 13 10 2 8 14 19 9 22 1 4) 
    arr2=(6 17 14 16 19 10 9 2 15 8 5 22 12 7 13 18 1 4 20 3 11 21)
    arr3=(8 5 4 6 17 7 1 18 22 14 9 10 15 11 20 2 21 19 13 16 12 3) 
    arr4=(5 21 14 19 15 17 12 6 4 9 8 16 11 2 10 18 1 13 7 22 3 20) 
    arr5=(21 15 4 6 7 16 19 18 14 22 11 13 3 1 2 5 8 20 12 17 10 9) 
    arr6=(10 3 15 13 6 8 9 7 4 11 22 18 12 1 5 16 2 14 19 20 17 21) 
    arr7=(18 8 20 21 2 4 22 17 1 11 9 19 3 13 5 7 10 16 6 14 15 12)
    arr8=(19 1 15 17 5 8 9 12 14 7 4 3 20 16 6 22 10 13 2 21 18 11) 
    arr9=(8 13 2 20 17 3 6 21 18 11 19 10 15 4 22 1 7 12 9 14 5 16) 
    arr10=(6 15 18 17 12 1 7 2 22 13 21 10 14 9 3 16 20 19 11 4 8 5)
    arr11=(15 14 18 17 10 20 16 11 1 8 4 22 5 12 3 9 21 2 13 6 19 7) 
    arr12=(1 7 16 17 18 22 12 6 8 9 11 4 2 5 20 21 13 10 19 3 14 15)
    arr13=(21 17 7 3 1 10 12 22 9 16 6 11 2 4 5 14 8 20 13 18 15 19)
    arr14=(2 9 5 4 18 1 20 15 16 17 7 21 13 14 19 8 22 11 10 3 12 6) 
    arr15=(16 9 17 8 14 11 10 12 6 21 7 3 15 5 22 20 1 13 19 2 4 18) 
    arr16=(1 3 6 5 2 16 14 22 17 20 4 9 10 11 15 8 12 19 18 13 7 21) 
    arr17=(3 16 5 11 21 9 2 15 10 18 17 7 8 19 14 13 1 4 22 20 6 12) 
    arr18=(14 4 13 5 21 11 8 6 3 17 2 20 1 19 10 9 12 18 15 7 22 16)
    arr19=(4 12 22 14 5 15 16 2 8 10 17 9 21 7 3 6 13 18 11 20 19 1) 
    arr20=(16 15 14 13 4 22 18 19 7 1 12 17 5 10 20 3 9 21 11 2 6 8) 
    arr21=(20 14 21 12 15 17 4 19 13 10 11 1 16 5 18 7 8 22 9 6 3 2) 
    arr22=(16 14 13 2 21 10 11 4 1 22 18 12 19 5 7 8 6 3 15 20 9 17) 
    arr23=(18 15 9 14 12 2 8 11 22 21 16 1 6 17 5 10 19 4 20 13 3 7) 
    arr24=(7 3 10 14 13 21 18 6 20 4 9 8 22 15 2 1 5 12 19 17 11 16) 
    arr25=(18 1 13 7 16 10 14 2 19 5 21 11 22 15 8 17 20 3 4 12 6 9) 
    arr26=(13 2 22 5 11 21 20 14 7 10 4 9 19 18 6 3 1 8 15 12 17 16) 
    arr27=(14 17 21 8 2 9 6 4 5 13 22 7 15 3 1 18 16 11 10 12 20 19) 
    arr28=(10 22 1 12 13 18 21 20 2 14 16 7 15 3 4 17 5 19 6 8 9 11) 
    arr29=(10 8 9 18 12 6 1 5 20 11 17 22 16 3 13 2 15 21 14 19 7 4) 
    arr30=(7 17 22 5 3 10 13 18 9 1 14 15 21 19 16 12 8 6 11 20 4 2) 
    arr31=(2 9 21 3 4 7 1 11 16 5 20 19 18 8 17 13 10 12 15 6 14 22) 
    arr32=(15 12 8 4 22 13 16 17 18 3 7 5 6 1 9 11 21 10 14 20 19 2) 
    arr33=(15 16 2 11 17 7 5 14 20 4 21 3 10 9 12 8 13 6 18 19 22 1)
    arr34=(1 13 11 3 4 21 6 14 15 22 18 9 7 5 10 20 12 16 17 8 19 2) 
    arr35=(14 17 22 20 8 16 5 10 1 13 2 21 12 9 4 18 3 7 6 19 15 11) 
    arr36=(9 17 7 4 5 13 21 18 11 3 22 1 6 16 20 14 15 10 8 2 12 19) 
    arr37=(13 14 5 22 19 11 9 6 18 15 8 10 7 4 17 16 3 1 12 2 21 20) 
    arr38=(20 5 4 14 11 1 6 16 8 22 7 3 2 12 21 19 17 13 10 15 18 9) 
    arr39=(3 7 14 15 6 5 21 20 18 10 4 16 19 1 13 9 8 17 11 12 22 2) 
    arr40=(13 15 17 1 22 11 3 4 7 20 14 21 9 8 2 18 16 6 10 12 5 19)

    declare -a total_times

    for i in $(seq 1 40); do
        total_time_for_run=0
        row="Run ${i}"
        array_name="arr${i}[@]"
        for q in "${!array_name}"; do
            start=$(date +%s%3N)
            if ! docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -d TPCH -i /data/tpch-schema/dbgen/generated_queries/${q}/0.sql >/dev/null; then
                echo "Failed to run query for q${q}. Exiting."
                return 1
            fi
            endt=$(date +%s%3N)
            query_time=$((endt - start))
            total_time_for_run=$((total_time_for_run + query_time))
            row="${row},${query_time}"
        done
        total_times+=($total_time_for_run)
        row="${row},${total_time_for_run}"

        echo "${row}" >> tmp.csv
    done
    echo "DONE"
    calculate_variance_and_transpose "throughput-test.csv" "${total_times[@]}"

} 


function print_usage()
{
    echo "      -d                    : generate data - scale d"
    echo "      -q                    : generate query - number of queries q"
    echo "      -l                    : load the data into database"
    echo "      -w                    : warm up the database"
    echo "      -p                    : run the Power test"
    echo "      -t                    : run the Throughput Test "
}


if [ "$#" -eq "0" ];
then
    print_usage
    exit 1
fi


while getopts 'd:q:wplt' opt; do
    case "$opt" in
       d)
           DATA_SIZE=$OPTARG
       ;;
       q)
           QUERY_NUM=$OPTARG
       ;;
       w)
           WARM_DB=1
       ;;
       l)
           LOAD_DATA=1
       ;;
       p)
           POWER_TEST=1
       ;;
       t)
           THROUGHPUT_TEST=1
       ;;       
       ?|h)
           print_usage
           exit 0
       ;;
    esac
done


generate-data
generate-queries
start-mssql
start-sql-exporter
# start-cadvisor
load-data
check-mssql
warm-the-database
power-test
throughput-test