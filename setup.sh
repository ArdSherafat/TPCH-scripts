#!/bin/bash

# Read the OS ID and version from /etc/os-release
os_id=$(grep -w ID /etc/os-release | cut -d'=' -f2 | tr -d '"')
version_id=$(grep -w VERSION_ID /etc/os-release | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
 
# Docker install for Ubuntu
function install-docker()
{
    if ! command -v docker &>/dev/null; then
        if [ ${os_id} = "fedora" ]; then
            sudo setenforce 0
            sudo dnf remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo docker info -f '{{ .DockerRootDir}}'

        elif [[ ${os_id} = "rhel" ]] || [[ ${os_id} = "centos" ]]; then 
            sudo setenforce 0
            sudo yum remove docker \
                    docker-client \
                    docker-client-latest \
                    docker-common \
                    docker-latest \
                    docker-latest-logrotate \
                    docker-logrotate \
                    docker-engine   
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker

        elif [ ${os_id} = "ubuntu" ]; then
            sudo apt update
            for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
            sudo apt install ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
            "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            "$(. /etc/os-release && echo "${VERSION_CODENAME}")" stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update
            sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo docker info -f '{{ .DockerRootDir}}'
        fi
    fi
}


function install-tools()
{
    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        if ! command -v make >/dev/null 2>&1; then
            sudo apt install make
        fi
        if ! command -v bc >/dev/null 2>&1; then
            sudo apt install bc 
        fi
        if ! dpkg -l | grep -q "^ii.*build-essential"; then
            sudo apt install build-essential
        fi

    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf check-update
        if ! command -v make >/dev/null 2>&1; then
            sudo dnf install make 
        fi
        if ! command -v bc >/dev/null 2>&1; then
            sudo dnf install bc 
        fi
        if ! dnf group list "Development Tools" | grep -q "Installed"; then
            sudo dnf groupinstall "Development Tools"
        fi
    elif command -v yum >/dev/null 2>&1; then
        sudo yum check-update
        if ! command -v make >/dev/null 2>&1; then
            sudo yum install make 
        fi
        if ! command -v bc >/dev/null 2>&1; then
            sudo yum install bc 
        fi
        if ! yum group list "Development Tools" | grep -q "Installed"; then
            sudo yum groupinstall "Development Tools"
        fi 
    else
        echo "[ERROR] Package manager not found. Cannot install"
        exit 1
    fi  
}


function vhd-setup() {
    if [ -z ${VIRTUAL_DRIVE} ];
    then
        return
    fi

    echo "SIZE: ${SIZE}"
    echo "VIRTUAL_PATH: ${VIRTUAL_PATH}"

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

function compile-files()
{
    cd dbgen
    sudo make
    cd ..
}


function print_usage()
{
    echo "      -v                    : create a virtual drive"
    echo "      -s                    : size of the virtual drive"
    echo "      -p                    : path for mounting the virtual drive"
}


while getopts 'vs:p:' opt; do
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
if [ -n "${VIRTUAL_DRIVE}" ]; then
    if [[ ( -z ${SIZE} || -z ${VIRTUAL_PATH} ) ]]; then
        echo "Both options -s and -p are required when -v is activated."
        print_usage
        exit 1
    fi
fi

install-tools
install-docker
vhd-setup
compile-files