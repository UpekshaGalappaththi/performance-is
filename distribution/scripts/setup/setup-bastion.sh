#!/usr/bin/env bash
# Copyright (c) 2018, wso2 Inc. (http://wso2.org) All Rights Reserved.
#
# wso2 Inc. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# ----------------------------------------------------------------------------
# Setup the bastion node to be used as the JMeter client.
# ----------------------------------------------------------------------------

wso2_is_ip=""
rds_host=""
is_image_link=""
cpus=""
memory=""
wso2is_host_alias=wso2is

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -w <wso2_is_ip> -r <rds_host> -i <image_link> -c <cpus> -m <memory>"
    echo ""
    echo "-w: The private IP of WSO2 IS node."
    echo "-l: The private hostname of Load balancer instance."
    echo "-r: The private hostname of RDS instance."
    echo "-i: IS docker image link"
    echo "-c: Number of CPU cores for the IS node"
    echo "-m: Memory for the IS node (GB)"
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "w:l:r:c:m:i:h" opts; do
    case $opts in
    w)
        wso2_is_ip=${OPTARG}
        ;;
    r)
        rds_host=${OPTARG}
        ;;
    i)
        is_image_link=${OPTARG}
        ;;
    c)
        cpus=${OPTARG}
        ;;
    m)
        memory=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done

if [[ -z $wso2_is_ip ]]; then
    echo "Please provide the private IP of WSO2 IS node."
    exit 1
fi

if [[ -z $rds_host ]]; then
    echo "Please provide the private hostname of the RDS instance."
    exit 1
fi

if [[ -z $is_image_link ]]; then
    echo "Please provide the link to the IS docker image."
    exit 1
fi

if [[ -z $cpus ]]; then
    echo "Please provide the number of CPU cores for the IS node."
    exit 1
fi

if [[ -z $memory ]]; then
    echo "Please provide the memory for the IS node."
    exit 1
fi

function get_ssh_hostname() {
    sudo -u ubuntu ssh -G $1 | awk '/^hostname / { print $2 }'
}

echo ""
echo "Setting up required files..."
echo "============================================"
cd /home/ubuntu
mkdir workspace
cd workspace

echo ""
echo "Extracting is performance distribution..."
echo "============================================"
tar -C /home/ubuntu/workspace -xzf /home/ubuntu/is-performance-distribution-*.tar.gz

echo ""
echo "Running JMeter setup script..."
echo "============================================"
cd /home/ubuntu
workspace/setup/setup-jmeter-client-is.sh -g -k /home/ubuntu/private_key.pem \
            -i /home/ubuntu \
            -c /home/ubuntu \
            -f /home/ubuntu/apache-jmeter-*.tgz \
            -a $wso2is_host_alias -n $wso2_is_ip \
            -a loadbalancer -n $wso2_is_ip\
            -a rds -n $rds_host
sudo chown -R ubuntu:ubuntu workspace
sudo chown -R ubuntu:ubuntu apache-jmeter-*
sudo chown -R ubuntu:ubuntu /tmp/jmeter.log
sudo chown -R ubuntu:ubuntu jmeter.log

echo ""
echo "Setting up IS instances..."
echo "============================================"
sudo -u ubuntu ssh $wso2is_host_alias mkdir sar setup
sudo -u ubuntu scp workspace/setup/setup-common.sh $wso2is_host_alias:/home/ubuntu/setup/
sudo -u ubuntu scp workspace/sar/install-sar.sh $wso2is_host_alias:/home/ubuntu/sar/
sudo -u ubuntu scp workspace/is/restart-is.sh $wso2is_host_alias:/home/ubuntu/
sudo -u ubuntu ssh $wso2is_host_alias sudo ./setup/setup-common.sh -p zip -p jq -p bc

# Running start-is.sh here as we cannot run it directly from the main script.
sudo -u ubuntu scp workspace/setup/start-is.sh $wso2is_host_alias:/home/ubuntu/
sudo -u ubuntu scp -r workspace/setup/resources $wso2is_host_alias:/home/ubuntu/
sudo -u ubuntu scp workspace/setup/createDB.sql $wso2is_host_alias:/home/ubuntu/
sudo -u ubuntu ssh $wso2is_host_alias sudo ./start-is.sh -r $rds_host -i $is_image_link -c $cpus -m $memory
