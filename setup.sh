#!/bin/bash

# Docker install for Ubuntu
function install-docker()
{
    if ! command -v docker &>/dev/null; then
        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
        sudo apt install ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          "$(. /etc/os-release && echo "${VERSION_CODENAME}")" stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        sudo docker info -f '{{ .DockerRootDir}}'
    fi
}


function install-tools()
{
  if ! command -v make &>/dev/null; then
      sudo apt install make
  fi
  if ! dpkg -l | grep -q "^ii.*build-essential"; then
      sudo apt install build-essential
  fi
}


function install-tools()
{
  if ! command -v make &>/dev/null; then
      sudo apt install make
  fi
  if ! dpkg -l | grep -q "^ii.*build-essential"; then
      sudo apt install build-essential
  fi
}

function VDH-setup() {
    if [ -z ${VIRTUAL_DRIVE} ];
    then
        return
    fi

    local img_path="${VIRTUAL_PATH}/virtual_drive.img"
    data_path=${VIRTUAL_PATH}/data

    sudo mkdir -p "${data_path}" || { echo "Failed to create data path"; return 1; }
    
    local loop_device
    loop_device=$(losetup -f) || { echo "Failed to find loop device"; return 1; }
    fallocate -l "${SIZE}G" "${img_path}" || { echo "Failed to allocate virtual drive image"; return 1; }
    sudo losetup --sector-size 4096 "${loop_device}" "${img_path}" || { echo "Failed to setup loop device"; return 1; }
    sudo mkfs.xfs "${loop_device}" || { echo "Failed to format the virtual drive"; return 1; }
    sudo mount "${loop_device}" "${data_path}" || { echo "Failed to mount the virtual drive"; return 1; }
}


function print_usage()
{
    echo "      -v                    : create a virtual drive"
    echo "      -s                    : size of the virtual drive"
    echo "      -p                    : path for mounting the virtual drive"
}


while getopts 'vsp' opt; do
    case "$opt" in
       v)
           VIRTUAL_DRIVE=1 
       ;;
       s)
           SIZE=$OPTARG
       ;;
       p)
           VIRTUAL_PATH=$OPTARG
       ;;
       ?|h)
           print_usage
           exit 0
       ;;
    esac
done

# Check if -v is activated -s or -p are provided
if [ "${VIRTUAL_DRIVE}" -eq "1" ]; then
    if [ -z "${SIZE}" ] || [ -z "${VIRTUAL_PATH}" ]; then
        echo "Both options -s and -p are required when -v is activated."
        print_usage
        exit 1
    fi
fi

sudo apt update
install-docker
install-tools
VDH-setup

cd TPC-H-Dataset-Generator-MS-SQL-Server/dbgen
sudo make
cd ..
