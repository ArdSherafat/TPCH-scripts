#!/usr/bin/env python3

import os
import random
import argparse
import subprocess
import random
from pathlib import Path


def generate_queries(indices, args, directory='.'):
    """Generate queries from the list of allowed templates"""
    for template in indices:
        print(template, end=' ')
        for count in range(args.num_queries):
            directory = f"./generated_queries/{template}/"
            file_path = directory+f"{str(count)}.sql"
            Path(directory).mkdir(parents=True, exist_ok=True)
            # print(file_path)
            subprocess.call('touch ' + file_path, shell=True)
            shell_cmd = f'./qgen {str(template)} -r {(count + 1) * 100} -s 100 > {file_path}'
            # print(shell_cmd)
            subprocess.call(shell_cmd, shell=True)
    print()



def run_queries(indices, args, directory='.'):
    """run queries"""

    for template in indices:
        for count in range(args.num_queries):
            input_directory = f"/data/tpch-repo/dbgen/generated_queries/{template}/"
            input_path = input_directory + f"{str(count)}.sql"
            
            directory = f"./run_queries/{template}/"
            d2 = f"/data/tpch-repo/dbgen/run_queries/{template}/"

            output_path = directory + str(count) + '.txt'
            out2 = d2 + str(count) + '.txt'

            Path(directory).mkdir(parents=True, exist_ok=True)
            subprocess.call('touch ' + output_path + ' && chmod 666 ' + output_path, shell=True)
            shell_cmd = f'docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S {args.server} -U {args.user} -P {args.password} -d TPCH -i {input_path} -o {out2}'

            subprocess.call(shell_cmd, shell=True)



if __name__ == "__main__":
    os.chdir('./dbgen')
    print(os.getcwd())
    NUM_TEMPLATES = 22

    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        "-U", "--user", help="db administrator", default="SA")
    arg_parser.add_argument("-P", "--password", help="password", default="Memverge#123")
    arg_parser.add_argument("--num_queries",
                            help="Number of queries to generate per template", type=int)
    arg_parser.add_argument(
        "--server", help="The server to run sqlcmd from", default="localhost")
    arg_parser.add_argument("--generate_queries",
                            action="store_true", default=False)
    arg_parser.add_argument("--runquery", action="store_true", default=False)
    args = arg_parser.parse_args()

    indices = list(range(1, NUM_TEMPLATES + 1))  # 22 query templates

    if args.generate_queries:
        # generate queries
        generate_queries(indices, args, "run")

    if args.runquery:
        # run queries
        run_queries(indices, args, "run")
