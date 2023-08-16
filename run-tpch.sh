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

function test-mssql() {
    # Check if mssql container is running
    if ! sudo docker ps | grep -q mssql; then
        echo "MSSQL container is not running!"
        exit 1
    fi

    # List of queries
    declare -a queries=(
        "USE TPCH; SELECT COUNT(*) FROM customer;"
        "USE TPCH; SELECT COUNT(*) FROM lineitem;"
        "USE TPCH; SELECT COUNT(*) FROM nation;"
        "USE TPCH; SELECT COUNT(*) FROM orders;"
        "USE TPCH; SELECT COUNT(*) FROM part;"
        "USE TPCH; SELECT COUNT(*) FROM partsupp;"
        "USE TPCH; SELECT COUNT(*) FROM region;"
        "USE TPCH; SELECT COUNT(*) FROM supplier;"
    )

    for query in "${queries[@]}"; do
        if ! sudo docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -Q "$query"; then
            echo "Failed to read the tables: $query"
            exit 1
        fi
    done

    echo "All queries executed successfully!"
    return 0
}

function power-test() 
{
    if [ -z ${POWERTEST} ];
    then
        return
    fi
    echo "Runnung TPC-H Power test..."
    # Create the CSV file with headers
    echo "Run,q14,q2,q9,q20,q6,q17,q18,q8,q21,q13,q3,q22,q16,q4,q11,q15,q1,q10,q19,q5,q7,q12,Total,Percentage Deviation" > temp.csv

    declare -a total_times

    for i in $(seq 1 3); do
        total_time_for_run=0

        # Begin the row with the run number
        row="Run ${i}"

        for q in 14 2 9 20 6 17 18 8 21 13 3 22 16 4 11 15 1 10 19 5 7 12; do

            # Capture start time
            start=$(date +%s%3N)

            # Run query
            if ! docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -d TPCH -i /data/tpch-schema/dbgen/generated_queries/${q}/0.sql >/dev/null; then
                echo "Failed to run query for q${q}. Exiting."
                return 1
            fi

            # Capture end time and calculate query time
            endt=$(date +%s%3N)
            query_time=$((endt - start))
            total_time_for_run=$((total_time_for_run + query_time))

            # Append query time to the current row
            row="${row},${query_time}"
        done

        # Store this run's total time
        total_times+=($total_time_for_run)

        # Append the total time for this run to the current row
        row="${row},${total_time_for_run}"

        # Write the row to the CSV file
        echo "${row}" >> temp.csv
    done

    # Calculate standard deviation
    sum=0
    for t in "${total_times[@]}"; do
        sum=$((sum + t))
    done
    mean=$(echo "$sum / ${#total_times[@]}" | bc -l)
    variance_sum=0
    for t in "${total_times[@]}"; do
        diff=$(echo "$t - $mean" | bc -l)
        diff_squared=$(echo "$diff^2" | bc -l)
        variance_sum=$(echo "$variance_sum + $diff_squared" | bc -l)
    done
    variance=$(echo "$variance_sum / (${#total_times[@]}-1)" | bc -l) # Corrected for sample variance
    stdev=$(echo "sqrt($variance)" | bc -l)

    # Add percentage deviation to the CSV
    for t in "${total_times[@]}"; do
        percentage_deviation=$(echo "scale=2; (($t - $mean) * 100) / $mean" | bc -l)
        sed -i "/${t}$/s/$/,${percentage_deviation}%/" temp.csv
    done

    echo "Standard Deviation of total_time_for_run: $stdev"

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
    }' temp.csv > powertest.csv
    sudo rm temp.csv
    echo "DONE"
}


function print_usage()
{
    echo "      -d                    : generate data - scale d"
    echo "      -q                    : generate query - number of queries q"
    echo "      -l                    : load the data into dataset"
    echo "      -p                    : run the power test"
}


if [ "$#" -eq "0" ];
then
    print_usage
    exit 1
fi


while getopts 'd:q:pl' opt; do
    case "$opt" in
       d)
           DATA_SIZE=$OPTARG
       ;;
       q)
           QUERY_NUM=$OPTARG
       ;;
       l)
           LOAD_DATA=1
       ;;
       p)
           POWER_TEST=1
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
load-data
test-mssql
power-test
