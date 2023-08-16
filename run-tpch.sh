#!/bin/bash

export SA_PASSWORD="Memverge#123"

SCRIPT_DIR_NAME=$( dirname $( readlink -f $0 ))

# schema_dir="${SCRIPT_DIR_NAME}/TPC-H-Dataset-Generator-MS-SQL-Server"
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
    if [ -z ${SIZE} ];
    then
        return
    fi

    for((i=1;i<=8;i++));
    do
       sudo ./dbgen/dbgen -s ${SIZE} -S $i -C 8 -f &
    done
}

function generate-queries()
{
    local indices=$1
    local args_num_queries=$2

    for template in $indices; do
        echo -n "$template "
        for count in $(seq 0 $(($args_num_queries - 1))); do
            directory="./generated_queries/${template}/"
            file_path="${directory}${count}.sql"
            mkdir -p $directory
            touch $file_path
            ./dbgen/qgen ${template} -r $(($count + 1) * 100) -s 100 > $file_path
        done
    done
    echo
}


function start-mssql()
{
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
    wait_for_sql

    # Create the schema and load the data into the database
    sudo docker exec mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -i /data/tpch-schema/schema/tpch.sql
    # Create primary keys and foreign keys
    sudo docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P ${SA_PASSWORD} -i /data/tpch-schema/schema/tpch_fk.sql
    
}


function print_usage()
{
    echo "      -s                    : generate the data with scale-GB"
}


if [ "$#" -eq "0" ];
then
    print_usage
    exit 1
fi


while getopts 's' opt; do
    case "$opt" in
       s)
           SIZE=$OPTARG
       ;;
       ?|h)
           print_usage
           exit 0
       ;;
    esac
done

generate-data
generate-queries
