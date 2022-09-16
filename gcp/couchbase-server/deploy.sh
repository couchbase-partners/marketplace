#!/bin/bash

SCRIPT_SOURCE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

BYOL=0

while getopts n:b flag
do
    case "${flag}" in
        n) STACK_NAME=${OPTARG};;
        b) BYOL=1;;
        *) exit 1;;
    esac
done

if [[ "$BYOL" == "0" ]]; then
    bash "${SCRIPT_SOURCE}/makeArchives.sh" "-n" "-l"
    DESCRIPTION="Couchbase Enterprise Edition Marketplace Offering Hourly Testing"
else
    bash "${SCRIPT_SOURCE}/makeArchives.sh" "-b" "-n" "-l"
    DESCRIPTION="Couchbase Enterprise Edition Marketplace Offering BYOL Testing"
fi


cd "${SCRIPT_SOURCE}/../../build/gcp/couchbase-server/package/" || exit 1

gcloud deployment-manager deployments create "$STACK_NAME" \
    --config=test_config.yaml \
    --description="$DESCRIPTION"