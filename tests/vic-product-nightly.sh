#!/bin/bash
# Copyright 2018 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

ESX_60_VERSION="ob-5251623"
VC_60_VERSION="ob-5112509"

ESX_65_VERSION="ob-7867845"
VC_65_VERSION="ob-7867539"

ESX_67_VERSION="ob-8169922"
VC_67_VERSION="ob-8217866"

DEFAULT_LOG_UPLOAD_DEST="vic-product-ova-logs"
DEFAULT_BRANCH=""
DEFAULT_BUILD="*"
DEFAULT_TESTCASES=("tests/manual-test-cases")

DEFAULT_PARALLEL_JOBS=4
DEFAULT_RUN_AS_OPS_USER=0

ARTIFACT_PREFIX="vic-"
ARTIFACT_BUCKET="vic-product-ova-builds"

start_node () {
    docker run -d --net grid -e HUB_HOST=selenium-hub -v /dev/shm:/dev/shm --name $1 $2

    for i in `seq 1 10`; do
        if [[ "$(docker logs $1)" = *"The node is registered to the hub and ready to use"* ]]; then
            echo "$1 node is up and ready to use";
            return 0;
        fi
        sleep 3;
    done
}

# get the env file and source it so we can use the variables both in this script and the container
envfile="$1"
. ${envfile}

# This is exported to propagate into the pybot processes launched by pabot
export RUN_AS_OPS_USER=${RUN_AS_OPS_USER:-${DEFAULT_RUN_AS_OPS_USER}}

PARALLEL_JOBS=${PARLLEL_JOBS:-${DEFAULT_PARALLEL_JOBS}}
LOG_UPLOAD_DEST="${LOG_UPLOAD_DEST:-${DEFAULT_LOG_UPLOAD_DEST}}"


# process the CLI arguments
target="$2"
if [[ ${target} != "6.0" && ${target} != "6.5" && ${target} != "6.7" ]]; then
    echo "Please specify a target version. One of: 6.0, 6.5, 6.7"
    exit 1
else
    echo "Target version: ${target}"
    excludes=("--exclude skip")
    case "$target" in
        "6.0")
            excludes+=("--exclude nsx")
            ESX_BUILD=${ESX_BUILD:-$ESX_60_VERSION}
            VC_BUILD=${VC_BUILD:-$VC_60_VERSION}
            ;;
        "6.5")
            ESX_BUILD=${ESX_BUILD:-$ESX_65_VERSION}
            VC_BUILD=${VC_BUILD:-$VC_65_VERSION}
            ;;
        "6.7")
            excludes+=("--exclude nsx" "--exclude hetero")
            ESX_BUILD=${ESX_BUILD:-$ESX_67_VERSION}
            VC_BUILD=${VC_BUILD:-$VC_67_VERSION}
            ;;
    esac
fi

# drop the first two arguements from the $@ array
shift
shift
# Take the remaining CLI arguments as a test case list - this is treated as an array to preserve quoting when passing to pabot
testcases=("${@:-${DEFAULT_TESTCASES[@]}}")

# Enforce short SHA
GIT_COMMIT=${GIT_COMMIT:0:7}

# TODO: the version downloaded by this logic is not coupled with the tests that will be run against it. This should be altered to pull a version that matches the commit SHA of the tests
# we will be running or similar mechanism.
BUILD=${BUILD:-${DEFAULT_BUILD}}
BRANCH=${BRANCH:-${DEFAULT_BRANCH}}
input=$(gsutil ls -l gs://${ARTIFACT_BUCKET}/${BRANCH}${BRANCH:+/}${ARTIFACT_PREFIX}${BUILD} | grep -v TOTAL | sort -k2 -r | head -n1 | xargs | cut -d ' ' -f 3 | cut -d '/' -f 4)

# strip prefix and suffix from archive filename
BUILD=${input#${ARTIFACT_PREFIX}}
BUILD=${BUILD%%.*}

echo "Kill any old selenium infrastructure..."
docker rm -f selenium-hub firefox1 firefox2 firefox3 firefox4
docker network prune -f

echo "Create the network, hub and workers..."
docker network create grid
docker run -d -p 4444:4444 --net grid --name selenium-hub selenium/hub:3.9.1
for i in `seq 1 10`; do
    if [[ "$(docker logs selenium-hub 2>&1)" = *"Selenium Grid hub is up and running"* ]]; then
        echo 'Selenium Server is up and running';
        break
    fi
    sleep 3;
done

start_node firefox1 selenium/node-firefox:3.9.1
start_node firefox2 selenium/node-firefox:3.9.1
start_node firefox3 selenium/node-firefox:3.9.1
start_node firefox4 selenium/node-firefox:3.9.1

n=0 && rm -f "$Repo/${input}"
until [ $n -ge 5 -o -f "$Repo/${input}" ]; do
    echo "Retry.. $n"
    echo "Downloading gcp file ${input}"
    wget --directory-prefix=$Repo/ --unlink -nv https://storage.googleapis.com/${ARTIFACT_BUCKET}/${input}

    ((n++))
    sleep 15
done

if [ ! -f  "$Repo/${input}" ]; then
    echo "VIC Product OVA download failed..quitting the run"
    exit
else
    echo "VIC Product OVA download complete...";
fi

docker run --net grid --privileged --rm --link selenium-hub:selenium-grid-hub -v /var/run/docker.sock:/var/run/docker.sock -v /etc/docker/certs.d:/etc/docker/certs.d -v $PWD/$Repo:/go -v /vic-cache:/vic-cache --env-file "${envfile}" --env-file vic-internal/vic-product-nightly-secrets.list gcr.io/eminent-nation-87317/vic-integration-test:${Tag} pabot --verbose --processes ${PARALLEL_JOBS} --removekeywords TAG:secret ${excludes[@]} --variable ESX_VERSION:${ESX_BUILD} --variable VC_VERSION:${VC_BUILD} -d ${target} "${testcases[@]}"
cat ${target}/pabot_results/*/stdout.txt | grep -E '::|\.\.\.' | grep -E 'PASS|FAIL' > console.log

# See if any VMs leaked
# TODO: should be a warning until clean, then changed to a failure if any leak
echo "There should not be any VMs listed here"
echo "======================================="
timeout 60s sshpass -p ${NIMBUS_PASSWORD} ssh -o StrictHostKeyChecking\=no ${NIMBUS_USER}@${NIMBUS_GW} nimbus-ctl list
echo "======================================="
echo "If VMs are listed we should investigate why they are leaking"

# Pretty up the email results
sed -i -e 's/^/<br>/g' console.log
sed -i -e 's|PASS|<font color="green">PASS</font>|g' console.log
sed -i -e 's|FAIL|<font color="red">FAIL</font>|g' console.log

#DATE=`date +%m-%d-%H-%M`
#outfile="vic-product-ova-results-"$DATE".zip"
# zip -9 $outfile output.xml log.html report.html
